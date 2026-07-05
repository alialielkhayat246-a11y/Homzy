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
BROKER_TEMPLATE = """You are {broker}, a senior property advisor at {brand}. You cover real estate all over Egypt — New Cairo, Sheikh Zayed, 6th of October, the New Capital, North Coast, and more.
Your job: understand exactly what the client needs, then recommend ONE property that fits — and hand them its brochure and photos.

LANGUAGE
- Reply ONLY in {language}.
- If Arabic: natural, polite Egyptian dialect (عامية مصرية محترمة) — the way a real Cairo broker talks.
- Keep messages short and easy to read on a phone. No walls of text.

TONE
- Formal but warm — professional, respectful, relaxed and human. Never stiff, robotic, or pushy.

NON-NEGOTIABLE RULES
1. NEVER invent or guess a price, property, compound, area, size, developer, delivery date or payment plan. Use ONLY the entries in "AVAILABLE MATCHES" below. If a detail isn't there, say you'll check — never make it up.
2. Every property and number you mention must come from AVAILABLE MATCHES.

GATHER FIRST — before recommending anything, make sure you know ALL FIVE:
  1. rent or buy
  2. budget (roughly)
  3. area / location they want
  4. number of bedrooms
  5. delivery timing — do they need to move in NOW (ready-to-move), or are they fine waiting 2-3 years?
Ask for whatever is still missing — one or two friendly questions at a time, never an interrogation. Do NOT recommend a unit until you have all five.

THEN RECOMMEND — once you know all five:
- Recommend EXACTLY ONE property: the FIRST entry in AVAILABLE MATCHES (it is the best fit). Do not list several — one clear recommendation.
- Present: the compound/name and its developer, the quick facts (bedrooms, size, price), and — when the data has them — delivery, down payment, and installment years / payment plan. Add ONE sharp reason it fits THIS client's stated needs.
- Tell the client you're sending the brochure and the unit's photos right below (the app attaches them automatically — do NOT paste any URLs or links).
- You know the developer and project details (about / track record / description) — if the client asks about the developer or project, answer from the data.
- If the client isn't convinced, ask what to change (budget, area, timing…) and recommend a different single unit next.

If there are NO matches, be honest and help them adjust (budget, area, bedrooms, rent vs buy, timing).
End almost every reply with one easy next step — a question or an offer to arrange a viewing.

Be human. Be honest. Recommend the ONE right home.

{matches}"""


def _render_matches(matches: list[dict[str, Any]]) -> str:
    if not matches:
        return (
            "AVAILABLE MATCHES: (none match the current criteria — do not invent any; "
            "instead help the client adjust their budget / area / bedrooms / rent-or-buy / timing.)"
        )
    lines = []
    for i, m in enumerate(matches, 1):
        price = listings_mod.price_str(m, "en")
        beds = m.get("bedrooms")
        beds_txt = "studio" if (m.get("type") == "studio" or beds == 0) else f"{beds} BR"
        dev = m.get("developer")
        dev_txt = f" | by {dev}" if dev else ""
        tag = "  <-- RECOMMEND THIS ONE" if i == 1 else ""
        has_media = []
        if m.get("brochure_url"):
            has_media.append("brochure")
        if m.get("images"):
            has_media.append(f"{len(m.get('images'))} photos")
        media_txt = (", ".join(has_media)) or "none"
        about = (m.get("developer_about") or "").strip()
        track = (m.get("developer_track") or "").strip()
        dev_info = " ".join(x for x in (about, track) if x)[:300]
        lines.append(
            f"{i}. [{m.get('id')}] {m.get('compound_en')} — {m.get('area_en')}{dev_txt}{tag}\n"
            f"   {m.get('purpose')} | {m.get('type')} | {beds_txt} "
            f"| {m.get('size_sqm')} sqm | {price} | finishing: {m.get('finishing') or '-'}\n"
            f"   AR name: {m.get('compound_ar')} — {m.get('area_ar')}\n"
            f"   Delivery: {m.get('delivery') or '-'} | Down payment: {m.get('down_payment') or '-'} "
            f"| Installments: {m.get('installment_years') or '-'} years\n"
            f"   Payment plan: {m.get('payment_plan_en') or '-'}\n"
            f"   Attached to the client: {media_txt}\n"
            f"   Developer/project info: {dev_info or '-'}"
        )
    return ("AVAILABLE MATCHES (talk about ONLY these; recommend the FIRST one; "
            "never invent others):\n" + "\n".join(lines))


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
ESSENTIALS = ("purpose", "budget_max", "area", "bedrooms", "delivery_pref")

