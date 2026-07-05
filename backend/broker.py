"""The orchestration layer: one client turn in, one broker reply out.

Pipeline per turn:
  1. detect the client's language (Arabic or English)
  2. update the running search criteria  (LLM extraction + heuristic safety net)
  3. find matching listings in code        (real prices, never invented)
  4. generate the reply                     (AI engine, or grounded template)

Because step 3 supplies the real listings and prices, the model can only ever
*present* what we hand it — it cannot invent a price.
"""
from __future__ import annotations

import json
import re
from typing import Any

from . import config, listings as listings_mod, llm, persona

# Cache the client object (cheap; chat() failures fall back to templates).
_client: Any = None
_client_resolved = False


def _client_or_none():
    global _client, _client_resolved
    if not _client_resolved:
        if config.LLM_PROVIDER == "mock":
            _client = None
        else:
            try:
                _client = llm.get_client()
            except llm.LLMUnavailable:
                _client = None
        _client_resolved = True
    return _client


# --------------------------------------------------------------------------
# Language
# --------------------------------------------------------------------------
_AR_RE = re.compile(r"[؀-ۿ]")


def detect_language(text: str) -> str:
    return "ar" if _AR_RE.search(text or "") else "en"


# --------------------------------------------------------------------------
# Requirement extraction
# --------------------------------------------------------------------------
_AR_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")

_AREA_ALIASES = {
    # more specific names first so e.g. "New Cairo" wins over a bare "Cairo"
    "New Capital": ["new capital", "administrative capital", "capital gardens",
                    "العاصمة الادارية", "العاصمة الإدارية", "العاصمة", "كابيتال"],
    "New Cairo": ["new cairo", "5th settlement", "fifth settlement", "north teseen",
                  "التجمع الخامس", "التجمع", "تجمع", "القاهرة الجديدة", "نيو كايرو"],
    "Mostakbal City": ["mostakbal", "المستقبل", "مدينة المستقبل", "مستقبل سيتي"],
    "New Zayed": ["new zayed", "زايد الجديدة", "الشيخ زايد الجديدة"],
    "Sheikh Zayed": ["sheikh zayed", "el sheikh zayed", "الشيخ زايد", "شيخ زايد", "زايد"],
    "October Gardens": ["october gardens", "حدائق اكتوبر", "حدائق أكتوبر"],
    "6th of October": ["6th of october", "6 october", "6th october", "october city",
                       "october", "أكتوبر", "اكتوبر", "السادس من اكتوبر", "٦ اكتوبر"],
    "Ras El Hekma": ["ras el hekma", "ras elhekma", "راس الحكمة", "رأس الحكمة", "راس الحكمه"],
    "North Coast": ["north coast", "sahel", "الساحل الشمالي", "الساحل", "ساحل"],
    "New Alamein": ["alamein", "new alamein", "العلمين", "علمين"],
    "Ain Sokhna": ["ain sokhna", "sokhna", "العين السخنة", "عين السخنة", "السخنة", "سخنة"],
    "Galala": ["galala", "الجلالة"],
    "Madinaty": ["madinaty", "مدينتي"],
    "El Shorouk": ["shorouk", "الشروق"],
    "El Obour": ["obour", "العبور"],
    "New Mansoura": ["new mansoura", "المنصورة الجديدة"],
    "Maadi": ["maadi", "المعادي"],
}


def _norm(text: str) -> str:
    return (text or "").translate(_AR_DIGITS)


def _extract_area(text: str):
    low = _norm(text).lower()
    raw = _norm(text)
    for canonical, aliases in _AREA_ALIASES.items():
        for a in aliases:
            if a.isascii():
                if a in low:
                    return canonical
            elif a in raw:
                return canonical
    return None


def _extract_bedrooms(text: str):
    low = _norm(text).lower()
    if any(w in low for w in ["studio", "استوديو", "ستوديو"]):
        return 0
    # Arabic dual words
    if any(w in text for w in ["غرفتين", "اوضتين", "أوضتين"]):
        return 2
    arabic_word_nums = {"غرفة": 1, "اوضة": 1, "أوضة": 1, "ثلاث": 3, "تلت": 3,
                        "اربع": 4, "أربع": 4, "خمس": 5}
    # digit followed by a bedroom keyword
    m = re.search(r"(\d+)\s*(?:bed|bedroom|bedrooms|br|rooms?|غرف|غرفه|غرفة|اوض|أوض|اود)", low)
    if m:
        return int(m.group(1))
    for word, num in arabic_word_nums.items():
        if word in text and any(k in text for k in ["غرف", "اوض", "أوض"]):
            return num
    return None


def _extract_budget(text: str):
    low = _norm(text).lower().replace(",", "")
    amounts: list[float] = []
    for m in re.finditer(r"(\d+(?:\.\d+)?)\s*(m|mn|million|مليون|k|ألف|الف|thousand)?", low):
        num = float(m.group(1))
        unit = m.group(2) or ""
        if unit in ("m", "mn", "million", "مليون"):
            num *= 1_000_000
        elif unit in ("k", "ألف", "الف", "thousand"):
            num *= 1_000
        if num >= 1000:  # ignore stray small numbers like "2 bedrooms"
            amounts.append(num)
    return int(max(amounts)) if amounts else None


