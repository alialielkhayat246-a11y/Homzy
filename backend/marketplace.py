"""Broker-posted listings (the marketplace side) as a search source for chat.

Reads the live Supabase `listings` table (status=active) so the AI advisor can
recommend units that brokers added in the app, alongside the byit catalog.
"""
from __future__ import annotations

from typing import Any

from . import config


def _to_listing(r: dict[str, Any]) -> dict[str, Any]:
    media = r.get("listing_media") or []
    images = [m.get("url") for m in media if m.get("url")]
    title = r.get("title") or "Listing"
    area = r.get("area") or ""
    return {
        "id": "MK-" + str(r.get("id", ""))[:8],
        "listing_id": r.get("id"),
        "purpose": r.get("purpose") or "sale",
        "type": r.get("type") or "apartment",
        "area_en": area,
        "area_ar": area,
        "compound_en": title,
        "compound_ar": title,
        "developer": None,
        "price": r.get("price"),
        "currency": "EGP",
        "bedrooms": r.get("bedrooms") or 0,
        "bathrooms": r.get("bathrooms"),
        "size_sqm": r.get("size_sqm"),
        "finishing": None,
        "delivery": "Ready to move",  # user listings are existing units
        "highlights_en": [h for h in [r.get("description")] if h],
        "highlights_ar": [h for h in [r.get("description")] if h],
        "images": images[:6],
        "cover_image": images[0] if images else None,
        "brochure_url": None,
        "address": r.get("address"),
        "lat": r.get("lat"),
        "lng": r.get("lng"),
        "source": "marketplace",
        "available": True,
    }


def search(req: dict[str, Any], n: int = 12) -> list[dict[str, Any]]:
    """Active marketplace listings matching the request (few rows, filtered)."""
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    try:
        import requests

        params: dict[str, str] = {
            "select": "id,title,description,purpose,type,price,area,address,"
                      "bedrooms,bathrooms,size_sqm,lat,lng,listing_media(url,sort)",
            "status": "eq.active",
            "limit": str(n),
            "order": "created_at.desc",
        }
        if req.get("purpose"):
            params["purpose"] = f"eq.{req['purpose']}"
        if req.get("type"):
            params["type"] = f"eq.{req['type']}"
        if req.get("area"):
            params["area"] = f"ilike.*{req['area']}*"
        if req.get("budget_max"):
            params["price"] = f"lte.{int(req['budget_max'] * 1.3)}"
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/listings",
            params=params,
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        return [_to_listing(x) for x in r.json()]
    except Exception:
        return []
