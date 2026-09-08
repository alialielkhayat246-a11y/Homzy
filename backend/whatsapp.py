"""HOMZY OS — Phase 7: WhatsApp Cloud API integration.

Two directions, both prewired so the feature activates the moment Meta creds are
set (WA_PHONE_ID / WA_TOKEN / WA_VERIFY_TOKEN):

  * Inbound  — Meta calls /api/wa/webhook (GET verify, POST messages). We parse
    each message and hand it to the secret-gated `crm_ingest_wa` RPC, which
    matches it to a lead by phone, logs it, and notifies the owner. No
    service_role key — the shared PUSH_CRON_TOKEN authenticates the RPC.
  * Outbound — /api/wa/send (broker's JWT) sends via the Cloud API, then logs
    the message with `crm_log_outbound` (owner-gated). Returns not_configured
    when creds are absent, so the UI degrades gracefully.
"""
from __future__ import annotations

from typing import Any

from . import config

_SHARED = "ELsEiHprVIZCwcsJz0j5Hk_PGuZ7Zx9q"  # same shared secret as push/cron RPCs


def configured() -> bool:
    return bool(config.WA_PHONE_ID and config.WA_TOKEN)


def _rpc(fn: str, payload: dict, token: str | None = None) -> Any:
    """Call a PostgREST RPC. `token` = a user JWT (RLS applies); default = anon."""
    import requests

    bearer = token or config.SUPABASE_KEY
    r = requests.post(
        config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/" + fn,
        headers={"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + bearer,
                 "Content-Type": "application/json"},
        json=payload, timeout=20,
    )
    try:
        return r.json()
    except Exception:
        return {"ok": r.ok, "status": r.status_code}


def verify_webhook(mode: str, token: str, challenge: str) -> tuple[int, str]:
    """Meta webhook handshake. Returns (status_code, body)."""
    if mode == "subscribe" and token and token == config.WA_VERIFY_TOKEN:
        return 200, challenge or ""
    return 403, "forbidden"


def handle_inbound(payload: dict) -> dict:
    """Parse a Meta webhook POST body and ingest every message it carries."""
    ingested = 0
    try:
        for entry in payload.get("entry", []) or []:
            for change in entry.get("changes", []) or []:
                value = change.get("value", {}) or {}
                meta_phone = ((value.get("metadata") or {}).get("display_phone_number")
                              or config.WA_PHONE_ID)
                for msg in value.get("messages", []) or []:
                    frm = msg.get("from")
                    wa_id = msg.get("id")
                    body = ""
                    mtype = msg.get("type")
                    if mtype == "text":
                        body = (msg.get("text") or {}).get("body", "")
                    elif mtype in ("button", "interactive"):
                        body = str(msg.get(mtype) or "")
                    else:
                        body = f"[{mtype}]"
                    _rpc("crm_ingest_wa", {
                        "p_key": _SHARED, "p_from": frm, "p_to": meta_phone,
                        "p_body": body, "p_wa_id": wa_id,
                        "p_meta": {"type": mtype},
                    })
                    ingested += 1
    except Exception as exc:  # never 500 back to Meta — it would retry forever
        return {"ok": True, "ingested": ingested, "warn": str(exc)[:120]}
    return {"ok": True, "ingested": ingested}


def send(token: str, lead_id: str | None, to_number: str, text: str) -> dict:
    """Send an outbound WhatsApp text (broker JWT), then log it. `to_number` is
    the customer's phone; creds gate the actual send."""
    if not text or not to_number:
        return {"ok": False, "error": "missing_text_or_number"}
    if not configured():
        return {"ok": False, "error": "not_configured",
                "hint": "set WA_PHONE_ID + WA_TOKEN in the Vercel env"}
    import requests

    to = "".join(c for c in to_number if c.isdigit())
    wa_id = None
    try:
        r = requests.post(
            f"{config.WA_API_BASE}/{config.WA_PHONE_ID}/messages",
            headers={"Authorization": "Bearer " + config.WA_TOKEN,
                     "Content-Type": "application/json"},
            json={"messaging_product": "whatsapp", "to": to, "type": "text",
                  "text": {"body": text}},
            timeout=20,
        )
        data = r.json() if r.content else {}
        if not r.ok:
            return {"ok": False, "error": "send_failed",
                    "detail": (data.get("error") or {}).get("message", r.status_code)}
        wa_id = ((data.get("messages") or [{}])[0]).get("id")
    except Exception as exc:
        return {"ok": False, "error": "send_exception", "detail": str(exc)[:160]}

    logged = _rpc("crm_log_outbound", {
        "p_lead": lead_id, "p_to": to_number, "p_body": text,
        "p_wa_id": wa_id, "p_status": "sent"}, token=token)
    return {"ok": True, "wa_id": wa_id, "log": logged}
