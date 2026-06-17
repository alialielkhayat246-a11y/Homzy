"""Property inventory: loading, searching and formatting.

This is the single source of truth for prices. The LLM is never allowed to
invent a property or a price — it may only talk about what `search()` returns.
"""
from __future__ import annotations

import json
from typing import Any

from . import config

_CACHE: list[dict[str, Any]] | None = None


def load() -> list[dict[str, Any]]:
    """Load listings from data/listings.json (cached)."""
    global _CACHE
    if _CACHE is None:
        path = config.DATA_DIR / "listings.json"
        with open(path, "r", encoding="utf-8") as fh:
            _CACHE = json.load(fh)
    return _CACHE


def reload() -> list[dict[str, Any]]:
    """Force a re-read from disk (used after the operator edits listings)."""
    global _CACHE
    _CACHE = None
    return load()


def price_str(listing: dict[str, Any], lang: str = "en") -> str:
    """Human-readable price, grounded in the listing's real numbers."""
    amount = listing.get("price")
    if amount is None:
        return "—"
    currency = "ج.م" if lang == "ar" else "EGP"
    money = f"{amount:,.0f} {currency}" if lang == "ar" else f"{currency} {amount:,.0f}"
    if listing.get("purpose") == "rent":
        per = "/شهر" if lang == "ar" else " / month"
        money += per
    return money


def _score(listing: dict[str, Any], budget_max, bedrooms) -> float:
    """Lower is better. Ranks by budget fit, then bedroom closeness."""
    s = 0.0
    price = listing.get("price") or 0
    if budget_max:
        if price > budget_max:
            s += (price - budget_max) / max(budget_max, 1) * 5.0  # over budget = bad
        s += abs(price - budget_max) / max(budget_max, 1) * 0.2
    if bedrooms is not None:
        s += abs(int(listing.get("bedrooms", 0)) - int(bedrooms)) * 1.5
    return s


def search(req: dict[str, Any], n: int = 4) -> list[dict[str, Any]]:
    """Return up to `n` listings that best match the requirements.

    Hard filters (purpose) are strict. Softer filters (type, area) relax if
    they would otherwise return nothing, so we always offer the client options
    when any exist — while budget/bedroom fit is handled by ranking, not
    exclusion, so 'closest matches' surface honestly.
    """
    items = [x for x in load() if x.get("available", True)]

    purpose = req.get("purpose")
    if purpose:
        items = [x for x in items if x.get("purpose") == purpose]

    typ = req.get("type")
    if typ:
        filtered = [x for x in items if x.get("type") == typ]
        if filtered:
            items = filtered

    area = req.get("area")
    if area:
        a_low = str(area).lower()
        filtered = [
            x for x in items
            if a_low in x.get("area_en", "").lower()
            or a_low in x.get("compound_en", "").lower()
            or str(area) in x.get("area_ar", "")
            or str(area) in x.get("compound_ar", "")
        ]
        if filtered:
            items = filtered

    budget_max = req.get("budget_max")
    bedrooms = req.get("bedrooms")
    items = sorted(items, key=lambda x: _score(x, budget_max, bedrooms))
    return items[:n]


def public(listing: dict[str, Any]) -> dict[str, Any]:
    """Trimmed view for the UI (e.g. optional listing cards)."""
    return {
        "id": listing.get("id"),
        "compound": listing.get("compound_en"),
        "compound_ar": listing.get("compound_ar"),
        "area": listing.get("area_en"),
        "area_ar": listing.get("area_ar"),
        "purpose": listing.get("purpose"),
        "type": listing.get("type"),
        "bedrooms": listing.get("bedrooms"),
        "size_sqm": listing.get("size_sqm"),
        "price_en": price_str(listing, "en"),
        "price_ar": price_str(listing, "ar"),
    }
