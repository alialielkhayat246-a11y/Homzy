# Homzy CRM sales upgrade — implementation report

Implemented as an extension of the existing FastAPI, static HTML/JavaScript and Supabase application. Marketplace, broker accounts, legacy project offers, commissions, WhatsApp integration, and Homzy Stays remain in place. The five migrations were applied to production Supabase on 2026-09-09 after transaction rollback validation. Application deployment follows through the existing Vercel production branch.

## Delivered

- **Client workspace:** bilingual, responsive modal opened from each client card. Detailed requirements, email/WhatsApp, client source, assigned broker information, timestamps, notes, extraction review, matching, copilot, messages, follow-ups, activity, and offer history.
- **Requirements:** buy/rent, residential/commercial, multiple locations, type, bedrooms/bathrooms, area and budget ranges, available deposit, installment years, delivery, developers and finishing. Validated fields are merged into existing `clients.custom`, with core fields synchronized. Optimistic concurrency rejects stale profile saves. Extraction never saves automatically; individual proposed fields must be selected before applying them to the editable form.
- **Matching:** weighted comparison across available marketplace listings, canonical Arabic/English area aliases, financing and physical requirements where recorded. Wrong intent/currency is excluded. Missing inventory values earn no matching points and reduce displayed coverage. Scores and per-criterion evidence are deterministic. Consented property activity breaks ties without inflating the property-fit percentage.
- **AI services:** extraction, client summaries, next actions, Arabic/English drafts across three channels, seven occasions and four tones, plus aggregate performance recommendations. Existing Ollama/Gemini provider configuration is reused with structured validation, bounded provider calls, and labeled deterministic fallbacks. No autonomous message sending, stage changes or financial actions.
- **Scoring:** configurable, capped, recency-aware intent scoring; removed favorites stop contributing favorite points. Broker-sent messages do not masquerade as customer engagement. Live scores are used in the client list and sales overview, while legacy persisted scoring records are preserved.
- **Pipeline:** ten stages, drag and drop plus the existing accessible stage selector. Transitions use an ownership-checked transaction and activity history. Lost reasons are required. Legacy stage aliases remain readable.
- **Follow-ups:** date/time, type, notes, priority and workspace reminder timing. Existing tasks are reused; task creation and next client follow-up are updated atomically. The timeline includes scheduled/completed follow-ups and lead creation.
- **Deals:** existing deal and commission workflows preserved; added inventory relationship, notes, editable probability, and weighted pipeline value. Lost reasons required.
- **Offers:** multi-listing, source-verified immutable property snapshots, client and broker details, images, pricing, financing, delivery/finishing and amenities where recorded. Preview, browser-native Print/Save PDF, private broker links, explicit seven-day public client links, WhatsApp handoff, and link revocation. Creation records an activity atomically. Premium entitlement is enforced in the database, not just the UI.
- **Overview/analytics:** KPI cards, recent/hot leads, recent activity, priority notifications, pipeline values, historical funnel, time to first recorded contact, conversion metrics, average deal value/sales cycle, task completion and lost reasons. Skipped stages and missing measurements are not invented. Existing `/my-day`, `/deals` and `/insights` remain accessible.
- **Search:** authenticated cross-entity search for clients/phone numbers, deals, available listings, projects and developers. Client/deal/listing search uses GIN full-text indexes with Arabic/English tokenization.
- **Behavior:** broker-issued invitation, explicit signed-in customer consent, and revocation. Marketplace views, searches, contact requests and shares are wired in; marketplace listing favorite additions/removals are recorded through a database trigger. Minute-level deduplication and a daily event cap limit noise. Revocation immediately stops capture and hides historical telemetry from the broker through RLS. No phone-based identity guessing.

## Files

Backend: `backend/crm_sales.py`, `backend/crm_routes.py`, `backend/app.py`, `backend/llm.py`, `requirements.txt`.

Frontend: `frontend/clients.html`, `frontend/deals.html`, `frontend/my-day.html`, `frontend/insights.html`, `frontend/app.html`, `frontend/crm-offer.html`, `frontend/assets/crm-sales.js`, `frontend/assets/crm-sales.css`, `frontend/assets/crm-behavior.js`.

Validation/documentation: `tests/test_crm_sales.py`, `tools/check_crm_sales.cjs`, this report, and `.gitignore` for temporary validation artifacts.

## Migrations and rollout

Apply in this order **before deploying the new frontend/API**:

1. `20260909000100_crm_sales_copilot.sql` — baseline preflight, deal extensions, offers, reviewed profiles and atomic pipeline transitions.
2. `20260909000200_crm_sales_search.sql` — indexed search and authorized search RPC.
3. `20260909000300_crm_offer_sharing.sql` — expiring/revocable offer capabilities.
4. `20260909000400_crm_behavior_consent.sql` — consent, RLS-isolated telemetry, deduplication and favorite trigger.
5. `20260909000500_crm_sales_followups.sql` — atomic follow-up scheduling and reminder metadata.

