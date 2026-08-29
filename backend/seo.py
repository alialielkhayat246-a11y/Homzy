"""Public, server-rendered SEO landing pages for a single project or listing.

These are the ONLY deep pages that stay outside the login gate: Google can crawl
them (real content + structured data in the HTML it receives), while the
contact / viewing actions still require a sign-in. That's the hybrid that gives
both organic reach and lead capture.
"""
from __future__ import annotations

import html
import json
import re
from typing import Any

from . import areas as areas_mod, config

SEO_BASE = "https://homzy-ai.com"
_H = None


def _headers() -> dict[str, str]:
    return {"apikey": config.SUPABASE_KEY,
            "Authorization": f"Bearer {config.SUPABASE_KEY}"}


def _get(path: str) -> Any:
    import requests
    r = requests.get(config.SUPABASE_URL.rstrip("/") + "/rest/v1" + path,
                     headers=_headers(), timeout=8)
    r.raise_for_status()
    return r.json()


def _rpc(fn: str, args: dict) -> Any:
    import requests
    r = requests.post(config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/" + fn,
                      headers={**_headers(), "Content-Type": "application/json"},
                      json=args, timeout=10)
    r.raise_for_status()
    return r.json()


# Same area-normalization as the client (HZ.normArea) so area pages merge the
# same way the browse filter + map do (New Zayed / Zayed → one page).
def _norm_area(a: str) -> str:
    s = (a or "").lower()
    s = re.sub(r"[^a-z0-9؀-ۿ ]", "", s)
    s = re.sub(r"(\d)(st|nd|rd|th)", r"\1", s)
    s = re.sub(r"\b(of|el|al|new)\b", "", s)
    s = re.sub(r"\bnaser\b", "nasr", s)
    s = re.sub(r"\bmokatam\b", "mokattam", s)
    s = re.sub(r"\b(sedr|sudar)\b", "sudr", s)
    return re.sub(r"\s+", " ", s).strip()


def area_slug(label: str) -> str:
    s = (label or "").lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")


def _area_groups() -> list[dict]:
    """Merged areas from the catalog (label, variants, projects), like the map."""
    rows = _get("/v_city_counts?select=area,projects&order=projects.desc&limit=80")
    groups: dict[str, dict] = {}
    for r in rows:
        a = r.get("area")
        if not a:
            continue
        k = _norm_area(a)
        g = groups.get(k)
        if not g:
            groups[k] = {"label": a, "variants": [a], "projects": r.get("projects") or 0}
        else:
            g["projects"] += r.get("projects") or 0
            g["variants"].append(a)
            if len(a) > len(g["label"]):
                g["label"] = a
    return list(groups.values())


def _esc(s: Any) -> str:
    return html.escape("" if s is None else str(s), quote=True)


def _money(n: Any) -> str:
    try:
        return f"{int(float(n)):,} ج.م"
    except (TypeError, ValueError):
        return ""


def _clip(s: str, n: int) -> str:
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


# ---------------------------------------------------------------------------
# Shared HTML shell
# ---------------------------------------------------------------------------
def _page(title: str, desc: str, canonical: str, og_image: str,
          jsonld: dict, body: str) -> str:
    ld = json.dumps(jsonld, ensure_ascii=False)
    og_img_tag = (f'<meta property="og:image" content="{_esc(og_image)}" />'
                  '<meta name="twitter:card" content="summary_large_image" />'
                  if og_image else '')
    return f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{_esc(title)}</title>
