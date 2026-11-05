"""Pull the developers/projects/unit-types catalog from Supabase and expose it
to the broker as listing rows, so Homzy recommends real projects in chat.

Any data added to the Supabase catalog (e.g. from WhatsApp ingestion) flows
into the chat automatically — the backend just reads it here (cached briefly).
"""
from __future__ import annotations

import time
from typing import Any

from . import config

_CACHE: list[dict[str, Any]] | None = None
_CACHE_AT = 0.0
_TTL = 300  # seconds

_OVERVIEW: str | None = None
_OVERVIEW_AT = 0.0


def market_overview() -> str:
    """A compact snapshot of what Homzy actually has (areas + counts + types +
    a payment-plan note), injected into the chat so the assistant is aware of the
    whole catalog, not just the few matched units. Cached (10 min)."""
    global _OVERVIEW, _OVERVIEW_AT
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return ""
    now = time.time()
    if _OVERVIEW is not None and now - _OVERVIEW_AT < 600:
        return _OVERVIEW
    try:
        import requests

        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/v_city_counts",
            params={"select": "area,projects", "order": "projects.desc", "limit": "40"},
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        rows = [x for x in r.json() if x.get("area")]
        areas = "، ".join(f"{x['area']} ({x.get('projects') or 0})" for x in rows[:32])
        _OVERVIEW = (
            "WHAT HOMZY COVERS (be aware of the whole catalog, not only the matches below):\n"
            f"- Areas we have inventory in (with project counts): {areas}.\n"
            "- Property types: mostly apartments/studios, plus other unit types where the "
            "developer offers them.\n"
            "- Payment plans differ per unit — the real down payment, installment years and "
            "delivery for each option are in AVAILABLE MATCHES; quote those, never a generic plan.\n"
            "If the client names an area or type we don't have a match for right now, say so "
            "honestly and offer the closest available option."
        )
        _OVERVIEW_AT = now
        return _OVERVIEW
    except Exception:
        return _OVERVIEW or ""


def _to_listing(u: dict[str, Any]) -> dict[str, Any]:
    proj = u.get("project") or {}
    dev = proj.get("developer") or {}
    price = u.get("price_from") or u.get("price_to")
    size = u.get("size_from") or u.get("size_to")
    hl = [h for h in (proj.get("description"), u.get("payment_plan")) if h]
    name = proj.get("name") or "Project"
    name_ar = proj.get("name_ar") or name
    media = proj.get("project_media") or []
    brochure = next(
        (m.get("url") for m in media if m.get("kind") == "brochure" and m.get("url")),
        None)
    images = [m.get("url") for m in media if m.get("kind") == "image" and m.get("url")]
    cover = proj.get("cover_image_url")
    if cover:
        images = [cover] + [i for i in images if i != cover]
    ar_first = lambda *ks: next((src.get(k) for src, k in ks if src.get(k)), None)  # noqa: E731
    return {
        # project-level detail (Arabic brief when we have it) for the advisor
        "project_about": ar_first((proj, "description_ar"), (proj, "description")),
        "project_amenities": ar_first((proj, "amenities_ar"), (proj, "amenities")),
        "project_location": proj.get("location"),
        "project_delivery": proj.get("delivery"),
        "project_status": proj.get("status"),
        "developer_id": proj.get("developer_id"),
        "developer_ar": dev.get("name_ar"),
        "developer_website": dev.get("website"),
        "id": "TC-" + str(u.get("id", ""))[:8],
        "project_id": proj.get("id"),
        "purpose": "sale",
        "type": u.get("type") or "apartment",
        "area_en": proj.get("area") or "",
        "area_ar": proj.get("area") or "",
        "compound_en": name,
        "compound_ar": name_ar,
        "developer": dev.get("name"),
        "developer_phone": dev.get("phone"),
        "developer_about": dev.get("about_ar") or dev.get("about"),
        "developer_track": dev.get("track_record_ar") or dev.get("track_record"),
        "price": price,
        "currency": "EGP",
        "price_period": None,
        "bedrooms": u.get("bedrooms") or 0,
        "bathrooms": None,
        "size_sqm": size,
        "finishing": u.get("finishing"),
        "highlights_en": hl,
        "highlights_ar": hl,
        "payment_plan_en": u.get("payment_plan"),
        "payment_plan_ar": u.get("payment_plan"),
        "down_payment": u.get("down_payment"),
        "installment_years": u.get("installment_years"),
        "delivery": u.get("delivery"),
        "brochure_url": brochure,
        "images": images[:6],
        "cover_image": cover or (images[0] if images else None),
        "source": "catalog",
        "market": "primary",   # new-launch / developer
        "available": True,
    }


