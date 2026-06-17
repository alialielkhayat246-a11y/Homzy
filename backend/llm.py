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
    """Google Gemini via the free AI Studio tier. Needs a free GEMINI_API_KEY."""

    name = "gemini"

    def __init__(self) -> None:
        if not config.GEMINI_API_KEY:
            raise LLMUnavailable("GEMINI_API_KEY is not set")
        try:
            import google.generativeai as genai
        except Exception as exc:
            raise LLMUnavailable(
                "google-generativeai is not installed (pip install google-generativeai): " + str(exc)
            )
        genai.configure(api_key=config.GEMINI_API_KEY)
        self._genai = genai
        self.model = config.GEMINI_MODEL

    def chat(self, messages: list[dict[str, str]], temperature: float = 0.6,
             force_json: bool = False) -> str:
        system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
        contents = []
        for m in messages:
            if m["role"] == "system":
                continue
            role = "user" if m["role"] == "user" else "model"
            contents.append({"role": role, "parts": [m["content"]]})
        gen_cfg: dict[str, Any] = {"temperature": temperature}
        if force_json:
            gen_cfg["response_mime_type"] = "application/json"
        try:
            model = self._genai.GenerativeModel(
                self.model,
                system_instruction=system or None,
                generation_config=gen_cfg,
            )
            resp = model.generate_content(contents)
            return (resp.text or "").strip()
        except Exception as exc:
            raise LLMUnavailable(f"Gemini request failed: {exc}")

    def available(self) -> bool:
        return True


def get_client(provider: str | None = None):
    """Return an LLM client for the configured provider, or None for 'mock'."""
    provider = (provider or config.LLM_PROVIDER).lower()
    if provider == "gemini":
        return GeminiClient()
    if provider == "mock":
        return None
    # default / unknown -> ollama
    return OllamaClient()
