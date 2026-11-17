"""Where is each project, really? (location audit for the catalog)

The chat once recommended an October project to a client who asked for New Cairo,
because the imported catalog had the wrong area. This module asks Gemini (vision +
PDF) to READ the evidence we hold for a project — its cover image, gallery images,
the developer brochure, the description and the WhatsApp updates that mention it —
and report the location that is actually written there, with the words it read.

The decision is made here, in code, not by the model:
  applied   area was empty, evidence explicit and confident        -> area set
  changed   area was wrong, evidence explicit, confident, primary   -> area replaced
  same      evidence agrees                                         -> location detail filled
  country   project is outside Egypt (e.g. the Dubai imports)       -> country set, never offered as Egypt
  review    unclear / conflicting / only weak evidence              -> admin decides on /admin/locations
  no_evidence nothing readable says where it is
Every verdict, with the old values, is stored in project_location_audit.
"""
from __future__ import annotations

import base64
import io
import json
import time
from typing import Any

from . import areas as areas_mod, config

WHY: list[str] = []
INLINE_PDF_MAX = 14 * 1024 * 1024      # bigger brochures go through the Gemini File API
PDF_MAX = 80 * 1024 * 1024

# Areas the catalog uses (projects.area). Kept in step with area_aliases in the DB.
CANONICAL = [
    "New Cairo", "New Capital", "Mostakbal City", "El Shorouk", "Madinaty", "El Obour", "Badr City",
    "New Heliopolis", "Heliopolis", "Sheraton", "Nasr City", "Maadi", "Zahraa El Maadi", "Mokattam", "Old Cairo",
    "6th of October", "October Gardens", "New October", "Sheikh Zayed", "New Zayed",
    "North Coast", "Ras El Hekma", "New Alamein", "Alexandria",
    "Ain Sokhna", "Galala", "Ras Sudr", "Hurghada", "El Gouna", "Sahl Hasheesh", "Soma Bay", "Makadi Bay",
    "Red Sea", "Sharm El Sheikh", "Marsa Alam", "New Mansoura", "Dreamland",
]
_CANON_LOWER = {c.lower(): c for c in CANONICAL}
_EXTRA = {"6 october": "6th of October", "october": "6th of October", "zayed": "Sheikh Zayed",
          "shorouk": "El Shorouk", "shorouk city": "El Shorouk", "obour": "El Obour", "naser city": "Nasr City",
          "fifth settlement": "New Cairo", "5th settlement": "New Cairo", "6th settlement": "New Cairo",
          "kattameya": "New Cairo", "katameya": "New Cairo", "administrative capital": "New Capital",
          "new administrative capital": "New Capital", "mostakbal": "Mostakbal City", "sokhna": "Ain Sokhna",
          "hadayek october": "October Gardens", "el gouna": "El Gouna", "gouna": "El Gouna",
          "sidi abdel rahman": "North Coast", "el alamein": "New Alamein", "alamein": "New Alamein"}

_SYSTEM = (
    "You verify WHERE a real-estate project is, for an Egyptian property platform. You get the project's "
    "name, developer, the area we currently have on file, its description, WhatsApp updates from brokers, "
    "and images / the developer brochure (PDF). Read them and report the location that is ACTUALLY WRITTEN "
    "or shown in this evidence. Do not use outside knowledge or guess from the project name alone.\n"
    "Rules:\n"
    "- The area is where the project itself sits, not places it is 'minutes from' or 'near'. A brochure line "
    "like '5 minutes from New Cairo' does NOT put the project in New Cairo. Location maps count only when the "
    "project's own plot is clearly labelled.\n"
    "- country: ISO code of the country the project is in (EG, AE, SA, ...). Dubai / Abu Dhabi / Sharjah / "
    "Ras Al Khaimah are AE. 'Sheikh Zayed Road', 'Business Bay', 'JVC', 'Dubai Marina', 'Al Furjan' etc. are "
    "Dubai, NOT Sheikh Zayed City in Egypt.\n"
    "- area (Egypt only): exactly one of this list: " + ", ".join(CANONICAL) + ". If the place is in Egypt "
    "but not in the list, answer \"OTHER: <name>\". For projects outside Egypt answer the city/community "
    "as \"OTHER: <name>\".\n"
    "- location_ar: a short Arabic location detail as written (e.g. 'التجمع الخامس - شارع التسعين الشمالي', "
    "'الكيلو 180 طريق الإسكندرية مطروح', 'دبي - قرية جميرا الدائرية'). Empty if none.\n"
    "- source: where you read it: cover | image | brochure | description | whatsapp | name | none.\n"
    "- quote: the exact words you read (original language, max 200 chars).\n"
    "- explicit: true only if the evidence literally names the location of THIS project.\n"
    "- confidence: 0..1.\n"
    "- note: one short English sentence, e.g. what conflicts with the area on file.\n"
    'Reply with JSON only: {"country":"EG","area":"New Cairo","location_ar":"","location_en":"","source":"brochure",'
    '"quote":"","explicit":true,"confidence":0.9,"note":""}'
)


