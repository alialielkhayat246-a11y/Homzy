"""Import byitcorp compounds into the Homzy catalog.

Reads the projects JSON (from api.app.byitcorp.com/.../projects/withoutPagenation/get),
transforms it into developers / projects / unit_types / project_media, and emits
idempotent PL/pgSQL chunks (upsert by external_id) to run via Supabase.

    python import_byit.py byit_projects.json outdir
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

APT_MAP = {
    "STUDIO": ("studio", 0),
    "ONE-BEDROOM": ("apartment", 1),
    "TWO-BEDROOM": ("apartment", 2),
    "THREE-BEDROOM": ("apartment", 3),
    "FOUR-BEDROOM": ("apartment", 4),
    "FIVE-BEDROOM": ("apartment", 5),
    "DUPLEX": ("duplex", None),
    "PENTHOUSE": ("penthouse", None),
    "SERVICE-APARTMENT": ("hotel apartment", None),
}
VILLA_MAP = {
    "TOWN": ("townhouse", None),
    "TWIN": ("twinhouse", None),
    "STAND-ALONE": ("villa", None),
    "S-VILLA": ("villa", None),
}

CHUNK = 120


def q(s):
    if s is None or s == "":
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def qn(v):
    try:
        n = float(v)
    except (TypeError, ValueError):
        return "NULL"
    if n <= 0:
        return "NULL"
    return str(int(n)) if n.is_integer() else str(n)


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")
    return s or "dev"


def usable_units(proj):
    out = []
    for a in proj.get("apartments") or []:
        if a.get("available") and (a.get("price") or 0) > 0 and a["type"] in APT_MAP:
            t, bd = APT_MAP[a["type"]]
            out.append((t, bd, a.get("area"), a.get("price")))
    for v in proj.get("villas") or []:
        if v.get("available") and (v.get("price") or 0) > 0 and v["type"] in VILLA_MAP:
            t, bd = VILLA_MAP[v["type"]]
            out.append((t, bd, v.get("area"), v.get("price")))
    return out


def main():
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["data"]
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)

    # collect developers + a phone for each
    devs = {}          # company_id -> {name, slug, phone}
    projects = []
    for p in data:
        if p.get("type") != "COMPOUND":
            continue
        units = usable_units(p)
        if not units:
            continue
        comp = p.get("company") or {}
        cid = comp.get("id")
        cname = comp.get("name") or "Unknown Developer"
        if cid is not None:
            d = devs.setdefault(cid, {"name": cname, "slug": slug(cname), "phone": None})
            if not d["phone"] and p.get("employePhone"):
                d["phone"] = p["employePhone"]
        offers = p.get("offers") or []
        pay = " / ".join(o for o in offers if isinstance(o, str)) or None
        projects.append({
            "ext": f"byit-{p['id']}",
            "cid": cid,
            "name": p.get("name_en") or p.get("name") or "Project",
            "img": p.get("img"),
            "pdf": p.get("pdf"),
            "pay": pay,
            "units": units,
        })

    # developers.sql
    dev_lines = []
    for cid, d in devs.items():
        dev_lines.append(
            "insert into public.developers (name, slug, phone, external_id) values "
            f"({q(d['name'])}, {q(d['slug'])}, {q(d['phone'])}, {q('byitc-'+str(cid))}) "
            "on conflict (slug) do update set phone=coalesce(excluded.phone, public.developers.phone), "
            "external_id=coalesce(public.developers.external_id, excluded.external_id);"
        )
    (outdir / "byit_devs.sql").write_text("\n".join(dev_lines), encoding="utf-8")

    # project chunks
    n = 0
    for i in range(0, len(projects), CHUNK):
        chunk = projects[i:i + CHUNK]
        lines = ["do $$", "declare proj_id uuid;", "begin"]
        for p in chunk:
            dev_sel = (f"(select id from public.developers where external_id={q('byitc-'+str(p['cid']))})"
                       if p["cid"] is not None else "NULL")
            lines.append(
                "  insert into public.projects (external_id, developer_id, name, status, cover_image_url) "
                f"values ({q(p['ext'])}, {dev_sel}, {q(p['name'])}, 'available', {q(p['img'])}) "
                "on conflict (external_id) do update set name=excluded.name, "
                "developer_id=excluded.developer_id, cover_image_url=excluded.cover_image_url "
                "returning id into proj_id;"
            )
            lines.append("  delete from public.unit_types where project_id = proj_id;")
            lines.append("  delete from public.project_media where project_id = proj_id;")
            vals = []
            for (t, bd, area, price) in p["units"]:
                vals.append(
                    f"(proj_id, {q(t)}, {qn(bd) if bd is not None else 'NULL'}, "
                    f"{qn(area)}, {qn(price)}, {q(p['pay'])})"
                )
            if vals:
                lines.append(
                    "  insert into public.unit_types (project_id, type, bedrooms, "
                    "size_from, price_from, payment_plan) values " + ",".join(vals) + ";"
                )
            if p["pdf"]:
                lines.append(
                    "  insert into public.project_media (project_id, kind, url) values "
                    f"(proj_id, 'brochure', {q(p['pdf'])});"
                )
        lines.append("end $$;")
        (outdir / f"byit_proj_{n:03d}.sql").write_text("\n".join(lines), encoding="utf-8")
        n += 1

    print(f"developers={len(devs)} projects={len(projects)} chunks={n}")


if __name__ == "__main__":
    main()
