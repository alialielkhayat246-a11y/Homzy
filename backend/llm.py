"""Pluggable, free LLM layer.

Default engine is local Ollama (no API key, no cost). A free Google Gemini
tier is supported as an alternative. The 'mock' provider means no AI engine at
all — the broker falls back to grounded templated replies.
"""
from __future__ import annotations

from typing import Any

from . import config


class LLMUnavailable(Exception):
    """Raised when the chosen engine can't be reached or isn't configured."""


class OllamaClient:
    """Talks to a local Ollama server. Free, offline, no key."""

    name = "ollama"

    def __init__(self) -> None:
        self.host = config.OLLAMA_HOST.rstrip("/")
        self.model = config.OLLAMA_MODEL

    def chat(self, messages: list[dict[str, str]], temperature: float = 0.6,
             force_json: bool = False) -> str:
        import requests  # imported lazily so 'mock' mode needs no dependency

        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": temperature},
        }
        if force_json:
            payload["format"] = "json"
        try:
            resp = requests.post(f"{self.host}/api/chat", json=payload, timeout=180)
            resp.raise_for_status()
        except Exception as exc:  # connection refused, timeout, model missing...
            raise LLMUnavailable(f"Ollama not reachable at {self.host}: {exc}")
        data = resp.json()
        return (data.get("message") or {}).get("content", "").strip()

    def available(self) -> bool:
        try:
            import requests

            resp = requests.get(f"{self.host}/api/tags", timeout=3)
            resp.raise_for_status()
            return True
        except Exception:
            return False


class GeminiClient:
    """Google Gemini via the free AI Studio tier. Needs a free GEMINI_API_KEY.

    Talks to the REST API directly with `requests` (no heavy SDK) so it stays
    light for serverless hosting (e.g. Vercel) and avoids the deprecated
    google-generativeai package.
    """

    name = "gemini"
    _BASE = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(self) -> None:
        if not config.GEMINI_API_KEY:
            raise LLMUnavailable("GEMINI_API_KEY is not set")
        self.api_key = config.GEMINI_API_KEY
        self.model = config.GEMINI_MODEL

    def chat(self, messages: list[dict[str, str]], temperature: float = 0.6,
             force_json: bool = False) -> str:
        import requests  # imported lazily so 'mock' mode needs no dependency

        system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
        contents = []
        for m in messages:
            if m["role"] == "system":
                continue
            role = "user" if m["role"] == "user" else "model"
            contents.append({"role": role, "parts": [{"text": m["content"]}]})

        gen_cfg: dict[str, Any] = {"temperature": temperature}
        if force_json:
            gen_cfg["responseMimeType"] = "application/json"
        payload: dict[str, Any] = {"contents": contents, "generationConfig": gen_cfg}
        if system:
            payload["systemInstruction"] = {"parts": [{"text": system}]}

        url = f"{self._BASE}/models/{self.model}:generateContent"
        try:
            resp = requests.post(
                url,
                headers={"x-goog-api-key": self.api_key,
                         "Content-Type": "application/json"},
                json=payload,
                timeout=120,
            )
            resp.raise_for_status()
        except Exception as exc:
            raise LLMUnavailable(f"Gemini request failed: {exc}")
        data = resp.json()
        try:
            parts = data["candidates"][0]["content"]["parts"]
            return "".join(p.get("text", "") for p in parts).strip()
        except (KeyError, IndexError):
            return ""

    def available(self) -> bool:
        return bool(self.api_key)


def get_client(provider: str | None = None):
    """Return an LLM client for the configured provider, or None for 'mock'."""
    provider = (provider or config.LLM_PROVIDER).lower()
    if provider == "gemini":
        return GeminiClient()
    if provider == "mock":
        return None
    # default / unknown -> ollama
    return OllamaClient()