def _key_ok() -> bool:
    return bool(config.GEMINI_API_KEY)


def _image_part(url: str) -> dict | None:
    import requests
    from PIL import Image
    try:
        r = requests.get(url, timeout=12, headers={"User-Agent": "Mozilla/5.0"})
        if not r.ok:
            return None
        im = Image.open(io.BytesIO(r.content)).convert("RGB")
        im.thumbnail((1024, 1024))          # big enough to read a location line on a flyer
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80)
        return {"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(buf.getvalue()).decode()}}
    except Exception:
        return None


def _pdf_url(url: str) -> str:
    """Google Drive share links -> a direct download link."""
    import re
    m = re.search(r"drive\.google\.com/(?:file/d/|open\?id=|uc\?id=)([\w-]{10,})", url or "")
    if m:
        return f"https://drive.usercontent.google.com/download?id={m.group(1)}&export=download&confirm=t"
    return url


def _download_pdf(url: str) -> bytes | None:
    import requests
    try:
        with requests.get(_pdf_url(url), timeout=40, stream=True, headers={"User-Agent": "Mozilla/5.0"}) as r:
            if not r.ok:
                WHY.append(f"brochure HTTP {r.status_code}")
                return None
            buf = io.BytesIO()
            for chunk in r.iter_content(1 << 20):
                buf.write(chunk)
                if buf.tell() > PDF_MAX:
                    WHY.append("brochure too big")
                    return None
            data = buf.getvalue()
        if not data.startswith(b"%PDF"):
            WHY.append("brochure is not a PDF")
            return None
        return data
    except Exception as exc:
        WHY.append(f"brochure: {exc}")
        return None


def _upload_file(data: bytes) -> tuple[dict | None, str | None]:
    """Gemini File API (for brochures over the inline limit). Returns (part, file name)."""
    import requests
    base = "https://generativelanguage.googleapis.com"
    h = {"x-goog-api-key": config.GEMINI_API_KEY}
    try:
        r = requests.post(base + "/upload/v1beta/files", timeout=30, json={"file": {"display_name": "brochure"}},
                          headers={**h, "X-Goog-Upload-Protocol": "resumable", "X-Goog-Upload-Command": "start",
                                   "X-Goog-Upload-Header-Content-Length": str(len(data)),
                                   "X-Goog-Upload-Header-Content-Type": "application/pdf"})
        up = r.headers.get("x-goog-upload-url")
        if not up:
            WHY.append(f"file api start {r.status_code}")
            return None, None
        r = requests.post(up, data=data, timeout=120,
                          headers={"X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize"})
        f = (r.json() or {}).get("file") or {}
        name = f.get("name")
        for _ in range(20):                       # PDFs are usually ACTIVE within seconds
            if f.get("state") == "ACTIVE" or not name:
                break
            time.sleep(2)
            f = requests.get(f"{base}/v1beta/{name}", headers=h, timeout=15).json()
        if f.get("state") != "ACTIVE":
            WHY.append(f"file api state {f.get('state')}")
            return None, name
        return {"file_data": {"mime_type": "application/pdf", "file_uri": f["uri"]}}, name
    except Exception as exc:
        WHY.append(f"file api: {exc}")
        return None, None


def _delete_file(name: str | None) -> None:
    if not name:
        return
    import requests
    try:
        requests.delete(f"https://generativelanguage.googleapis.com/v1beta/{name}",
                        headers={"x-goog-api-key": config.GEMINI_API_KEY}, timeout=10)
    except Exception:
        pass


def canon(area: str | None) -> str | None:
    a = (area or "").strip()
    if not a or a.upper().startswith("OTHER"):
        return None
    low = a.lower()
    if low in _CANON_LOWER:
        return _CANON_LOWER[low]
    if low in _EXTRA:
        return _EXTRA[low]
    ex = areas_mod.extract(a)
    return ex if ex in CANONICAL else None


def _ask(item: dict[str, Any]) -> dict[str, Any] | None:
    import requests
    wa = "\n---\n".join(item.get("whatsapp") or [])[:3000]
    head = (f"PROJECT: {item.get('name')} / {item.get('name_ar') or ''}\nDEVELOPER: {item.get('developer') or ''}\n"
            f"AREA ON FILE: {item.get('area') or '(none)'}\nLOCATION ON FILE: {item.get('location') or '(none)'}\n"
            f"DESCRIPTION: {item.get('description') or '(none)'}\nWHATSAPP UPDATES:\n{wa or '(none)'}")
    parts: list[dict] = [{"text": head}]
    imgs = [u for u in [item.get("cover")] + list(item.get("images") or []) if u]
    for i, u in enumerate(dict.fromkeys(imgs), 1):
        p = _image_part(u)
        if p:
            parts += [{"text": "cover image:" if i == 1 else f"image {i}:"}, p]
    fname = None
    if item.get("brochure"):
        data = _download_pdf(item["brochure"])
        if data:
            if len(data) <= INLINE_PDF_MAX:
                parts += [{"text": "developer brochure (PDF):"},
                          {"inline_data": {"mime_type": "application/pdf", "data": base64.b64encode(data).decode()}}]
            else:
                part, fname = _upload_file(data)
                if part:
                    parts += [{"text": "developer brochure (PDF):"}, part]
    try:
        payload = {"systemInstruction": {"parts": [{"text": _SYSTEM}]},
                   "contents": [{"role": "user", "parts": parts}],
                   "generationConfig": {"temperature": 0, "responseMimeType": "application/json",
                                        "maxOutputTokens": 4096}}
        for model in dict.fromkeys(("gemini-flash-latest", "gemini-flash-lite-latest", config.GEMINI_MODEL)):
            cfg = dict(payload["generationConfig"])
            if model.startswith("gemini-2.5"):
                cfg["thinkingConfig"] = {"thinkingBudget": 0}
            try:
                r = requests.post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                                  headers={"x-goog-api-key": config.GEMINI_API_KEY, "Content-Type": "application/json"},
                                  json={**payload, "generationConfig": cfg}, timeout=150)
            except Exception as exc:
                WHY.append(f"{model}: {exc}")
                continue
            if r.status_code != 200:
                WHY.append(f"{model}: HTTP {r.status_code} {r.text[:160]}")
                continue
            cand = (r.json().get("candidates") or [{}])[0]
            text = "".join(p.get("text", "") for p in (cand.get("content") or {}).get("parts", []) if not p.get("thought"))
            try:
                out = json.loads(text[text.find("{"): text.rfind("}") + 1])
            except Exception:
                WHY.append(f"{model}: unreadable {text[:120]!r}")
                continue
            out["model"] = model
            out["_had"] = [p.get("text") for p in parts if p.get("text") and p["text"].endswith(":")]
            return out
        return None
    finally:
        _delete_file(fname)


