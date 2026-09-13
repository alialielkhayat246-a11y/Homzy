
-- Lead assignee (§6). Current assignee on the lead; history kept separately.
alter table public.clients
  add column if not exists assigned_to uuid;

-- Owner / acquisition database (§8, §9)
create table if not exists public.owners (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid(),   -- record owner (creating broker)
  agency_id     uuid references public.agencies(id) on delete set null,
  team_id       uuid references public.teams(id) on delete set null,
  created_by     uuid default auth.uid(),
  assigned_to    uuid,                                -- acquisition agent
  name          text not null,
  phone         text,
  whatsapp      text,
  area          text,
  property_type text,
  purpose       text,                                 -- sale | rent
  asking_price  numeric,
  property_ref  text,
  source        text,                                 -- facebook | dubizzle | referral | ...
  source_kind   text not null default 'agent',        -- company | agent (for commission, §9/§14)
  stage         text not null default 'new',
  status        text not null default 'active',       -- active | not_interested | rejected | unavailable
  last_contact  timestamptz,
  next_followup date,
  notes         text,
  custom        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
alter table public.owners drop constraint if exists owners_stage_chk;
alter table public.owners add constraint owners_stage_chk check (stage in
  ('new','not_contacted','contacted','interested','info_collected','verification',
   'owner_approval','ready_marketing','active_listing'));
alter table public.owners drop constraint if exists owners_status_chk;
alter table public.owners add constraint owners_status_chk check (status in
  ('active','not_interested','rejected','unavailable'));
alter table public.owners drop constraint if exists owners_source_kind_chk;
alter table public.owners add constraint owners_source_kind_chk check (source_kind in ('company','agent'));
create index if not exists owners_agency_idx on public.owners(agency_id);
create index if not exists owners_owner_idx on public.owners(owner_id);
create index if not exists owners_assigned_idx on public.owners(assigned_to);

-- Lead assignment history (§6/§15 accountability)
create table if not exists public.lead_assignments (
  id           bigint generated always as identity primary key,
  lead_id      uuid not null references public.clients(id) on delete cascade,
  agency_id    uuid references public.agencies(id) on delete set null,
  assigned_to  uuid,
  assigned_by  uuid default auth.uid(),
  assigned_at  timestamptz not null default now(),
  unassigned_at timestamptz,
  reason       text
);
create index if not exists lead_assign_lead_idx on public.lead_assignments(lead_id);
create index if not exists lead_assign_agency_idx on public.lead_assignments(agency_id);

-- Multi-party commission contributors (§14)
create table if not exists public.deal_contributors (
  id           bigint generated always as identity primary key,
  deal_id      bigint not null references public.crm_deals(id) on delete cascade,
  agency_id    uuid references public.agencies(id) on delete set null,
  user_id      uuid,
  role_in_deal text not null default 'other',   -- acquisition | buyer_broker | team_leader | closer | other
  share_pct    numeric not null default 0,
  share_amount numeric,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists deal_contrib_deal_idx on public.deal_contributors(deal_id);

-- Configurable commission rules (§14 — never hardcode a single %)
create table if not exists public.commission_rules (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null references public.agencies(id) on delete cascade,
  key         text not null,
  label_en    text,
  label_ar    text,
  applies_to  text,                 -- company_owner_lead | agent_sourced | agent_closed | ...
  agent_pct   numeric not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (agency_id, key)
);

alter table public.owners enable row level security;
alter table public.lead_assignments enable row level security;
alter table public.deal_contributors enable row level security;
alter table public.commission_rules enable row level security;
