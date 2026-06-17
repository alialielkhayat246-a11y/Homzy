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
GEMINI_MODEL = _get("GEMINI_MODEL", "gemini-2.0-flash")

# --- Brand / persona -----------------------------------------------------
BRAND_NAME = _get("BRAND_NAME", "Homzy")
BROKER_NAME = _get("BROKER_NAME", "Nour")

# --- Behaviour -----------------------------------------------------------
MAX_RESULTS = int(_get("MAX_RESULTS", "4"))
LLM_TEMPERATURE = float(_get("LLM_TEMPERATURE", "0.6"))
