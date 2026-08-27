"""Egyptian area names, bilingual — one source of truth for both extracting a
client's area and matching it against a listing (whose area may be stored in
Arabic or English). This is what lets "New Cairo" match a listing in "التجمع".
"""
from __future__ import annotations

from typing import Any

_AR_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")

# Canonical area -> aliases (English + Arabic). Specific names first so e.g.
# "New Cairo" wins over a bare "Cairo".
AREA_ALIASES: dict[str, list[str]] = {
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
    "Dreamland": ["dreamland", "dream land", "دريم لاند"],
    "New Heliopolis": ["new heliopolis", "هليوبوليس الجديدة", "مصر الجديدة الجديدة"],
}


# Short, factual profile per canonical area — what it's known for and who it
# suits — so the advisor can speak about a place, not just name it. Kept concise
# (the model expands naturally). AR is primary; EN mirrors it.
AREA_PROFILES: dict[str, dict[str, str]] = {
    "New Capital": {
        "ar": "العاصمة الإدارية الجديدة: مدينة حكومية حديثة شرق القاهرة، أسعار دخول أرخص من التجمع مع بنية تحتية جديدة ومخططة، الحي الحكومي والمالي والداون تاون. مناسبة للمستثمر وطالب الأوف بلان بتقسيط مريح على المطوّر؛ التسليم غالبًا بعد سنوات.",
        "en": "New Administrative Capital: a new, planned government city east of Cairo — lower entry prices than New Cairo, brand-new infrastructure, government/financial district. Best for investors and off-plan buyers wanting long developer installments; delivery is usually a few years out.",
    },
    "New Cairo": {
        "ar": "القاهرة الجديدة / التجمع الخامس: أرقى مناطق شرق القاهرة وأكثرها طلبًا، خدمات ومدارس دولية وجامعات ومولات، سيولة إعادة بيع عالية وثبات في القيمة. مناسبة للسكن العائلي الراقي والمستثمر اللي عايز أصل آمن. أسعارها أعلى من العاصمة والمستقبل.",
        "en": "New Cairo / Fifth Settlement: the most established and in-demand east-Cairo district — international schools, universities, malls, strong resale liquidity and value retention. Best for premium family living and safe-asset investors. Priced above the New Capital and Mostakbal.",
    },
    "Mostakbal City": {
        "ar": "مدينة المستقبل: امتداد شرقي واعد جنب التجمع والعاصمة، مشاريع كبرى جديدة (زي بلوم فيلدز/سيليا) بأسعار أقل من التجمع وإمكانية نمو عالية. مناسبة للمشتري اللي عايز موقع صاعد بسعر معقول.",
        "en": "Mostakbal (Future) City: a promising eastern corridor between New Cairo and the Capital — major new projects at prices below New Cairo with strong upside. Good for buyers wanting an emerging location at a reasonable price.",
    },
    "Sheikh Zayed": {
        "ar": "الشيخ زايد: غرب القاهرة الراقي، هادي وأخضر وقريب من مولات كبرى (أركان/مول مصر) وميدان جهينة، جالية وخدمات ممتازة. مناسب للعائلات اللي بتفضّل الغرب والفلل والتاون هاوس. سيولة إعادة بيع كويسة.",
        "en": "Sheikh Zayed: upscale west Cairo — quiet, green, near major malls (Arkan, Mall of Egypt), excellent services. Ideal for families who prefer the west and villas/townhouses. Good resale liquidity.",
    },
    "New Zayed": {
        "ar": "الشيخ زايد الجديدة: امتداد زايد الأحدث، مشاريع مطوّرين كبار جديدة بأسعار دخول أقل من زايد القديمة مع نفس روح الغرب الراقي. مناسبة لطالب الأوف بلان في الغرب.",
        "en": "New Zayed: the newest extension of Sheikh Zayed — fresh top-developer projects at lower entry prices than old Zayed, same upscale west character. Great for off-plan buyers on the west side.",
    },
    "6th of October": {
        "ar": "السادس من أكتوبر: مدينة غرب القاهرة متكاملة ومتنوعة الأسعار، مناسبة للميزانيات المتوسطة والباحث عن سكن جاهز أو تقسيط، قريبة من زايد والجامعات والصناعة. تنوع كبير بين اقتصادي وراقي.",
        "en": "6th of October: a self-contained west-Cairo city with a wide price range — good for mid budgets and buyers wanting ready units or installments, near Zayed, universities and industry.",
    },
    "North Coast": {
        "ar": "الساحل الشمالي: وجهة المصايف الصيفية على المتوسط، شاليهات وفلل في قرى مسوّرة (خصوصًا الكيلومترات المرتفعة ورأس الحكمة). منتج ثانِ سكن/استثمار موسمي أكتر من سكن دائم؛ الأسعار تتفاوت جدًا حسب القرية والموقع من البحر.",
        "en": "North Coast (Sahel): the summer Mediterranean destination — chalets and villas in gated resorts (especially the higher KMs and Ras El Hekma). A second-home / seasonal-investment product more than year-round living; prices vary widely by resort and distance from the sea.",
    },
    "Ras El Hekma": {
        "ar": "رأس الحكمة: أهم منطقة صاعدة في الساحل بعد صفقة الاستثمار الإماراتية الضخمة، توقعات نمو قوية جدًا للقيمة، مشاريع نجوم ومراسي جديدة. مناسبة للمستثمر بعيد المدى في الساحل.",
        "en": "Ras El Hekma: the hottest emerging North-Coast zone after the large UAE investment deal — very strong value-growth expectations, flagship new resorts. Best for long-horizon coastal investors.",
    },
    "New Alamein": {
        "ar": "العلمين الجديدة: مدينة ساحلية بأبراج على البحر ونشاط على مدار السنة، رؤية دولة لمدينة رابعة جيل ساحلية. مناسبة لمن يريد ساحل بطابع مدينة لا قرية مصيف.",
        "en": "New Alamein: a coastal city of seafront towers with year-round activity — a state-backed fourth-generation coastal city. For buyers wanting a coastal city rather than a seasonal resort.",
    },
    "Ain Sokhna": {
        "ar": "العين السخنة: أقرب بحر للقاهرة (ساعة تقريبًا)، مصايف شتوية وصيفية على البحر الأحمر، شاليهات وفلل. مناسبة لثاني سكن قريب أو استثمار إيجاري موسمي.",
        "en": "Ain Sokhna: the closest sea to Cairo (~1 hour) — Red-Sea resorts usable most of the year, chalets and villas. Good for a nearby second home or seasonal rental investment.",
    },
    "Madinaty": {
        "ar": "مدينتي: مدينة متكاملة كبيرة لطلعت مصطفى شرق القاهرة، خدمات ناضجة وسيولة عالية وإدارة قوية. مناسبة للعائلات الباحثة عن مجتمع متكامل جاهز.",
        "en": "Madinaty: a large, mature master-planned city by TMG east of Cairo — established services, high liquidity, strong management. Ideal for families wanting a complete, ready community.",
    },
    "El Shorouk": {
        "ar": "الشروق: مدينة شرقية هادية وخضراء بأسعار في المتناول، فلل ومساكن عائلية، قريبة من العبور والعاصمة. مناسبة للميزانيات المتوسطة والسكن الهادي.",
        "en": "El Shorouk: a quiet, green eastern city with affordable prices — villas and family housing, near Obour and the Capital. Good for mid budgets and calm living.",
    },
    "New Heliopolis": {
        "ar": "هليوبوليس الجديدة: امتداد شرقي على طريق السويس/العاصمة، مشاريع حديثة بموقع وسط بين مصر الجديدة والعاصمة. مناسبة لمن يعمل في مصر الجديدة ويريد وحدة جديدة قريبة.",
        "en": "New Heliopolis: an eastern extension toward the Suez road / Capital — modern projects midway between Heliopolis and the Capital. Suits those working in Heliopolis who want a new nearby unit.",
    },
}


