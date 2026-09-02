"""Web Push for broker follow-up reminders.

Two responsibilities:
  * send_one()      — encrypt + deliver a single Web Push message (pywebpush).
  * run_followups() — the daily job: ask Supabase (service_role) which brokers
                      have client follow-ups due today/overdue, then push each
                      of their subscribed devices a reminder.

Everything is best-effort: a dead subscription (410/404) is pruned so we don't
keep hammering it; a missing key just means "push disabled" and we no-op.
"""
from __future__ import annotations

import json
from typing import Any

from . import config


def enabled() -> bool:
    return bool(
        config.VAPID_PRIVATE_KEY
        and config.SUPABASE_URL
        and config.SUPABASE_KEY
        and config.PUSH_CRON_TOKEN
    )


def _vapid_claims() -> dict[str, str]:
    return {"sub": config.VAPID_SUBJECT}


def send_one(subscription: dict[str, Any], payload: dict[str, Any]) -> int:
    """Deliver one push. Returns the HTTP status (201 = queued by the push
    service). Raises WebPushException on transport errors so the caller can
    decide whether to prune the subscription."""
    from pywebpush import webpush

    resp = webpush(
        subscription_info=subscription,
        data=json.dumps(payload, ensure_ascii=False),
        vapid_private_key=config.VAPID_PRIVATE_KEY,
        vapid_claims=dict(_vapid_claims()),
        ttl=60 * 60 * 12,
    )
    return getattr(resp, "status_code", 201)


def _anon_headers() -> dict[str, str]:
    key = config.SUPABASE_KEY
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


def _delete_subscription(endpoint: str) -> None:
    """Prune a subscription the push service says is gone (410/404). Goes
    through a secret-gated SECURITY DEFINER RPC (no service_role needed)."""
    import requests

    try:
        requests.post(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/delete_push_subscription",
            headers=_anon_headers(),
            json={"p_key": config.PUSH_CRON_TOKEN, "p_endpoint": endpoint},
            timeout=10,
        )
    except Exception:
        pass


def run_followups() -> dict[str, Any]:
    """Fan out follow-up reminders. Returns a small report dict."""
    if not enabled():
        return {"ok": False, "error": "push_not_configured"}

    import requests

    try:
        r = requests.post(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/due_followups_for_push",
            headers=_anon_headers(),
            json={"p_key": config.PUSH_CRON_TOKEN},
            timeout=20,
        )
        r.raise_for_status()
        rows = r.json() or []
    except Exception as exc:  # pragma: no cover - network
        return {"ok": False, "error": f"rpc_failed: {exc}"}

    sent = failed = pruned = 0
    for row in rows:
        sub = row.get("subscription")
        if isinstance(sub, str):
            try:
                sub = json.loads(sub)
            except Exception:
                continue
        if not isinstance(sub, dict) or not sub.get("endpoint"):
            continue
        n = int(row.get("due_count") or 0)
        names = (row.get("names") or "").strip()
        body = f"عندك {n} متابعة مستحقة اليوم"
        if names:
            first = "، ".join(names.split("، ")[:3])
            body += f": {first}"
        payload = {
            "title": "Homzy — متابعات اليوم",
            "body": body,
            "url": "/clients",
            "tag": "homzy-followups",
        }
        try:
            send_one(sub, payload)
            sent += 1
        except Exception as exc:  # WebPushException carries .response
            resp = getattr(exc, "response", None)
            code = getattr(resp, "status_code", None)
            if code in (404, 410):
                _delete_subscription(sub["endpoint"])
                pruned += 1
            else:
                failed += 1
    return {"ok": True, "brokers": len(rows), "sent": sent,
            "failed": failed, "pruned": pruned}