# What to ask for each still-missing essential (bilingual, short).
_ASK = {
    "purpose": ("إيجار ولا تمليك؟", "rent or buy?"),
    "budget_max": ("ميزانيتك تقريبًا قد إيه؟", "what's your rough budget?"),
    "area": ("في أنهي منطقة؟", "which area?"),
    "bedrooms": ("كام غرفة؟", "how many bedrooms?"),
    "delivery_pref": ("محتاج تستلم دلوقتي ولا عادي بعد سنتين-تلاتة؟",
                      "do you need to move in now, or is 2-3 years ok?"),
}


def _missing(req: dict[str, Any]) -> list[str]:
    return [k for k in ESSENTIALS if not req.get(k)]


def template_reply(language: str, req: dict[str, Any], matches: list[dict[str, Any]]) -> str:
    ar = language == "ar"
    broker = config.BROKER_NAME
    missing = _missing(req)

    # Still gathering — ask for what's missing (one short line), don't pitch yet.
    if missing:
        qs = " ".join(_ASK[k][0 if ar else 1] for k in missing[:3])
        if ar:
            return (f"أهلاً بيك! أنا {broker} من {config.BRAND_NAME} 👋 "
                    f"عشان أرشّحلك أنسب وحدة: {qs}")
        return (f"Welcome! I'm {broker} from {config.BRAND_NAME} 👋 "
                f"To recommend the best fit: {qs}")

    if not matches:
        if ar:
            return ("للأسف مفيش عندي دلوقتي وحدة مطابقة بالظبط. "
                    "تحب نوسّع الميزانية أو نغيّر المنطقة شوية؟")
        return ("I don't have an exact match right now. "
                "Want to widen the budget or try a nearby area?")

    # All five gathered — recommend exactly ONE (the best match).
    m = matches[0]
    price = listings_mod.price_str(m, "ar" if ar else "en")
    if ar:
        name = f"{m.get('compound_ar')} - {m.get('area_ar')}"
        beds = "استوديو" if m.get("type") == "studio" else f"{m.get('bedrooms')} غرف"
        dev = f" من {m.get('developer')}" if m.get("developer") else ""
        pay = m.get("payment_plan_en")
        pay_line = f"\nخطة الدفع: {pay}" if pay else ""
        return (f"تمام، أنسب وحدة ليك:\n"
                f"🏠 {name}{dev}\n{beds} · {m.get('size_sqm')} م² · {price}{pay_line}\n\n"
                "بعتلك البروشور وصور الوحدة تحت 👇 تحب أرتّبلك معاينة؟")
    name = f"{m.get('compound_en')} - {m.get('area_en')}"
    beds = "studio" if m.get("type") == "studio" else f"{m.get('bedrooms')}-bed"
    dev = f" by {m.get('developer')}" if m.get("developer") else ""
    pay = m.get("payment_plan_en")
    pay_line = f"\nPayment: {pay}" if pay else ""
    return (f"Great — here's the best fit for you:\n"
            f"🏠 {name}{dev}\n{beds} · {m.get('size_sqm')} sqm · {price}{pay_line}\n\n"
            "I've sent the brochure and the unit's photos below 👇 Want me to arrange a viewing?")
