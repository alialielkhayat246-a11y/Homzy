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