The first migration fails before modifications if required deployed CRM columns/functions or baseline RLS are missing. Historical phase 2/3/4/7 migration files in this repository contain descriptions of applied SQL rather than replayable definitions. A fresh database cannot be reliably reconstructed from this checkout alone; recover that applied baseline before fresh-environment migration testing.

Production schema inspection corrected activity ownership queries to join `clients.owner_id` (activities have `actor_id`) and mapped the UI's medium follow-up priority to the existing database value `normal`. All five migrations passed a rollback transaction against the production schema before being applied atomically and recorded in `supabase_migrations.schema_migrations`. Synthetic-record runtime checks covered profile saves/stale-save rejection, stage transitions/lost reasons, follow-up scheduling, search, subscription gating, offer sharing/revocation, cross-owner access, consent, favorite triggers, deduplication, and revoked telemetry isolation. All test records were rolled back. Concurrent load testing remains outside these checks.

## Routes and APIs

Existing `/clients` and `/crm` entry points are reused. `/clients?overview=1` opens the sales overview; `/clients?lead=…&offer=…` opens a private offer. New `/crm-offer?token=…` displays an explicitly shared, expiring offer. `/app?crm_consent=…` presents customer consent; `/app?listing=…` opens a shared listing.

Under `/api/crm/sales`:

- `POST /extract`
- `GET /scores`, `/overview`, `/search`
- `GET /clients/{id}/copilot`
- `PUT /clients/{id}/profile`
- `POST /clients/{id}/message`, `/clients/{id}/followups`, `/clients/{id}/behavior-invite`
- `GET|POST /clients/{id}/offers`
- `POST|DELETE /offers/{id}/share`
- `GET /public-offers/{token}` — capability-scoped public snapshot only, with no-store caching.

Authenticated operations validate identity with Supabase and use the caller's JWT plus explicit ownership checks. The existing `/api/crm/ai/lead` endpoint was also hardened against missing authentication and malformed/filter-injected lead IDs. Public-offer reads expose neither lead/owner IDs and notes nor another broker's private records.

## Environment and validation

No new secrets. Reuse `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `LLM_PROVIDER`, `OLLAMA_HOST`, `OLLAMA_MODEL`, `GEMINI_API_KEY`, and `GEMINI_MODEL` as appropriate. AI keys remain server-side; the existing public Supabase browser key is unchanged. Existing push/WhatsApp configuration is unchanged. Pydantic 2.6+ is now explicitly required.

- 29 backend/domain/ASGI tests: passed.
- Existing `tools/check_ui.cjs` and `tools/check_broker.cjs`: passed.
- Playwright fixture tests: Arabic/English at 390/768/1280px; extraction does not overwrite/save automatically; reviewed save; drafts do not send; reminder payload; PDF preview/shared page; capture disabled without consent and after revocation. Deal inventory/probability form checks included.
- Ruff: new backend modules and tests checked; fatal syntax/undefined-name checks cover touched existing backend modules.
- Python compilation, Vercel entry-point import and OpenAPI generation: passed. Mock broker pipeline smoke: passed.
- SQL parsed locally and executed in PostgreSQL rollback tests against the live schema, including the favorite trigger and RLS behavior.
- This is a static-frontend/FastAPI repository with no `package.json` or production bundle script. No Vercel production build or deployment was performed.

## Remaining limits

- Database/RLS behavior was verified in rollback transactions; real AI-provider calls remain unverified. Browser integration tests use isolated fixture data.
- Enhanced matching/multi-property snapshots cover active marketplace listings. The existing primary-project matcher and project PDF workflow remain separate and available; catalog type ranges are not misrepresented as exact available units.
- Ranking is bounded at 10,000 listings; score/history reads at 10,000 events per source; overview entities at 1,000. Truncation is disclosed. Full-text phone lookup works on complete tokens, not arbitrary phone-number substrings. Project/developer search remains RLS-scoped but does not add new indexes to their existing schema.
- Workspace reminders/notifications update on load. Existing background push jobs remain unchanged; this upgrade does not add a new minute-level push scheduler. Dismissals are browser-local.
- Behavioral tracking currently covers the web marketplace and listing favorites. Native mobile events and primary-project viewing telemetry are not yet wired.
- Browser-native PDF generation uses the browser's **Save as PDF** dialog, preserving Arabic shaping; there is no server-rendered PDF attachment endpoint. Printing itself is not proof of delivery, and offer generation is not counted as an offer sent.
- Rate limiting is per API worker. A shared production gateway limiter is still needed for a strict account-wide multi-instance quota. Extended sales operations are owner-only; existing agency features are preserved separately.
