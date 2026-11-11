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
from urllib.parse import quote

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


def _intl_phone(raw: str) -> str:
    """Any way a broker typed an Egyptian number (01…, 1…, 201…, +20 …, 0020…)
    -> 2010… digits, for wa.me links and tel:+ dialling."""
    d = re.sub(r"\D", "", raw or "")
    if d.startswith("00"):
        d = d[2:]
    if d.startswith("20"):
        return d
    if d.startswith("0"):
        return "2" + d               # 01… -> 201…
    if d.startswith("1") and len(d) == 10:
        return "20" + d              # 1… (leading 0 dropped) -> 201…
    return d                         # already international (another country code)


def _clip(s: str, n: int) -> str:
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


# ---------------------------------------------------------------------------
# Shared HTML shell
# ---------------------------------------------------------------------------
def _share_bar(url: str, text: str) -> str:
    """WhatsApp / Facebook / copy-link buttons, so visitors can pass a page on too."""
    wa = quote(f"{text}\n{url}")
    fb = quote(url, safe="")
    btn = ("display:inline-flex;align-items:center;gap:6px;font-weight:800;font-size:13.5px;"
           "padding:9px 15px;border-radius:11px;text-decoration:none;cursor:pointer;border:none;font-family:inherit;")
    return (
        '<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:12px 0 2px">'
        '<span style="font-size:13px;color:var(--muted);font-weight:700;margin-inline-end:4px">شارك:</span>'
        f'<a target="_blank" rel="noopener" href="https://wa.me/?text={wa}" style="{btn}background:#22C55E;color:#fff">واتساب</a>'
        f'<a target="_blank" rel="noopener" href="https://www.facebook.com/sharer/sharer.php?u={fb}" style="{btn}background:#1877F2;color:#fff">فيسبوك</a>'
        f'<button type="button" onclick="navigator.clipboard.writeText(\'{_esc(url)}\').then(()=>{{this.textContent=\'✓ اتنسخ\'}})" '
        f'style="{btn}background:#fff;color:var(--navy);border:1.5px solid var(--line-2)">🔗 نسخ اللينك</button>'
        '</div>')


