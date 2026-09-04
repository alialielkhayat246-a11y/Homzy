"""FastAPI server: serves the chat UI and the broker API.

Run from the project root:
    python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
"""
from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import (FileResponse, HTMLResponse, JSONResponse,
                               Response, StreamingResponse)
import json as _json
from fastapi.staticfiles import StaticFiles

from . import (broker, config, listings as listings_mod, llm, notify, push,
               seo, valuation)

app = FastAPI(title="Homzy Broker")

# Allow the web build (hosted on a different origin) to call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Brand assets (logo etc.) — drop files into frontend/assets/ and they're served.
# The mkdir is best-effort: on a read-only host (e.g. Vercel) the dir is shipped
# in the bundle and creating it would fail, so we tolerate that.
_assets_dir = config.FRONTEND_DIR / "assets"
try:
    _assets_dir.mkdir(parents=True, exist_ok=True)
except OSError:
    pass
if _assets_dir.is_dir():
    app.mount("/assets", StaticFiles(directory=_assets_dir), name="assets")

# In-memory sessions: fine for Phase 1 (single tester). Not persisted.
SESSIONS: dict[str, dict[str, Any]] = {}


@app.get("/")
def index():
    return FileResponse(config.FRONTEND_DIR / "index.html")


@app.get("/app")
@app.get("/browse")
@app.get("/projects")
def browse_page():
    """Functional web browse page (developer projects + marketplace)."""
    return FileResponse(config.FRONTEND_DIR / "app.html")


# Marketing sections — each on its own page/link (shared shell in /assets).
@app.get("/features")
def features_page():
    return FileResponse(config.FRONTEND_DIR / "features.html")


@app.get("/areas")
def areas_page():
    return FileResponse(config.FRONTEND_DIR / "areas.html")


@app.get("/brokers")
def brokers_page():
    return FileResponse(config.FRONTEND_DIR / "brokers.html")


@app.get("/download")
def download_page():
    return FileResponse(config.FRONTEND_DIR / "download.html")


@app.get("/leads")
def leads_page():
    """Broker leads marketplace (browse leads, pay to reveal the phone)."""
    return FileResponse(config.FRONTEND_DIR / "leads.html")


@app.get("/clients")
def clients_page():
    """Broker CRM — manage clients through a sales pipeline, match units, and
    generate offers. Auth + CRUD run client-side against Supabase (RLS scopes
    every client row to owner_id = the signed-in broker)."""
    return FileResponse(config.FRONTEND_DIR / "clients.html")


@app.get("/my-listings")
def my_listings_page():
    """Broker dashboard: post / edit / delete their own units (listings) with
    photos. Auth + all CRUD run client-side against Supabase (RLS scopes every
    row to owner_id = the signed-in broker)."""
    return FileResponse(config.FRONTEND_DIR / "my-listings.html")


@app.get("/sell")
def sell_page():
    """Public broker-acquisition landing ('list your unit on Homzy'). Shareable
    + indexable; its CTAs go to /my-listings (which handles login/registration)."""
    return FileResponse(config.FRONTEND_DIR / "sell.html")


@app.get("/map")
def map_page():
    """Interactive area map (Leaflet + OpenStreetMap). Gated like the rest of the
    app; markers are areas sized by project count, click → browse that area."""
    return FileResponse(config.FRONTEND_DIR / "map.html")


@app.get("/inbox")
def inbox_page():
    """Admin leads inbox — reads web_leads client-side with the admin's Google
    session; RLS restricts SELECT to profiles.is_admin, so non-admins see nothing."""
    return FileResponse(config.FRONTEND_DIR / "leads-inbox.html")


@app.get("/login")
def login_page():
    """Client sign-in / sign-up gate. Everything past the public homepage
    requires a session (see the head guard on the protected pages)."""
    return FileResponse(config.FRONTEND_DIR / "login.html")


# --- Homzy Stays (short-term rental marketplace) ------------------------
# Guest browse pages are PUBLIC (no login gate) so they can rank in Google;
# booking/host/dashboard actions require a session (checked client-side).
@app.get("/stays")
def stays_page():
    """Homzy Stays landing + search (public)."""
    return FileResponse(config.FRONTEND_DIR / "stays.html")


