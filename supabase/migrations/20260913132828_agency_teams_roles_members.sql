
-- 1) Extend the agency workspace (§1)
alter table public.agencies
  add column if not exists logo_url    text,
  add column if not exists phone       text,
  add column if not exists email       text,
  add column if not exists address     text,
  add column if not exists description text,
  add column if not exists settings    jsonb not null default '{}'::jsonb,
  add column if not exists updated_at   timestamptz not null default now();

-- 2) Teams (§18)
create table if not exists public.teams (
  id         uuid primary key default gen_random_uuid(),
  agency_id  uuid not null references public.agencies(id) on delete cascade,
  name       text not null,
  leader_id  uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists teams_agency_idx on public.teams(agency_id);

-- 3) Roles — default + custom, per agency (§3/§4)
create table if not exists public.roles (
  id         uuid primary key default gen_random_uuid(),
  agency_id  uuid not null references public.agencies(id) on delete cascade,
  key        text not null,
  name_en    text not null,
  name_ar    text not null,
  is_system  boolean not null default false,
  rank       int not null default 100,
  created_at timestamptz not null default now(),
  unique (agency_id, key)
);
create index if not exists roles_agency_idx on public.roles(agency_id);

-- 4) Role → permissions (RBAC join, §4)
create table if not exists public.role_permissions (
  role_id        uuid not null references public.roles(id) on delete cascade,
  permission_key text not null references public.permissions(key) on delete cascade,
  primary key (role_id, permission_key)
);

-- 5) Extend membership (§2 statuses, teams, role link, invites)
alter table public.agency_members
  add column if not exists member_id     uuid not null default gen_random_uuid(),
  add column if not exists role_id        uuid references public.roles(id) on delete set null,
  add column if not exists team_id        uuid references public.teams(id) on delete set null,
  add column if not exists status         text not null default 'active',
  add column if not exists title          text,
  add column if not exists invited_email  text,
  add column if not exists invited_at     timestamptz,
  add column if not exists joined_at       timestamptz not null default now(),
  add column if not exists suspended_at    timestamptz,
  add column if not exists created_by      uuid;

alter table public.agency_members drop constraint if exists agency_members_status_chk;
alter table public.agency_members add constraint agency_members_status_chk
  check (status in ('active','inactive','suspended','pending'));

create unique index if not exists agency_members_member_id_key on public.agency_members(member_id);
create index if not exists agency_members_team_idx on public.agency_members(team_id);
create index if not exists agency_members_role_idx on public.agency_members(role_id);

alter table public.teams enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
