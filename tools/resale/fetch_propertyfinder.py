"""Pull a sample of PropertyFinder Egypt for-sale listings into resale_listings.

Used as a SECONDARY / review source: RE/MAX is the base; PropertyFinder is
refreshed monthly to cross-check price levels and to serve as a fallback when
RE/MAX has too few comparables for a given area/type. Kept polite — a modest
number of pages with a delay between requests.

Usage:  PAGES=60 python tools/resale/fetch_propertyfinder.py
Needs SUPABASE_URL + SUPABASE_ANON_KEY in the env (defaults to Homzy project).
"""
from __future__ import annotations

import json
import os
import re
import time

import requests

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ceoqtkbpdxnkuptnnwjg.supabase.co")
ANON = os.environ.get("SUPABASE_ANON_KEY", "")
PAGES = int(os.environ.get("PAGES", "60"))
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}

TYPE_MAP = {
    "apartment": "apartment", "duplex": "duplex", "penthouse": "penthouse",
    "studio": "studio", "villa": "villa", "townhouse": "townhouse",
    "town house": "townhouse", "twin house": "twinhouse", "twinhouse": "twinhouse",
    "chalet": "chalet", "office": "office", "clinic": "clinic", "retail": "shop",
    "shop": "shop", "whole building": "villa",
}
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


def canon_area(*parts) -> str | None:
    blob = " ".join(p for p in parts if p).lower()
    for kw, canon in AREA_RULES:
        if kw in blob:
            return canon
    return None


def _map(p: dict) -> dict | None:
    price = (p.get("price") or {}).get("value")
    size = (p.get("size") or {}).get("value")
    if not price or price < 100000:
        return None
    loc = p.get("location") or {}
    ptype = (p.get("property_type") or "").strip().lower()
    beds = p.get("bedrooms")
    try:
        beds = int(beds)
    except (TypeError, ValueError):
        beds = None
    return {
        "source": "propertyfinder",
        "external_id": str(p.get("id")),
        "purpose": "sale",
        "type": TYPE_MAP.get(ptype, ptype or None),
        "area": canon_area(loc.get("path_name"), loc.get("full_name"), loc.get("name")),
        "region": loc.get("full_name"),
        "price": price,
        "size_sqm": size,
        "bedrooms": beds,
        "url": p.get("share_url"),
    }


def fetch(pages: int) -> list[dict]:
    seen, out = set(), []
    for page in range(1, pages + 1):
        url = f"https://www.propertyfinder.eg/en/search?c=1&t=1&ob=nd&page={page}"
        try:
            t = requests.get(url, headers=UA, timeout=40).text
            m = re.search(
                r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
                t, re.S)
            listings = (json.loads(m.group(1))["props"]["pageProps"]
                        ["searchResult"]["listings"]) if m else []
        except Exception:
            listings = []
        n0 = len(out)
        for l in listings:
            if l.get("listing_type") != "property":
                continue
            uid = str((l.get("property") or {}).get("id"))
            if uid in seen:
                continue
            seen.add(uid)
            row = _map(l["property"])
            if row:
                out.append(row)
        if page % 10 == 0:
            print(f"  …page {page}/{pages} (collected {len(out)})")
        if len(out) == n0 and not listings:
            break  # no more results
        time.sleep(0.7)  # be polite
    return out


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
    rows = fetch(PAGES)
    with_area = sum(1 for x in rows if x["area"])
    with_size = sum(1 for x in rows if x["size_sqm"])
    print(f"propertyfinder: {len(rows)} listings | area {with_area} | size {with_size}")
    if rows:
        print("import_resale upserted:", push(rows))


if __name__ == "__main__":
    main()