@app.get("/stays/host/{hid}")
def stay_host_profile_page(hid: str):
    """Public host reputation profile."""
    return FileResponse(config.FRONTEND_DIR / "host-profile.html")


_STAY_META_DEFAULT = (
    '<title>Homzy Stays</title>'
    '<meta name="description" content="تفاصيل الإقامة على Homzy Stays — الصور، '
    'المميزات، السعر، والحجز الآمن." />'
    '<link rel="canonical" href="https://homzy-ai.com/stays" />'
)


@app.get("/stays/{pid}")
def stay_detail_page(pid: str):
    """Public property detail + booking flow, with server-rendered SEO meta
    (title/description/OG/JSON-LD) injected so property pages rank in Google."""
    path = config.FRONTEND_DIR / "stay.html"
    try:
        page = path.read_text(encoding="utf-8")
        meta = None
        try:
            meta = seo.stay_meta(pid)
        except Exception:
            meta = None
        page = page.replace("<!--HZ_SEO-->", meta or _STAY_META_DEFAULT, 1)
        return HTMLResponse(page)
    except Exception:
        return FileResponse(path)


@app.get("/host")
def host_landing_page():
    """Become-a-host landing (Homzy Stays)."""
    return FileResponse(config.FRONTEND_DIR / "host.html")


# Host dashboard — one page, tab chosen from the path (properties/new/calendar/
# bookings/earnings/reviews/verification). All require a session (client-side gate).
@app.get("/host/properties")
@app.get("/host/properties/new")
@app.get("/host/properties/{pid}")
@app.get("/host/calendar")
@app.get("/host/bookings")
@app.get("/host/earnings")
@app.get("/host/reviews")
@app.get("/host/verification")
@app.get("/host/profile")
def host_dashboard_page(pid: str = ""):
    return FileResponse(config.FRONTEND_DIR / "host-dashboard.html")


@app.get("/my-stays")
def my_stays_page():
    """Guest bookings dashboard."""
    return FileResponse(config.FRONTEND_DIR / "my-stays.html")


@app.get("/my-stays/{bid}")
def my_stay_detail_page(bid: str = ""):
    return FileResponse(config.FRONTEND_DIR / "my-stays.html")


# Public, crawlable per-project / per-listing pages (outside the login gate) so
# broker + developer units can rank in Google; the contact action stays gated.
@app.get("/project/{pid}")
def project_page(pid: str):
    try:
        page = seo.render_project(pid)
    except Exception:
        page = None
    if not page:
        return HTMLResponse(_not_found_html(), status_code=404)
    return HTMLResponse(page)


@app.get("/listing/{lid}")
def listing_page(lid: str):
    try:
        page = seo.render_listing(lid)
    except Exception:
        page = None
    if not page:
        return HTMLResponse(_not_found_html(), status_code=404)
    return HTMLResponse(page)


@app.get("/area/{slug}")
def area_page(slug: str):
    try:
        page = seo.render_area(slug)
    except Exception:
        page = None
    if not page:
        return HTMLResponse(_not_found_html(), status_code=404)
    return HTMLResponse(page)


def _not_found_html() -> str:
    return ('<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">'
            '<meta name="robots" content="noindex"><title>Homzy — غير موجود</title>'
            '<link rel="icon" href="/favicon.ico">'
            '<style>body{font-family:system-ui,Cairo,sans-serif;background:#F7F3EC;color:#0B1D36;'
            'display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;text-align:center}'
            'a{color:#0B5563;font-weight:800}</style></head><body><div><h1>الصفحة مش موجودة</h1>'
            '<p>العقار ده مش متاح دلوقتي. <a href="/app">اتصفّح باقي المشاريع</a></p></div></body></html>')


# ---------------------------------------------------------------------------
# SEO: robots.txt + sitemap.xml (public marketing pages only).
# ---------------------------------------------------------------------------
SEO_BASE = "https://homzy-ai.com"
# Public, crawlable pages: the homepage + the areas hub (its cards link to the
# per-area landing pages, which the sitemap also lists). The rest of the app
# stays behind the login gate.
_PUBLIC_PATHS = ["/", "/areas", "/sell"]


