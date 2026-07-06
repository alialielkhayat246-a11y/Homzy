"""Pull RE/MAX Egypt (remax.com.eg) for-sale listings into resale_listings.

RE/MAX embeds its full listing set as JSON in the /listings page. These are real
secondary-market asking prices (with size in m²), which feed the resale price
estimator. This is the user's own brokerage (RE/MAX Everest), so it's first-party
data.

Usage:  python tools/resale/fetch_remax.py
Needs SUPABASE_URL + SUPABASE_ANON_KEY in the env (defaults to the Homzy project).
"""
from __future__ import annotations

import json
import os
import re

import requests

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ceoqtkbpdxnkuptnnwjg.supabase.co")
ANON = os.environ.get("SUPABASE_ANON_KEY", "")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

# RE/MAX property_type name -> our catalog type slug
TYPE_MAP = {
    "apartment": "apartment", "duplex": "duplex", "penthouse": "penthouse",
    "studio": "studio", "villa": "villa", "townhouse": "townhouse",
    "town house": "townhouse", "twin house": "twinhouse", "twinhouse": "twinhouse",
    "chalet": "chalet", "office": "office", "clinic": "clinic", "retail": "shop",
    "shop": "shop", "standalone": "villa", "stand alone": "villa",
}

# Canonical area keywords (first match wins) -> catalog area name
AREA_RULES = [
    ("new capital", "New Capital"), ("administrative capital", "New Capital"),
    ("mostakbal", "Mostakbal City"), ("future city", "Mostakbal City"),
    ("new cairo", "New Cairo"), ("5th settlement", "New Cairo"),
    ("fifth settlement", "New Cairo"), ("tagamoa", "New Cairo"),
    ("madinaty", "Madinaty"), ("shorouk", "El Shorouk"), ("obour", "El Obour"),
    ("new zayed", "New Zayed"), ("sheikh zayed", "Sheikh Zayed"),
    ("zayed", "Sheikh Zayed"), ("october gardens", "October Gardens"),
    ("6 october", "6th of October"), ("6th october", "6th of October"),
    ("october", "6th of October"),
    ("ras el hekma", "Ras El Hekma"), ("north coast", "North Coast"),
    ("sahel", "North Coast"), ("alamein", "New Alamein"),
    ("sokhna", "Ain Sokhna"), ("galala", "Galala"),
    ("maadi", "Maadi"), ("new mansoura", "New Mansoura"),
    ("alexandria", "Alexandria"),
]


def canon_area(*parts: str) -> str | None:
    blob = " ".join(p for p in parts if p).lower()
    for kw, canon in AREA_RULES:
        if kw in blob:
            return canon
    return None


def num(s) -> float | None:
    if s is None:
        return None
    m = re.search(r"[\d.]+", str(s).replace(",", ""))
    return float(m.group()) if m else None


def fetch() -> list[dict]:
    # The page embeds the full set; purpose comes from each item's
    # property_purpose ('S' = sale), so one fetch is enough.
    t = requests.get("https://remax.com.eg/listings", headers=UA, timeout=60).text
    seen, out, i = set(), [], t.find('{"unit_id":')
    while i != -1:
        depth, j = 0, i
        while j < len(t):
            c = t[j]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        try:
            obj = json.loads(t[i:j + 1])
        except json.JSONDecodeError:
            obj = None
        if obj and "price" in obj:
            uid = str(obj.get("unit_id"))
            if uid not in seen:
                seen.add(uid)
                m = _map(obj)
                if m:
                    out.append(m)
        i = t.find('{"unit_id":', j + 1)
    return out


def _map(o: dict) -> dict | None:
    purpose = "sale" if (o.get("property_purpose") or "").upper() == "S" else "rent"
    price = num(o.get("price"))
    size = num(o.get("size"))
    if not price or price < 100000:      # skip junk / missing
        return None
    ptype = ((o.get("property_type") or {}).get("prop_type_name") or "").strip().lower()
    typ = TYPE_MAP.get(ptype, ptype or None)
    region = o.get("region") or ""
    area = canon_area(o.get("community"), o.get("sub_community"), region, o.get("city"))
    return {
        "source": "remax",
        "external_id": str(o.get("unit_id")),
        "purpose": purpose,
        "type": typ,
        "area": area,
        "region": region,
        "price": price,
        "size_sqm": size,
        "bedrooms": int(num(o.get("bedrooms")) or 0) or None,
        "url": "https://remax.com.eg/property/" + (o.get("seo_url") or ""),
    }


def push(items: list[dict]) -> int:
    r = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/import_resale",
        headers={"apikey": ANON, "Authorization": f"Bearer {ANON}",
                 "Content-Type": "application/json"},
        data=json.dumps({"items": items}).encode("utf-8"),
        timeout=120,
    )
    r.raise_for_status()
    return r.json()


def main():
    if not ANON:
        raise SystemExit("Set SUPABASE_ANON_KEY in the env.")
    total = fetch()
    sale = sum(1 for x in total if x["purpose"] == "sale")
    print(f"remax: {len(total)} usable listings ({sale} sale, {len(total)-sale} rent)")
    with_area = sum(1 for x in total if x["area"])
    with_size = sum(1 for x in total if x["size_sqm"])
    print(f"total {len(total)} | with canonical area {with_area} | with size {with_size}")
    n = push(total)
    print("import_resale upserted:", n)


if __name__ == "__main__":
    main()
