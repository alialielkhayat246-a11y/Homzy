"""Pull the developers/projects/unit-types catalog from Supabase and expose it
to the broker as listing rows, so Homzy recommends real projects in chat.

Any data added to the Supabase catalog (e.g. from WhatsApp ingestion) flows
into the chat automatically — the backend just reads it here (cached briefly).
"""
from __future__ import annotations

import time
from typing import Any

from . import config

_CACHE: list[dict[str, Any]] | None = None
_CACHE_AT = 0.0
_TTL = 300  # seconds


def _to_listing(u: dict[str, Any]) -> dict[str, Any]:
    proj = u.get("project") or {}
    dev = proj.get("developer") or {}
    price = u.get("price_from") or u.get("price_to")
    size = u.get("size_from") or u.get("size_to")
    hl = [h for h in (proj.get("description"), u.get("payment_plan")) if h]
    name = proj.get("name") or "Project"
    name_ar = proj.get("name_ar") or name
    media = proj.get("project_media") or []
    brochure = next(
        (m.get("url") for m in media if m.get("kind") == "brochure" and m.get("url")),
        None)
    images = [m.get("url") for m in media if m.get("kind") == "image" and m.get("url")]
    cover = proj.get("cover_image_url")
    if cover:
        images = [cover] + [i for i in images if i != cover]
    return {
        "id": "TC-" + str(u.get("id", ""))[:8],
        "project_id": proj.get("id"),
        "purpose": "sale",
        "type": u.get("type") or "apartment",
        "area_en": proj.get("area") or "",
        "area_ar": proj.get("area") or "",
        "compound_en": name,
        "compound_ar": name_ar,
        "developer": dev.get("name"),
        "developer_phone": dev.get("phone"),
        "developer_about": dev.get("about"),
        "developer_track": dev.get("track_record"),
        "price": price,
        "currency": "EGP",
        "price_period": None,
        "bedrooms": u.get("bedrooms") or 0,
        "bathrooms": None,
        "size_sqm": size,
        "finishing": u.get("finishing"),
        "highlights_en": hl,
        "highlights_ar": hl,
        "payment_plan_en": u.get("payment_plan"),
        "payment_plan_ar": u.get("payment_plan"),
        "down_payment": u.get("down_payment"),
        "installment_years": u.get("installment_years"),
        "delivery": u.get("delivery"),
        "brochure_url": brochure,
        "images": images[:6],
        "cover_image": cover or (images[0] if images else None),
        "source": "catalog",
        "available": True,
    }


_SELECT = ("id,type,bedrooms,size_from,size_to,price_from,price_to,down_payment,"
           "installment_years,payment_plan,finishing,delivery,"
           "project:projects!inner(id,name,name_ar,area,description,cover_image_url,"
           "project_media(kind,url),"
           "developer:developers(name,phone,about,track_record))")


def search(req: dict[str, Any], n: int = 24) -> list[dict[str, Any]]:
    """Query the catalog for units matching the request (fast: fetches only a
    handful of rows instead of the whole catalog). Catalog is primary-market
    'sale', so returns nothing for rent requests."""
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    if req.get("purpose") == "rent":
        return []
    try:
        import requests

        params: dict[str, str] = {
            "select": _SELECT,
            "limit": str(n),
            "order": "price_from.asc.nullslast",
        }
        # Area is matched (and relaxed) in Python via the shared alias helper,
        # so a request in an area with no stock still surfaces the same type
        # elsewhere instead of silently returning nothing.
        if req.get("type"):
            params["type"] = f"eq.{req['type']}"
        if req.get("budget_max"):
            params["price_from"] = f"lte.{int(req['budget_max'] * 1.3)}"
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types",
            params=params,
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        return [_to_listing(x) for x in r.json()]
    except Exception:
        return []


def listings() -> list[dict[str, Any]]:
    """Catalog unit-types as listing rows (cached). Empty if not configured."""
    global _CACHE, _CACHE_AT
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    now = time.time()
    if _CACHE is not None and now - _CACHE_AT < _TTL:
        return _CACHE
    try:
        import requests

        url = config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types"
        select = ("id,type,bedrooms,size_from,size_to,price_from,price_to,"
                  "down_payment,installment_years,payment_plan,finishing,delivery,"
                  "project:projects(name,area,description,developer:developers(name))")
        r = requests.get(
            url,
            params={"select": select},
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=10,
        )
        r.raise_for_status()
        out = [_to_listing(x) for x in r.json()]
        _CACHE, _CACHE_AT = out, now
        return out
    except Exception:
        return _CACHE or []
