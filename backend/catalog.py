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

_OVERVIEW: str | None = None
_OVERVIEW_AT = 0.0


def market_overview() -> str:
    """A compact snapshot of what Homzy actually has (areas + counts + types +
    a payment-plan note), injected into the chat so the assistant is aware of the
    whole catalog, not just the few matched units. Cached (10 min)."""
    global _OVERVIEW, _OVERVIEW_AT
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return ""
    now = time.time()
    if _OVERVIEW is not None and now - _OVERVIEW_AT < 600:
        return _OVERVIEW
    try:
        import requests

        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/v_city_counts",
            params={"select": "area,projects", "order": "projects.desc", "limit": "40"},
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        rows = [x for x in r.json() if x.get("area")]
        areas = "، ".join(f"{x['area']} ({x.get('projects') or 0})" for x in rows[:32])
        _OVERVIEW = (
            "WHAT HOMZY COVERS (be aware of the whole catalog, not only the matches below):\n"
            f"- Areas we have inventory in (with project counts): {areas}.\n"
            "- Property types: mostly apartments/studios, plus other unit types where the "
            "developer offers them.\n"
            "- Payment plans differ per unit — the real down payment, installment years and "
            "delivery for each option are in AVAILABLE MATCHES; quote those, never a generic plan.\n"
            "If the client names an area or type we don't have a match for right now, say so "
            "honestly and offer the closest available option."
        )
        _OVERVIEW_AT = now
        return _OVERVIEW
    except Exception:
        return _OVERVIEW or ""


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
        "market": "primary",   # new-launch / developer
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
        # Budget's UPPER side is a ranking signal (listings._score), not a hard
        # cut — so we always surface the closest options instead of "no match".
        # But drop absurdly-cheap outliers (< half budget) so we never recommend
        # a mispriced/tiny unit to a serious buyer.
        bmax = req.get("budget_max")
        if bmax:
            params["price_from"] = f"gte.{int(bmax) // 2}"
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


_DEV_CACHE: dict[str, list[str]] = {}


def developer_projects(developer: str | None, exclude: str | None = None,
                       limit: int = 6) -> list[str]:
    """Other projects by the same developer — "Name (Area)" strings — so the
    advisor can speak to the developer's wider portfolio. Cached per developer."""
    if not developer or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    key = developer.strip().lower()
    if key in _DEV_CACHE:
        rows = _DEV_CACHE[key]
    else:
        try:
            import requests

            r = requests.get(
                config.SUPABASE_URL.rstrip("/") + "/rest/v1/projects",
                params={
                    "select": "name,name_ar,area,developer:developers!inner(name)",
                    "developer.name": f"eq.{developer}",
                    "order": "updated_at.desc",
                    "limit": "40",
                },
                headers={"apikey": config.SUPABASE_KEY,
                         "Authorization": f"Bearer {config.SUPABASE_KEY}"},
                timeout=8,
            )
            r.raise_for_status()
            seen: set[str] = set()
            rows = []
            for p in r.json():
                nm = (p.get("name") or p.get("name_ar") or "").strip()
                if not nm or nm.lower() in seen:
                    continue
                seen.add(nm.lower())
                area = (p.get("area") or "").strip()
                rows.append(f"{nm} ({area})" if area else nm)
            _DEV_CACHE[key] = rows
        except Exception:
            return []
    ex = (exclude or "").strip().lower()
    out = [x for x in rows if not ex or not x.lower().startswith(ex)]
    return out[:limit]


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
