"""Daily AI message allowance per broker plan (see plan_limits.ai_daily_messages).

Each deliberate AI action by a signed-in broker (broker-mode chat message, voice
command, AI lead analysis, message draft…) counts as one message. The count is
kept in Supabase (`ai_consume`) with the broker's own JWT, so it is shared by
all serverless instances. If the check itself can't run (no token, network),
the action is allowed — a broker is never blocked by our own outage.
"""
from __future__ import annotations

from typing import Any

from . import config

LIMIT_AR = "خلصت رسايل الذكاء الاصطناعي بتاعة النهارده ({limit} رسالة في باقتك). الرصيد بيتجدد بكرة الساعة 12 بالليل، أو رقّي باقتك من صفحة الأسعار."
LIMIT_EN = "You've used today's AI messages ({limit} on your plan). They reset at midnight Cairo time — or upgrade your plan on the pricing page."


def consume(token: str | None, kind: str = "chat") -> dict[str, Any] | None:
    """Count one AI message. Returns {ok, used, limit, left} or None if unchecked."""
    if not token or not config.SUPABASE_URL:
        return None
    import requests

    try:
        r = requests.post(config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/ai_consume",
                          headers={"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + token,
                                   "Content-Type": "application/json"},
                          json={"p_kind": kind}, timeout=6)
        return r.json() if r.ok else None
    except Exception:
        return None


def blocked(q: dict[str, Any] | None) -> bool:
    return bool(q) and q.get("ok") is False


def limit_text(q: dict[str, Any], language: str = "ar") -> str:
    return (LIMIT_EN if language == "en" else LIMIT_AR).format(limit=q.get("limit"))


def left(q: dict[str, Any] | None) -> int | None:
    return q.get("left") if q and q.get("ok") else None
