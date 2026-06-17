# Homzy — Project Plan & Handoff

This is the master plan for Homzy. It captures the vision, every product/tech
decision made so far, the architecture, the brand system, and the full phased
roadmap. Anyone (human or AI) on any device should be able to read this and the
[`CLAUDE.md`](../CLAUDE.md) and continue without losing context.

---

## 1. Vision

A bilingual (Arabic / English) AI **property broker** for Ali's real-estate
business. End users are buyers & renters (leads). The assistant behaves like a
sharp, warm human broker: it understands a client's requirements, then presents
**multiple tailored property options that fit**, sells each one honestly, and
guides the client toward booking a viewing. It is grounded in real listings and
a sales/marketing playbook, plus anything Ali feeds it.

The product ships as a **mobile app (Android + iOS)**. We build the "brain"
first (testable on desktop), then wrap it in the mobile app.

---

## 2. Decisions log (from the requirements interview)

| Question | Decision |
|---|---|
| Platform | **Mobile app**, Android **and** iOS → cross-platform (Flutter) |
| Audience | **Buyers & renters (leads)** — public-facing |
| Language | **Bilingual AR/EN**, auto-detect; Egyptian dialect for Arabic |
| Knowledge | **Listings + sales/marketing playbook + custom info** Ali feeds |
| "Hot lead" behaviour | **Present multiple matching deals** that fit the client's needs (a matching + persuasion engine — not just contact capture) |
| Feeding info | **File upload + admin control panel** (Phase 2) |
| LLM | **Free, not paid** → local Ollama (default) / Gemini free tier |
| Tone | **Formal but casual**; urgency handled tastefully (honest/gentle) |
| Pricing rule | **Never invent a price** |
| Location | Work **only** in `D:\Project\Homzy` (separate from the PDF app) |

---

## 3. Constraints (non-negotiable)

1. **Free LLM only** — no paid APIs. Pluggable engine layer; Ollama default.
2. **Never invent a price/property** — matching in Python over the listings
   file; the model only presents supplied rows.
3. **Formal-but-casual bilingual persona**, honest gentle urgency, always offer
   a viewing.
4. **Fixed brand identity** (section 5).
5. Keep the codebase runnable with **zero install** (template/preview fallback).

---

## 4. Architecture

### Per-turn pipeline (`backend/broker.py`)
```
client message
   │
   ├─ 1. detect language (Arabic vs English)
   ├─ 2. update search criteria
   │        ├─ heuristic extractor (works with no engine)
   │        └─ LLM extraction across the whole conversation (when engine on)
   ├─ 3. search listings in code  → real matching rows (real prices)
   └─ 4. generate reply
            ├─ AI engine (Ollama/Gemini): persona prompt + history + matches
            └─ template fallback (no engine): grounded, bilingual
```
Because step 3 supplies the real listings, the model can only **present** what
it is given — it cannot invent a price.

### File map
| Path | Responsibility |
|------|----------------|
| `backend/app.py` | FastAPI app; serves UI + `/api/chat`, `/api/health`, `/api/reset`; mounts `/assets` |
| `backend/broker.py` | Orchestration pipeline; language detection; heuristic + LLM extraction; reply generation |
| `backend/listings.py` | Load/search/format listings; **source of truth for prices** |
| `backend/persona.py` | `EXTRACT_SYSTEM`, `BROKER_TEMPLATE`, preview templates |
| `backend/llm.py` | `OllamaClient`, `GeminiClient`, factory; `LLMUnavailable` |
| `backend/config.py` | Env-driven settings |
| `data/listings.json` | Inventory (sample placeholder data) |
| `frontend/index.html` | Chat UI (vanilla HTML/CSS/JS, bilingual + RTL) |
| `frontend/assets/` | Brand assets (`logo.png` auto-loads if present) |
| `run.bat` | Windows one-click setup + launch |

### Config (`.env`, see `.env.example`)
`LLM_PROVIDER` (ollama|gemini|mock), `OLLAMA_HOST`, `OLLAMA_MODEL`,
`GEMINI_API_KEY`, `GEMINI_MODEL`, `BRAND_NAME`, `BROKER_NAME`, `MAX_RESULTS`,
`LLM_TEMPERATURE`.

---

## 5. Brand system (from the official identity sheet)

| Token | Value |
|---|---|
| Navy (primary dark / text) | `#0D1B2A` |
| Blue (primary accent) | `#2563EB` |
| Light blue | `#E0F2FE` |
| Green (success / AI status) | `#22C55E` |
| Gray (background) | `#F3F4F6` |
| Fonts | **Poppins** (Latin) + **Cairo** (Arabic) |
| Logo | House outline with a 2×2 blue window; navy app-icon variant |
| Tagline | "Your guide to finding the right home." |

The chat UI already implements this. The mobile app (Phase 3) reuses the same
system: splash/onboarding, home dashboard with feature cards, chat screen, and
a bottom nav (Home / Projects / Chat / Saved / Profile) — all shown on the
identity sheet.

---

## 6. Persona & sales spec (`backend/persona.py`)

- Name: **Nour** (configurable via `BROKER_NAME`), advisor at Homzy.
- Voice: formal but warm and conversational; Egyptian Arabic when the client
  writes Arabic, English otherwise. Phone-friendly, short messages.