def _page(title: str, desc: str, canonical: str, og_image: str,
          jsonld: dict, body: str, og_size: tuple[int, int] | None = None) -> str:
    ld = json.dumps(jsonld, ensure_ascii=False)
    og_img_tag = (f'<meta property="og:image" content="{_esc(og_image)}" />'
                  + (f'<meta property="og:image:width" content="{og_size[0]}" />'
                     f'<meta property="og:image:height" content="{og_size[1]}" />'
                     '<meta property="og:image:type" content="image/jpeg" />' if og_size else '')
                  + f'<meta property="og:image:alt" content="{_esc(title)}" />'
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
<link rel="stylesheet" href="/assets/homzy.css?v=2">
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
  .sp-top-cta{{display:flex; gap:10px; flex-wrap:wrap; margin:6px 0 4px;}} .sp-top-cta .btn{{flex:1 1 160px; padding:11px 14px; font-size:14px;}}
  .sp-note{{font-size:13px; color:#526074; margin:-4px 0 10px;}}
  .sp-cover.ph{{background:linear-gradient(135deg,var(--navy),#0B5563);}}
  .sp-chips .c{{background:#fff; border:1px solid var(--line); border-radius:10px; padding:6px 12px; font-size:13px; font-weight:600; color:#40506a;}}
  .sp-sec{{background:#fff; border:1px solid var(--line); border-radius:16px; padding:18px; margin-top:16px;}}
  .sp-sec h2{{font-size:17px; color:var(--navy); margin-bottom:10px;}}
  .sp-sec p{{color:#40506a; font-size:14.5px; line-height:1.8;}}
  .sp-gallery{{display:flex; gap:10px; overflow-x:auto; padding-bottom:4px;}}
  .sp-gallery img{{height:150px; border-radius:12px; flex:none; object-fit:cover; border:1px solid var(--line); cursor:zoom-in;}}
  .sp-cover[data-photos]{{cursor:zoom-in;}}
  .lbx{{position:fixed; inset:0; z-index:200; background:rgba(5,12,24,.94); display:none; align-items:center; justify-content:center;}}
  .lbx.open{{display:flex;}}
  .lbx img{{max-width:94vw; max-height:84vh; border-radius:10px; object-fit:contain; user-select:none;}}
  .lbx button{{position:absolute; border:none; background:rgba(255,255,255,.14); color:#fff; width:46px; height:46px; border-radius:50%; font-size:24px; cursor:pointer;}}
  .lbx .x{{top:16px; inset-inline-end:16px;}} .lbx .pv{{right:14px;}} .lbx .nx{{left:14px;}}
  .lbx .n{{position:absolute; bottom:18px; direction:ltr; color:#cfd8e3; font-size:14px; font-weight:700;}}
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
<div class="lbx" id="lbx" onclick="if(event.target===this)lbClose()">
  <button class="x" onclick="lbClose()" aria-label="close">×</button>
  <button class="pv" onclick="lbGo(-1)" aria-label="previous">›</button>
  <img id="lbImg" alt="">
  <button class="nx" onclick="lbGo(1)" aria-label="next">‹</button>
  <div class="n" id="lbN"></div>
</div>
<script>
// Photo viewer: gallery thumbnails and the cover open the full-size photos.
var LB=[], LBI=0;
function lbShow(){{ document.getElementById('lbImg').src=LB[LBI]; document.getElementById('lbN').textContent=(LBI+1)+' / '+LB.length; }}
function lbOpen(list,i){{ LB=list; LBI=i||0; if(!LB.length) return; lbShow(); document.getElementById('lbx').classList.add('open'); }}
function lbClose(){{ document.getElementById('lbx').classList.remove('open'); }}
function lbGo(d){{ LBI=(LBI+d+LB.length)%LB.length; lbShow(); }}
document.addEventListener('keydown',function(e){{ if(!document.getElementById('lbx').classList.contains('open')) return;
  if(e.key==='Escape') lbClose(); else if(e.key==='ArrowLeft') lbGo(1); else if(e.key==='ArrowRight') lbGo(-1); }});
(function(){{ var x0=null, box=document.getElementById('lbx');
  box.addEventListener('touchstart',function(e){{ x0=e.touches[0].clientX; }},{{passive:true}});
  box.addEventListener('touchend',function(e){{ if(x0===null) return; var dx=e.changedTouches[0].clientX-x0; if(Math.abs(dx)>40) lbGo(dx<0?-1:1); x0=null; }}); }})();
document.addEventListener('DOMContentLoaded',function(){{
  var imgs=[].slice.call(document.querySelectorAll('.sp-gallery img')), urls=imgs.map(function(i){{ return i.src; }});
  imgs.forEach(function(im,i){{ im.addEventListener('click',function(){{ lbOpen(urls,i); }}); }});
  var cv=document.querySelector('.sp-cover'); if(cv&&urls.length){{ cv.setAttribute('data-photos','1'); cv.addEventListener('click',function(){{ lbOpen(urls,0); }}); }}
}});
</script>
<script src="/assets/homzy.js?v=11"></script>
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
# Homzy Stays property — server-rendered <head> meta (injected into stay.html)
# ---------------------------------------------------------------------------
def stay_meta(pid: str) -> str | None:
    """SEO <head> block for a Homzy Stays property, or None if not found/approved."""
    try:
        rows = _get("/stay_cards?id=eq." + pid + "&select=title,description,city,area,"
                    "governorate,type_ar,type_en,base_price,currency,rating_avg,reviews_count,cover&limit=1")
    except Exception:
        return None
    if not rows:
        return None
    p = rows[0]
    title = (p.get("title") or "Homzy Stays").strip()
    loc = " · ".join([x for x in (p.get("area") or p.get("city"), p.get("governorate")) if x])
    desc = _clip((p.get("description") or f"{p.get('type_ar') or ''} {loc}").strip(), 160)
    canonical = "https://homzy-ai.com/stays/" + pid
    cover = p.get("cover") or ""
    full_title = f"{title} — Homzy Stays"
    jsonld: dict[str, Any] = {
        "@context": "https://schema.org", "@type": "LodgingBusiness",
        "name": title, "description": desc, "url": canonical,
    }
    if loc:
        jsonld["address"] = {"@type": "PostalAddress",
                             "addressLocality": p.get("city") or loc, "addressCountry": "EG"}
    if cover:
        jsonld["image"] = cover
    if p.get("reviews_count"):
        jsonld["aggregateRating"] = {"@type": "AggregateRating",
                                     "ratingValue": p.get("rating_avg"),
                                     "reviewCount": p.get("reviews_count")}
    if p.get("base_price"):
        try:
            jsonld["priceRange"] = f"{int(float(p['base_price']))} {p.get('currency') or 'EGP'}"
        except Exception:
            pass
    ld = json.dumps(jsonld, ensure_ascii=False)
    parts = [
        f"<title>{_esc(full_title)}</title>",
        f'<meta name="description" content="{_esc(desc)}" />',
        f'<link rel="canonical" href="{canonical}" />',
        '<meta property="og:type" content="website" /><meta property="og:site_name" content="Homzy" />',
        f'<meta property="og:url" content="{canonical}" />',
        f'<meta property="og:title" content="{_esc(full_title)}" />',
        f'<meta property="og:description" content="{_esc(desc)}" />',
        (f'<meta property="og:image" content="{_esc(cover)}" />'
         '<meta name="twitter:card" content="summary_large_image" />' if cover else
         '<meta name="twitter:card" content="summary" />'),
        f'<script type="application/ld+json">{ld}</script>',
    ]
    return "\n".join(parts)


# Old cover host that no longer serves images — skip it so pages never show a blank cover.
_DEAD_IMG = re.compile(r"res\.cloudinary\.com/boody-car")
_AR_TYPES = {"apartment": "شقة", "duplex": "دوبلكس", "penthouse": "بنتهاوس", "studio": "استوديو",
             "townhouse": "تاون هاوس", "twinhouse": "توين هاوس", "villa": "فيلا", "chalet": "شاليه",
             "cabin": "كابينة", "office": "مكتب إداري", "clinic": "عيادة", "shop": "محل",
             "pharmacy": "صيدلية", "hotel apartment": "شقة فندقية"}


def _ar_text(v) -> str:
    """Arabic display for English catalog phrases (same rules as HZ.catalog.text)."""
    t = str(v or "")
    def yrs(m):
        n = int(m.group(1))
        return "خلال " + ("سنة" if n == 1 else "سنتين" if n == 2 else f"{n} سنوات" if n <= 10 else f"{n} سنة")
    t = re.sub(r"after\s+(\d+)\s+years?", yrs, t, flags=re.I)
    t = re.sub(r"ready to move", "استلام فوري", t, flags=re.I)
    t = re.sub(r"off[ -]plan", "تحت الإنشاء", t, flags=re.I)
    t = re.sub(r"fully finished", "تشطيب كامل", t, flags=re.I)
    t = re.sub(r"semi[ -]finished", "نص تشطيب", t, flags=re.I)
    return t


def _ok_img(u) -> bool:
    return bool(u) and not _DEAD_IMG.search(u)


# ---------------------------------------------------------------------------
# Project (primary / developer)
# ---------------------------------------------------------------------------
def render_project(pid: str) -> str | None:
    sel = ("id,developer_id,name,name_ar,area,description,description_ar,delivery,status,"
           "amenities,amenities_ar,cover_image_url,updated_at,"
           "developer:developers(name,about,about_ar,track_record,track_record_ar,website)")
    rows = _get(f"/projects?select={sel}&id=eq.{pid}&limit=1")
    if not rows:
        return None
    p = rows[0]
    # The remaining lookups are independent: fetch them in parallel (was 4 round
    # trips one after another, ~1.2 s per page under load).
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(4) as ex:
        f_units = ex.submit(_get, f"/unit_types?select=type,bedrooms,size_from,size_to,price_from,"
                                  f"price_to,down_payment,installment_years,payment_plan,delivery"
                                  f"&project_id=eq.{pid}&order=price_from.asc&limit=40")
        f_media = ex.submit(_get, f"/project_media?select=kind,url&project_id=eq.{pid}&limit=12")
        f_others = (ex.submit(_get, f"/projects?select=id,name,name_ar,area&developer_id=eq."
                                    f"{p['developer_id']}&id=neq.{pid}&area=not.is.null"
                                    f"&order=updated_at.desc&limit=6")
                    if p.get("developer_id") else None)
        f_intel = ex.submit(_get, f"/project_intel?select=content_ar,observed_at&project_id=eq.{pid}"
                                  f"&order=observed_at.desc&limit=5")
        units, media = f_units.result(), f_media.result()
        others = f_others.result() if f_others else []
        try:
            prefetched_intel = f_intel.result() or []
        except Exception:
            prefetched_intel = []

    dev = p.get("developer") or {}
    # This page is Arabic: prefer the Arabic briefs, fall back to English.
    p["description"] = p.get("description_ar") or p.get("description")
    p["amenities"] = p.get("amenities_ar") or p.get("amenities")
    dev["about"] = dev.get("about_ar") or dev.get("about")
    dev["track_record"] = dev.get("track_record_ar") or dev.get("track_record")
    name = p.get("name_ar") or p.get("name") or "مشروع"
    name_en = p.get("name") or name
    area = p.get("area") or ""
    images = [m["url"] for m in media if m.get("kind") == "image" and _ok_img(m.get("url"))]
    cover = p.get("cover_image_url") if _ok_img(p.get("cover_image_url")) else (images[0] if images else "")
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
                            "highPrice": int(maxp) if maxp else int(minp)}

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
        f"<tr><td>{_esc(_AR_TYPES.get((u.get('type') or '').lower(), u.get('type') or ''))}</td><td>{_beds(u)}</td>"
        f"<td>{_size(u)}</td><td class='pr'>{_money(u.get('price_from')) or '—'}</td>"
        f"<td>{_esc(u.get('down_payment') or '—')}</td>"
        f"<td>{(str(u.get('installment_years'))+' سنة') if u.get('installment_years') else '—'}</td>"
        f"<td>{_esc(_ar_text(u.get('delivery')) or '—')}</td></tr>"
        for u in units)
    plans = []
    for pl in dict.fromkeys(u.get("payment_plan") for u in units if u.get("payment_plan")):
        plans.append(f"<p>💳 {_esc(pl)}</p>")

    status = p.get("status") or ""
    chips = []
    if p.get("delivery"):
        chips.append(f"<span class='c'>🗓️ التسليم: {_esc(_ar_text(p['delivery']))}</span>")
    if status:
        chips.append(f"<span class='c'>{_esc(_ar_text(status))}</span>")
    if units:
        chips.append(f"<span class='c'>🏠 {len(units)} نوع وحدة</span>")
    updated = (p.get("updated_at") or "")[:10]

    # public developer updates (WhatsApp groups) — public tier only via RLS
    intel = prefetched_intel
    intel_html = ""
    if intel:
        intel_html = ("<div class='sp-sec'><h2>آخر تحديثات المطوّر</h2>" + "".join(
            f"<p>{_esc(i.get('content_ar'))} <small>· {_esc((i.get('observed_at') or '')[:10])}</small></p>" for i in intel) + "</div>")
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
    chat_ctx = html.escape(json.dumps(
        {"name": name, "area": area, "market": "primary"}, ensure_ascii=True), quote=True)

    body = f"""
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/app">المشاريع</a>{(' › ' + _esc(area)) if area else ''} › {_esc(name)}</nav>
    <div class="sp-cover{'' if cover else ' ph'}" style="{('background-image:url(' + chr(39) + _esc(cover) + chr(39) + ')') if cover else ''}">
      <span class="badge">مشروع تطوير{(' · ' + _esc(area)) if area else ''}</span>
    </div>
    <h1>{_esc(name)}</h1>
    <div class="sp-sub">{_esc(dev.get('name') or '')}{(' · ' + _esc(area)) if area else ''}</div>
    {('<div class="sp-price">يبدأ من ' + _money(minp) + '</div>') if minp else ''}
    <div class="sp-chips">{''.join(chips)}</div>
    <div class="sp-top-cta">
      <button class="btn btn-teal" onclick='HZ.openChat({{context:{chat_ctx}}})'>💬 اسأل Homzy عن المشروع ده</button>
      <a class="btn btn-ghost" href="/app?project={pid}">⇄ قارن بمشاريع تانية</a>
    </div>
    {_share_bar(canonical, name)}
    {('<div class="sp-sec"><p>' + _esc(p.get('description')) + '</p></div>') if p.get('description') else ''}
    {('<div class="sp-sec"><div class="sp-gallery">' + ''.join(f'<img loading="lazy" src="{_esc(u)}" alt="{_esc(name)}">' for u in images) + '</div></div>') if images else ''}
    {('<div class="sp-sec"><h2>الوحدات والأسعار</h2><p class="sp-note">ℹ️ الأسعار من آخر تحديث عندنا' + ((' (' + updated + ')') if updated else '') + '، وممكن تتغير — أكّد السعر والتوفّر مع المطوّر قبل الحجز.</p><div class="utscroll"><table class="utable"><thead><tr><th>النوع</th><th>الغرف</th><th>المساحة</th><th>السعر</th><th>المقدم</th><th>التقسيط</th><th>التسليم</th></tr></thead><tbody>' + urows + '</tbody></table></div>' + (''.join(plans)) + '</div>') if units else ''}
    {('<div class="sp-sec"><h2>عن المطوّر' + ((' — ' + _esc(dev.get('name'))) if dev.get('name') else '') + '</h2><p>' + _esc((dev.get('about') or '') + ' ' + (dev.get('track_record') or '')) + '</p></div>') if (dev.get('about') or dev.get('track_record')) else ''}
    {intel_html}
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
           "bedrooms,bathrooms,size_sqm,status,updated_at,owner_id,listing_media(url,sort)")
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

    # brokers usually already wrote the area / "للبيع" into the title — don't repeat them
    said = lambda w: bool(w) and w.replace("ال", "") in title_txt.replace("ال", "")
    title = (title_txt + (f" - {area}" if area and not said(area) else "")
             + ("" if said(purpose[2:]) else f" {purpose}") + " | Homzy")
    size = l.get("size_sqm")
    facts = " · ".join(x for x in [
        _money(price) if price else "",
        f"{l['bedrooms']} غرف" if l.get("bedrooms") else "",
        f"{float(size):g} م²" if size else "",
        area if area and not said(area) else ""] if x)
    desc = _clip(f"{facts}. {l.get('description') or ''}" if facts else (l.get("description") or title_txt), 160)
    canonical = f"{SEO_BASE}/listing/{lid}"
    ver = re.sub(r"\D", "", str(l.get("updated_at") or ""))[:14]
    share_img = f"{SEO_BASE}/og/listing/{lid}.jpg?v={ver}"

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

    # Broker's own registered contact (name/company/phone) — they added it at
    # registration / in "بيانات شركتك"; shown so clients can reach them directly.
    contact_html = ""
    try:
        cr = _rpc("listing_contact", {"p_lid": lid})
        c = cr[0] if cr else {}
    except Exception:
        c = {}
    phone_raw = (c.get("phone") or "").strip()
    if phone_raw:
        wa = _intl_phone(phone_raw)
        who = _esc(c.get("company") or c.get("full_name") or "")
        wtext = quote(f"مهتم بـ {title_txt} — Homzy")
        contact_html = (
            '<div class="sp-sec" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;'
            'background:#fff;border:1px solid var(--line,#EBE5DE);border-radius:16px;padding:16px">'
            + (f'<a href="/broker/{_esc(l.get("owner_id"))}" style="font-weight:800;margin-inline-end:auto;color:inherit">🏢 {who} ←</a>'
               if who and l.get("owner_id") else
               f'<span style="font-weight:800;margin-inline-end:auto">🏢 {who}</span>' if who else
               '<span style="font-weight:800;margin-inline-end:auto">تواصل مع المعلن</span>')
            + f'<a target="_blank" rel="noopener" href="https://wa.me/{wa}?text={wtext}" '
            'style="background:#22C55E;color:#fff;font-weight:800;padding:11px 18px;border-radius:12px;text-decoration:none">💬 واتساب</a>'
            # stored as 2010…: dial it in international form, or the phone treats the 2 as a digit
            + f'<a href="tel:+{wa}" '
            'style="background:#0B1D36;color:#fff;font-weight:800;padding:11px 18px;border-radius:12px;text-decoration:none">📞 اتصال</a>'
            '</div>'
        )

    body = f"""
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/app">سوق العقارات</a>{(' › ' + _esc(area)) if area else ''} › {_esc(title_txt)}</nav>
    <div class="sp-cover" style="{('background-image:url(' + chr(39) + _esc(cover) + chr(39) + ')') if cover else ''}">
      <span class="badge">{purpose}{(' · ' + _esc(area)) if area else ''}</span>
    </div>
    <h1>{_esc(title_txt)}</h1>
    <div class="sp-sub">{_esc(l.get('address') or area)}</div>
    {('<div class="sp-price">' + _money(price) + '</div>') if price else ''}
    <div class="sp-chips">{''.join(chips)}</div>
    {_share_bar(canonical, title_txt)}
    {('<div class="sp-sec"><p>' + _esc(l.get('description')) + '</p></div>') if l.get('description') else ''}
    {('<div class="sp-sec"><div class="sp-gallery">' + ''.join(f'<img loading="lazy" src="{_esc(u)}" alt="{_esc(title_txt)}">' for u in images) + '</div></div>') if images else ''}
    {contact_html}
    <div id="book" style="margin-top:16px"></div>
    <script src="/assets/booking.js?v=2"></script>
    <script>document.addEventListener('DOMContentLoaded',function(){{ HZBook.mount(document.getElementById('book'),{{listingId:'{lid}'}}); if(location.hash==='#book') document.getElementById('book').scrollIntoView();
      // one view per visitor session, for the owner report (the page itself is edge-cached)
      try{{ var k='hzv_{lid}'; if(!sessionStorage.getItem(k)){{ sessionStorage.setItem(k,'1');
        var s=HZ.session&&HZ.session(), src=(document.referrer&&!document.referrer.startsWith(location.origin))?new URL(document.referrer).hostname:'direct';
        fetch(window.SB_URL+'/rest/v1/rpc/listing_view_ping',{{method:'POST',headers:{{apikey:window.SB_KEY,Authorization:'Bearer '+((s&&s.token)||window.SB_KEY),'Content-Type':'application/json'}},body:JSON.stringify({{p_listing:'{lid}',p_source:src}})}}).catch(function(){{}}); }} }}catch(e){{}} }});</script>
    """
    return _page(title, desc, canonical, share_img, jsonld, body, og_size=(1200, 630))


# ---------------------------------------------------------------------------
# Broker public profile (/broker/{id}) — the link a broker puts in their bio.
# ---------------------------------------------------------------------------
def render_broker(bid: str) -> str | None:
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", bid or ""):
        return None
    b = _rpc("broker_public_profile", {"p_id": bid})
    if not b:
        return None
    name = b.get("company") or b.get("name") or "بروكر"
    person = b.get("name") if b.get("company") and b.get("name") != b.get("company") else ""
    rating = b.get("rating") or {}
    listings = b.get("listings") or []
    areas_txt = "، ".join(a for a in (b.get("work_areas") or []) if a)
    since = str(b.get("since") or "")[:4]
    canonical = f"{SEO_BASE}/broker/{bid}"
    title = f"{name} — بروكر عقارات على Homzy"
    facts = [f"{b.get('listings_count') or 0} وحدة متاحة"]
    if rating.get("n"):
        facts.append(f"تقييم {rating.get('avg')}/5 من {rating.get('n')} عميل")
    if b.get("viewings_done"):
        facts.append(f"{b['viewings_done']} معاينة تمّت")
    desc = _clip(" · ".join(facts) + (f" · {areas_txt}" if areas_txt else ""), 160)
    img = b.get("logo") or b.get("avatar") or next((x["cover"] for x in listings if x.get("cover")), "")
    jsonld = {"@context": "https://schema.org", "@type": "RealEstateAgent", "name": name, "url": canonical}
    if img:
        jsonld["image"] = img
    if rating.get("n"):
        jsonld["aggregateRating"] = {"@type": "AggregateRating", "ratingValue": rating.get("avg"),
                                     "reviewCount": rating.get("n"), "bestRating": 5}

    wa = _intl_phone(b.get("phone") or "")
    stars = lambda n: "★" * int(n or 0) + "☆" * (5 - int(n or 0))
    stat = lambda v, lbl: (f'<div style="flex:1;min-width:110px;background:#fff;border:1px solid var(--line);border-radius:14px;'
                           f'padding:12px;text-align:center"><b style="display:block;font-size:22px;color:var(--navy)">{v}</b>'
                           f'<span style="font-size:12.5px;color:var(--muted);font-weight:700">{lbl}</span></div>')
    cards = "".join(
        f'<a class="devchip" href="/listing/{_esc(x["id"])}" style="padding:0;overflow:hidden">'
        f'<div style="height:120px;background:#e9e2da {("url(" + chr(39) + _esc(x["cover"]) + chr(39) + ")") if x.get("cover") else ""} center/cover no-repeat"></div>'
        f'<div style="padding:9px 11px"><b>{_esc(x.get("title") or "وحدة")}</b>'
        f'<span>{_esc(x.get("area") or "")}{(" · " + str(x["bedrooms"]) + " غرف") if x.get("bedrooms") else ""}</span>'
        f'<span style="color:var(--teal-d);font-weight:800">{_money(x.get("price")) if x.get("price") else ""}'
        f'{" / شهر" if x.get("purpose") == "rent" and x.get("price") else ""}</span></div></a>'
        for x in listings)
    reviews = "".join(
        f'<div style="border-bottom:1px solid var(--line);padding:8px 0;font-size:14px">'
        f'<span style="color:#F59E0B">{stars(r.get("rating"))}</span> — {_esc(r.get("comment"))}</div>'
        for r in (b.get("reviews") or []))
    logo = (f'<img src="{_esc(img)}" alt="" style="width:76px;height:76px;border-radius:18px;object-fit:cover;'
            f'border:1px solid var(--line);background:#fff">' if img else
            '<div style="width:76px;height:76px;border-radius:18px;background:var(--navy);color:#fff;display:flex;'
            f'align-items:center;justify-content:center;font-size:30px;font-weight:900">{_esc(name[:1])}</div>')
    body = f"""
    <nav class="sp-crumb"><a href="/">Homzy</a> › <a href="/app">سوق العقارات</a> › {_esc(name)}</nav>
    <div style="display:flex;gap:14px;align-items:center;flex-wrap:wrap">
      {logo}
      <div style="flex:1;min-width:200px"><h1 style="margin:0">{_esc(name)}{' <span title="رقم موبايل متأكد منه" style="font-size:16px;color:#1E8E5A">✔︎</span>' if b.get('verified') else ''}</h1>
        <div class="sp-sub">{_esc(person)}{' · ' if person and since else ''}{('على Homzy من ' + since) if since else ''}</div>
        {('<div class="sp-sub" style="margin-top:2px">📍 ' + _esc(areas_txt) + '</div>') if areas_txt else ''}</div>
    </div>
    <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:16px">
      {stat((str(rating.get('avg')) + '/5') if rating.get('n') else '—', ('تقييم ' + str(rating.get('n')) + ' عميل بعد المعاينة') if rating.get('n') else 'لسه مفيش تقييمات')}
      {stat(b.get('viewings_done') or 0, 'معاينة تمّت على Homzy')}
      {stat(b.get('listings_count') or 0, 'وحدة متاحة دلوقتي')}
    </div>
    {('<div class="sp-top-cta" style="margin-top:14px">'
      + f'<a class="btn" target="_blank" rel="noopener" href="https://wa.me/{wa}?text={quote("أهلاً، شفت صفحتك على Homzy")}" style="background:#22C55E;color:#fff">💬 واتساب</a>'
      + f'<a class="btn" href="tel:+{wa}" style="background:#0B1D36;color:#fff">📞 اتصال</a></div>') if wa else ''}
    {_share_bar(canonical, title)}
    {('<div class="sp-sec"><h2>آراء العملاء بعد المعاينة</h2>' + reviews + '</div>') if reviews else ''}
    <div class="sp-sec"><h2>الوحدات المتاحة ({b.get('listings_count') or 0})</h2>
      {('<div class="devgrid">' + cards + '</div>') if cards else '<p>مفيش وحدات منشورة دلوقتي.</p>'}
      <p style="font-size:13px;margin-top:10px">تقدر تحجز معاينة من صفحة أي وحدة — هتختار ميعاد من المواعيد المتاحة فعلاً.</p></div>
    """
    return _page(title, desc, canonical, img, jsonld, body)


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
    <div class="sp-cta" style="display:flex;gap:10px;flex-wrap:wrap">
      <a class="btn btn-teal" href="/app?area={_esc(label)}">اتصفّح كل مشاريع {_esc(label)} ←</a>
      <a class="btn btn-ghost" href="/community/{area_slug(label)}">💬 شات بروكرز {_esc(label)}</a>
    </div>
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