@app.get("/robots.txt")
def robots_txt():
    body = (
        "User-agent: *\n"
        "Allow: /\n"
        "Disallow: /leads\n"
        "Disallow: /admin\n"
        "Disallow: /api/\n"
        f"Sitemap: {SEO_BASE}/sitemap.xml\n"
    )
    return Response(body, media_type="text/plain")


import time as _time
_SITEMAP_CACHE: dict[str, object] = {"xml": None, "at": 0.0}
_SITEMAP_TTL = 3600  # 1h — the catalog rarely changes and crawlers refetch often


def _build_sitemap() -> str:
    urls = "".join(
        f"<url><loc>{SEO_BASE}{p}</loc>"
        f"<changefreq>daily</changefreq>"
        f"<priority>1.0</priority></url>"
        for p in _PUBLIC_PATHS
    )
    try:
        deep = seo.sitemap_urls()
    except Exception:
        deep = []
    urls += "".join(
        f"<url><loc>{loc}</loc><changefreq>{cf}</changefreq><priority>0.7</priority></url>"
        for loc, cf in deep
    )
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
            f"{urls}</urlset>")


@app.get("/sitemap.xml")
def sitemap_xml():
    # Cache the rendered XML so Google's fetch is fast + reliable (building it
    # pulls ~1000 rows from Supabase, which can be slow enough to trip a
    # "temporary processing error" on every fetch).
    now = _time.time()
    xml = _SITEMAP_CACHE["xml"]
    if not xml or now - float(_SITEMAP_CACHE["at"]) > _SITEMAP_TTL:
        xml = _build_sitemap()
        _SITEMAP_CACHE["xml"], _SITEMAP_CACHE["at"] = xml, now
    return Response(xml, media_type="application/xml",
                    headers={"Cache-Control": "public, max-age=3600"})


# ---------------------------------------------------------------------------
# Brand icons at stable root URLs. Google looks for /favicon.ico at the site
# root to show the site's icon next to the search result, so it must be a real
# crawlable file (a data: URI is ignored). Also serves the PWA manifest.
# ---------------------------------------------------------------------------
@app.get("/favicon.ico")
def favicon():
    return FileResponse(config.FRONTEND_DIR / "assets" / "favicon.ico",
                        media_type="image/x-icon")


@app.get("/apple-touch-icon.png")
@app.get("/apple-touch-icon-precomposed.png")
def apple_touch_icon():
    return FileResponse(config.FRONTEND_DIR / "assets" / "apple-touch-icon.png",
                        media_type="image/png")


@app.get("/site.webmanifest")
def webmanifest():
    return FileResponse(config.FRONTEND_DIR / "site.webmanifest",
                        media_type="application/manifest+json")


@app.get("/api/health")
def health():
    provider = config.LLM_PROVIDER
    reachable = False
    detail = ""
    if provider == "mock":
        detail = "Preview mode: no AI engine — replies are templated but use real listings."
    else:
        try:
            client = llm.get_client()
            reachable = bool(getattr(client, "available", lambda: False)())
            if not reachable and provider == "ollama":
                detail = "Ollama isn't running yet — start it (see README) for full AI chat."
        except llm.LLMUnavailable as exc:
            detail = str(exc)
    mode = "ai" if (provider != "mock" and reachable) else "template"
    return {
        "provider": provider,
        "reachable": reachable,
        "mode": mode,
        "brand": config.BRAND_NAME,
        "broker": config.BROKER_NAME,
        "listings": len(listings_mod.load()),
        "detail": detail,
    }


@app.post("/api/chat")
async def chat(req: Request):
    body = await req.json()
    session_id = body.get("session_id", "default")
    message = (body.get("message") or "").strip()
    if not message:
        return JSONResponse({"error": "empty message"}, status_code=400)
    session = SESSIONS.setdefault(session_id, {})
    history = body.get("history")
    if not isinstance(history, list):
        history = None
    coach = body.get("mode") == "broker"
    return broker.handle_turn(session, message, client_history=history, coach=coach)


