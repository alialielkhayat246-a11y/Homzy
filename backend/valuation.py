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


def _comps(area: str | None, type_: str | None) -> tuple[list[dict], str, bool]:
    """Return (rows, scope_label, relaxed). Relaxes area→type-only when thin."""
    base = {
        "select": "price_from,size_from,type,"
                  "project:projects!inner(name,area)",
        "price_from": "gt.0",
        "size_from": "gt.0",
        "limit": "400",
    }

    def run(with_area: bool, with_type: bool):
        p = dict(base)
        if with_type and type_:
            p["type"] = f"eq.{type_}"
        if with_area and area:
            p["project.area"] = f"ilike.*{area}*"
        try:
            return _fetch(p)
        except Exception:
            return []

    rows = run(True, True)
    if len(rows) >= 5:
        return rows, "area+type", False
    # relax: same area, any type
    rows = run(True, False)
    if len(rows) >= 5:
        return rows, "area", True
    # relax: same type, any area
    rows = run(False, True)
    return rows, "type", True


def _ppsqm(rows: list[dict]) -> list[float]:
    out = []
    for r in rows:
        try:
            p = float(r["price_from"]); s = float(r["size_from"])
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


def estimate(area: str | None, type_: str | None, size: float,
             finishing: str | None = None) -> dict[str, Any]:
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return {"ok": False, "error": "catalog not configured"}
    if not size or size <= 0:
        return {"ok": False, "error": "size (m²) is required"}

    rows, scope, relaxed = _comps(area, type_)
    ppsqm = _trim(_ppsqm(rows))
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
    scored = sorted(rows, key=lambda r: abs(
        (float(r["price_from"]) / float(r["size_from"])) - median)
        if r.get("size_from") else 1e18)
    comps = []
    for r in scored[:5]:
        proj = r.get("project") or {}
        try:
            p = float(r["price_from"]); s = float(r["size_from"])
        except (TypeError, ValueError):
            continue
        comps.append({
            "name": proj.get("name"),
            "area": proj.get("area"),
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
        "scope": scope,          # area+type | area | type
        "relaxed": relaxed,
        "comps": comps,
    }
