"""Build full catalog records for byit compounds so the importer RPC can insert
any that aren't in the catalog yet (existing ones are skipped server-side).

Input : data/byit_properties.json
Output: data/byit_import.json  (list of project objects with nested units + media)
"""
from __future__ import annotations

import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "data", "byit_properties.json")
OUT = os.path.join(ROOT, "data", "byit_import.json")

DELIVERY = {
    "READY-To-MOVE":     ("Ready to move", True),
    "AFTER-ONE-YEAR":    ("After 1 year",  False),
    "AFTER-TWO-YEARS":   ("After 2 years", False),
    "AFTER-THREE-YEARS": ("After 3 years", False),
}
FINISH = {
    "CORE-SHELL": "Core & Shell", "SEMI-FINISHED": "Semi finished",
    "FULLY-FINISHED": "Fully finished",
}
# byit grid unit type -> (our type, bedrooms)
UNIT = {
    "STUDIO": ("studio", 0), "ONE-BEDROOM": ("apartment", 1),
    "TWO-BEDROOM": ("apartment", 2), "THREE-BEDROOM": ("apartment", 3),
    "FOUR-BEDROOM": ("apartment", 4), "FIVE-BEDROOM": ("apartment", 5),
    "DUPLEX": ("duplex", None), "PENTHOUSE": ("penthouse", None),
    "SERVICE-APARTMENT": ("apartment", None),
    "TOWN": ("townhouse", None), "TWIN": ("twinhouse", None),
    "STAND-ALONE": ("villa", None), "S-VILLA": ("villa", None),
    "SHOP": ("shop", None), "OFFICE": ("office", None),
    "CLINIC": ("clinic", None), "PHARMACY": ("pharmacy", None),
}


def first(x):
    return x[0] if isinstance(x, list) and x else None


def representative(offers):
    inst = [o for o in offers if o.get("priceType") == "INSTALLMENT"]
    pool = inst or offers

    def dp(o):
        try:
            return float(o.get("downPayment") or 1e9)
        except (TypeError, ValueError):
            return 1e9
    return sorted(pool, key=dp)[0]


def main():
    with open(SRC, "r", encoding="utf-8-sig") as f:
        props = json.load(f)

    by_project = defaultdict(list)
    for p in props:
        pid = (p.get("project") or {}).get("id")
        if pid:
            by_project[pid].append(p)

    out = []
    for pid, offers in by_project.items():
        rep = representative(offers)
        proj = rep.get("project") or {}
        comp = rep.get("company") or {}
        loc = rep.get("location") or {}

        d_key = first(rep.get("deliveryStatus"))
        delivery, is_ready = DELIVERY.get(d_key, (None, False))
        finishing = FINISH.get(first(rep.get("finishingType")))
        dp_raw = rep.get("downPayment")
        try:
            dp_txt = f"{float(dp_raw):g}%" if dp_raw not in (None, "") else None
        except (TypeError, ValueError):
            dp_txt = None
        inst = rep.get("installmentDuration") if rep.get("priceType") == "INSTALLMENT" else None
        inst = int(inst) if inst else None

        parts = []
        if dp_txt:
            parts.append(f"{dp_txt} down payment")
        if inst:
            parts.append(f"{inst}-year installments")
        if delivery:
            parts.append(f"delivery {delivery.lower()}")
        if finishing:
            parts.append(finishing.lower())
        plan = " · ".join(parts) or None

        # unit grid across all offerings of this project (dedupe by our type)
        units = {}
        for src_key in ("apartments", "villas", "mall"):
            for g in (proj.get(src_key) or []):
                if not g.get("available") or not g.get("price"):
                    continue
                m = UNIT.get(g.get("type"))
                if not m:
                    continue
                t, beds = m
                key = (t, beds, g.get("area"))
                price = g.get("price")
                if key not in units or price < units[key]["price_from"]:
                    units[key] = {
                        "type": t, "bedrooms": beds,
                        "size_from": g.get("area") or None,
                        "price_from": price,
                        "down_payment": dp_txt, "installment_years": inst,
                        "delivery": delivery, "finishing": finishing,
                        "payment_plan": plan,
                    }
        # fall back to category headline if no grid rows
        if not units:
            cat = (rep.get("category") or {}).get("categoryName_en", "apartment").lower()
            price = rep.get("price") or proj.get("startingPrice") or None
            if price:
                units[(cat, None, None)] = {
                    "type": cat, "bedrooms": None, "size_from": None,
                    "price_from": price, "down_payment": dp_txt,
                    "installment_years": inst, "delivery": delivery,
                    "finishing": finishing, "payment_plan": plan,
                }

        imgs = [u for u in (rep.get("imgs") or []) if u][:6]
        out.append({
            "ext": f"byit-{pid}",
            "dev_name": comp.get("name_en") or comp.get("name"),
            "dev_name_ar": comp.get("name_ar"),
            "dev_logo": comp.get("logo"),
            "dev_phone": (proj.get("vendors") or [{}])[0].get("contactPhone") or proj.get("employePhone"),
            "name": proj.get("name_en") or proj.get("name"),
            "name_ar": proj.get("name_ar"),
            "area": loc.get("name_en") or loc.get("name"),
            "delivery": delivery,
            "status": "Ready to move" if is_ready else "Off-plan",
            "cover": imgs[0] if imgs else (comp.get("logo")),
            "pdf": proj.get("pdf"),
            "imgs": imgs,
            "units": list(units.values()),
        })

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    total_units = sum(len(o["units"]) for o in out)
    print(f"projects: {len(out)}  units(total): {total_units}  -> {OUT}")


if __name__ == "__main__":
    main()
