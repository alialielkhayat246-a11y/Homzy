"""HOMZY OS — Phase 9: AI lead intelligence.

Given a lead the signed-in broker owns, produce a concise summary, the
next-best-action, a ready-to-send WhatsApp draft, a win-probability and a
priority. Design rules (from the brief):

  * RLS-respecting: the lead + its activity timeline are read with the BROKER'S
    OWN Supabase JWT, so a broker can only analyse a lead they can see. We never
    use the service key here and never bypass RLS.
  * Read-only & safe: this module only READS. It never writes, deletes, changes
    financials, or sends messages — it only *suggests* a message for the broker
    to send themselves.
  * Provider-abstracted: uses llm.get_client() (Ollama / Gemini free tier /
    mock). If no engine is configured or the call fails, a deterministic
    heuristic still returns a useful result, so the feature always works.
"""
from __future__ import annotations

import json
from typing import Any

from . import config, llm


def _sb_get(path: str, token: str) -> Any:
    """GET PostgREST as the user (their JWT), so row-level security applies."""
    import requests

    r = requests.get(
        config.SUPABASE_URL.rstrip("/") + "/rest/v1" + path,
        headers={
            "apikey": config.SUPABASE_KEY,
            "Authorization": "Bearer " + (token or config.SUPABASE_KEY),
            "Accept": "application/json",
        },
        timeout=20,
    )
    if not r.ok:
        return None
    try:
        return r.json()
    except Exception:
        return None


_TEMP_AR = {"very_hot": "ساخن جدًا", "hot": "ساخن", "warm": "دافئ", "cold": "بارد"}
_STAGE_AR = {"new": "جديد", "contacted": "تم التواصل", "viewing": "معاينة",
             "negotiation": "تفاوض", "closed": "مغلق (مكسوب)", "lost": "خسارة"}


def _budget_txt(c: dict) -> str:
    lo, hi, b = c.get("budget_min"), c.get("budget_max"), c.get("budget")
    if lo and hi:
        return f"{int(lo):,}–{int(hi):,} ج.م"
    if hi:
        return f"حتى {int(hi):,} ج.م"
    if b:
        return f"حوالي {int(b):,} ج.م"
    return "غير محددة"


def _requirements(c: dict) -> str:
    bits = []
    if c.get("type"):
        bits.append(str(c["type"]))
    if c.get("bedrooms") is not None:
        bits.append(f"{c['bedrooms']} غرف")
    if c.get("area"):
        bits.append(str(c["area"]))
    purpose = (c.get("purpose") or c.get("intent") or "").lower()
    if "rent" in purpose or "إيجار" in purpose or "ايجار" in purpose:
        bits.append("إيجار")
    elif purpose:
        bits.append("تمليك")
    bits.append("ميزانية " + _budget_txt(c))
    return " · ".join(bits)


def _heuristic(c: dict, acts: list[dict]) -> dict:
    """Deterministic fallback — always available, even with no AI engine."""
    score = int(c.get("lead_score") or 0)
    temp = c.get("temperature") or "cold"
    # win probability: score is the backbone, nudged by temperature.
    prob = score
    prob += {"very_hot": 8, "hot": 4, "warm": 0, "cold": -5}.get(temp, 0)
    prob = max(3, min(97, prob))
    priority = "high" if temp in ("very_hot", "hot") else ("medium" if temp == "warm" else "low")

    name = c.get("name") or "العميل"
    kinds = {a.get("kind") for a in acts}
    if not acts or ("call" not in kinds and "whatsapp" not in kinds):
        nba = f"تواصل مع {name} لأول مرة خلال أقرب وقت (سرعة الرد بتزوّد فرصة القفل)."
    elif "viewing_requested" in kinds and "viewing_attended" not in kinds:
        nba = "أكّد ميعاد المعاينة وابعت العنوان + لوكيشن."
    elif "negotiation" in kinds:
        nba = "اقفل التفاوض: ابعت أفضل عرض وسعر نهائي مع حث لطيف على الحجز."
    elif "property_sent" in kinds or "property_requested" in kinds:
        nba = "تابع على الوحدات اللي اتبعتت واعرض معاينة."
    else:
        nba = f"ابعت لـ {name} 2–3 وحدات مطابقة واقترح معاينة."

    req = _requirements(c)
    msg = (f"أهلًا {name} 👋 معاك بروكر Homzy. لسه فاكر إنك بتدور على "
           f"{req}. لقيت لك كذا وحدة ممكن تناسبك — تحب أبعتهم لك وأرتّب معاينة؟")
    summary = (f"{name} — عميل {_TEMP_AR.get(temp, temp)} (سكور {score}/100)، "
               f"المرحلة: {_STAGE_AR.get(c.get('stage'), c.get('stage') or 'جديد')}. "
               f"المطلوب: {req}.")
    return {
        "summary": summary,
        "next_best_action": nba,
        "suggested_message": msg,
        "win_probability": prob,
        "priority": priority,
        "engine": "heuristic",
    }


