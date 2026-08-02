-- Restrict the launches/offers feed to the app owner (admin) only.
alter table public.profiles add column if not exists is_admin boolean not null default false;

drop policy if exists launches_insert_broker on public.launches;
create policy launches_insert_admin on public.launches for insert
  with check (created_by = auth.uid() and exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