def _heuristic_extract(text: str) -> dict[str, Any]:
    low = _norm(text).lower()
    out: dict[str, Any] = {}

    if any(w in low for w in ["rent", "rental", "lease", "إيجار", "ايجار", "للايجار", "للإيجار"]):
        out["purpose"] = "rent"
    elif any(w in low for w in ["buy", "sale", "purchase", "own", "تمليك", "للبيع", "شراء", "اشتري", "أشتري"]):
        out["purpose"] = "sale"

    if any(w in low for w in ["villa", "فيلا", "فيلة", "فله"]):
        out["type"] = "villa"
    elif any(w in low for w in ["townhouse", "town house", "تاون"]):
        out["type"] = "townhouse"
    elif any(w in low for w in ["studio", "استوديو", "ستوديو"]):
        out["type"] = "studio"
    elif any(w in low for w in ["apartment", "flat", "شقة", "شقه", "شقق"]):
        out["type"] = "apartment"
    elif any(w in low for w in ["office", "مكتب"]):
        out["type"] = "office"

    # Delivery timing preference: move in now vs fine waiting a couple of years.
    if any(w in low for w in ["استلام فوري", "فوري", "جاهز", "جاهزة", "دلوقتي",
                              "حالا", "حالاً", "ready", "move in now", "immediately",
                              "right now", "move now"]):
        out["delivery_pref"] = "ready"
    elif any(w in low for w in ["مش مستعجل", "مستعجلش", "عادي استنى", "ممكن استنى",
                                "بعد سنتين", "بعد تلات", "بعد ٣", "تحت الانشاء",
                                "off plan", "off-plan", "under construction",
                                "can wait", "2 years", "3 years", "two years", "three years"]):
        out["delivery_pref"] = "flexible"

    beds = _extract_bedrooms(text)
    if beds is not None:
        out["bedrooms"] = beds

    area = _extract_area(text)
    if area:
        out["area"] = area

    budget = _extract_budget(text)
    if budget is not None:
        out["budget_max"] = budget

    return out


def _parse_json(raw: str) -> dict[str, Any]:
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        pass
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            return json.loads(raw[start:end + 1])
        except Exception:
            return {}
    return {}


def _llm_extract(history_text: str) -> dict[str, Any]:
    client = _client_or_none()
    if client is None:
        return {}
    messages = [
        {"role": "system", "content": persona.EXTRACT_SYSTEM},
        {"role": "user", "content": history_text},
    ]
    try:
        raw = client.chat(messages, temperature=0.0, force_json=True)
    except llm.LLMUnavailable:
        return {}
    return _parse_json(raw)


def _history_to_text(history: list[dict[str, str]]) -> str:
    lines = []
    for turn in history:
        who = "Client" if turn["role"] == "user" else "Broker"
        lines.append(f"{who}: {turn['content']}")
    return "\n".join(lines)


def _merge(req: dict[str, Any], found: dict[str, Any]) -> None:
    for key in ("purpose", "type", "area", "bedrooms", "budget_max",
                "budget_min", "delivery_pref"):
        val = found.get(key)
        if val not in (None, "", []):
            req[key] = val


# --------------------------------------------------------------------------
# Reply generation
# --------------------------------------------------------------------------
def _llm_reply(history: list[dict[str, str]], language: str,
               matches: list[dict[str, Any]]):
    client = _client_or_none()
    if client is None:
        return None
    system = persona.broker_system(language, matches)
    messages = [{"role": "system", "content": system}] + history
    try:
        text = client.chat(messages, temperature=config.LLM_TEMPERATURE)
        return text or None
    except llm.LLMUnavailable:
        return None


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------
def handle_turn(session: dict[str, Any], message: str,
                client_history: list[dict[str, str]] | None = None) -> dict[str, Any]:
    language = detect_language(message)
    session["language"] = language
    req = session.setdefault("requirements", {})

    # If the client sends the conversation history (recommended — serverless
    # instances don't share in-memory sessions), trust it so the AI remembers.
    if client_history is not None:
        session["history"] = [
            {"role": m["role"], "content": m["content"]}
            for m in client_history
            if m.get("role") in ("user", "assistant") and m.get("content")
        ]
        # rebuild requirements from the whole conversation via heuristics
        req = {}
        for m in session["history"]:
            if m["role"] == "user":
                _merge(req, _heuristic_extract(m["content"]))
        session["requirements"] = req
    history = session.setdefault("history", [])

    history.append({"role": "user", "content": message})

    # 1) heuristic from this message (always works, even with no AI engine)
    _merge(req, _heuristic_extract(message))
    # 2) optional LLM extraction across the whole conversation. Off by default
    #    (one fewer LLM call per turn = faster replies).
    if config.LLM_EXTRACT:
        _merge(req, _llm_extract(_history_to_text(history)))

    # 3) find real listings
    matches = listings_mod.search(req, config.MAX_RESULTS)

    # 4) reply
    reply = _llm_reply(history, language, matches)
    mode = "ai"
    if reply is None:
        reply = persona.template_reply(language, req, matches)
        mode = "template"

    history.append({"role": "assistant", "content": reply})

    # Once we know all five essentials and have a match, surface ONE structured
    # recommendation so the app can render its photos + brochure below the reply.
    recommendation = None
    if not persona._missing(req) and matches:
        recommendation = listings_mod.public(matches[0])

    return {
        "reply": reply,
        "language": language,
        "mode": mode,
        "requirements": req,
        "recommendation": recommendation,
        "matches": [listings_mod.public(m) for m in matches],
    }
