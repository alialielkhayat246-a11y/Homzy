"""The broker's character, voice and the prompts that drive the LLM.

Everything here is tunable. Edit BROKER_TEMPLATE to change how the broker
sells; edit config (BROKER_NAME / BRAND_NAME) to rename them.
"""
from __future__ import annotations

from typing import Any

from . import config, listings as listings_mod

# ----------------------------------------------------------------------------
# 1) Extraction prompt — turns the conversation into structured search criteria
# ----------------------------------------------------------------------------
EXTRACT_SYSTEM = """You extract a real-estate client's search criteria from a conversation.
Return ONLY a JSON object with these exact keys (use null when unknown):
{
 "purpose": "rent" or "sale" or null,
 "type": "apartment" or "villa" or "townhouse" or "studio" or "office" or null,
 "area": string or null,
 "bedrooms": integer or null,
 "budget_max": integer or null,
 "budget_min": integer or null
}
Notes:
- Infer from the WHOLE conversation, not just the last line.
- budget is in Egyptian Pounds (EGP): monthly amount for rent, total amount for sale.
- "area" is a place like "Sheikh Zayed" or "6th of October".
- Output JSON only. No explanation, no markdown."""

# ----------------------------------------------------------------------------
# 2) Broker persona — the system prompt for generating replies
# ----------------------------------------------------------------------------
BROKER_TEMPLATE = """You are {broker}, a senior property advisor at {brand}, a real-estate brokerage in Greater Cairo, Egypt (Sheikh Zayed, 6th of October and nearby areas).
Your job: understand what each client needs, present the best-matching properties from OUR current listings, and guide them toward booking a viewing.

LANGUAGE
- Reply ONLY in {language}.
- If Arabic: write in natural, polite Egyptian dialect (عامية مصرية محترمة) — the way a real Cairo broker talks.
- Keep messages short and easy to read on a phone. No walls of text.

TONE
- Formal but warm — professional and respectful, yet relaxed and human. Never stiff, never robotic, never pushy.
- You sound like a knowledgeable person who genuinely wants to help, not a sales script.

NON-NEGOTIABLE RULES
1. NEVER invent or guess a price, a property, a compound, an area, a size, or any fact. Use ONLY the entries in the "AVAILABLE MATCHES" block below. If something isn't listed there, say you'll check and get back to them — do not make it up.
2. Every property and every price you mention must come from AVAILABLE MATCHES.
3. If there are no matches, be honest about it and help the client adjust (budget, area, bedrooms, rent vs buy).

HOW YOU WORK
- Make sure you know the four essentials before pitching hard: budget, area, rent or buy, and number of bedrooms. Ask for whatever is missing — one or two friendly questions at a time, never an interrogation.
- Once you have matches, present 2-4 options. For each one give: the compound/name, a couple of quick facts (bedrooms, size, price), and ONE sharp reason it fits THIS client's stated needs.
- Use honest, gentle urgency: point out when a unit is well-priced or in a sought-after spot, and always offer the next step ("want me to arrange a viewing?"). Never use fake scarcity or pressure.
- End almost every reply with one easy next step — a question or an offer to set up a viewing.

Be human. Be honest. Help them find the right home.

{matches}"""


def _render_matches(matches: list[dict[str, Any]]) -> str:
    if not matches:
        return (
            "AVAILABLE MATCHES: (none match the current criteria — do not invent any; "
            "instead help the client adjust their budget / area / bedrooms / rent-or-buy.)"
        )
    lines = []
    for i, m in enumerate(matches, 1):
        price = listings_mod.price_str(m, "en")
        beds = m.get("bedrooms")
        beds_txt = "studio" if (m.get("type") == "studio" or beds == 0) else f"{beds} BR"
        lines.append(
            f"{i}. [{m.get('id')}] {m.get('compound_en')} — {m.get('area_en')} "
            f"| {m.get('purpose')} | {m.get('type')} | {beds_txt} / {m.get('bathrooms')} BA "
            f"| {m.get('size_sqm')} sqm | {price} | {m.get('finishing')}\n"
            f"   AR name: {m.get('compound_ar')} — {m.get('area_ar')}\n"
            f"   Selling points (EN): {', '.join(m.get('highlights_en', []))}\n"
            f"   Selling points (AR): {', '.join(m.get('highlights_ar', []))}\n"
            f"   Terms: {m.get('payment_plan_en', '-')}"
        )
    return "AVAILABLE MATCHES (talk about ONLY these; never invent others):\n" + "\n".join(lines)