_SELECT = ("id,type,bedrooms,size_from,size_to,price_from,price_to,down_payment,"
           "installment_years,payment_plan,finishing,delivery,"
           "project:projects!inner(id,developer_id,name,name_ar,area,description,description_ar,amenities,amenities_ar,"
           "location,delivery,status,cover_image_url,project_media(kind,url),"
           "developer:developers(name,name_ar,phone,website,about,about_ar,track_record,track_record_ar))")


def search(req: dict[str, Any], n: int = 24) -> list[dict[str, Any]]:
    """Query the catalog for units matching the request (fast: fetches only a
    handful of rows instead of the whole catalog). Catalog is primary-market
    'sale', so returns nothing for rent requests."""
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    if req.get("purpose") == "rent":
        return []
    try:
        import requests

        params: dict[str, str] = {
            "select": _SELECT,
            "limit": str(n),
            "order": "price_from.asc.nullslast",
        }
        # Area is matched (and relaxed) in Python via the shared alias helper,
        # so a request in an area with no stock still surfaces the same type
        # elsewhere instead of silently returning nothing.
        if req.get("type"):
            params["type"] = f"eq.{req['type']}"
        # Budget's UPPER side is a ranking signal (listings._score), not a hard
        # cut — so we always surface the closest options instead of "no match".
        # But drop absurdly-cheap outliers (< half budget) so we never recommend
        # a mispriced/tiny unit to a serious buyer.
        bmax = req.get("budget_max")
        if bmax:
            params["price_from"] = f"gte.{int(bmax) // 2}"
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types",
            params=params,
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        return [_to_listing(x) for x in r.json()]
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Projects the client names ("ايه اسعار نيوم اكتوبر", "tell me about Plato"):
# the budget/type search above only returns the cheapest fits, so a named
# project that exists in the catalog could be missing and the advisor would
# wrongly call it unavailable. These pin the named project's units in.
# ---------------------------------------------------------------------------
_NAMES: list[tuple[str, list[str]]] | None = None
_NAMES_AT = 0.0
_AR_FOLD = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ة": "ه", "ى": "ي", "ؤ": "و", "ئ": "ي", "ـ": ""})


def _fold(s: str) -> str:
    import re
    s = (s or "").lower().translate(_AR_FOLD)
    s = re.sub(r"[ً-ْ]", "", s)            # Arabic diacritics
    return " " + re.sub(r"[^0-9a-zء-ي]+", " ", s).strip() + " "


def _project_names() -> list[tuple[str, list[str]]]:
    global _NAMES, _NAMES_AT
    if _NAMES is not None and time.time() - _NAMES_AT < 1800:
        return _NAMES
    import requests
    rows, start = [], 0
    while True:   # PostgREST pages at 1000 rows
        r = requests.get(config.SUPABASE_URL.rstrip("/") + "/rest/v1/projects",
                         params={"select": "id,name,name_ar", "order": "id"},
                         headers={"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}",
                                  "Range": f"{start}-{start + 999}"}, timeout=8)
        r.raise_for_status()
        page = r.json(); rows += page; start += 1000
        if len(page) < 1000:
            break
    out = []
    for p in rows:
        keys = {k for k in (_fold(p.get("name")), _fold(p.get("name_ar"))) if len(k.strip()) >= 4}
        if keys:
            out.append((p["id"], sorted(keys, key=len, reverse=True)))
    _NAMES, _NAMES_AT = out, time.time()
    return out


def mentioned_projects(text: str, limit: int = 3) -> list[str]:
    """Ids of catalog projects whose full name appears (as whole words) in `text`;
    the longest names win, so "Nyoum October" beats a bare "Nyoum"."""
    if not text or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    try:
        names = _project_names()
    except Exception:
        return []
    t = _fold(text)
    hits = []
    for pid, keys in names:
        k = next((k for k in keys if k in t), None)
        if k:
            hits.append((len(k), pid))
    hits.sort(reverse=True)
    return [pid for _, pid in hits[:limit]]


