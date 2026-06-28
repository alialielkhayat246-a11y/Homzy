"""Turn a WhatsApp export into the Homzy catalog (developer -> projects -> units).

Pipeline:
  1. parse + pre-filter the chat to listing candidates,
  2. extract structured listings with Gemini (extract.py),
  3. consolidate them into one developer, its projects, and unit *types*
     (grouped by type+bedrooms, with price/size ranges),
  4. emit an idempotent PL/pgSQL block that upserts into Supabase.

Usage:
    GEMINI_API_KEY=...  python build_catalog.py chat.txt \
        --developer "Tesla Developments" \
        --about "..." --track "..." \
        --json catalog.json --sql catalog.sql
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from typing import Any

import extract


def _num(v: Any):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return v
    m = re.search(r"\d[\d,\.]*", str(v))
    return float(m.group(0).replace(",", "")) if m else None


def consolidate(listings: list[dict], developer: str) -> dict:
    """Group listings -> {developer, projects:[{name, units:[...]}]}."""
    projects: dict[str, dict] = {}
    for l in listings:
        proj = (l.get("project") or l.get("developer") or "General").strip()
        p = projects.setdefault(proj, {
            "name": proj,
            "area": l.get("area"),
            "delivery": l.get("delivery"),
            "status": "available",
            "_units": defaultdict(lambda: {
                "type": None, "bedrooms": None,
                "sizes": [], "prices": [],
                "down_payment": None, "installment_years": None,
                "payment_plan": None, "finishing": None, "delivery": None,
            }),
        })
        if not p["area"] and l.get("area"):
            p["area"] = l.get("area")
        key = (l.get("type"), l.get("bedrooms"))
        u = p["_units"][key]
        u["type"] = l.get("type")
        u["bedrooms"] = l.get("bedrooms")
        sz, pr = _num(l.get("size_sqm")), _num(l.get("price"))
        if sz:
            u["sizes"].append(sz)
        if pr:
            u["prices"].append(pr)
        for f in ("down_payment", "installment_years", "payment_plan",
                  "finishing", "delivery"):
            if not u[f] and l.get(f):
                u[f] = l.get(f)

    out_projects = []
    for p in projects.values():
        units = []
        for u in p["_units"].values():
            units.append({
                "type": u["type"],
                "bedrooms": u["bedrooms"],
                "size_from": min(u["sizes"]) if u["sizes"] else None,
                "size_to": max(u["sizes"]) if u["sizes"] else None,
                "price_from": min(u["prices"]) if u["prices"] else None,
                "price_to": max(u["prices"]) if u["prices"] else None,
                "down_payment": u["down_payment"],
                "installment_years": _num(u["installment_years"]),
                "payment_plan": u["payment_plan"],
                "finishing": u["finishing"],
                "delivery": u["delivery"],
            })
        out_projects.append({
            "name": p["name"], "area": p["area"],
            "delivery": p["delivery"], "status": p["status"], "units": units,
        })
    return {"developer": developer, "projects": out_projects}


# --- SQL generation -------------------------------------------------------
def _q(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def _qn(v):
    n = _num(v)
    return "NULL" if n is None else (str(int(n)) if float(n).is_integer() else str(n))


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def to_sql(cat: dict, about: str | None, track: str | None) -> str:
    dev = cat["developer"]
    lines = ["do $$", "declare dev_id uuid; proj_id uuid;", "begin"]
    lines.append(
        f"  insert into public.developers (name, slug, about, track_record) "
        f"values ({_q(dev)}, {_q(_slug(dev))}, {_q(about)}, {_q(track)}) "
        f"on conflict (slug) do update set about=excluded.about, "
        f"track_record=excluded.track_record returning id into dev_id;"
    )
    lines.append("  delete from public.projects where developer_id = dev_id;")
    for p in cat["projects"]:
        lines.append(
            f"  insert into public.projects (developer_id, name, area, delivery, status) "
            f"values (dev_id, {_q(p['name'])}, {_q(p['area'])}, {_q(p['delivery'])}, "
            f"{_q(p['status'])}) returning id into proj_id;"
        )
        for u in p["units"]:
            lines.append(
                "  insert into public.unit_types (project_id, type, bedrooms, "
                "size_from, size_to, price_from, price_to, down_payment, "
                "installment_years, payment_plan, finishing, delivery) values "
                f"(proj_id, {_q(u['type'])}, {_qn(u['bedrooms'])}, "
                f"{_qn(u['size_from'])}, {_qn(u['size_to'])}, {_qn(u['price_from'])}, "
                f"{_qn(u['price_to'])}, {_q(u['down_payment'])}, "
                f"{_qn(u['installment_years'])}, {_q(u['payment_plan'])}, "
                f"{_q(u['finishing'])}, {_q(u['delivery'])});"
            )
    lines.append("end $$;")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("chat")
    ap.add_argument("--developer", required=True)
    ap.add_argument("--about", default=None)
    ap.add_argument("--track", default=None)
    ap.add_argument("--json", default=None)
    ap.add_argument("--sql", default=None)
    args = ap.parse_args()

    with open(args.chat, encoding="utf-8") as fh:
        msgs = extract.parse_whatsapp_export(fh.read())
    cands = [m for m in msgs if extract.looks_like_listing(m)]
    print(f"messages={len(msgs)} candidates={len(cands)}", flush=True)
    listings = extract.extract_listings(cands)
    print(f"extracted listings={len(listings)}", flush=True)

    cat = consolidate(listings, args.developer)
    nproj = len(cat["projects"])
    nunits = sum(len(p["units"]) for p in cat["projects"])
    print(f"projects={nproj} unit_types={nunits}", flush=True)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(cat, fh, ensure_ascii=False, indent=2)
    sql = to_sql(cat, args.about, args.track)
    if args.sql:
        with open(args.sql, "w", encoding="utf-8") as fh:
            fh.write(sql)
    print("--- SQL written ---" if args.sql else sql)


if __name__ == "__main__":
    main()