def broker_system(language: str, matches: list[dict[str, Any]]) -> str:
    language_name = "Arabic (Egyptian dialect)" if language == "ar" else "English"
    return BROKER_TEMPLATE.format(
        broker=config.BROKER_NAME,
        brand=config.BRAND_NAME,
        language=language_name,
        matches=_render_matches(matches),
    )


# ----------------------------------------------------------------------------
# 3) Template fallback — used in preview mode (no AI engine) so the app is
#    always useful and always grounded in real prices.
# ----------------------------------------------------------------------------
ESSENTIALS = ("purpose", "budget_max", "area", "bedrooms")


def _missing(req: dict[str, Any]) -> list[str]:
    return [k for k in ESSENTIALS if not req.get(k)]


def template_reply(language: str, req: dict[str, Any], matches: list[dict[str, Any]]) -> str:
    ar = language == "ar"
    broker = config.BROKER_NAME

    if not matches:
        if ar:
            return (
                f"أهلاً! أنا {broker} من {config.BRAND_NAME}. "
                "للأسف مفيش عندي دلوقتي وحدة مطابقة بالظبط للي طلبته. "
                "تحب نوسّع البحث شوية في الميزانية أو المنطقة؟ "
                "قوللي ميزانيتك تقريبًا، إيجار ولا تمليك، وفي أنهي منطقة؟"
            )
        return (
            f"Hi! I'm {broker} from {config.BRAND_NAME}. "
            "I don't have an exact match for that right now. "
            "Want to widen the search a little on budget or area? "
            "Tell me your rough budget, rent or buy, and which area you prefer."
        )

    missing = _missing(req)
    if len(missing) >= 3:  # very early in the chat — ask before pitching hard
        if ar:
            return (
                f"أهلاً بيك! أنا {broker}، مستشار العقارات في {config.BRAND_NAME} 👋 "
                "عشان أجبلك أنسب اختيارات: ميزانيتك تقريبًا قد إيه؟ "
                "بتدوّر على إيجار ولا تمليك؟ وفي أنهي منطقة وكام غرفة؟"
            )
        return (
            f"Welcome! I'm {broker}, your property advisor at {config.BRAND_NAME} 👋 "
            "To pull the best options for you: what's your rough budget? "
            "Are you looking to rent or buy, in which area, and how many bedrooms?"
        )

    # We have matches — present them with their real prices.
    bullets = []
    for m in matches:
        price = listings_mod.price_str(m, "ar" if ar else "en")
        if ar:
            name = f"{m.get('compound_ar')} - {m.get('area_ar')}"
            hl = (m.get("highlights_ar") or [""])[0]
            beds = "استوديو" if m.get("type") == "studio" else f"{m.get('bedrooms')} غرف"
            bullets.append(f"• {name}: {beds}، {m.get('size_sqm')} م²، {price}. {hl}")
        else:
            name = f"{m.get('compound_en')} - {m.get('area_en')}"
            hl = (m.get("highlights_en") or [""])[0]
            beds = "studio" if m.get("type") == "studio" else f"{m.get('bedrooms')}-bed"
            bullets.append(f"• {name}: {beds}, {m.get('size_sqm')} sqm, {price}. {hl}")

    body = "\n".join(bullets)
    n = len(matches)
    if ar:
        head = "لقيت ليك وحدة ممكن تناسبك:" if n == 1 else f"لقيت ليك {n} وحدات ممكن تناسبك:"
        return (
            f"تمام! {head}\n{body}\n\n"
            "تحب أرتّبلك معاينة؟ ولو حابب أظبط البحث أكتر، قوللي تفاصيل أكتر."
        )
    head = "here's an option that could fit you:" if n == 1 else f"here are {n} options that could fit you:"
    return (
        f"Great — {head}\n{body}\n\n"
        "Want me to arrange a viewing for any of these? Or tell me more and I'll fine-tune the search."
    )
