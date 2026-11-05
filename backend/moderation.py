"""Automatic content review for marketplace listings (photos + text).

The database keeps a published listing in 'pending' until its current content
is approved (see migration 20261105000700_listing_moderation). This module
takes queued listings, asks Gemini (free tier, vision) whether the photos or
text contain sexual content, violence, hate, profanity or incitement, and
records the verdict through the key-gated listing_moderation_apply RPC:

  ok      -> public
  reject  -> 'rejected', with an Arabic reason the broker sees
  review  -> stays pending for an admin (unsure, or Gemini refused to look)

Any failure (no key, quota, network) leaves the listing queued for the next run.
"""
from __future__ import annotations

import base64
import io
import json
from typing import Any

from . import config

MAX_PHOTOS = 8
WHY: list[str] = []   # why the last review could not run (shown by /api/moderation/run)
_SYSTEM = (
    "You are the content-safety reviewer for Homzy, an Egyptian real-estate marketplace. "
    "You get a property listing: its title, description and photos. Decide if it is appropriate "
    "to publish.\n"
    "NOT allowed (reject when clear): sexual content, nudity or sexually suggestive images/text; "
    "violence, gore, blood, injuries, dead bodies; weapons shown threateningly; hate speech, "
    "insults, profanity or obscene words (Arabic, English or Franco-Arabic); incitement to "
    "violence, crime, terrorism or hatred; drugs.\n"
    "ALLOWED (normal real-estate content): rooms, buildings, renders, floor/master plans, maps, "
    "logos, designed flyers with prices or phone numbers, people dressed normally, pools and "
    "beaches seen normally, empty or under-construction units.\n"
    "Use 'review' only when something is genuinely ambiguous. Photos are numbered from 1.\n"
    'Reply with JSON only: {"verdict":"ok"|"reject"|"review","issues":[{"where":"title"|"description"|'
    '"photo N","category":"sexual"|"violence"|"weapons"|"hate"|"profanity"|"incitement"|"drugs"|"other",'
    '"note_ar":"short Arabic explanation"}]}'
)
_CAT_AR = {"sexual": "محتوى جنسي أو غير لائق", "violence": "عنف أو مشاهد دموية", "weapons": "أسلحة",
           "hate": "كراهية أو إهانة", "profanity": "ألفاظ غير لائقة", "incitement": "تحريض",
           "drugs": "مخدرات", "other": "محتوى غير مناسب"}


def _where_ar(w: str) -> str:
    w = (w or "").strip().lower()
    if w.startswith("photo"):
        return "الصورة " + w.split()[-1]
    return {"title": "العنوان", "description": "الوصف"}.get(w, w or "الإعلان")


