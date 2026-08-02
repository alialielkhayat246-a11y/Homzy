-- Curated launches & offers feed: brokers post, everyone reads active items.
create table if not exists public.launches (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references auth.users(id) on delete cascade,
  kind text not null default 'launch',   -- launch | offer
  title text not null,
  developer text,
  project text,
  area text,
  description text,
  image_url text,
  link text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists launches_active_idx on public.launches(active, created_at desc);

alter table public.launches enable row level security;

create policy launches_read on public.launches for select
  using (active = true or created_by = auth.uid());
create policy launches_insert_broker on public.launches for insert
  with check (created_by = auth.uid() and exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'broker'));
create policy launches_update_own on public.launches for update
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy launches_delete_own on public.launches for delete
  using (created_by = auth.uid());
