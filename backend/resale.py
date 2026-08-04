"""Resale (secondary-market) units from resale_listings (RE/MAX +
PropertyFinder) as a chat source, so the broker can recommend a real ready
resale unit — distinct from the primary/new-launch catalog.
"""
from __future__ import annotations

from typing import Any

from . import config


def _to_listing(r: dict[str, Any]) -> dict[str, Any]:
    area = r.get("area") or ""
    region = r.get("region") or area
    src = r.get("source") or "resale"
    return {
        "id": "RS-" + str(r.get("id", ""))[:8],
        "market": "resale",
        "source": src,
        "purpose": r.get("purpose") or "sale",
        "type": r.get("type") or "apartment",
        "area_en": area,
        "area_ar": area,
        "compound_en": region,
        "compound_ar": region,
        "developer": None,
        "price": r.get("price"),
        "currency": "EGP",
        "bedrooms": r.get("bedrooms") or 0,
        "bathrooms": None,
        "size_sqm": r.get("size_sqm"),
        "finishing": None,
        "delivery": "Ready to move",  # resale = existing/ready
        "highlights_en": [f"Resale ({'RE/MAX' if src == 'remax' else 'PropertyFinder'})"],
        "highlights_ar": ["سوق ثانوي (وحدة جاهزة)"],
        "brochure_url": None,
        "images": [],
        "url": r.get("url"),
        "available": True,
    }


def search(req: dict[str, Any], n: int = 12) -> list[dict[str, Any]]:
    """Active resale listings matching the request (filtered slice)."""
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    try:
        import requests

        params: dict[str, str] = {
            "select": "id,source,purpose,type,area,region,price,size_sqm,bedrooms,url",
            "purpose": "eq.sale",
            "price": "gt.0",
            "size_sqm": "gt.0",
            "order": "fetched_at.desc",
            "limit": str(n),
        }
        if req.get("type"):
            params["type"] = f"eq.{req['type']}"
        if req.get("area"):
            params["area"] = f"ilike.*{req['area']}*"
        # Drop absurdly-cheap outliers (< half budget) so a mispriced row never
        # becomes the recommendation for a serious buyer.
        bmax = req.get("budget_max")
        if bmax:
            params["price"] = f"gte.{int(bmax) // 2}"
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/resale_listings",
            params=params,
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        return [_to_listing(x) for x in r.json()]
    except Exception:
        return []