@app.post("/api/chat/stream")
async def chat_stream(req: Request):
    """Streaming version of /api/chat — emits newline-delimited JSON events
    ({type: meta|token|done}) so the reply appears word-by-word."""
    body = await req.json()
    session_id = body.get("session_id", "default")
    message = (body.get("message") or "").strip()
    if not message:
        return JSONResponse({"error": "empty message"}, status_code=400)
    session = SESSIONS.setdefault(session_id, {})
    history = body.get("history")
    if not isinstance(history, list):
        history = None
    coach = body.get("mode") == "broker"

    def gen():
        for evt in broker.handle_turn_stream(session, message, client_history=history, coach=coach):
            yield _json.dumps(evt, ensure_ascii=False) + "\n"

    return StreamingResponse(gen(), media_type="application/x-ndjson",
                             headers={"X-Accel-Buffering": "no",
                                      "Cache-Control": "no-cache"})


@app.post("/api/estimate")
async def estimate(req: Request):
    """Resale price estimate for a unit from comparable catalog units."""
    body = await req.json()
    try:
        size = float(body.get("size") or 0)
    except (TypeError, ValueError):
        size = 0
    return valuation.estimate(
        area=(body.get("area") or "").strip() or None,
        type_=(body.get("type") or "").strip() or None,
        size=size,
        finishing=(body.get("finishing") or "").strip() or None,
    )


@app.post("/api/offer")
async def offer(req: Request):
    """AI-written selling advantages for a broker's PDF offer (grounded in the
    real unit facts the client sends). Returns {advantages: [...]}"""
    body = await req.json()
    unit = body.get("unit") or {}
    language = "ar" if (body.get("language") or "ar").startswith("ar") else "en"
    try:
        adv = broker.offer_advantages(unit, language)
    except Exception:
        adv = []
    return {"advantages": adv}


@app.post("/api/parse-client")
async def parse_client(req: Request):
    """Voice → structured CRM fields: the broker speaks, the browser transcribes,
    and this turns the Arabic sentence into client fields to fill/merge the form."""
    body = await req.json()
    text = (body.get("text") or "").strip()
    if not text:
        return {"fields": {}}
    try:
        fields = broker.parse_client(text)
    except Exception:
        fields = {}
    return {"fields": fields}


@app.get("/sw.js")
def service_worker():
    """The push service worker. Must be served from root so its scope is the
    whole site (the browser refuses a wider scope than the script's path)."""
    return FileResponse(
        config.FRONTEND_DIR / "sw.js",
        media_type="application/javascript",
        headers={"Service-Worker-Allowed": "/", "Cache-Control": "no-cache"},
    )


@app.get("/api/push/config")
def push_config():
    """Public VAPID key the browser needs to subscribe. Safe to expose."""
    return {"publicKey": config.VAPID_PUBLIC_KEY, "enabled": push.enabled()}


@app.post("/api/push/run-followups")
async def push_run_followups(req: Request):
    """Daily reminder fan-out. Guarded by PUSH_CRON_TOKEN (the scheduler sends
    it as ?token= or the X-Push-Token header) so only our cron can trigger it."""
    token = req.query_params.get("token") or req.headers.get("x-push-token") or ""
    if not config.PUSH_CRON_TOKEN or token != config.PUSH_CRON_TOKEN:
        raise HTTPException(status_code=403, detail="forbidden")
    return push.run_followups()


