"""Vercel serverless entrypoint for the Homzy backend.

Vercel's Python runtime serves the ASGI `app` exported here. We add the repo
root to sys.path so `backend` imports resolve, and default to template/preview
mode because Ollama can't run on serverless (set LLM_PROVIDER=gemini + a key in
the Vercel project env for real AI replies).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("LLM_PROVIDER", "mock")

from backend.app import app  # noqa: E402  (import after sys.path tweak)

# Vercel looks for a module-level `app` (ASGI) — re-exported above.
