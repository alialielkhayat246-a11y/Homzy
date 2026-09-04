"""Central configuration for the Homzy broker brain.

Everything is read from environment variables (optionally a .env file) so the
non-technical operator can change the persona, brand, or LLM engine without
touching code. See .env.example for the full list.
"""
from __future__ import annotations

import os
from pathlib import Path

# Load .env if python-dotenv is available (optional dependency).
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
except Exception:
    pass

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
FRONTEND_DIR = PROJECT_ROOT / "frontend"


def _get(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


# --- LLM engine (all free options) --------------------------------------
# ollama  -> local, free, no key, runs on this PC      (default)
# gemini  -> Google AI Studio free tier, needs a free key
# mock    -> no AI engine; templated replies only (instant preview)
LLM_PROVIDER = _get("LLM_PROVIDER", "ollama").lower()

OLLAMA_HOST = _get("OLLAMA_HOST", "http://127.0.0.1:11434")
OLLAMA_MODEL = _get("OLLAMA_MODEL", "qwen2.5:7b")

GEMINI_API_KEY = _get("GEMINI_API_KEY", "")
# gemini-2.5-flash: strongest reasoning on the free tier (llm.py falls back to
# other free models if it's rate-limited).
GEMINI_MODEL = _get("GEMINI_MODEL", "gemini-2.5-flash")

# --- Brand / persona -----------------------------------------------------
BRAND_NAME = _get("BRAND_NAME", "Homzy")
BROKER_NAME = _get("BROKER_NAME", "Homzy")

# --- Supabase catalog (developers/projects/units feed the chat) ---------
SUPABASE_URL = _get("SUPABASE_URL", "")
SUPABASE_KEY = _get("SUPABASE_ANON_KEY", "")

# Run a second LLM call to extract search criteria across the whole
# conversation. On by default now (the stronger model understands nuance the
# heuristics miss, e.g. "something cheap near services"), for better matches.
LLM_EXTRACT = _get("LLM_EXTRACT", "1") == "1"

# --- Admin panel (Phase 2) ----------------------------------------------
# Optional password for the listings admin panel. Leave empty for local,
# single-user use; set it before exposing Homzy on a network.
ADMIN_TOKEN = _get("ADMIN_TOKEN", "")

# True on a serverless/public host (Vercel sets these). Used to FAIL CLOSED:
# the admin panel is refused on a public deployment unless ADMIN_TOKEN is set,
# so an unconfigured deploy can never expose read/write of the inventory.
IS_HOSTED = bool(os.environ.get("VERCEL") or os.environ.get("VERCEL_ENV")
                 or os.environ.get("AWS_LAMBDA_FUNCTION_NAME"))

# --- Web Push (broker follow-up reminders) -------------------------------
# Background notifications to the broker's device, even when the app is closed.
# The PUBLIC key is safe to ship in the frontend; the PRIVATE key must stay a
# server secret (set it in the Vercel env, never commit it).
VAPID_PUBLIC_KEY = _get(
    "VAPID_PUBLIC_KEY",
    "BCuomI2RTVdHmy0pjZciv6j5VdG8n5-K_3wJ15-6EyFRv_2Jcb9UOPJxcaDPbPpBVivBdFQqW2lh4gCAISxcfxI",
)
VAPID_PRIVATE_KEY = _get("VAPID_PRIVATE_KEY", "")
VAPID_SUBJECT = _get("VAPID_SUBJECT", "mailto:hello@homzy-ai.com")

# Shared secret for the daily reminder job. It guards the /api/push endpoint
# AND authenticates the secret-gated SECURITY DEFINER RPCs that read due
# follow-ups + prune dead subscriptions — so no service_role key is needed.
PUSH_CRON_TOKEN = _get("PUSH_CRON_TOKEN", "")

# --- Lead notification email (a client asks a sales rep to contact them) ------
# SMTP is optional: if not configured, the lead is still recorded (visible in
# /inbox) — the email is just an extra. Spacemail: mail.spacemail.com:465 (SSL).
SMTP_HOST = _get("SMTP_HOST", "mail.spacemail.com")
SMTP_PORT = int(_get("SMTP_PORT", "465"))
SMTP_USER = _get("SMTP_USER", "")
SMTP_PASS = _get("SMTP_PASS", "")
LEAD_NOTIFY_FROM = _get("LEAD_NOTIFY_FROM", "") or SMTP_USER
LEAD_NOTIFY_TO = _get("LEAD_NOTIFY_TO", "hello@homzy-ai.com")

# --- Paymob (Accept) payment gateway --------------------------------------
# Server secrets — set in the Vercel env, never committed. Empty => payments off
# (the mock/trial paths keep working). Test with Paymob's test keys first.
PAYMOB_SECRET_KEY = _get("PAYMOB_SECRET_KEY", "")
PAYMOB_PUBLIC_KEY = _get("PAYMOB_PUBLIC_KEY", "")
PAYMOB_HMAC = _get("PAYMOB_HMAC", "")
# Comma-separated integration IDs (card / wallet) from Paymob → Payment Integrations.
PAYMOB_INTEGRATION_IDS = _get("PAYMOB_INTEGRATION_IDS", "")
PAYMOB_BASE = _get("PAYMOB_BASE", "https://accept.paymob.com")
# Where the browser returns after paying, and where Paymob POSTs the result.
PUBLIC_SITE = _get("PUBLIC_SITE", "https://homzy-ai.com")
API_SITE = _get("API_SITE", "https://homzy-jet.vercel.app")

# --- Behaviour -----------------------------------------------------------
MAX_RESULTS = int(_get("MAX_RESULTS", "4"))
LLM_TEMPERATURE = float(_get("LLM_TEMPERATURE", "0.6"))
