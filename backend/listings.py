"""Property inventory: loading, searching and formatting.

This is the single source of truth for prices. The LLM is never allowed to
invent a property or a price — it may only talk about what `search()` returns.
"""
from __future__ import annotations

import json
import os
import re
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


# ---------------------------------------------------------------------------
# Write side (Phase 2 admin panel)
#
# The JSON file stays the single source of truth. Every write validates the
# incoming data, mutates the in-memory cache, and persists atomically to disk
# so the broker's matching picks up edits without a restart.
# ---------------------------------------------------------------------------

PURPOSES = ("rent", "sale")
TYPES = ("apartment", "villa", "townhouse", "studio", "office")

# Fields the operator may set; everything else is rejected to keep the file clean.
_TEXT_FIELDS = (
    "area_en", "area_ar", "compound_en", "compound_ar",
    "finishing", "payment_plan_en", "payment_plan_ar",
)
_LIST_FIELDS = ("highlights_en", "highlights_ar")


class ListingError(ValueError):
    """Raised when an incoming listing fails validation."""


def _coerce_int(value: Any, field: str, *, minimum: int = 0) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError):
        raise ListingError(f"{field} must be a whole number")
    if n < minimum:
        raise ListingError(f"{field} must be {minimum} or more")
    return n


def validate(data: dict[str, Any], *, existing: dict[str, Any] | None = None) -> dict[str, Any]:
    """Validate + normalise an incoming listing into a clean stored record.

    `existing` (for an update) supplies the current values so partial edits
    keep untouched fields. Returns a brand-new dict; never mutates the input.
    """
    base: dict[str, Any] = dict(existing or {})
    base.update({k: v for k, v in data.items() if k != "id"})

    purpose = (base.get("purpose") or "").strip().lower()
    if purpose not in PURPOSES:
        raise ListingError(f"purpose must be one of {', '.join(PURPOSES)}")

    typ = (base.get("type") or "").strip().lower()
    if typ not in TYPES:
        raise ListingError(f"type must be one of {', '.join(TYPES)}")

    if not str(base.get("compound_en") or "").strip():
        raise ListingError("compound_en (the property/compound name) is required")

    price = _coerce_int(base.get("price"), "price", minimum=1)
    bedrooms = _coerce_int(base.get("bedrooms", 0), "bedrooms")
    bathrooms = _coerce_int(base.get("bathrooms", 1), "bathrooms")
    size_sqm = _coerce_int(base.get("size_sqm", 0), "size_sqm")

    out: dict[str, Any] = {
        "purpose": purpose,
        "type": typ,
        "price": price,
        "currency": "EGP",
        "price_period": "month" if purpose == "rent" else None,
        "bedrooms": bedrooms,
        "bathrooms": bathrooms,
        "size_sqm": size_sqm,
        "available": bool(base.get("available", True)),
    }
    for field in _TEXT_FIELDS:
        out[field] = str(base.get(field) or "").strip()
    for field in _LIST_FIELDS:
        raw = base.get(field) or []
        if isinstance(raw, str):  # accept newline/comma separated text from a form
            raw = [p.strip() for p in re.split(r"[\n,]", raw)]
        out[field] = [str(p).strip() for p in raw if str(p).strip()]
    return out


def next_id(purpose: str) -> str:
    """Generate the next sequential id, e.g. HZ-R05 (rent) or HZ-S03 (sale)."""
    prefix = "HZ-R" if purpose == "rent" else "HZ-S"
    nums = [
        int(m.group(1))
        for x in load()
        if (m := re.fullmatch(rf"{re.escape(prefix)}(\d+)", str(x.get("id", ""))))
    ]
    return f"{prefix}{(max(nums) + 1) if nums else 1:02d}"


def _save() -> None:
    """Persist the cache to disk atomically (write to a temp file, then replace)."""
    path = config.DATA_DIR / "listings.json"
    tmp = path.with_suffix(".json.tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(_CACHE, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def _index(listing_id: str) -> int:
    for i, x in enumerate(load()):
        if x.get("id") == listing_id:
            return i
    raise ListingError(f"no listing with id {listing_id!r}")


def add(data: dict[str, Any]) -> dict[str, Any]:
    """Validate, assign a fresh id, store and persist a new listing."""
    record = validate(data)
    record = {"id": next_id(record["purpose"]), **record}
    load().append(record)
    _save()
    return record


def update(listing_id: str, data: dict[str, Any]) -> dict[str, Any]:
    """Validate a (possibly partial) edit against the existing listing, persist."""
    i = _index(listing_id)
    current = load()[i]
    record = {"id": listing_id, **validate(data, existing=current)}
    load()[i] = record
    _save()
    return record


def delete(listing_id: str) -> None:
    """Remove a listing by id and persist."""
    i = _index(listing_id)
    del load()[i]
    _save()