def units_for_projects(project_ids: list[str], n: int = 12) -> list[dict[str, Any]]:
    if not project_ids or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    try:
        import requests
        r = requests.get(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types",
            params={"select": _SELECT, "project_id": "in.(" + ",".join(project_ids) + ")",
                    "order": "price_from.asc.nullslast", "limit": str(n)},
            headers={"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=8)
        r.raise_for_status()
        rows = [_to_listing(x) for x in r.json()]
        # keep the order the client named them in
        rank = {pid: i for i, pid in enumerate(project_ids)}
        rows.sort(key=lambda x: rank.get(x.get("project_id"), 99))
        for x in rows:
            x["asked_for"] = True
        return rows
    except Exception:
        return []


# Developers the client names ("مين بالم هيلز وايه سابقة أعمالهم", "Is Artal reliable?").
_DEVS: list[tuple[str, list[str], int]] | None = None
_DEVS_AT = 0.0
_DEV_SUFFIX = r"\b(developments?|developers?|development company|properties|property|real estate development|" \
              r"real estate|group|holding|company|l\.?l\.?c|fz)\b"
# words that signal the client is talking about a company, so even a short or
# common-word name ("Times", "Prime", "كود") can be taken as a developer
_DEV_CUES = ("شركه", "شركة", "مطور", "المطور", "سابقه", "سابقة", "اعمال", "أعمال", "مشاريع", "مشروعات",
             "developer", "company", "track record", "projects by")


def _developers() -> list[tuple[str, list[str], int]]:
    global _DEVS, _DEVS_AT
    if _DEVS is not None and time.time() - _DEVS_AT < 1800:
        return _DEVS
    import re
    import requests
    r = requests.get(config.SUPABASE_URL.rstrip("/") + "/rest/v1/developers",
                     params={"select": "id,name,name_ar,projects(count)"},
                     headers={"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}",
                              "Range": "0-1999"}, timeout=8)
    r.raise_for_status()
    out = []
    for d in r.json():
        core = re.sub(_DEV_SUFFIX, " ", (d.get("name") or "").lower())
        keys = {k for k in (_fold(d.get("name")), _fold(core), _fold(d.get("name_ar"))) if len(k.strip()) >= 3}
        n = ((d.get("projects") or [{}])[0] or {}).get("count") or 0
        if keys:
            out.append((d["id"], sorted(keys, key=len, reverse=True), n))
    _DEVS, _DEVS_AT = out, time.time()
    return out


def mentioned_developers(text: str, limit: int = 2) -> list[str]:
    if not text or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    try:
        devs = _developers()
    except Exception:
        return []
    t = _fold(text)
    cue = any(_fold(c) in t for c in _DEV_CUES)
    import re
    hits = []
    for did, keys, n in devs:
        for k in keys:
            if k not in t:
                continue
            words = len(k.split())
            latin = bool(re.search(r"[a-z]", k))
            # a bare single word ("prime", "times", "هيلز") only counts with a company
            # cue, or when it's a distinctive Arabic name of a sizeable developer ("سوديك")
            if words >= 2 or cue or (not latin and len(k.strip()) >= 4 and n >= 3):
                hits.append((len(k), did, k))
                break
    hits.sort(reverse=True)
    # "بالم هيلز" must not also bring in a developer called just "هيلز"
    kept = [h for h in hits if not any(h[2] != o[2] and h[2] in o[2] for o in hits)]
    return [d for _, d, _ in kept[:limit]]


def developer_profile(dev_id: str, user_token: str | None = None) -> str:
    """A grounded profile of one developer for the advisor: who they are, their
    track record and their projects on Homzy with starting prices."""
    try:
        import requests
        h = {"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}"}
        base = config.SUPABASE_URL.rstrip("/") + "/rest/v1"
        d = requests.get(base + "/developers", headers=h, timeout=8, params={
            "select": "name,name_ar,website,about,about_ar,track_record,track_record_ar", "id": f"eq.{dev_id}"}).json()[0]
        ps = requests.get(base + "/projects", headers=h, timeout=8, params={
            "select": "name,name_ar,area,delivery,status,unit_types(price_from,type)",
            "developer_id": f"eq.{dev_id}", "limit": "40"}).json()
    except Exception:
        return ""
    lines = [f"DEVELOPER: {d.get('name')}" + (f" ({d['name_ar']})" if d.get("name_ar") else "")]
    about = d.get("about_ar") or d.get("about")
    track = d.get("track_record_ar") or d.get("track_record")
    if about:
        lines.append(f"   About: {about[:900]}")
    if track:
        lines.append(f"   Track record: {track[:900]}")
    if d.get("website"):
        lines.append(f"   Website: {d['website']}")
    if not about and not track:
        lines.append("   (No company background on file — don't guess; offer to check with the developer.)")
    rows = []
    for p in ps:
        prices = [u.get("price_from") for u in (p.get("unit_types") or []) if u.get("price_from")]
        types = sorted({u.get("type") for u in (p.get("unit_types") or []) if u.get("type")})
        bits = [p.get("area") or "", f"from {int(min(prices)):,} EGP" if prices else "",
                ", ".join(types[:4]), (f"delivery {p['delivery']}" if p.get("delivery") else "")]
        rows.append(f"     - {p.get('name')}" + (f" / {p['name_ar']}" if p.get("name_ar") else "")
                    + ": " + " | ".join(b for b in bits if b))
    if rows:
        lines.append(f"   Projects on Homzy ({len(rows)}):")
        lines += rows[:25]
    # company-level updates from the developers' WhatsApp groups; the database
    # filters the tiers by the caller (clients only ever get public ones)
    try:
        r = requests.post(base + "/rpc/developer_intel_for_ai", json={"p_developer_ids": [dev_id]}, timeout=8,
                          headers={**h, "Content-Type": "application/json",
                                   "Authorization": f"Bearer {user_token or config.SUPABASE_KEY}"})
        intel = r.json() if r.ok else []
    except Exception:
        intel = []
    for it in (intel if isinstance(intel, list) else [])[:6]:
        when = (it.get("observed_at") or "")[:10]
        tag = {"broker": "broker-only update", "ai": "internal context — do NOT quote"}.get(
            it.get("tier"), "Latest developer update")
        lines.append(f"   [{tag}, {when}] {it.get('content_ar')}")
    return "\n".join(lines)


_DEV_CACHE: dict[str, list[str]] = {}


def developer_projects(developer: str | None, exclude: str | None = None,
                       limit: int = 6) -> list[str]:
    """Other projects by the same developer — "Name (Area)" strings — so the
    advisor can speak to the developer's wider portfolio. Cached per developer."""
    if not developer or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    key = developer.strip().lower()
    if key in _DEV_CACHE:
        rows = _DEV_CACHE[key]
    else:
        try:
            import requests

            r = requests.get(
                config.SUPABASE_URL.rstrip("/") + "/rest/v1/projects",
                params={
                    "select": "name,name_ar,area,developer:developers!inner(name)",
                    "developer.name": f"eq.{developer}",
                    "order": "updated_at.desc",
                    "limit": "40",
                },
                headers={"apikey": config.SUPABASE_KEY,
                         "Authorization": f"Bearer {config.SUPABASE_KEY}"},
                timeout=8,
            )
            r.raise_for_status()
            seen: set[str] = set()
            rows = []
            for p in r.json():
                nm = (p.get("name") or p.get("name_ar") or "").strip()
                if not nm or nm.lower() in seen:
                    continue
                seen.add(nm.lower())
                area = (p.get("area") or "").strip()
                rows.append(f"{nm} ({area})" if area else nm)
            _DEV_CACHE[key] = rows
        except Exception:
            return []
    ex = (exclude or "").strip().lower()
    out = [x for x in rows if not ex or not x.lower().startswith(ex)]
    return out[:limit]


def listings() -> list[dict[str, Any]]:
    """Catalog unit-types as listing rows (cached). Empty if not configured."""
    global _CACHE, _CACHE_AT
    if not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return []
    now = time.time()
    if _CACHE is not None and now - _CACHE_AT < _TTL:
        return _CACHE
    try:
        import requests

        url = config.SUPABASE_URL.rstrip("/") + "/rest/v1/unit_types"
        select = ("id,type,bedrooms,size_from,size_to,price_from,price_to,"
                  "down_payment,installment_years,payment_plan,finishing,delivery,"
                  "project:projects(name,area,description,developer:developers(name))")
        r = requests.get(
            url,
            params={"select": select},
            headers={"apikey": config.SUPABASE_KEY,
                     "Authorization": f"Bearer {config.SUPABASE_KEY}"},
            timeout=10,
        )
        r.raise_for_status()
        out = [_to_listing(x) for x in r.json()]
        _CACHE, _CACHE_AT = out, now
        return out
    except Exception:
        return _CACHE or []


def project_intel(project_ids: list[str], user_token: str | None = None) -> dict[str, list[dict[str, Any]]]:
    """Latest developer updates (from the WhatsApp groups) per project.

    Calls project_intel_for_ai with the CALLER's token when given: the database
    returns broker/ai-tier items only if that token belongs to a broker/admin,
    so a client (or a forged "broker" flag) only ever gets the public tier."""
    ids = [i for i in dict.fromkeys(project_ids) if i]
    if not ids or not config.SUPABASE_URL or not config.SUPABASE_KEY:
        return {}
    try:
        import requests

        r = requests.post(
            config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/project_intel_for_ai",
            json={"p_project_ids": ids},
            headers={"apikey": config.SUPABASE_KEY, "Content-Type": "application/json",
                     "Authorization": f"Bearer {user_token or config.SUPABASE_KEY}"},
            timeout=8,
        )
        rows = r.json() if r.ok else []
    except Exception:
        return {}
    out: dict[str, list[dict[str, Any]]] = {}
    for row in rows if isinstance(rows, list) else []:
        out.setdefault(row.get("project_id"), []).append(row)
    return out