@app.post("/api/stays/cron")
async def stays_cron(req: Request):
    """Daily Homzy Stays maintenance: complete past-checkout bookings and publish
    reviews whose window expired. Guarded by PUSH_CRON_TOKEN; the scheduler (n8n)
    sends it as ?token=. The RPCs are secret-gated with the same shared token."""
    token = req.query_params.get("token") or req.headers.get("x-push-token") or ""
    if not config.PUSH_CRON_TOKEN or token != config.PUSH_CRON_TOKEN:
        raise HTTPException(status_code=403, detail="forbidden")
    import requests

    hdr = {"apikey": config.SUPABASE_KEY,
           "Authorization": "Bearer " + config.SUPABASE_KEY,
           "Content-Type": "application/json"}
    out: dict[str, Any] = {}
    for fn in ("stay_complete_due_bookings", "stay_publish_expired_reviews"):
        try:
            r = requests.post(
                config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/" + fn,
                headers=hdr, json={"p_key": config.PUSH_CRON_TOKEN}, timeout=25,
            )
            out[fn] = r.json() if r.ok else {"error": r.status_code, "detail": r.text[:200]}
        except Exception as exc:  # pragma: no cover
            out[fn] = {"error": str(exc)}
    return {"ok": True, "results": out}


@app.post("/api/lead-contact")
async def lead_contact(req: Request):
    """A signed-in client asked a sales rep to contact them. Emails the operator
    with the client's REGISTERED name + phone (read server-side, not trusted from
    the browser). Best-effort: the lead is also recorded client-side (web_leads)."""
    body = await req.json()
    token = (body.get("token") or "").strip()
    return notify.handle_lead_contact(
        token, body.get("context") or "", body.get("message") or "",
        body.get("lang") or "ar",
    )


@app.post("/api/reset")
async def reset(req: Request):
    body = await req.json()
    SESSIONS.pop(body.get("session_id", "default"), None)
    return {"ok": True}


# --------------------------------------------------------------------------
# Phase 2 — listings admin panel
#
# CRUD over data/listings.json. Writes are gated by an optional ADMIN_TOKEN
# (sent as the X-Admin-Token header); when it's blank the panel is open, which
# is fine for local single-user use.
# --------------------------------------------------------------------------
@app.get("/admin")
def admin_page():
    return FileResponse(config.FRONTEND_DIR / "admin.html")


# Homzy Stays admin — one page, tab chosen from the path. Access is enforced by
# RLS (is_admin) on the data itself; non-admins simply see empty lists.
@app.get("/admin/stays")
@app.get("/admin/stays/properties")
@app.get("/admin/stays/bookings")
@app.get("/admin/stays/hosts")
@app.get("/admin/stays/reviews")
@app.get("/admin/stays/verifications")
@app.get("/admin/stays/disputes")
@app.get("/admin/stays/settings")
def admin_stays_page():
    return FileResponse(config.FRONTEND_DIR / "admin-stays.html")


def _require_admin(token: str | None) -> None:
    if config.ADMIN_TOKEN:
        if token != config.ADMIN_TOKEN:
            raise HTTPException(status_code=401, detail="Invalid or missing admin token")
        return
    # No token configured. Open locally (single-user dev), but FAIL CLOSED on a
    # public host so an unconfigured deployment never exposes the inventory.
    if config.IS_HOSTED:
        raise HTTPException(
            status_code=403,
            detail="Admin panel is disabled on this deployment. Set ADMIN_TOKEN to enable it.",
        )


@app.get("/api/listings")
def list_listings(x_admin_token: str | None = Header(default=None)):
    """Full records — the admin panel needs every field to edit them.

    Protected: on a public host this requires the admin token, so the internal
    dashboard and inventory are never readable from the open URL.
    """
    _require_admin(x_admin_token)
    return {"listings": listings_mod.load(), "auth_required": bool(config.ADMIN_TOKEN)}


@app.post("/api/listings")
async def create_listing(req: Request, x_admin_token: str | None = Header(default=None)):
    _require_admin(x_admin_token)
    try:
        return listings_mod.add(await req.json())
    except listings_mod.ListingError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.put("/api/listings/{listing_id}")
async def edit_listing(listing_id: str, req: Request,
                       x_admin_token: str | None = Header(default=None)):
    _require_admin(x_admin_token)
    try:
        return listings_mod.update(listing_id, await req.json())
    except listings_mod.ListingError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.delete("/api/listings/{listing_id}")
def remove_listing(listing_id: str, x_admin_token: str | None = Header(default=None)):
    _require_admin(x_admin_token)
    try:
        listings_mod.delete(listing_id)
    except listings_mod.ListingError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return {"ok": True}
