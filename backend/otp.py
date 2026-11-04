"""Phone verification codes sent on WhatsApp (Meta Cloud API, Authentication template).

The code is generated and stored (hashed) by the key-gated `phone_otp_issue`
RPC, so only this backend ever sees it; the browser checks it with
`phone_otp_verify`. Rate limits (1/min, 5/day per phone) live in the database;
a light per-IP limit here stops one visitor from spraying many numbers.
"""
from __future__ import annotations

import time
from typing import Any

from . import config

_IP_HITS: dict[str, list[float]] = {}
_IP_MAX, _IP_WINDOW = 10, 3600.0


def enabled() -> bool:
    return bool(config.OTP_WA_TOKEN and config.OTP_WA_PHONE_ID and config.PUSH_CRON_TOKEN and config.SUPABASE_URL)


def _ip_allowed(ip: str) -> bool:
    now = time.time()
    hits = [t for t in _IP_HITS.get(ip, []) if now - t < _IP_WINDOW]
    if len(hits) >= _IP_MAX:
        _IP_HITS[ip] = hits
        return False
    hits.append(now)
    _IP_HITS[ip] = hits
    return True


def _send_whatsapp(phone: str, code: str, lang: str) -> bool:
    import requests

    url = f"https://graph.facebook.com/{config.OTP_WA_API_VERSION}/{config.OTP_WA_PHONE_ID}/messages"
    hdr = {"Authorization": "Bearer " + config.OTP_WA_TOKEN, "Content-Type": "application/json"}
    for code_lang in dict.fromkeys([lang, "ar"]):          # fall back to Arabic if the other language isn't approved
        body = {
            "messaging_product": "whatsapp", "to": phone, "type": "template",
            "template": {"name": config.OTP_WA_TEMPLATE, "language": {"code": code_lang},
                         "components": [
                             {"type": "body", "parameters": [{"type": "text", "text": code}]},
                             {"type": "button", "sub_type": "url", "index": "0",
                              "parameters": [{"type": "text", "text": code}]}]},
        }
        try:
            r = requests.post(url, headers=hdr, json=body, timeout=12)
            if r.ok:
                return True
        except Exception:
            pass
    return False


def send_code(phone: str, lang: str, ip: str) -> dict[str, Any]:
    if not enabled():
        return {"ok": False, "error": "disabled"}
    if not _ip_allowed(ip or "?"):
        return {"ok": False, "error": "too_many"}
    import requests

    try:
        r = requests.post(config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/phone_otp_issue",
                          headers={"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + config.SUPABASE_KEY,
                                   "Content-Type": "application/json"},
                          json={"p_key": config.PUSH_CRON_TOKEN, "p_phone": phone}, timeout=8)
        res = r.json() if r.ok else {"ok": False, "error": "server"}
    except Exception:
        return {"ok": False, "error": "server"}
    if not res.get("ok"):
        return {k: v for k, v in res.items() if k != "code"}
    if not _send_whatsapp(res["phone"], res["code"], "en" if lang == "en" else "ar"):
        return {"ok": False, "error": "send_failed"}
    return {"ok": True, "channel": "whatsapp"}
