# Homzy — AI Property Advisor (Phase 1: the Brain)

A bilingual (Arabic / English) AI "broker" that understands a client's needs and
pitches **matching properties from your real listings** — never invented prices.

This is **Phase 1** (the brain + chat screen) plus **Phase 2** (a built-in admin
panel to add/edit/delete your listings). Phase 3 = the Android/iOS mobile app.

> **Continuing the project, or picking it up on another device?**
> Read **[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md)** for the full plan,
> decisions, brand system, and the complete roadmap — and **[`CLAUDE.md`](CLAUDE.md)**
> for the AI-assistant operating guide. The repo is self-contained: clone it and go.

---

## Quick start (easiest)

Double-click **`run.bat`**. It sets up Python, installs everything, and opens the
chat at <http://127.0.0.1:8000>.

The first time, it runs in **Preview mode**: replies are templated but already use
your real listings and prices, so you can see the matching working. To turn on
full, natural AI conversation, pick one of the two free engines below.

---

## Turn on the AI brain (pick one — both free)

### Option A — Ollama (local, free, no key, private) — recommended
1. Install Ollama for Windows: <https://ollama.com/download>
2. Open a terminal and pull a bilingual model (one-time, a few GB):
   ```
   ollama pull qwen2.5:7b
   ```
   (On a lighter PC use `qwen2.5:3b` and set `OLLAMA_MODEL=qwen2.5:3b` in `.env`.)
3. Make sure Ollama is running, then start Homzy with `run.bat`.
   The status pill turns green ("AI: ollama").

### Option B — Google Gemini (free cloud tier, needs a free key)
1. Get a free key: <https://aistudio.google.com/apikey>
2. Copy `.env.example` to `.env` and set:
   ```
   LLM_PROVIDER=gemini
   GEMINI_API_KEY=your_key_here
   ```
3. Install the client: `pip install google-generativeai`
4. Start Homzy with `run.bat`.

No paid API is used anywhere. Your Anthropic/Claude key is **not** required.

---

## Editing the broker and the listings

| What | Where |
|------|-------|
| Broker name / brand | `.env` (`BROKER_NAME`, `BRAND_NAME`) |
| Personality & sales style | `backend/persona.py` → `BROKER_TEMPLATE` |
| The properties & prices | `data/listings.json` |
| How many options to show | `.env` (`MAX_RESULTS`) |

After editing `data/listings.json`, just restart `run.bat`.

### Or use the admin panel (no JSON editing)

Open <http://127.0.0.1:8000/admin> (or click the ⚙︎ in the chat header) to add,
edit, and delete properties in a form — bilingual fields included. Changes save
straight to `data/listings.json` and the broker picks them up immediately, no
restart needed. To password-protect the panel, set `ADMIN_TOKEN` in `.env`.

---

## How "never invent a price" is guaranteed

The AI never makes up properties. Each turn, the code reads the client's needs,
**searches `data/listings.json` itself**, and hands the model only the real
matching rows. The model may only present what it's given — prices come from your
file, not from the model.

---

## Project layout

```
Homzy/
├─ backend/
│  ├─ app.py        FastAPI server + chat API
│  ├─ broker.py     per-turn pipeline (language, needs, match, reply)
│  ├─ listings.py   load + search the inventory (source of truth for prices)
│  ├─ persona.py    the broker's character + prompts + preview templates
│  ├─ llm.py        free engines: Ollama / Gemini / mock
│  └─ config.py     settings from .env
├─ data/listings.json   your properties (sample data — replace with real)
├─ frontend/index.html  the chat screen
├─ frontend/admin.html  the listings admin panel (/admin)
├─ run.bat              one-click setup + launch
└─ requirements.txt
```

The listings in `data/listings.json` are **sample placeholders** — replace them
with your real units (or we'll wire up file upload in Phase 2).
