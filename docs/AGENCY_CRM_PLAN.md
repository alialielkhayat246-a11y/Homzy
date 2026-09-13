# Agency & Team Management — build plan & progress

Extends the existing Homzy CRM (do **not** rebuild). Homzy = platform; agencies =
tenants. Every agency workspace is isolated at the **database (RLS)** level.

## Architecture decisions
- **Ownership stays per-row** via `owner_id = auth.uid()` (individual brokers keep
  working, agency_id IS NULL). Agency rows additionally carry `agency_id` / `team_id`
  / `assigned_to`, and **agency-row access requires ACTIVE membership** — so
  suspending a member instantly revokes access (§28-M) while history is retained.
- **RBAC** = global `permissions` catalog (expandable) + per-agency `roles` +
  `role_permissions`. Access is checked by `has_perm(agency_id, perm)`:
  platform admin OR agency owner OR **active** member whose role grants the perm.
- Legacy `agency_members.role` text (owner/admin/agent) kept in sync so the older
  `is_agency_admin_of()` overlay keeps working.

## Phase 1 — Foundation (DONE, verified 2026-09-13)
Migrations applied (Supabase project `ceoqtkbpdxnkuptnnwjg`):
`agency_permissions_catalog`, `agency_teams_roles_members`,
`agency_owners_assignments_commission`, `agency_rbac_functions_and_rls`,
`agency_management_rpcs`, `fix_agency_members_policy_recursion`,
`agency_membership_gated_access`.

New/extended tables: `agencies`(+logo/phone/email/address/description/settings),
`agency_members`(+member_id/role_id/team_id/status/invite/joined/created_by),
`teams`, `permissions`(31 seeded), `roles`, `role_permissions`, `owners`
(acquisition pipeline), `lead_assignments`, `deal_contributors`(≤100% trigger),
`commission_rules`; `clients.assigned_to`.

Functions: `has_perm`, `is_active_member`, `my_primary_agency`, `deal_contrib_guard`.
RPCs: `create_agency`, `agency_seed_default_roles`, `agency_add_member`,
`agency_set_member_status`, `agency_assign_lead`.

Default roles seeded per agency: owner, admin, team_leader, agent, acquisition,
call_center, coordinator (Arabic names included). Custom roles = add a `roles`
row + `role_permissions`.

**Isolation tests passed (RLS-simulated JWTs):** L (cross-agency = 0 rows),
D (assigned agent sees lead / unassigned same-agency agent does not; via
assignment, not blanket perm), M (suspended member → 0, history preserved).
Security advisor: no new RLS gaps (only pre-existing `crm_offer_shares`).

## Remaining phases (frontend + wiring)
- **P2 Team Management + Agency setup** — `/team`: create agency (`create_agency`),
  invite/add/suspend/reactivate/change-role, teams, role editor over `permissions`.
- **P3 Owners DB + Acquisition pipeline** — `/owners` Kanban over `owners.stage`.
- **P4 Lead Inbox + assignment + Sales pipeline Kanban** — extend `/clients`;
  unassigned-inbox view; `agency_assign_lead`; drag-drop stages → `crm_sales_move_stage`.
- **P5 Commission engine UI** — `commission_rules` editor + `deal_contributors` on `/deals`.
- **P6 Team dashboard / performance / notifications / activity feed** (`crm_events`).

CRM sub-nav lives in `frontend/assets/homzy.js` `buildCrmSubnav()`; routes in
`backend/app.py` (FileResponse per page); i18n via `data-ar/data-en` + `HZ.t()`.