def profile(area: str) -> dict[str, str] | None:
    """Return the {ar,en} profile for a raw area string (resolved to canonical),
    or None if we don't have one for it."""
    if not area:
        return None
    canonical = extract(str(area)) or (str(area) if str(area) in AREA_PROFILES else None)
    if canonical and canonical in AREA_PROFILES:
        return AREA_PROFILES[canonical]
    return None


def _norm(text: str) -> str:
    return (text or "").translate(_AR_DIGITS)


def extract(text: str) -> str | None:
    """Return the canonical area mentioned in free text, or None."""
    low = _norm(text).lower()
    raw = _norm(text)
    for canonical, aliases in AREA_ALIASES.items():
        for a in aliases:
            if a.isascii():
                if a in low:
                    return canonical
            elif a in raw:
                return canonical
    return None


def candidates(area: str) -> list[str]:
    """All the strings that mean the same place as `area` (so a canonical
    English name also matches Arabic aliases and vice-versa)."""
    if not area:
        return []
    low = str(area).lower()
    out = {str(area)}
    for canonical, aliases in AREA_ALIASES.items():
        group = [canonical] + aliases
        if str(area) == canonical or low in [x.lower() for x in aliases] \
                or any(str(area) in a or a in str(area) for a in aliases):
            out.update(group)
    return list(out)


def matches(listing: dict[str, Any], area: str) -> bool:
    """True if the listing sits in the requested area (bilingual)."""
    hay_en = (str(listing.get("area_en", "")) + " "
              + str(listing.get("compound_en", ""))).lower()
    hay_ar = (str(listing.get("area_ar", "")) + " "
              + str(listing.get("compound_ar", "")))
    for c in candidates(area):
        if c.isascii():
            if c.lower() in hay_en:
                return True
        elif c in hay_ar:
            return True
    return False
