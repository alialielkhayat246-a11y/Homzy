"""Extract structured property listings from raw WhatsApp messages using Gemini.

This is the core ingestion step for Homzy's developer data: raw, messy WhatsApp
posts (Arabic / Egyptian dialect / English) go in, clean structured listings
come out. It deliberately knows nothing about *where* the text came from, so the
same function works for a manual chat export today and a live WhatsApp bot later.

Usage:
    GEMINI_API_KEY=... python extract.py path/to/whatsapp_export.txt > listings.json
    GEMINI_API_KEY=... python extract.py --demo        # run on built-in samples

Never invents prices: if a field isn't in the message, it's null.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from typing import Any

import requests

GEMINI_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")
_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"

# Batch this many messages per Gemini call (keeps prompts small but cuts calls).
BATCH_SIZE = int(os.environ.get("INGEST_BATCH", "12"))

EXTRACT_SYSTEM = """You read raw WhatsApp messages from Egyptian real-estate / developer groups and pull out PROPERTY LISTINGS as clean structured data.

The messages are messy: Arabic (Egyptian dialect), English, or mixed, with emojis, phone numbers, and chit-chat. Many messages are NOT listings (greetings, questions, "available?", voice-note notes, etc.) — skip those.

Return ONLY a JSON object of this exact shape:
{"listings": [ <listing>, ... ]}
If a message contains several unit types (e.g. different sizes/prices in one post), output one listing object per distinct unit. If the batch has no real listing, return {"listings": []}.