def _timeline(acts: list[dict]) -> str:
    lines = []
    for a in acts[:15]:
        k = a.get("kind") or "?"
        body = (a.get("body") or "").strip().replace("\n", " ")
        when = (a.get("created_at") or "")[:10]
        lines.append(f"- {when} [{k}] {body}"[:160])
    return "\n".join(lines) or "(لا يوجد نشاط بعد)"


def analyze_lead(token: str, lead_id: str) -> dict:
    """Return AI intelligence for one lead the caller owns (RLS-enforced)."""
    if not lead_id:
        return {"ok": False, "error": "missing lead_id"}
    rows = _sb_get(f"/clients?id=eq.{lead_id}&select=*", token)
    if not rows:  # RLS hid it, or it doesn't exist
        return {"ok": False, "error": "not_found_or_forbidden"}
    c = rows[0]
    acts = _sb_get(
        f"/crm_lead_activities?lead_id=eq.{lead_id}"
        f"&select=kind,body,created_at&order=created_at.desc&limit=15",
        token,
    ) or []

    # Deterministic result first — it's the guaranteed fallback and the shape spec.
    result = _heuristic(c, acts)

    client = None
    try:
        client = llm.get_client()  # None in 'mock' mode
    except Exception:
        client = None
    if client is None:
        result["ok"] = True
        return result

    sys = (
        "أنت مساعد مبيعات عقارية خبير داخل نظام Homzy CRM. حلّل بيانات العميل "
        "والنشاط وأخرج JSON فقط بالمفاتيح: summary (سطرين مختصرين بالعربي "
        "المصري)، next_best_action (خطوة واحدة عملية دلوقتي)، suggested_message "
        "(رسالة واتساب جاهزة للإرسال بالعربي المصري، ودّية ومحترمة، بدون مبالغة أو "
        "ندرة كاذبة)، win_probability (رقم صحيح 0-100)، priority "
        "(high/medium/low). لا تخترع أي تفاصيل عن عقارات أو أسعار غير الموجودة."
    )
    profile = {
        "name": c.get("name"), "temperature": c.get("temperature"),
        "lead_score": c.get("lead_score"), "stage": c.get("stage"),
        "type": c.get("type"), "bedrooms": c.get("bedrooms"),
        "area": c.get("area"), "budget": _budget_txt(c),
        "purpose": c.get("purpose") or c.get("intent"),
        "source": c.get("source"), "next_followup": c.get("next_followup"),
    }
    user = ("بيانات العميل:\n" + json.dumps(profile, ensure_ascii=False)
            + "\n\nآخر النشاط:\n" + _timeline(acts))
    try:
        raw = client.chat(
            [{"role": "system", "content": sys}, {"role": "user", "content": user}],
            temperature=0.4, force_json=True, max_tokens=700,
        )
        data = raw if isinstance(raw, dict) else json.loads(raw)
        out = {
            "summary": str(data.get("summary") or result["summary"])[:600],
            "next_best_action": str(data.get("next_best_action") or result["next_best_action"])[:400],
            "suggested_message": str(data.get("suggested_message") or result["suggested_message"])[:900],
            "priority": (data.get("priority") if data.get("priority") in ("high", "medium", "low") else result["priority"]),
            "engine": getattr(client, "name", "llm"),
            "ok": True,
        }
        try:
            wp = int(round(float(data.get("win_probability"))))
            out["win_probability"] = max(0, min(100, wp))
        except Exception:
            out["win_probability"] = result["win_probability"]
        return out
    except Exception:
        # engine failed → deterministic result still stands
        result["ok"] = True
        return result