- Method: confirm the four essentials (budget, area, rent/buy, bedrooms) with
  one or two friendly questions, then present 2–4 options, each with a sharp
  reason it fits the client. Honest, gentle urgency; always offer a viewing.
- Rules: never invent prices/properties; if no match, say so and help adjust.

---

## 7. Listings data model (`data/listings.json`)

Array of objects:
```jsonc
{
  "id": "HZ-R01",
  "purpose": "rent" | "sale",
  "type": "apartment" | "villa" | "townhouse" | "studio" | "office",
  "area_en": "Sheikh Zayed", "area_ar": "الشيخ زايد",
  "compound_en": "Westown Residences", "compound_ar": "ويستاون",
  "price": 25000, "currency": "EGP", "price_period": "month" | null,
  "bedrooms": 2, "bathrooms": 2, "size_sqm": 120,
  "finishing": "fully finished",
  "highlights_en": ["..."], "highlights_ar": ["..."],
  "payment_plan_en": "...", "payment_plan_ar": "...",
  "available": true
}
```
Current data is **sample placeholder** Sheikh Zayed / 6th October units.
Replace with Ali's real inventory (Phase 2 will add upload/edit tooling).

---

## 8. Setup on a new device

1. Clone: `git clone https://github.com/alialielkhayat246-a11y/Homzy.git`
2. Python 3.12+: create venv, `pip install -r requirements.txt`.
3. Run: `python -m uvicorn backend.app:app --reload --port 8000` → open
   http://127.0.0.1:8000. (Windows: double-click `run.bat`.)
4. Turn on AI (pick one):
   - **Ollama**: install from https://ollama.com, then `ollama pull qwen2.5:7b`.
   - **Gemini**: copy `.env.example` → `.env`, set `LLM_PROVIDER=gemini` and a
     free key from https://aistudio.google.com/apikey, `pip install google-generativeai`.

---

## 9. Roadmap

### ✅ Phase 1 — The Brain (DONE)
- [x] FastAPI backend + chat API
- [x] Pluggable free LLM layer (Ollama / Gemini / mock fallback)
- [x] Language detection + bilingual replies
- [x] Requirement extraction (heuristic + LLM)
- [x] Listings search/ranking grounded in real prices ("never invent a price")
- [x] Branded chat UI (Homzy identity, Poppins/Cairo, logo, chips, RTL)
- [x] Sample listings, persona, `run.bat`, README, LICENSE, CONTRIBUTING
- [ ] Turn on Ollama and run a live bilingual test (in progress on dev machine)
- [ ] Replace sample listings with real data

### 🟡 Phase 2 — Admin / data tooling
Goal: let Ali manage listings and the persona without touching code.
- [x] Admin page (`frontend/admin.html`) behind an optional passcode
      (`ADMIN_TOKEN` in `.env`, sent as the `X-Admin-Token` header).
- [x] CRUD endpoints for listings (`/api/listings` GET/POST/PUT/DELETE); persist
      back to `data/listings.json` (atomic write). Cache is kept in sync so the
      broker sees edits with no restart. (SQLite migration deferred to scale.)
- [ ] **File upload + parse** → listings schema:
      Excel (`openpyxl`), PDF (`pdfplumber`), Word (`python-docx`). Map columns
      to the schema in section 7; show a preview/confirm before saving.
- [ ] Edit persona/brand fields and `MAX_RESULTS` from the panel.
- [ ] (Optional) lightweight auth for the admin panel.

### ⬜ Phase 3 — Mobile app (Flutter, Android + iOS)
Goal: ship the brain as a real app matching the identity sheet.
- [ ] Flutter project (e.g. `mobile/`). Screens: splash/onboarding, home
      dashboard (feature cards + "continue your journey"), chat, with the
      bottom nav from the brand sheet.
- [ ] Chat screen calls the FastAPI `/api/chat`; bilingual + RTL; quick-reply
      chips; bot avatar; brand colors + Poppins/Cairo.
- [ ] **Host the backend** (the app needs a reachable API): containerize the
      FastAPI app and deploy (a small VPS or a free-tier host); run Ollama or
      Gemini server-side. Document the base URL config.
- [ ] App icon (navy house mark) + store metadata.

### ⬜ Phase 4 — Enhancements (backlog)
- [ ] Lead capture + handoff (collect contact, notify Ali / WhatsApp) — opt-in.
- [ ] Saved/favourite listings; viewing-request flow.
- [ ] Conversation persistence (DB) instead of in-memory sessions.
- [ ] Analytics: what clients ask for, conversion to viewings.
- [ ] Multi-tenant / multiple brokers; richer sales playbook tooling.
- [ ] Tests (pytest) for the broker pipeline and listings search.
- [ ] Tune the persona with Ali after live testing.

---

## 10. Continue here (TL;DR for the next session)

1. Read `CLAUDE.md` for the constraints.
2. Finish the AI engine: install Ollama + `ollama pull qwen2.5:7b`, confirm the
   green "AI · ollama" status, run a bilingual test chat.
3. Get Ali's real listings in via the `/admin` panel (Phase 2 — done).
4. Finish Phase 2's **file upload/parse** (Excel/PDF/Word) or start **Phase 3**
   (Flutter mobile app) per section 9.

Keep it free, keep prices grounded in the data, keep the persona human.