Each <listing> has these keys (use null when the message doesn't state it — NEVER guess a price or a number):
{
  "purpose": "sale" | "rent" | null,        // primary/developer posts are usually "sale"
  "type": "apartment" | "villa" | "townhouse" | "twinhouse" | "duplex" | "studio" | "chalet" | "office" | "clinic" | "retail" | null,
  "developer": string | null,               // e.g. "SODIC", "Palm Hills", "Mountain View"
  "project": string | null,                 // compound / project name
  "area": string | null,                    // e.g. "Sheikh Zayed", "New Cairo", "6th of October"
  "price": number | null,                   // total price in EGP (number only, no text)
  "currency": "EGP",
  "down_payment": string | null,            // as written, e.g. "10%" or "500000"
  "installment_years": number | null,
  "delivery": string | null,                // e.g. "2027", "ready", "تسليم 2026"
  "bedrooms": integer | null,
  "bathrooms": integer | null,
  "size_sqm": number | null,
  "finishing": string | null,               // e.g. "fully finished", "core & shell", "نص تشطيب"
  "phone": string | null,                    // contact number if present
  "summary": string,                         // one short neutral line describing the unit
  "raw": string                              // the original message text (trimmed)
}

Rules:
- Output JSON only. No markdown, no commentary.
- Copy numbers exactly; if a price is written like "4.2M" convert to 4200000, "850 ألف" -> 850000.
- Keep developer/project/area names in their original language but Title Case English when obvious.
- Do not merge two different messages into one listing."""


def _gemini(messages_block: str, _retries: int = 4) -> dict[str, Any]:
    if not GEMINI_KEY:
        raise RuntimeError("GEMINI_API_KEY is not set")
    payload = {
        "systemInstruction": {"parts": [{"text": EXTRACT_SYSTEM}]},
        "contents": [{"role": "user", "parts": [{"text": messages_block}]}],
        "generationConfig": {"temperature": 0.0, "responseMimeType": "application/json"},
    }
    last_exc: Exception | None = None
    for attempt in range(_retries):
        try:
            resp = requests.post(
                _URL,
                headers={"x-goog-api-key": GEMINI_KEY, "Content-Type": "application/json"},
                json=payload,
                timeout=120,
            )
            # Retry on overload / rate limit / transient server errors.
            if resp.status_code in (429, 500, 502, 503, 504):
                raise requests.exceptions.HTTPError(f"{resp.status_code}", response=resp)
            resp.raise_for_status()
            break
        except requests.exceptions.RequestException as exc:
            last_exc = exc
            if attempt == _retries - 1:
                raise
            wait = 3 * (2 ** attempt)  # 3s, 6s, 12s, 24s
            print(f"  …Gemini busy ({exc}); retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    data = resp.json()
    try:
        text = "".join(
            p.get("text", "") for p in data["candidates"][0]["content"]["parts"]
        )
    except (KeyError, IndexError):
        return {"listings": []}
    try:
        return json.loads(text)
    except Exception:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end != -1:
            try:
                return json.loads(text[start:end + 1])
            except Exception:
                return {"listings": []}
        return {"listings": []}


def extract_listings(messages: list[str]) -> list[dict[str, Any]]:
    """Run extraction over a list of raw messages, batched. Returns listings."""
    out: list[dict[str, Any]] = []
    clean = [m.strip() for m in messages if m and m.strip()]
    total = (len(clean) + BATCH_SIZE - 1) // BATCH_SIZE
    for n, i in enumerate(range(0, len(clean), BATCH_SIZE), 1):
        batch = clean[i:i + BATCH_SIZE]
        block = "\n\n".join(f"--- MESSAGE {i + j + 1} ---\n{m}"
                            for j, m in enumerate(batch))
        print(f"  batch {n}/{total}…", file=sys.stderr)
        try:
            result = _gemini(block)
        except Exception as exc:  # don't lose the whole run over one bad batch
            print(f"  ! batch {n} failed, skipping: {exc}", file=sys.stderr)
            continue
        for item in result.get("listings", []):
            if isinstance(item, dict):
                item.setdefault("currency", "EGP")
                out.append(item)
    return out


# ---------------------------------------------------------------------------
# WhatsApp "Export chat" (.txt) parsing
# ---------------------------------------------------------------------------
# Lines look like:  "12/06/2026, 9:14 PM - Name: message text"
# (formats vary by phone locale; this handles the common bracketed + dash ones)
_HEADER = re.compile(
    r"^\[?\d{1,2}[./]\d{1,2}[./]\d{2,4}[,]?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:[APap][Mm])?\]?\s*[-]?\s*"
)


def parse_whatsapp_export(text: str) -> list[str]:
    """Split an exported chat into individual message bodies (sender stripped)."""
    messages: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        if _HEADER.match(line):
            if current:
                messages.append("\n".join(current).strip())
                current = []
            body = _HEADER.sub("", line)
            # strip "Sender Name: " prefix
            body = re.sub(r"^[^:]{1,40}:\s*", "", body, count=1)
            current.append(body)
        else:
            current.append(line)
    if current:
        messages.append("\n".join(current).strip())
    # drop system lines / empties / media placeholders
    skip = ("<Media omitted>", "image omitted", "video omitted",
            "Messages and calls are end-to-end encrypted")
    return [m for m in messages if m and not any(s in m for s in skip)]


_DEMO = [
    "صباح الخير 🌞 حد عنده شقة للايجار في زايد؟",
    "🏡 Palm Hills New Cairo\nشقة 165م 3 غرف نوم\nمقدم 10% وتقسيط 8 سنين\nالسعر 9,500,000 جنيه\nتسليم 2027 - نص تشطيب\nللتواصل 01001234567",
    "متاح فيلا مستقلة في سوديك ايست - الشيخ زايد\n4 غرف، 350 متر، تشطيب كامل\n22 مليون كاش او تقسيط على 5 سنين\n01122334455",
    "تمام شكراً 🙏",
    "Mountain View iCity October\nStudio 70 sqm - 4,200,000 EGP\n5% down payment, 9 years installments\nDelivery 2026",
]


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--demo":
        msgs = _DEMO
    elif args:
        with open(args[0], "r", encoding="utf-8") as fh:
            msgs = parse_whatsapp_export(fh.read())
    else:
        msgs = parse_whatsapp_export(sys.stdin.read())

    listings = extract_listings(msgs)
    print(json.dumps({"count": len(listings), "listings": listings},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
