"""Pull byit's authenticated `properties` feed → data/byit_properties.json.

This feed (unlike the public projects feed) carries the real sales terms:
down payment, installment years, delivery status, finishing and starting price.

Two non-obvious things are required to get Egyptian data back:
  1. Log in with the phone WITHOUT its leading zero  (1559998799, not 0155…),
     country "+20", against POST /api/v1/signin.
  2. Send a `country: 50` header on every request (50 = Egypt's coverage id);
     without it the endpoint returns an empty list.

Credentials come from the environment so nothing secret lives in the repo:
    BYIT_PHONE=1559998799  BYIT_PASSWORD=****  python tools/whatsapp_ingest/byit_pull.py

Then run byit_enrich.py (updates existing rows) and byit_import_missing.py
(inserts compounds not yet in the catalog).
"""
from __future__ import annotations

import json
import os
import sys
import time

import requests

BASE = "https://api.app.byitcorp.com/api/v1"
EGYPT_COVERAGE_ID = "50"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "byit_properties.json")


def login(phone: str, password: str) -> str:
    r = requests.post(
        f"{BASE}/signin",
        json={"phone": phone, "password": password, "country": "+20"},
        headers={"origin": "https://www.byitcorp.com"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["token"]


def pull(token: str) -> list[dict]:
    h = {
        "Authorization": f"Bearer {token}",
        "origin": "https://www.byitcorp.com",
        "Accept-Language": "en",
        "country": EGYPT_COVERAGE_ID,
    }
    out: list[dict] = []
    page, pages = 1, 1
    while page <= pages:
        r = requests.get(
            f"{BASE}/properties",
            params={"page": page, "available": "true", "type": "RELATED-TO-COMPOUND"},
            headers=h, timeout=60,
        )
        r.raise_for_status()
        body = r.json()
        out.extend(body.get("data") or [])
        pages = body.get("pageCount") or 1
        if page % 15 == 0:
            print(f"  …page {page}/{pages}  ({len(out)})")
        page += 1
        time.sleep(0.1)
    return out


def main() -> None:
    phone = os.environ.get("BYIT_PHONE")
    password = os.environ.get("BYIT_PASSWORD")
    if not phone or not password:
        sys.exit("Set BYIT_PHONE and BYIT_PASSWORD in the environment first.")
    token = login(phone, password)
    print("logged in; pulling properties…")
    data = pull(token)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    print(f"saved {len(data)} properties -> {OUT}")


if __name__ == "__main__":
    main()
