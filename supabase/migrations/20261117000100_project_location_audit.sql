-- Project locations the chat can trust.
--
-- 1) projects.country: the catalog import brought in ~600 UAE (Dubai) projects with no
--    area and prices labelled EGP. The chat must never offer those to an Egyptian
--    client as if they were in Egypt. Default 'EG'; the location audit sets the rest.
-- 2) One spelling per area ("Zayed" / "Sheikh Zayed", "Shorouk City" / "Shorouk"…):
--    the chat filters projects by exact area names, so variants silently fell out of
--    searches. area_aliases + a trigger keep every write canonical.
-- 3) project_location_audit: Gemini reads each project's cover, brochure, description
--    and WhatsApp updates and reports where the project really is, with the quote it
--    read. Explicit, high-confidence findings are applied (old value kept here);
--    the rest wait for an admin on /admin/locations.

alter table public.projects
  add column if not exists country text not null default 'EG',
  add column if not exists location_verified_at timestamptz,
  add column if not exists location_source text;

create table if not exists public.area_aliases (
  alias text primary key,          -- lower(trim(spelling))
  canonical text not null
);
alter table public.area_aliases enable row level security;
drop policy if exists area_aliases_read on public.area_aliases;
create policy area_aliases_read on public.area_aliases for select using (true);
grant select on public.area_aliases to anon, authenticated;

insert into public.area_aliases(alias, canonical) values
  ('6 october','6th of October'), ('6th october','6th of October'), ('october','6th of October'),
  ('october city','6th of October'), ('6th of october city','6th of October'),
  ('zayed','Sheikh Zayed'), ('el sheikh zayed','Sheikh Zayed'), ('sheikh zayed city','Sheikh Zayed'),
  ('shorouk','El Shorouk'), ('shorouk city','El Shorouk'), ('el shorouk city','El Shorouk'),
  ('obour','El Obour'), ('obour city','El Obour'), ('new obour','El Obour'),
  ('naser city','Nasr City'), ('nasr city','Nasr City'),
  ('el mokatam','Mokattam'), ('mokatam','Mokattam'), ('el mokattam','Mokattam'),
  ('el maadi','Maadi'),
  ('ras sedr','Ras Sudr'), ('ras sudar','Ras Sudr'), ('ras sudr','Ras Sudr'),
  ('hadayek october','October Gardens'), ('hadayek el october','October Gardens'),
  ('6th settlement','New Cairo'), ('fifth settlement','New Cairo'), ('5th settlement','New Cairo'),
  ('kattameya','New Cairo'), ('katameya','New Cairo'),
  ('new administrative capital','New Capital'), ('administrative capital','New Capital'),
  ('mostakbal','Mostakbal City'), ('future city','Mostakbal City'),
  ('sahel','North Coast'), ('alex','Alexandria'), ('sokhna','Ain Sokhna'),
  ('gouna','El Gouna'), ('sahl hashish','Sahl Hasheesh')
on conflict (alias) do update set canonical = excluded.canonical;

create or replace function public._project_area_canon()
returns trigger language plpgsql set search_path = public as $$
declare c text;
begin
  if new.area is not null then
    new.area := nullif(btrim(new.area), '');
    select canonical into c from public.area_aliases where alias = lower(new.area);
    if c is not null then new.area := c; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_project_area_canon on public.projects;
create trigger trg_project_area_canon before insert or update of area on public.projects
  for each row execute function public._project_area_canon();

-- canonicalise what is already there (6th Settlement / Kattameya keep their detail as location)
update public.projects set location = coalesce(nullif(location, ''),
         case lower(area) when '6th settlement' then 'التجمع السادس' when 'kattameya' then 'القطامية' end)
 where lower(area) in ('6th settlement', 'kattameya');
update public.projects p set area = a.canonical
  from public.area_aliases a where a.alias = lower(btrim(p.area)) and p.area is distinct from a.canonical;

create table if not exists public.project_location_audit (
  id bigserial primary key,
  project_id uuid not null references public.projects(id) on delete cascade,
  checked_at timestamptz not null default now(),
  old_area text, old_country text, old_location text,
  found_country text, found_area text, location_ar text, location_en text,
  source text,          -- cover | brochure | image | description | whatsapp | name | none
  quote text,           -- the words actually read
  confidence numeric,
  action text not null, -- applied | changed | same | country | review | no_evidence
  model text, note text,
  reviewed_by uuid, reviewed_at timestamptz, review_decision text
);
create index if not exists project_location_audit_project on public.project_location_audit(project_id, checked_at desc);
create index if not exists project_location_audit_open on public.project_location_audit(action) where reviewed_at is null;
alter table public.project_location_audit enable row level security;
revoke all on public.project_location_audit from anon, authenticated;

