"""Transform byit `properties` records (which carry the real payment terms —
down payment, installment years, delivery, finishing, starting price) into
batched SQL that ENRICHES the already-imported catalog.

Input : data/byit_properties.json   (pulled from the authenticated byit API)
Output: data/byit_enrich_*.sql       (UPDATE statements, keyed by external_id)

Safe by design: only UPDATEs existing rows keyed by `byit-<projectId>`; it never
touches WhatsApp-sourced projects (those have no byit- external_id).
"""
from __future__ import annotations

import json
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "data", "byit_properties.json")
OUT_DIR = os.path.join(ROOT, "data")

# --- enum → human-readable maps -------------------------------------------
DELIVERY = {
    "READY-To-MOVE":     ("Ready to move",   "استلام فوري",        True),
    "AFTER-ONE-YEAR":    ("After 1 year",    "تسليم بعد سنة",      False),
    "AFTER-TWO-YEARS":   ("After 2 years",   "تسليم بعد سنتين",    False),
    "AFTER-THREE-YEARS": ("After 3 years",   "تسليم بعد 3 سنوات",  False),
}
FINISH = {
    "CORE-SHELL":     ("Core & Shell",   "نصف تشطيب (كور آند شل)"),
    "SEMI-FINISHED":  ("Semi finished",  "نصف تشطيب"),
    "FULLY-FINISHED": ("Fully finished", "تشطيب كامل"),
}


def first(lst):
    return lst[0] if isinstance(lst, list) and lst else None


def sql(s):
    """Quote a value for SQL; None -> NULL."""
    if s is None or s == "":
        return "NULL"
    if isinstance(s, (int, float)):
        return str(s)
    return "'" + str(s).replace("'", "''") + "'"


def representative(offers):
    """Pick the offering that best represents a project's headline terms:
    prefer an INSTALLMENT plan (has down payment + installments), then the one
    with the most complete data / lowest down payment."""
    installment = [o for o in offers if o.get("priceType") == "INSTALLMENT"]
    pool = installment or offers

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
        proj = p.get("project") or {}
        # the property list items carry a lighter project object; the id lives
        # on the property's project when present, else skip.
        pid = proj.get("id") or p.get("projectId")
        if pid:
            by_project[pid].append(p)

    proj_rows = []   # (ext, delivery_en, delivery_ar, status, starting_price)
    unit_rows = []   # (ext, down_payment, installment_years, delivery_en, finishing_en, payment_plan_en, payment_plan_ar)

    for pid, offers in by_project.items():
        ext = f"byit-{pid}"
        rep = representative(offers)
        d_key = first(rep.get("deliveryStatus"))
        f_key = first(rep.get("finishingType"))
        d_en, d_ar, is_ready = DELIVERY.get(d_key, (None, None, False))
        f_en, f_ar = FINISH.get(f_key, (None, None))
        dp_raw = rep.get("downPayment")
        try:
            dp_txt = f"{float(dp_raw):g}%" if dp_raw not in (None, "") else None
        except (TypeError, ValueError):
            dp_txt = None
        inst = rep.get("installmentDuration") if rep.get("priceType") == "INSTALLMENT" else None
        inst = int(inst) if inst else None
        proj_obj = rep.get("project") or {}
        starting = proj_obj.get("startingPrice") or None
        status = "Ready to move" if is_ready else "Off-plan"

        # human payment-plan sentence
        parts_en, parts_ar = [], []
        if dp_txt:
            parts_en.append(f"{dp_txt} down payment")
            parts_ar.append(f"مقدم {dp_txt}")
        if inst:
            parts_en.append(f"{inst}-year installments")
            parts_ar.append(f"تقسيط على {inst} سنوات")
        if d_en:
            parts_en.append(f"delivery {d_en.lower()}")
            parts_ar.append(d_ar)
        if f_en:
            parts_en.append(f_en.lower())
            parts_ar.append(f_ar)
        plan_en = " · ".join(parts_en) or None
        plan_ar = " · ".join(parts_ar) or None

        proj_rows.append((ext, d_en, d_ar, status, starting))
        unit_rows.append((ext, dp_txt, inst, d_en, f_en, plan_en, plan_ar))

    # --- emit compact JSON for the enrich_catalog() RPC --------------------
    items = []
    for (ext, d_en, d_ar, status, starting), (_, dp, inst, _d, f_en, plan_en, plan_ar) in zip(proj_rows, unit_rows):
        items.append({
            "ext": ext,
            "delivery": d_en,
            "delivery_ar": d_ar,
            "status": status,
            "dp": dp,
            "inst": inst,
            "finishing": f_en,
            "plan": plan_en,
            "plan_ar": plan_ar,
            "starting": starting,
        })

    out = os.path.join(OUT_DIR, "byit_enrich.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False)

    print(f"projects grouped: {len(by_project)}")
    print(f"enrich items: {len(items)}  ->  {out}")
    print("sample:", json.dumps(items[0], ensure_ascii=False))


if __name__ == "__main__":
    main()
