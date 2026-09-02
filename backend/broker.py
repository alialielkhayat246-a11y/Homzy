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

from . import areas, catalog, config, listings as listings_mod, llm, persona, valuation

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
    return areas.extract(text)


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
    # Strip phone numbers FIRST so a contact number is never read as a budget
    # (e.g. "رقمي 01000000000" was becoming a 1,000,000,000 EGP budget).
    #  1) a number that follows a phone-intent word, and
    #  2) any bare run of 10+ digits (Egyptian mobiles are 11) — no residential
    #     budget is written as 10+ raw digits.
    low = re.sub(
        r"(?:رقمي|رقمى|رقم|موبايل|موبيل|تليفون|تلفون|واتس|واتساب|phone|mobile|"
        r"whatsapp|number|no\.?)\s*[:\-]?\s*\+?\d[\d\s\-]{6,}\d",
        " ", low)
    low = re.sub(r"\d{10,}", " ", low)
    # Strip down-payment mentions so a deposit ("مقدم مليون") is NOT read as the
    # total budget — that was making everything look out of budget.
    low = re.sub(
        r"(مقدم|مقدّم|المقدم|down\s*payment|downpayment|deposit)\s*\d+(?:\.\d+)?"
        r"\s*(?:m|mn|million|مليون|k|ألف|الف|thousand)?",
        " ", low)
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
    elif any(w in low for w in ["hotel apartment", "hotel unit", "hotel",
                                "شقة فندقية", "شقه فندقيه", "فندقية", "فندقيه", "فندقي"]):
        out["type"] = "hotel apartment"
    elif any(w in low for w in ["apartment", "flat", "شقة", "شقه", "شقق"]):
        out["type"] = "apartment"
    elif any(w in low for w in ["office", "مكتب", "اداري", "إداري"]):
        out["type"] = "office"
    elif any(w in low for w in ["shop", "retail", "commercial", "محل", "تجاري", "متجر"]):
        out["type"] = "shop"
    elif any(w in low for w in ["clinic", "عيادة", "عياده"]):
        out["type"] = "clinic"
    elif any(w in low for w in ["pharmacy", "صيدلية", "صيدليه"]):
        out["type"] = "pharmacy"

    # Primary (from the developer) vs resale (secondary / ready from owner).
    if any(w in low for w in ["resale", "ريسيل", "سوق ثانوي", "ثانوي", "اعادة بيع",
                              "إعادة بيع", "من المالك", "من مالك", "من صاحبها",
                              "وحدة جاهزة من", "ready resale"]):
        out["market_pref"] = "resale"
    elif any(w in low for w in ["primary", "بريماري", "من المطور", "من الشركة",
                                "لانش", "launch", "new launch", "مشروع جديد",
                                "اوف بلان", "أوف بلان", "off plan", "off-plan",
                                "تقسيط على المطور"]):
        out["market_pref"] = "primary"

    # Delivery timing preference: move in now vs fine waiting a couple of years.
    if any(w in low for w in ["استلام فوري", "فوري", "جاهز", "جاهزة", "دلوقتي",
                              "حالا", "حالاً", "ready", "move in now", "immediately",
                              "right now", "move now"]):
        out["delivery_pref"] = "ready"
    elif any(w in low for w in ["مش مستعجل", "مستعجلش", "عادي استنى", "ممكن استنى",
                                "عادي استلم", "اي مدة", "أي مدة", "اي وقت", "أي وقت",
                                "مش فارقة", "مش فارق", "مفيش مشكلة", "براحتك", "براحتى",
                                "بعد سنتين", "بعد تلات", "بعد ٣", "تحت الانشاء",
                                "off plan", "off-plan", "under construction", "anytime",
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
        raw = client.chat(messages, temperature=0.0, force_json=True, max_tokens=512)
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
                "budget_min", "delivery_pref", "market_pref"):
        val = found.get(key)
        if val not in (None, "", []):
            req[key] = val


# --------------------------------------------------------------------------
# Reply generation
# --------------------------------------------------------------------------
def _llm_reply(history: list[dict[str, str]], language: str,
               matches: list[dict[str, Any]], coach: bool = False):
    client = _client_or_none()
    if client is None:
        return None
    overview = catalog.market_overview()
    system = (persona.broker_coach_system(language, matches, overview) if coach
              else persona.broker_system(language, matches, overview))
    messages = [{"role": "system", "content": system}] + history
    try:
        text = client.chat(messages, temperature=config.LLM_TEMPERATURE, max_tokens=900)
        return text or None
    except llm.LLMUnavailable:
        return None


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------
def _prepare(session: dict[str, Any], message: str,
             client_history: list[dict[str, str]] | None):
    """Shared per-turn setup: language, requirements, matches. Appends the
    user message to history and returns (language, history, req, matches)."""
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
        req = {}
        for m in session["history"]:
            if m["role"] == "user":
                _merge(req, _heuristic_extract(m["content"]))
        session["requirements"] = req
    history = session.setdefault("history", [])
    history.append({"role": "user", "content": message})

    # 1) heuristic from this message (always works, even with no AI engine)
    _merge(req, _heuristic_extract(message))
    # 2) LLM extraction — but ONLY while an essential is still missing, so the
    #    recommendation turns are a single LLM round trip (≈2× faster).
    if config.LLM_EXTRACT and persona._missing(req):
        _merge(req, _llm_extract(_history_to_text(history)))

    # 3) find real listings
    matches = listings_mod.search(req, config.MAX_RESULTS)

    # 3b) enrich the top unit so the advisor can speak with real depth: position
    #     it against ITS own market, describe its AREA, and know the developer's
    #     wider portfolio (other projects).
    if matches and not persona._missing(req):
        top = matches[0]
        if not top.get("value_note"):
            note = valuation.value_note(
                top.get("area_en"), top.get("type"),
                top.get("price"), top.get("size_sqm"),
                market=top.get("market", "resale"))
            if note:
                top["value_note"] = note
        if "area_profile" not in top:
            top["area_profile"] = areas.profile(top.get("area_en") or top.get("area_ar"))
        if "dev_other_projects" not in top:
            top["dev_other_projects"] = catalog.developer_projects(
                top.get("developer"), exclude=top.get("compound_en"))
    return language, history, req, matches


def _offer_facts_text(u: dict[str, Any]) -> str:
    def g(*keys):
        for k in keys:
            v = u.get(k)
            if v not in (None, "", []):
                return v
        return None
    rows = [
        ("Project/unit", g("compound_ar", "compound", "name")),
        ("Area", g("area_ar", "area")),
        ("Developer", g("developer")),
        ("Market", "resale (ready)" if g("market") == "resale" else "primary (from developer)"),
        ("Type", g("type")),
        ("Bedrooms", g("bedrooms")),
        ("Size (sqm)", g("size_sqm")),
        ("Price", g("price_ar", "price_en", "price")),
        ("Down payment", g("down_payment")),
        ("Installment years", g("installment_years")),
        ("Delivery", g("delivery")),
        ("Payment plan", g("payment_plan")),
    ]
    return "\n".join(f"- {k}: {v}" for k, v in rows if v not in (None, ""))


def _derived_advantages(u: dict[str, Any], language: str) -> list[str]:
    ar = language == "ar"
    out = []
    if u.get("delivery"):
        out.append((f"استلام: {u['delivery']}") if ar else f"Delivery: {u['delivery']}")
    if u.get("down_payment"):
        out.append((f"مقدم يبدأ من {u['down_payment']}") if ar else f"Down payment from {u['down_payment']}")
    if u.get("installment_years"):
        out.append((f"تقسيط يصل إلى {u['installment_years']} سنة") if ar else f"Installments up to {u['installment_years']} years")
    if u.get("developer"):
        out.append((f"من مطوّر معروف: {u['developer']}") if ar else f"By a trusted developer: {u['developer']}")
    if u.get("market") == "resale":
        out.append("جاهزة للاستلام الفوري — من غير انتظار" if ar else "Ready to move — no waiting")
    else:
        out.append("وحدة جديدة من المطوّر بخطة سداد مريحة" if ar else "Brand-new from the developer with a comfortable plan")
    return out[:6]


def offer_advantages(unit: dict[str, Any], language: str) -> list[str]:
    """AI-written honest selling advantages for a PDF offer, grounded ONLY in the
    unit's real facts. Falls back to data-derived bullets if the LLM is off."""
    client = _client_or_none()
    if client is not None:
        lang = "Arabic (Egyptian dialect)" if language == "ar" else "English"
        system = (
            "You write the selling ADVANTAGES for a real-estate OFFER a broker will send a "
            f"client. Using ONLY the facts below, write 4-6 short, punchy, HONEST advantages "
            f"in {lang} — one per line, no numbering, no intro, no invented facts or prices.\n\n"
            + _offer_facts_text(unit))
        try:
            txt = client.chat(
                [{"role": "system", "content": system},
                 {"role": "user", "content": "اكتب المزايا." if language == "ar" else "Write the advantages."}],
                temperature=0.5, max_tokens=320)
            if txt:
                lines = [re.sub(r"^[\-•‣\d\.\)\s]+", "", l).strip()
                         for l in txt.splitlines() if l.strip()]
                lines = [l for l in lines if len(l) > 3][:6]
                if lines:
                    return lines
        except Exception:
            pass
    return _derived_advantages(unit, language)


def _recommendation(req, matches):
    if not persona._missing(req) and matches:
        return listings_mod.public(matches[0])
    return None


def handle_turn(session: dict[str, Any], message: str,
                client_history: list[dict[str, str]] | None = None,
                coach: bool = False) -> dict[str, Any]:
    language, history, req, matches = _prepare(session, message, client_history)

    reply = _llm_reply(history, language, matches, coach=coach)
    mode = "ai"
    if reply is None:
        greet = sum(1 for m in history if m["role"] == "user") <= 1
        reply = persona.template_reply(language, req, matches, greet=greet)
        mode = "template"

    history.append({"role": "assistant", "content": reply})
    return {
        "reply": reply,
        "language": language,
        "mode": mode,
        "requirements": req,
        "recommendation": _recommendation(req, matches),
        "matches": [listings_mod.public(m) for m in matches],
    }


def handle_turn_stream(session: dict[str, Any], message: str,
                       client_history: list[dict[str, str]] | None = None,
                       coach: bool = False):
    """Same pipeline as handle_turn, but yields events so the reply streams
    token-by-token. Events: {'type':'meta'|'token'|'done', ...}."""
    language, history, req, matches = _prepare(session, message, client_history)
    yield {"type": "meta", "language": language}

    client = _client_or_none()
    reply = None
    if client is not None and hasattr(client, "stream"):
        overview = catalog.market_overview()
        system = (persona.broker_coach_system(language, matches, overview) if coach
                  else persona.broker_system(language, matches, overview))
        messages = [{"role": "system", "content": system}] + [
            {"role": m["role"], "content": m["content"]} for m in history]
        parts: list[str] = []
        try:
            for chunk in client.stream(messages, temperature=config.LLM_TEMPERATURE,
                                       max_tokens=900):
                parts.append(chunk)
                yield {"type": "token", "text": chunk}
            reply = "".join(parts) or None
        except llm.LLMUnavailable:
            reply = None

    mode = "ai"
    if reply is None:  # non-streaming engine, or streaming failed → one shot
        reply = _llm_reply(history, language, matches, coach=coach)
        if reply is None:
            greet = sum(1 for m in history if m["role"] == "user") <= 1
            reply = persona.template_reply(language, req, matches, greet=greet)
            mode = "template"
        yield {"type": "token", "text": reply}

    history.append({"role": "assistant", "content": reply})
    yield {
        "type": "done",
        "language": language,
        "mode": mode,
        "requirements": req,
        "recommendation": _recommendation(req, matches),
        "matches": [listings_mod.public(m) for m in matches],
    }
