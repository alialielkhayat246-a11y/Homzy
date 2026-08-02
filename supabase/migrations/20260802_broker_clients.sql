-- Broker CRM: each broker's private client pipeline (RLS: owner-only).
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text,
  purpose text,
  type text,
  area text,
  bedrooms int,
  budget numeric,
  stage text not null default 'new',  -- new | contacted | viewing | closed | lost
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists clients_owner_idx on public.clients(owner_id, stage);
alter table public.clients enable row level security;
create policy clients_own on public.clients for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
