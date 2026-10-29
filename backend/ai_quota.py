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

LIMIT_AR = "خلصت رسايل الذكاء الاصطناعي بتاعة النهارده ({limit} رسالة في باقتك). الرصيد بيتجدد بكرة الساعة 12 بالليل — أو اشحن 500 رسالة بـ 199 ج من صفحة الأسعار."
LIMIT_EN = "You've used today's AI messages ({limit} on your plan). They reset at midnight Cairo time — or top up 500 messages for 199 EGP on the pricing page."
POOL_AR = "رصيد الذكاء الاصطناعي الشهري لفريقك خلص ({limit} رسالة). بيتجدد أول الشهر — أو مدير الحساب يشحن 500 رسالة بـ 199 ج من صفحة الأسعار."
POOL_EN = "Your team's monthly AI messages are used up ({limit}). They reset on the 1st — or the account owner can top up 500 messages for 199 EGP on the pricing page."
TRIAL_AR = "تجربتك المجانية انتهت — اشترك من صفحة الأسعار عشان تكمل تستخدم الذكاء الاصطناعي."
TRIAL_EN = "Your free trial has ended — subscribe on the pricing page to keep using the AI."


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
    en = language == "en"
    if q.get("trial_ended"):
        return TRIAL_EN if en else TRIAL_AR
    if q.get("pool"):
        return (POOL_EN if en else POOL_AR).format(limit=q.get("limit"))
    return (LIMIT_EN if en else LIMIT_AR).format(limit=q.get("limit"))


def left(q: dict[str, Any] | None) -> int | None:
    return q.get("left") if q and q.get("ok") else None
