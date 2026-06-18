# CLAUDE.md — operating guide for continuing Homzy

This file is for any AI assistant (Claude Code) picking up this project on any
device. Read it first, then `docs/PROJECT_PLAN.md` for the full plan.

## What Homzy is
A bilingual (Arabic / English) AI **property broker** app. A client chats in
Arabic or English; the assistant figures out their needs (rent vs buy, area,
bedrooms, budget) and pitches **multiple matching properties from real
listings**, then nudges toward booking a viewing. It acts like a warm, human
broker — not a form.

## Hard constraints — DO NOT break these
1. **Free LLM only.** No paid APIs. Default engine is local **Ollama**
   (`qwen2.5:7b`); alternative is the **Google Gemini free tier**. There is also
   a `mock`/template fallback so the app runs with zero install. Never wire a
   paid Anthropic/OpenAI key. The engine layer is pluggable in `backend/llm.py`.
2. **Never invent a price (or any property detail).** Matching is done in
   Python over `data/listings.json`; the model is only ever given the real
   matching rows and may only present those. Keep this guarantee intact.
3. **Persona = formal but casual**, bilingual. Egyptian dialect for Arabic,
   English for English (auto-detected). Honest, gentle urgency; always offer a
   viewing; never fake scarcity. Persona lives in `backend/persona.py`.
4. **Brand identity is fixed** (see `docs/PROJECT_PLAN.md` → Brand). Navy
   `#0D1B2A`, blue `#2563EB`, Poppins + Cairo, house-with-window logo.

## Current state
- **Phase 1 (the "brain") is built and verified.** FastAPI backend + the LLM
  layer + listings matching + the branded bilingual chat UI all work. In
  Preview mode (no engine) replies are templated but still grounded in real
  prices; with Ollama/Gemini it holds natural conversations.
- **Phase 2 (listings admin panel) is built.** `/admin` (frontend/admin.html)
  gives a bilingual add/edit/delete form over `data/listings.json`. Backend CRUD
  lives in `listings.py` (validate/add/update/delete/next_id, atomic `_save`)
  and `app.py` (`/api/listings` GET/POST/PUT/DELETE). Writes are gated by an
  optional `ADMIN_TOKEN` (sent as the `X-Admin-Token` header). Edits hit the
  in-memory cache + disk so the broker sees them with no restart.
- **Phase 3 (Flutter mobile app) is scaffolded** in `mobile/` — splash, home
  dashboard (status pill, "continue your journey", feature cards), bilingual +
  RTL chat wired to `/api/chat`, and the Home/Projects/Chat/Saved/Profile bottom
  nav. Brand-matched (navy/blue, Poppins/Cairo, CustomPaint house logo). Native
  `android/`/`ios/` folders are NOT committed — run `flutter create .` in
  `mobile/` to generate them. Not yet compiled (no Flutter SDK on the dev box).
- Public repo: https://github.com/alialielkhayat246-a11y/Homzy (MIT).
- `data/listings.json` is **sample placeholder data** — replace with real units.
- Next up: finish Phase 3 (run/verify the app, app icon, Projects/Saved/Profile,
  backend hosting) — see `mobile/README.md` and `docs/PROJECT_PLAN.md` §9.

## Where things are
| Path | What it is |
|------|------------|
| `backend/app.py` | FastAPI server + `/api/chat`, `/api/health`, `/api/reset` |
| `backend/broker.py` | Per-turn pipeline: language → needs → match → reply |
| `backend/listings.py` | Load + search inventory (source of truth for prices) |
| `backend/persona.py` | Broker character, prompts, preview templates |
| `backend/llm.py` | Free engines: Ollama / Gemini / mock |
| `backend/config.py` | Settings from `.env` |
| `data/listings.json` | Property inventory |
| `frontend/index.html` | The chat UI (single file) |
| `frontend/admin.html` | The listings admin panel (`/admin`, single file) |
| `run.bat` | One-click setup + launch (Windows) |

## Run it (any device)
Needs Python 3.12+.
```bash
python -m venv .venv
.venv\Scripts\activate            # Windows  (use source .venv/bin/activate on macOS/Linux)
pip install -r requirements.txt
python -m uvicorn backend.app:app --reload --port 8000
```
Open http://127.0.0.1:8000. For full AI: install Ollama + `ollama pull qwen2.5:7b`,
or copy `.env.example` to `.env` and set a free Gemini key. (Windows users can
just double-click `run.bat`.)

## Immediate next actions (continue here)
1. Turn on the AI engine (install Ollama, `ollama pull qwen2.5:7b`) and confirm
   the status pill goes green; run a bilingual test chat.
2. Replace sample listings with Ali's real units — now doable via `/admin`.
3. Start **Phase 3** (Flutter mobile app) — see `docs/PROJECT_PLAN.md` → Roadmap.

## Working norms
- Test the broker pipeline before claiming a change works (a quick
  `broker.handle_turn({}, "...")` in `LLM_PROVIDER=mock` is enough to smoke-test
  matching without any engine).
- Match the existing code style; keep functions small and commented where
  intent isn't obvious.
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
