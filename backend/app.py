"""FastAPI server: serves the chat UI and the broker API.

Run from the project root:
    python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
"""
from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import broker, config, listings as listings_mod, llm

app = FastAPI(title="Homzy Broker")

# Brand assets (logo etc.) — drop files into frontend/assets/ and they're served.
(config.FRONTEND_DIR / "assets").mkdir(parents=True, exist_ok=True)
app.mount("/assets", StaticFiles(directory=config.FRONTEND_DIR / "assets"), name="assets")

# In-memory sessions: fine for Phase 1 (single tester). Not persisted.
SESSIONS: dict[str, dict[str, Any]] = {}


@app.get("/")
def index():
    return FileResponse(config.FRONTEND_DIR / "index.html")


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
    return broker.handle_turn(session, message)


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


def _require_admin(token: str | None) -> None:
    if config.ADMIN_TOKEN and token != config.ADMIN_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing admin token")


@app.get("/api/listings")
def list_listings():
    """Full records — the admin panel needs every field to edit them."""
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