def decide(item: dict[str, Any], out: dict[str, Any]) -> dict[str, Any]:
    """Turn the model's reading into an action (see module docstring)."""
    country = (out.get("country") or "").strip().upper()[:2] or None
    found = canon(out.get("area"))
    old = canon(item.get("area")) or (item.get("area") or None)
    conf = float(out.get("confidence") or 0)
    explicit = bool(out.get("explicit"))
    src = (out.get("source") or "none").lower()
    strong = explicit and src in ("cover", "image", "brochure", "description")
    res = {"country": country or item.get("country") or "EG", "area": found or out.get("area"),
           "location_ar": (out.get("location_ar") or "").strip()[:200],
           "location_en": (out.get("location_en") or "").strip()[:200],
           "source": src, "quote": out.get("quote"), "confidence": conf, "model": out.get("model"),
           "note": out.get("note")}
    if country and country != "EG":
        if explicit and conf >= 0.8:
            res["area"] = None
            # an Egyptian area on file that now reads as abroad needs a person
            res["action"] = "review" if old else "country"
        else:
            res["action"] = "review"
        return res
    res["country"] = "EG" if country == "EG" or (country is None and old) else (country or item.get("country") or "EG")
    if not found:
        res["action"] = "review" if (out.get("area") and explicit) else "no_evidence"
        return res
    if old and found == old:
        res["action"] = "same"
    elif not old:
        res["action"] = "applied" if explicit and conf >= 0.8 and src != "name" else "review"
    else:
        res["action"] = "changed" if strong and conf >= 0.9 else "review"
    return res


def run(limit: int = 1, project_id: str | None = None, shard: int = 0, mod: int = 1) -> list[dict[str, Any]]:
    import requests
    WHY.clear()
    if not (config.SUPABASE_URL and config.SUPABASE_KEY and config.PUSH_CRON_TOKEN and _key_ok()):
        return [{"error": "not configured"}]
    base = config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/"
    h = {"apikey": config.SUPABASE_KEY, "Authorization": f"Bearer {config.SUPABASE_KEY}",
         "Content-Type": "application/json"}
    q = requests.post(base + "project_location_queue", headers=h, timeout=15,
                      json={"p_key": config.PUSH_CRON_TOKEN, "p_limit": limit, "p_project": project_id,
                            "p_shard": shard, "p_mod": mod}).json()
    done = []
    for item in q if isinstance(q, list) else []:
        out = _ask(item)
        if out is None:
            done.append({"id": item["id"], "name": item.get("name"), "action": "retry", "why": WHY[-4:]})
            continue
        res = decide(item, out)
        r = requests.post(base + "project_location_apply", headers=h, timeout=15,
                          json={"p_key": config.PUSH_CRON_TOKEN, "p_project": item["id"], "p_result": res})
        done.append({"id": item["id"], "name": item.get("name"), "old": item.get("area"), **res,
                     "saved": r.json() if r.ok else f"HTTP {r.status_code}", "evidence": out.get("_had"),
                     "why": WHY[-4:]})
    return done