def _photo_part(url: str) -> dict | None:
    import requests
    from PIL import Image
    try:
        r = requests.get(url, timeout=10)
        if not r.ok:
            return None
        im = Image.open(io.BytesIO(r.content)).convert("RGB")
        im.thumbnail((512, 512))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=70)
        return {"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(buf.getvalue()).decode()}}
    except Exception:
        return None


def review(title: str, description: str, photos: list[str]) -> dict[str, Any] | None:
    """{'verdict','reason','issues'}; None when the reviewer couldn't run (retry later)."""
    import requests
    WHY.clear()
    if not config.GEMINI_API_KEY:
        WHY.append("no GEMINI_API_KEY")
        return None
    parts: list[dict] = [{"text": f"TITLE: {title or ''}\nDESCRIPTION: {description or ''}\nPHOTOS: {min(len(photos), MAX_PHOTOS)}"}]
    for i, u in enumerate(photos[:MAX_PHOTOS], 1):
        p = _photo_part(u)
        if p:
            parts += [{"text": f"photo {i}:"}, p]
    payload = {
        "systemInstruction": {"parts": [{"text": _SYSTEM}]},
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"temperature": 0, "responseMimeType": "application/json", "maxOutputTokens": 400},
        # a reviewer must be able to look at bad content and say so, not be blocked by it
        "safetySettings": [{"category": c, "threshold": "BLOCK_NONE"} for c in (
            "HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
            "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT")],
    }
    for model in (config.GEMINI_MODEL_PUBLIC, "gemini-2.5-flash", "gemini-flash-latest"):
        cfg = dict(payload["generationConfig"])
        if model.startswith("gemini-2.5"):
            cfg["thinkingConfig"] = {"thinkingBudget": 0}
        try:
            resp = requests.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                headers={"x-goog-api-key": config.GEMINI_API_KEY, "Content-Type": "application/json"},
                json={**payload, "generationConfig": cfg}, timeout=40)
        except Exception as exc:
            WHY.append(f"{model}: {exc}")
            continue
        if resp.status_code in (429, 500, 503):
            WHY.append(f"{model}: HTTP {resp.status_code}")
            continue
        if resp.status_code != 200:
            WHY.append(f"{model}: HTTP {resp.status_code} {resp.text[:200]}")
            return None
        data = resp.json()
        # Gemini refusing to even look at the content is itself a signal: a person checks it
        if (data.get("promptFeedback") or {}).get("blockReason"):
            return {"verdict": "review", "reason": "الفحص الآلي رفض يعرض المحتوى — محتاج مراجعة من الفريق.",
                    "issues": [{"category": "other", "where": "listing", "note_ar": "blocked by safety filter"}]}
        cand = (data.get("candidates") or [{}])[0]
        if cand.get("finishReason") == "SAFETY":
            return {"verdict": "review", "reason": "الفحص الآلي لقى محتوى حساس — محتاج مراجعة من الفريق.",
                    "issues": [{"category": "other", "where": "listing", "note_ar": "safety stop"}]}
        text = "".join(p.get("text", "") for p in (cand.get("content") or {}).get("parts", []))
        try:
            out = json.loads(text[text.find("{"): text.rfind("}") + 1])
        except Exception:
            WHY.append(f"{model}: unreadable reply {text[:120]!r}")
            return None
        verdict = out.get("verdict") if out.get("verdict") in ("ok", "reject", "review") else "review"
        issues = [i for i in (out.get("issues") or []) if isinstance(i, dict)][:6]
        reason = "؛ ".join(f"{_where_ar(i.get('where'))}: {_CAT_AR.get(i.get('category'), 'محتوى غير مناسب')}"
                           + (f" ({i['note_ar']})" if i.get("note_ar") else "") for i in issues) or None
        if verdict == "ok":
            reason, issues = None, []
        return {"verdict": verdict, "reason": reason, "issues": issues}
    return None


def run(limit: int = 1) -> list[dict[str, Any]]:
    """Review up to `limit` queued listings; returns what was decided."""
    import requests
    if not (config.SUPABASE_URL and config.SUPABASE_KEY and config.PUSH_CRON_TOKEN):
        return []
    base = config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/"
    h = {"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}",
         "Content-Type": "application/json"}
    try:
        q = requests.post(base + "listing_moderation_queue", headers=h, timeout=10,
                          json={"p_key": config.PUSH_CRON_TOKEN, "p_limit": limit}).json()
    except Exception:
        return []
    done = []
    for item in q if isinstance(q, list) else []:
        res = review(item.get("title"), item.get("description"), item.get("photos") or [])
        if res is None:
            done.append({"id": item["id"], "verdict": "retry", "why": WHY[-3:]})
            continue
        try:
            r = requests.post(base + "listing_moderation_apply", headers=h, timeout=10, json={
                "p_key": config.PUSH_CRON_TOKEN, "p_listing": item["id"], "p_hash": item["content_hash"],
                "p_verdict": res["verdict"], "p_reason": res["reason"], "p_flags": {"issues": res["issues"]}})
            done.append({"id": item["id"], "verdict": r.json() if r.ok else "error"})
        except Exception:
            done.append({"id": item["id"], "verdict": "error"})
    return done
