-- Daily developer-update pipeline: messages read from the developer WhatsApp
-- groups land here as PENDING; an admin approves before anything touches the
-- live catalog.
create table if not exists public.catalog_updates (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  group_name text not null,
  sender text,
  message_at timestamptz,
  message_text text not null,
  has_media text,                      -- 'IMG' / 'PDF' / 'IMG,PDF'
  msg_hash text unique,                -- dedupe across runs
  developer_id uuid references public.developers(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  project_name_raw text,
  kind text not null default 'other'
    check (kind in ('price','payment_plan','new_launch','new_phase','delivery','brochure','other')),
  summary_ar text,
  extracted jsonb not null default '{}'::jsonb,   -- {area, units:[{type,bedrooms,size_from,size_to,price_from,down_payment,installment_years,payment_plan,finishing,delivery}]}
  status text not null default 'pending' check (status in ('pending','applied','rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text
);
create index if not exists catalog_updates_status_idx on public.catalog_updates(status, created_at desc);

create table if not exists public.wa_sync_state (
  group_name text primary key,
  enabled boolean not null default true,
  developer_id uuid references public.developers(id) on delete set null,
  last_message_at timestamptz,
  last_run_at timestamptz
);

alter table public.catalog_updates enable row level security;
alter table public.wa_sync_state enable row level security;

create or replace function public.is_admin_user() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

drop policy if exists catalog_updates_admin on public.catalog_updates;
create policy catalog_updates_admin on public.catalog_updates for all to authenticated
  using (public.is_admin_user()) with check (public.is_admin_user());
drop policy if exists wa_sync_state_admin on public.wa_sync_state;
create policy wa_sync_state_admin on public.wa_sync_state for all to authenticated
  using (public.is_admin_user()) with check (public.is_admin_user());

-- Apply an approved update to the live catalog (admin only).
--  * inserts each extracted unit into unit_types for the project
--  * p_replace: first removes the project's existing rows of the same unit type
--    (and bedrooms when given) so the old price stops showing
--  * no project_id + p_create_project: creates the project from the extracted
--    name/area under the update's developer
create or replace function public.apply_catalog_update(p_id uuid, p_replace boolean default false, p_create_project boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u public.catalog_updates;
  v_project uuid;
  x jsonb;
  n int := 0;
begin
  if not public.is_admin_user() then raise exception 'admin only'; end if;
  select * into u from catalog_updates where id = p_id for update;
  if not found then raise exception 'update not found'; end if;
  if u.status <> 'pending' then raise exception 'already %', u.status; end if;

  v_project := u.project_id;
  if v_project is null then
    if not p_create_project then raise exception 'no project linked'; end if;
    if u.developer_id is null or coalesce(u.extracted->>'project_name', u.project_name_raw) is null then
      raise exception 'need developer and project name to create a project';
    end if;
    insert into projects (developer_id, name, area, status, delivery)
    values (u.developer_id, coalesce(u.extracted->>'project_name', u.project_name_raw),
            u.extracted->>'area', coalesce(u.extracted->>'status', 'Off-plan'), u.extracted->>'delivery')
    returning id into v_project;
  end if;

  for x in select * from jsonb_array_elements(coalesce(u.extracted->'units', '[]'::jsonb)) loop
    if p_replace and x->>'type' is not null then
      delete from unit_types t where t.project_id = v_project and lower(t.type) = lower(x->>'type')
        and (x->>'bedrooms' is null or t.bedrooms = (x->>'bedrooms')::int);
    end if;
    insert into unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, currency,
                            down_payment, installment_years, payment_plan, finishing, delivery)
    values (v_project, coalesce(x->>'type','apartment'), nullif(x->>'bedrooms','')::int,
            nullif(x->>'size_from','')::numeric, nullif(x->>'size_to','')::numeric,
            nullif(x->>'price_from','')::numeric, nullif(x->>'price_to','')::numeric, 'EGP',
            x->>'down_payment', nullif(x->>'installment_years','')::int, x->>'payment_plan',
            x->>'finishing', x->>'delivery');
    n := n + 1;
  end loop;

  update projects set updated_at = now() where id = v_project;
  update catalog_updates set status = 'applied', project_id = v_project,
         reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('project_id', v_project, 'units_added', n);
end $$;
revoke all on function public.apply_catalog_update(uuid, boolean, boolean) from public, anon;
grant execute on function public.apply_catalog_update(uuid, boolean, boolean) to authenticated;
