-- Broker-to-broker board (co-broking): brokers post, everyone reads active.
create table if not exists public.cobroking (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'have',   -- have | want
  title text not null,
  purpose text, type text, area text, bedrooms int, budget numeric,
  description text, phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists cobroking_active_idx on public.cobroking(active, created_at desc);
alter table public.cobroking enable row level security;
create policy cobroking_read on public.cobroking for select
  using (active = true or owner_id = auth.uid());
create policy cobroking_insert_broker on public.cobroking for insert
  with check (owner_id = auth.uid() and exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'broker'));
create policy cobroking_update_own on public.cobroking for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy cobroking_delete_own on public.cobroking for delete
  using (owner_id = auth.uid());