-- evidence for the next projects to check (worker side, key-gated)
create or replace function public.project_location_queue(p_key text, p_limit int default 1, p_project uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(x) from (
      select jsonb_build_object(
        'id', p.id, 'name', p.name, 'name_ar', p.name_ar, 'area', p.area, 'country', p.country,
        'location', p.location, 'developer', d.name,
        'description', left(coalesce(p.description, p.description_ar, ''), 1500),
        'cover', p.cover_image_url,
        'images', (select coalesce(jsonb_agg(m.url), '[]'::jsonb) from (
                     select url from public.project_media m where m.project_id = p.id and m.kind = 'image'
                      order by m.created_at limit 2) m),
        'brochure', (select m.url from public.project_media m where m.project_id = p.id and m.kind = 'brochure'
                      order by m.created_at limit 1),
        'whatsapp', (select coalesce(jsonb_agg(t.txt), '[]'::jsonb) from (
                     select left(u.message_text, 600) txt from public.catalog_updates u
                      where u.project_id = p.id and u.message_text is not null
                      order by u.message_at desc nulls last limit 6) t)
      ) x
      from public.projects p left join public.developers d on d.id = p.developer_id
      where (p_project is not null and p.id = p_project)
         or (p_project is null and p.location_verified_at is null)
      order by (p.area is null), p.created_at
      limit greatest(1, least(p_limit, 20))
    ) q), '[]'::jsonb);
end $$;

-- record a verdict; p_action decides what changes on the project
create or replace function public.project_location_apply(p_key text, p_project uuid, p_result jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare pr public.projects; act text := coalesce(p_result->>'action', 'review');
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into pr from public.projects where id = p_project for update;
  if not found then return 'missing'; end if;
  insert into public.project_location_audit(project_id, old_area, old_country, old_location, found_country, found_area,
         location_ar, location_en, source, quote, confidence, action, model, note)
  values (p_project, pr.area, pr.country, pr.location, p_result->>'country', p_result->>'area',
          p_result->>'location_ar', p_result->>'location_en', p_result->>'source', left(p_result->>'quote', 600),
          nullif(p_result->>'confidence', '')::numeric, act, p_result->>'model', left(p_result->>'note', 400));
  update public.projects set
    area = case when act in ('applied', 'changed') then p_result->>'area' else area end,
    country = case when act in ('applied', 'changed', 'country', 'same') and coalesce(p_result->>'country', '') <> ''
                   then p_result->>'country' else country end,
    location = case when act in ('applied', 'changed', 'same', 'country') and coalesce(p_result->>'location_ar', '') <> ''
                    then p_result->>'location_ar' else location end,
    location_verified_at = now(),
    location_source = case when act in ('applied', 'changed', 'same', 'country') then p_result->>'source' else location_source end
  where id = p_project;
  return act;
end $$;

-- admin review page
create or replace function public.admin_location_review(p_all boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin_user() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(r order by r->>'checked_at' desc) from (
    select jsonb_build_object('id', a.id, 'project_id', a.project_id, 'name', p.name, 'name_ar', p.name_ar,
             'developer', d.name, 'cover', p.cover_image_url, 'area_now', p.area, 'country_now', p.country,
             'old_area', a.old_area, 'found_area', a.found_area, 'found_country', a.found_country,
             'location_ar', a.location_ar, 'source', a.source, 'quote', a.quote, 'confidence', a.confidence,
             'action', a.action, 'note', a.note, 'checked_at', a.checked_at,
             'reviewed_at', a.reviewed_at, 'review_decision', a.review_decision) r
      from public.project_location_audit a
      join public.projects p on p.id = a.project_id
      left join public.developers d on d.id = p.developer_id
     where (p_all and a.action in ('changed', 'country')) or (a.action = 'review' and a.reviewed_at is null)
     order by a.checked_at desc limit 400) s), '[]'::jsonb);
end $$;

create or replace function public.admin_location_decide(p_audit bigint, p_area text, p_country text default 'EG',
                                                        p_location text default null)
returns text language plpgsql security definer set search_path = public as $$
declare a public.project_location_audit;
begin
  if not public.is_admin_user() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into a from public.project_location_audit where id = p_audit for update;
  if not found then return 'missing'; end if;
  update public.projects set area = nullif(btrim(coalesce(p_area, '')), ''),
         country = coalesce(nullif(p_country, ''), country),
         location = coalesce(nullif(btrim(coalesce(p_location, '')), ''), location),
         location_verified_at = now(), location_source = 'admin'
   where id = a.project_id;
  update public.project_location_audit set reviewed_by = auth.uid(), reviewed_at = now(),
         review_decision = coalesce(p_country, '') || ':' || coalesce(p_area, '')
   where id = p_audit;
  return 'ok';
end $$;

revoke all on function public.project_location_queue(text, int, uuid) from public;
revoke all on function public.project_location_apply(text, uuid, jsonb) from public;
revoke all on function public.admin_location_review(boolean) from public;
revoke all on function public.admin_location_decide(bigint, text, text, text) from public;
grant execute on function public.project_location_queue(text, int, uuid) to anon, authenticated;
grant execute on function public.project_location_apply(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.admin_location_review(boolean) to authenticated;
grant execute on function public.admin_location_decide(bigint, text, text, text) to authenticated;