<meta name="description" content="{_esc(desc)}" />
<meta name="robots" content="index, follow" />
<link rel="canonical" href="{_esc(canonical)}" />
<meta property="og:site_name" content="Homzy" /><meta property="og:locale" content="ar_EG" />
<meta property="og:type" content="website" />
<meta property="og:url" content="{_esc(canonical)}" />
<meta property="og:title" content="{_esc(title)}" />
<meta property="og:description" content="{_esc(desc)}" />
{og_img_tag}
<link rel="icon" href="/favicon.ico" sizes="any" />
<link rel="icon" type="image/svg+xml" href="/assets/icon.svg" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/site.webmanifest" />
<meta name="theme-color" content="#0B1D36" />
<script type="application/ld+json">{ld}</script>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700;800;900&family=Poppins:wght@600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/assets/homzy.css">
<style>
  .sp-wrap{{max-width:900px; margin:0 auto; padding:18px 18px 60px;}}
  .sp-crumb{{font-size:13px; color:var(--muted); margin:10px 0 14px;}}
  .sp-crumb a{{color:var(--teal-d); text-decoration:none;}}
  .sp-cover{{height:min(46vw,360px); border-radius:20px; background:#e9e2da center/cover no-repeat; position:relative; border:1px solid var(--line);}}
  .sp-cover .badge{{position:absolute; bottom:14px; inset-inline-start:14px; background:var(--teal); color:#fff; font-size:12px; font-weight:800; padding:6px 13px; border-radius:100px;}}
  .sp-wrap h1{{font-size:28px; color:var(--navy); margin:18px 0 4px; line-height:1.25;}}
  .sp-sub{{color:var(--muted); font-size:15px;}}
  .sp-price{{color:var(--teal-d); font-weight:800; font-size:22px; margin-top:10px;}}
  .sp-chips{{display:flex; gap:8px; flex-wrap:wrap; margin:14px 0;}}
  .sp-chips .c{{background:#fff; border:1px solid var(--line); border-radius:10px; padding:6px 12px; font-size:13px; font-weight:600; color:#40506a;}}
  .sp-sec{{background:#fff; border:1px solid var(--line); border-radius:16px; padding:18px; margin-top:16px;}}
  .sp-sec h2{{font-size:17px; color:var(--navy); margin-bottom:10px;}}
  .sp-sec p{{color:#40506a; font-size:14.5px; line-height:1.8;}}
  .sp-gallery{{display:flex; gap:10px; overflow-x:auto; padding-bottom:4px;}}
  .sp-gallery img{{height:150px; border-radius:12px; flex:none; object-fit:cover; border:1px solid var(--line);}}
  .utscroll{{overflow-x:auto;}} .utable{{width:100%; border-collapse:collapse; font-size:13.5px; min-width:560px;}}
  .utable th{{text-align:start; color:var(--muted); font-weight:700; padding:8px; border-bottom:1px solid var(--line); white-space:nowrap;}}
  .utable td{{padding:9px 8px; border-bottom:1px solid var(--line); color:#40506a;}}
  .utable .pr{{color:var(--teal-d); font-weight:800; white-space:nowrap;}}
  .devgrid{{display:grid; grid-template-columns:1fr 1fr; gap:8px;}}
  .devchip{{display:block; background:#fff; border:1px solid var(--line); border-radius:12px; padding:10px 12px; text-decoration:none; transition:border-color .15s;}}
  .devchip:hover{{border-color:var(--teal);}}
  .devchip b{{display:block; font-size:13.5px; color:var(--navy);}} .devchip span{{display:block; font-size:12px; color:var(--muted); margin-top:2px;}}
  .sp-cta{{display:flex; gap:10px; flex-wrap:wrap; margin-top:20px; position:sticky; bottom:0; background:linear-gradient(transparent,var(--cream) 34%); padding:14px 0 6px;}}
  .sp-cta .btn{{flex:1; min-width:150px;}}
  .vin{{width:100%; box-sizing:border-box; font-family:var(--ff); font-size:14px; padding:11px 13px; margin-bottom:9px; border:1.5px solid var(--line-2); border-radius:11px; background:#fff; color:var(--navy);}}
  .vmsg{{margin-top:8px; font-weight:700; font-size:13.5px;}} .vmsg.err{{color:#B42318;}} .vmsg.ok{{color:#1E8E5A;}}
  @media(max-width:480px){{ .devgrid{{grid-template-columns:1fr;}} }}
</style>
</head>
<body data-mode="client">
<div id="hz-header"></div>
<main class="sp-wrap">
{body}
</main>
<div id="hz-footer"></div>
<script src="/assets/homzy.js"></script>
<script>
// Contact / viewing is gated: guests get sent to login, then straight back.
function spViewing(ctx){{
  if(!(window.HZ&&HZ.isLoggedIn&&HZ.isLoggedIn())){{
    location.href='/login?next='+encodeURIComponent(location.pathname+location.search); return;
  }}
  var box=document.getElementById('spForm'); if(box) box.style.display='block';
  window.__spctx=ctx;
}}
async function spSubmit(){{
  var name=(document.getElementById('vName').value||'').trim();
  var phone=(document.getElementById('vPhone').value||'').trim();
  var time=(document.getElementById('vTime').value||'').trim();
  var m=document.getElementById('vMsg');
  if(name.length<2||phone.replace(/\\D/g,'').length<8){{ m.className='vmsg err'; m.textContent=(HZ.lang==='ar'?'اكتب اسمك ورقمك.':'Enter your name and phone.'); return; }}
  var b=document.getElementById('vSend'); b.disabled=true;
  var c=window.__spctx||{{}};
  var ctxTxt=(HZ.lang==='ar'?'طلب معاينة':'Viewing request')+': '+(c.name||'')+(c.area?(' · '+c.area):'');
  try{{
    await HZ.rpc('upsert_web_lead',{{p_session_id:'view-'+Math.random().toString(36).slice(2),p_name:name,p_phone:phone,p_context:ctxTxt,p_messages:[{{role:'user',content:ctxTxt+(time?(' — '+time):'')}}],p_lang:HZ.lang,p_req:{{type:'viewing_request',project_id:c.project_id||null,listing_id:c.listing_id||null,project:c.name||null,area:c.area||null,preferred_time:time||null}}}});
    document.getElementById('spForm').innerHTML='<div class="vmsg ok">✅ '+(HZ.lang==='ar'?'وصلنا طلبك، وهنتواصل معاك قريب.':'We got your request and will contact you soon.')+'</div>';
  }}catch(e){{ m.className='vmsg err'; m.textContent=(HZ.lang==='ar'?'حصل خطأ، جرّب تاني.':'Something went wrong.'); b.disabled=false; }}
}}
</script>
</body>
</html>"""


def _viewing_form(ctx_json: str) -> str:
    return f"""
    <div class="sp-cta">
      <button class="btn btn-teal" onclick='spViewing({ctx_json})'>📅 اطلب معاينة</button>
    </div>
    <div class="sp-sec" id="spForm" style="display:none">
      <h2>📅 اطلب معاينة</h2>
      <input class="vin" id="vName" placeholder="اسمك" />
      <input class="vin" id="vPhone" type="tel" inputmode="tel" placeholder="رقم موبايلك" />
      <input class="vin" id="vTime" placeholder="الوقت المفضّل (اختياري)" />
      <button class="btn btn-teal" id="vSend" style="width:100%" onclick="spSubmit()">ابعت الطلب</button>
      <div class="vmsg" id="vMsg"></div>
    </div>"""


# ---------------------------------------------------------------------------
# Project (primary / developer)
# ---------------------------------------------------------------------------
def render_project(pid: str) -> str | None:
    sel = ("id,developer_id,name,name_ar,area,description,delivery,status,amenities,"
           "cover_image_url,developer:developers(name,about,track_record,website)")
    rows = _get(f"/projects?select={sel}&id=eq.{pid}&limit=1")
    if not rows:
        return None
    p = rows[0]
    units = _get(f"/unit_types?select=type,bedrooms,size_from,size_to,price_from,"
                 f"price_to,down_payment,installment_years,payment_plan,delivery"
                 f"&project_id=eq.{pid}&order=price_from.asc&limit=40")
    media = _get(f"/project_media?select=kind,url&project_id=eq.{pid}&limit=12")
    others = []
    if p.get("developer_id"):
        others = _get(f"/projects?select=id,name,name_ar,area&developer_id=eq."
                      f"{p['developer_id']}&id=neq.{pid}&area=not.is.null"
                      f"&order=updated_at.desc&limit=6")

    dev = p.get("developer") or {}
    name = p.get("name_ar") or p.get("name") or "مشروع"
    name_en = p.get("name") or name
    area = p.get("area") or ""
    cover = p.get("cover_image_url") or next(
        (m["url"] for m in media if m.get("kind") == "image" and m.get("url")), "")
    images = [m["url"] for m in media if m.get("kind") == "image" and m.get("url")]
    prices = sorted(u["price_from"] for u in units if u.get("price_from"))
    minp = prices[0] if prices else None
    maxp = max((u["price_to"] or u["price_from"]) for u in units) if units else None

    title = f"{name} {('- ' + area) if area else ''} | Homzy".replace("  ", " ")
    desc = _clip(
        (f"{name}{(' في ' + area) if area else ''}"
         f"{(' من ' + dev.get('name')) if dev.get('name') else ''}. "
         f"{('يبدأ من ' + _money(minp) + '. ') if minp else ''}"
         f"{p.get('description') or ''}"),
        160)
    canonical = f"{SEO_BASE}/project/{pid}"

    jsonld = {"@context": "https://schema.org", "@type": "Product",
              "name": name_en, "description": desc,
              "category": "Real Estate",
              "url": canonical}
    if cover:
        jsonld["image"] = cover
    if dev.get("name"):
        jsonld["brand"] = {"@type": "Organization", "name": dev["name"]}
    if minp:
        jsonld["offers"] = {"@type": "AggregateOffer", "priceCurrency": "EGP",
                            "lowPrice": int(minp),
                            "highPrice": int(maxp) if maxp else int(minp),
                            "availability": "https://schema.org/InStock"}

    # unit table
    def _beds(u):
        b = u.get("bedrooms")
        return "استوديو" if b == 0 else (f"{b} غرف" if b else "—")

    def _size(u):
        a, b = u.get("size_from"), u.get("size_to")
        if not a:
            return "—"
        return f"{a}–{b} م²" if (b and b != a) else f"{a} م²"

    urows = "".join(
        f"<tr><td>{_esc(u.get('type') or '')}</td><td>{_beds(u)}</td>"
        f"<td>{_size(u)}</td><td class='pr'>{_money(u.get('price_from')) or '—'}</td>"
        f"<td>{_esc(u.get('down_payment') or '—')}</td>"
        f"<td>{(str(u.get('installment_years'))+' سنة') if u.get('installment_years') else '—'}</td>"
        f"<td>{_esc(u.get('delivery') or '—')}</td></tr>"
        for u in units)
    plans = []
    for pl in dict.fromkeys(u.get("payment_plan") for u in units if u.get("payment_plan")):
        plans.append(f"<p>💳 {_esc(pl)}</p>")

    status = p.get("status") or ""
    chips = []
    if p.get("delivery"):
        chips.append(f"<span class='c'>🗓️ التسليم: {_esc(p['delivery'])}</span>")
    if status:
        chips.append(f"<span class='c'>{_esc(status)}</span>")
    if minp:
        chips.append(f"<span class='c'>💰 يبدأ من {_money(minp)}</span>")

    others_html = ""
    if others:
        cards = "".join(
            f"<a class='devchip' href='/project/{o['id']}'><b>{_esc(o.get('name_ar') or o.get('name'))}</b>"
            f"{('<span>'+_esc(o['area'])+'</span>') if o.get('area') else ''}</a>"
            for o in others)
        others_html = (f"<div class='sp-sec'><h2>مشاريع تانية لنفس المطوّر</h2>"
                       f"<div class='devgrid'>{cards}</div></div>")

    ctx = html.escape(json.dumps(
        {"project_id": pid, "name": name, "area": area}, ensure_ascii=True), quote=True)

    body = f"""
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/app">المشاريع</a>{(' › ' + _esc(area)) if area else ''} › {_esc(name)}</nav>
    <div class="sp-cover" style="{('background-image:url(' + chr(39) + _esc(cover) + chr(39) + ')') if cover else ''}">
      <span class="badge">مشروع تطوير{(' · ' + _esc(area)) if area else ''}</span>
    </div>
    <h1>{_esc(name)}</h1>
    <div class="sp-sub">{_esc(dev.get('name') or '')}{(' · ' + _esc(area)) if area else ''}</div>
    {('<div class="sp-price">يبدأ من ' + _money(minp) + '</div>') if minp else ''}
    <div class="sp-chips">{''.join(chips)}</div>
    {('<div class="sp-sec"><p>' + _esc(p.get('description')) + '</p></div>') if p.get('description') else ''}
    {('<div class="sp-sec"><div class="sp-gallery">' + ''.join(f'<img loading="lazy" src="{_esc(u)}" alt="{_esc(name)}">' for u in images) + '</div></div>') if images else ''}
    {('<div class="sp-sec"><h2>الوحدات المتاحة</h2><div class="utscroll"><table class="utable"><thead><tr><th>النوع</th><th>الغرف</th><th>المساحة</th><th>السعر</th><th>المقدم</th><th>التقسيط</th><th>التسليم</th></tr></thead><tbody>' + urows + '</tbody></table></div>' + (''.join(plans)) + '</div>') if units else ''}
    {('<div class="sp-sec"><h2>عن المطوّر' + ((' — ' + _esc(dev.get('name'))) if dev.get('name') else '') + '</h2><p>' + _esc((dev.get('about') or '') + ' ' + (dev.get('track_record') or '')) + '</p></div>') if (dev.get('about') or dev.get('track_record')) else ''}
    {others_html}
    {('<div class="sp-sec"><h2>المميزات</h2><p>' + _esc(p.get('amenities')) + '</p></div>') if p.get('amenities') else ''}
    {_viewing_form(ctx)}
    """
    return _page(title, desc, canonical, cover, jsonld, body)


# ---------------------------------------------------------------------------
# Listing (broker resale / secondary)
# ---------------------------------------------------------------------------
def render_listing(lid: str) -> str | None:
    sel = ("id,title,description,purpose,type,price,currency,area,address,"
           "bedrooms,bathrooms,size_sqm,status,listing_media(url,sort)")
    rows = _get(f"/listings?select={sel}&id=eq.{lid}&status=eq.active&limit=1")
    if not rows:
        return None
    l = rows[0]
    title_txt = l.get("title") or "عقار"
    area = l.get("area") or ""
    purpose = "للإيجار" if l.get("purpose") == "rent" else "للبيع"
    media = sorted((l.get("listing_media") or []), key=lambda m: m.get("sort") or 0)
    cover = next((m["url"] for m in media if m.get("url")), "")
    images = [m["url"] for m in media if m.get("url")]
    price = l.get("price")

    title = f"{title_txt} {('- ' + area) if area else ''} {purpose} | Homzy".replace("  ", " ")
    desc = _clip(f"{title_txt}{(' في ' + area) if area else ''} {purpose}. "
                 f"{(_money(price) + '. ') if price else ''}{l.get('description') or ''}", 160)
    canonical = f"{SEO_BASE}/listing/{lid}"

    jsonld = {"@context": "https://schema.org", "@type": "Product",
              "name": title_txt, "description": desc, "category": "Real Estate",
              "url": canonical}
    if cover:
        jsonld["image"] = cover
    if price:
        jsonld["offers"] = {"@type": "Offer", "priceCurrency": l.get("currency") or "EGP",
                            "price": int(float(price)),
                            "availability": "https://schema.org/InStock"}

    chips = []
    if l.get("bedrooms"):
        chips.append(f"<span class='c'>🛏️ {l['bedrooms']} غرف</span>")
    if l.get("size_sqm"):
        chips.append(f"<span class='c'>📐 {l['size_sqm']} م²</span>")
    if l.get("bathrooms"):
        chips.append(f"<span class='c'>🚿 {l['bathrooms']} حمام</span>")
    if area:
        chips.append(f"<span class='c'>📍 {_esc(area)}</span>")

    ctx = html.escape(json.dumps(
        {"listing_id": lid, "name": title_txt, "area": area}, ensure_ascii=True), quote=True)

    body = f"""
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/app">سوق العقارات</a>{(' › ' + _esc(area)) if area else ''} › {_esc(title_txt)}</nav>
    <div class="sp-cover" style="{('background-image:url(' + chr(39) + _esc(cover) + chr(39) + ')') if cover else ''}">
      <span class="badge">{purpose}{(' · ' + _esc(area)) if area else ''}</span>
    </div>
    <h1>{_esc(title_txt)}</h1>
    <div class="sp-sub">{_esc(l.get('address') or area)}</div>
    {('<div class="sp-price">' + _money(price) + '</div>') if price else ''}
    <div class="sp-chips">{''.join(chips)}</div>
    {('<div class="sp-sec"><p>' + _esc(l.get('description')) + '</p></div>') if l.get('description') else ''}
    {('<div class="sp-sec"><div class="sp-gallery">' + ''.join(f'<img loading="lazy" src="{_esc(u)}" alt="{_esc(title_txt)}">' for u in images) + '</div></div>') if images else ''}
    {_viewing_form(ctx)}
    """
    return _page(title, desc, canonical, cover, jsonld, body)


# ---------------------------------------------------------------------------
# Area landing page (public, indexable) — one per area, high-intent SEO
# ("عقارات التجمع الخامس"). Lists the area's projects + a profile blurb.
# ---------------------------------------------------------------------------
def render_area(slug: str) -> str | None:
    slug = (slug or "").lower()
    groups = _area_groups()
    g = next((x for x in groups if area_slug(x["label"]) == slug), None)
    if not g:
        g = next((x for x in groups
                  if any(area_slug(v) == slug for v in x["variants"])), None)
    if not g:
        return None
    label = g["label"]
    variants = g["variants"]
    n = g["projects"]
    try:
        projects = _rpc("search_projects", {"p_areas": variants, "p_sort": "recent",
                                            "p_limit": 24, "p_offset": 0})
    except Exception:
        projects = []

    prof = areas_mod.profile(label) or {}
    intro = (prof.get("ar") or "").strip()
    canonical = f"{SEO_BASE}/area/{area_slug(label)}"
    title = f"عقارات {label} — مشاريع وأسعار | Homzy"
    desc = _clip(f"مشاريع ومطوّرين وعقارات في {label}. "
                 f"{n} مشروع بأسعار وخطط تقسيط. {intro}", 160)
    cover = next((p.get("cover_image_url") for p in projects if p.get("cover_image_url")), "")

    # cards
    cards = []
    for p in projects:
        nm = p.get("name_ar") or p.get("name") or "مشروع"
        pid = p.get("id")
        img = p.get("cover_image_url") or ""
        price = _money(p.get("price_from_min")) if p.get("price_from_min") is not None else ""
        dev = p.get("developer_name") or ""
        cards.append(
            f"<a class='acard' href='/project/{pid}'>"
            f"<div class='acard-img' style=\"{('background-image:url('+chr(39)+_esc(img)+chr(39)+')') if img else ''}\"></div>"
            f"<div class='acard-b'><div class='acard-n'>{_esc(nm)}</div>"
            f"{('<div class=' + chr(39) + 'acard-d' + chr(39) + '>' + _esc(dev) + '</div>') if dev else ''}"
            f"{('<div class=' + chr(39) + 'acard-p' + chr(39) + '>يبدأ من ' + price + '</div>') if price else ''}"
            f"</div></a>")
    grid = "<div class='agrid'>" + "".join(cards) + "</div>" if cards else \
        "<p class='sp-sub'>لسه مفيش مشاريع منشورة في المنطقة دي.</p>"

    # JSON-LD: a CollectionPage listing the projects
    jsonld = {"@context": "https://schema.org", "@type": "CollectionPage",
              "name": f"عقارات {label}", "description": desc, "url": canonical,
              "about": {"@type": "Place", "name": label,
                        "address": {"@type": "PostalAddress", "addressCountry": "EG",
                                    "addressRegion": label}},
              "mainEntity": {"@type": "ItemList", "numberOfItems": n}}
    if cover:
        jsonld["primaryImageOfPage"] = cover

    extra_css = """
    .agrid{display:grid; grid-template-columns:repeat(auto-fill,minmax(210px,1fr)); gap:16px; margin-top:8px;}
    .acard{background:var(--surface,#fff); border:1px solid var(--line,#E6DDCF); border-radius:16px; overflow:hidden; text-decoration:none; display:block; transition:transform .15s, box-shadow .15s;}
    .acard:hover{transform:translateY(-3px); box-shadow:var(--shadow);}
    .acard-img{height:130px; background:#e9e2da center/cover no-repeat;}
    .acard-b{padding:12px 14px;} .acard-n{font-weight:800; color:var(--navy,#0B1D36); font-size:14.5px; line-height:1.35;}
    .acard-d{color:var(--muted,#66717F); font-size:12.5px; margin-top:2px;}
    .acard-p{color:var(--teal-d,#0B5563); font-weight:800; font-size:14px; margin-top:6px;}
    """
    body = f"""
    <style>{extra_css}</style>
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/areas">المناطق</a> › {_esc(label)}</nav>
    <h1>عقارات {_esc(label)}</h1>
    <div class="sp-sub">{n} مشروع من كبار المطوّرين — أسعار وخطط تقسيط محدّثة.</div>
    {('<div class="sp-sec"><p>' + _esc(intro) + '</p></div>') if intro else ''}
    <div class="sp-sec"><h2>مشاريع {_esc(label)}</h2>{grid}</div>
    <div class="sp-cta"><a class="btn btn-teal" href="/app?area={_esc(label)}">اتصفّح كل مشاريع {_esc(label)} ←</a></div>
    """
    return _page(title, desc, canonical, cover, jsonld, body)


# ---------------------------------------------------------------------------
# Sitemap URLs (public project + listing + area pages)
# ---------------------------------------------------------------------------
def sitemap_urls(limit: int = 1000) -> list[tuple[str, str]]:
    """(loc, changefreq) for every public deep page, best-effort."""
    out: list[tuple[str, str]] = []
    try:
        for g in _area_groups():
            out.append((f"{SEO_BASE}/area/{area_slug(g['label'])}", "weekly"))
    except Exception:
        pass
    try:
        for p in _get(f"/projects?select=id&area=not.is.null&limit={limit}"):
            out.append((f"{SEO_BASE}/project/{p['id']}", "weekly"))
    except Exception:
        pass
    try:
        for l in _get("/listings?select=id&status=eq.active&limit=1000"):
            out.append((f"{SEO_BASE}/listing/{l['id']}", "daily"))
    except Exception:
        pass
    return out
