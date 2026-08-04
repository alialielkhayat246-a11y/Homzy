"""Resale price estimator (comparables / market approach).

We don't have historical resale transactions, so we estimate a fair price from
the live catalog: the median price-per-m² of comparable units (same area + type)
scaled by the unit's size, with small adjustments for finishing. It returns a
range plus the comparables it used, so the number is transparent, not a guess.

Feed real resale data later by inserting rows the same shape into a `resale`
source and blending it here.
"""
from __future__ import annotations

import statistics
from typing import Any

from . import config

# Finishing multipliers (relative to an average/unfinished baseline).
_FINISH_ADJ = {
    "fully_finished": 1.07,
    "fully finished": 1.07,
    "semi_finished": 1.0,
    "semi finished": 1.0,
    "core_shell": 0.93,
    "core & shell": 0.93,
    "core-shell": 0.93,
}


def _fetch(params: dict[str, str]) -> list[dict[str, Any]]:
    import requests

    r = requests.get(
        config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types",
        params=params,
        headers={"apikey": config.SUPABASE_KEY,
                 "Authorization": f"Bearer {config.SUPABASE_KEY}"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def _fetch_from(table: str, params: dict[str, str]) -> list[dict]:
    import requests

    r = requests.get(
        config.SUPABASE_URL.rstrip("/") + f"/rest/v1/{table}",
        params=params,
        headers={"apikey": config.SUPABASE_KEY,
                 "Authorization": f"Bearer {config.SUPABASE_KEY}"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def _resale_comps(area: str | None, type_: str | None,
                  source: str | None = None) -> list[dict]:
    """Secondary-market asking prices from one source (remax | propertyfinder),
    normalised to the common {price, size, name, area, type} comp shape."""
    base = {
        "select": "price,size_sqm,type,area,region",
        "purpose": "eq.sale",
        "price": "gt.0",
        "size_sqm": "gt.0",
        "limit": "400",
    }
    if source:
        base["source"] = f"eq.{source}"

    def run(with_area, with_type):
        p = dict(base)
        if with_type and type_:
            p["type"] = f"eq.{type_}"
        if with_area and area:
            p["area"] = f"ilike.*{area}*"
        try:
            return _fetch_from("resale_listings", p)
        except Exception:
            return []

    rows = run(True, True)
    if len(rows) < 5:
        rows = run(True, False) if area else run(False, True)
    return [{"price": r.get("price"), "size": r.get("size_sqm"),
             "name": r.get("region") or r.get("area"), "area": r.get("area"),
             "type": r.get("type")} for r in rows]


def _catalog_comps(area: str | None, type_: str | None) -> tuple[list[dict], str, bool]:
    """Primary-market catalog comps (fallback when resale is thin)."""
    base = {
        "select": "price_from,size_from,type,project:projects!inner(name,area)",
        "price_from": "gt.0", "size_from": "gt.0", "limit": "400",
    }

    def run(with_area, with_type):
        p = dict(base)
        if with_type and type_:
            p["type"] = f"eq.{type_}"
        if with_area and area:
            p["project.area"] = f"ilike.*{area}*"
        try:
            return _fetch_from("unit_types", p)
        except Exception:
            return []

    rows, scope, relaxed = run(True, True), "area+type", False
    if len(rows) < 5:
        rows, scope, relaxed = run(True, False), "area", True
    if len(rows) < 5:
        rows, scope, relaxed = run(False, True), "type", True
    return ([{"price": r.get("price_from"), "size": r.get("size_from"),
              "name": (r.get("project") or {}).get("name"),
              "area": (r.get("project") or {}).get("area"), "type": r.get("type")}
             for r in rows], scope, relaxed)


def _ppsqm(rows: list[dict]) -> list[float]:
    out = []
    for r in rows:
        try:
            p = float(r["price"]); s = float(r["size"])
            if p > 0 and s > 0:
                v = p / s
                if 1000 <= v <= 500000:  # sanity bounds (EGP/m²)
                    out.append(v)
        except (TypeError, ValueError, KeyError):
            continue
    return out


def _trim(values: list[float]) -> list[float]:
    """Drop the top/bottom 10% to reduce outlier pull."""
    if len(values) < 10:
        return values
    v = sorted(values)
    k = max(1, len(v) // 10)
    return v[k:-k]


def median_ppsqm(area: str | None, type_: str | None,
                 market: str = "resale") -> float | None:
    """Median price/m² for an area+type in a given market — resale (RE/MAX +
    PropertyFinder) or primary (the developer catalog). Used to position a
    recommended unit against ITS OWN market for honest persuasion."""
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return None
    if market == "primary":
        rows, _, _ = _catalog_comps(area, type_)
        pp = _trim(_ppsqm(rows))
        return statistics.median(pp) if len(pp) >= 3 else None
    for src in ("remax", "propertyfinder"):
        pp = _trim(_ppsqm(_resale_comps(area, type_, src)))
        if len(pp) >= 5:
            return statistics.median(pp)
    return None


def value_note(area: str | None, type_: str | None, price, size,
               market: str = "resale") -> str | None:
    """A short, honest market-position note comparing a unit to its own market
    ('~15% below the area resale average'), or None when we can't compare."""
    try:
        price = float(price); size = float(size)
    except (TypeError, ValueError):
        return None
    if price <= 0 or size <= 0:
        return None
    med = median_ppsqm(area, type_, market)
    if not med:
        return None
    ratio = (price / size) / med
    if ratio < 0.6 or ratio > 1.6:
        return None  # too far from market to be a credible comparison (likely an outlier)
    label = "resale" if market == "resale" else "new-launch"
    if ratio <= 0.9:
        return f"about {round((1 - ratio) * 100)}% below the area {label} average price/m² — strong value"
    if ratio >= 1.12:
        return f"about {round((ratio - 1) * 100)}% above the area {label} average price/m² (premium)"
    return f"in line with the area {label} average price/m²"


def estimate(area: str | None, type_: str | None, size: float,
             finishing: str | None = None) -> dict[str, Any]:
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return {"ok": False, "error": "catalog not configured"}
    if not size or size <= 0:
        return {"ok": False, "error": "size (m²) is required"}

    # Source priority: RE/MAX (our own, the base) -> PropertyFinder (monthly
    # review / fallback) -> primary catalog. Use the first with enough comps.
    rows, ppsqm, source, scope, relaxed = [], [], "catalog", "area+type", False
    for src in ("remax", "propertyfinder"):
        cand = _resale_comps(area, type_, src)
        pp = _trim(_ppsqm(cand))
        if len(pp) >= 5:
            rows, ppsqm, source = cand, pp, src
            break
    if not ppsqm:
        rows, scope, relaxed = _catalog_comps(area, type_)
        ppsqm = _trim(_ppsqm(rows))
        source = "catalog"

    if len(ppsqm) < 3:
        return {"ok": False, "error": "not enough comparable units to estimate"}

    median = statistics.median(ppsqm)
    adj = _FINISH_ADJ.get((finishing or "").strip().lower(), 1.0)
    est = size * median * adj

    # Range from the middle of the comparable spread (35th–65th pct), widened a
    # little, so it reflects the real market band — not a flat ±%.
    lo_ppsqm = statistics.quantiles(ppsqm, n=20)[6] if len(ppsqm) >= 20 else min(ppsqm)
    hi_ppsqm = statistics.quantiles(ppsqm, n=20)[12] if len(ppsqm) >= 20 else max(ppsqm)
    low = min(est * 0.9, size * lo_ppsqm * adj)
    high = max(est * 1.1, size * hi_ppsqm * adj)

    # a few example comparables (closest ppsqm to the median)
    def _pps(r):
        try:
            return float(r["price"]) / float(r["size"])
        except (TypeError, ValueError, ZeroDivisionError):
            return 1e18

    comps = []
    for r in sorted(rows, key=lambda r: abs(_pps(r) - median))[:5]:
        try:
            p = float(r["price"]); s = float(r["size"])
        except (TypeError, ValueError):
            continue
        if s <= 0:
            continue
        comps.append({
            "name": r.get("name"),
            "area": r.get("area"),
            "type": r.get("type"),
            "price": round(p),
            "size": round(s),
            "ppsqm": round(p / s),
        })

    return {
        "ok": True,
        "estimate": round(est),
        "low": round(low),
        "high": round(high),
        "ppsqm": round(median),
        "n_comps": len(ppsqm),
        "source": source,        # resale | catalog
        "scope": scope,
        "relaxed": relaxed,
        "comps": comps,
    }
