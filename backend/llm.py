"""Pluggable, free LLM layer.

Default engine is local Ollama (no API key, no cost). A free Google Gemini
tier is supported as an alternative. The 'mock' provider means no AI engine at
all — the broker falls back to grounded templated replies.
"""
from __future__ import annotations

import json
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
             force_json: bool = False, max_tokens: int | None = None) -> str:
        import requests  # imported lazily so 'mock' mode needs no dependency

        options: dict[str, Any] = {"temperature": temperature}
        if max_tokens:
            options["num_predict"] = max_tokens
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": options,
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
    # Tried in order — if the primary is rate-limited (429/503), fall through to
    # another current free-tier model before giving up (separate quotas).
    _FALLBACKS = ["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash"]

    def __init__(self) -> None:
        if not config.GEMINI_API_KEY:
            raise LLMUnavailable("GEMINI_API_KEY is not set")
        self.api_key = config.GEMINI_API_KEY
        self.model = config.GEMINI_MODEL

    def chat(self, messages: list[dict[str, str]], temperature: float = 0.6,
             force_json: bool = False, max_tokens: int | None = None) -> str:
        import requests  # imported lazily so 'mock' mode needs no dependency

        system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
        contents = []
        for m in messages:
            if m["role"] == "system":
                continue
            role = "user" if m["role"] == "user" else "model"
            contents.append({"role": role, "parts": [{"text": m["content"]}]})

        base_cfg: dict[str, Any] = {"temperature": temperature}
        if force_json:
            base_cfg["responseMimeType"] = "application/json"
        if max_tokens:
            base_cfg["maxOutputTokens"] = max_tokens

        models = [self.model] + [m for m in self._FALLBACKS if m != self.model]
        last_err = "no model tried"
        for model in models:
            gen_cfg = dict(base_cfg)
            # 2.5 models "think" before answering, which adds latency we don't
            # need for a broker chat — disable it so the smarter model stays fast.
            if model.startswith("gemini-2.5"):
                gen_cfg["thinkingConfig"] = {"thinkingBudget": 0}
            payload: dict[str, Any] = {"contents": contents, "generationConfig": gen_cfg}
            if system:
                payload["systemInstruction"] = {"parts": [{"text": system}]}
            url = f"{self._BASE}/models/{model}:generateContent"
            try:
                resp = requests.post(
                    url,
                    headers={"x-goog-api-key": self.api_key,
                             "Content-Type": "application/json"},
                    json=payload,
                    timeout=60,
                )
            except Exception as exc:
                last_err = f"{model}: {exc}"
                continue
            if resp.status_code in (429, 500, 503):  # busy / quota — try next model
                last_err = f"{model}: HTTP {resp.status_code}"
                continue
            if resp.status_code != 200:
                last_err = f"{model}: HTTP {resp.status_code}"
                continue
            data = resp.json()
            try:
                parts = data["candidates"][0]["content"]["parts"]
                text = "".join(p.get("text", "") for p in parts).strip()
            except (KeyError, IndexError):
                text = ""
            if text:
                return text
            last_err = f"{model}: empty response"
        raise LLMUnavailable(f"Gemini unavailable ({last_err})")

    def _contents(self, messages):
        system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
        contents = []
        for m in messages:
            if m["role"] == "system":
                continue
            role = "user" if m["role"] == "user" else "model"
            contents.append({"role": role, "parts": [{"text": m["content"]}]})
        return system, contents

    def stream(self, messages: list[dict[str, str]], temperature: float = 0.6,
               max_tokens: int | None = None):
        """Yield reply text chunks as the model generates them (SSE). Falls back
        across models only BEFORE the first token; once streaming starts it
        commits to that model."""
        import requests

        system, contents = self._contents(messages)
        base_cfg: dict[str, Any] = {"temperature": temperature}
        if max_tokens:
            base_cfg["maxOutputTokens"] = max_tokens

        models = [self.model] + [m for m in self._FALLBACKS if m != self.model]
        last_err = "no model tried"
        for model in models:
            gen_cfg = dict(base_cfg)
            if model.startswith("gemini-2.5"):
                gen_cfg["thinkingConfig"] = {"thinkingBudget": 0}
            payload: dict[str, Any] = {"contents": contents, "generationConfig": gen_cfg}
            if system:
                payload["systemInstruction"] = {"parts": [{"text": system}]}
            url = f"{self._BASE}/models/{model}:streamGenerateContent?alt=sse"
            try:
                resp = requests.post(
                    url,
                    headers={"x-goog-api-key": self.api_key, "Content-Type": "application/json"},
                    json=payload, timeout=60, stream=True)
            except Exception as exc:
                last_err = f"{model}: {exc}"
                continue
            if resp.status_code != 200:
                last_err = f"{model}: HTTP {resp.status_code}"
                resp.close()
                continue
            got = False
            for line in resp.iter_lines():
                if not line:
                    continue
                s = line.decode("utf-8", "ignore")
                if s.startswith("data:"):
                    s = s[5:].strip()
                if not s or s == "[DONE]":
                    continue
                try:
                    data = json.loads(s)
                    parts = data["candidates"][0]["content"]["parts"]
                    text = "".join(p.get("text", "") for p in parts)
                except (KeyError, IndexError, ValueError):
                    continue
                if text:
                    got = True
                    yield text
            if got:
                return
            last_err = f"{model}: empty stream"
        raise LLMUnavailable(f"Gemini stream unavailable ({last_err})")

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
