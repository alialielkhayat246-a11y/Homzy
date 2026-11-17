-- Homzy sells Egypt. Projects outside Egypt (the ~630 Dubai projects that came in with
-- the BYIT import, priced in AED but labelled EGP) are hidden everywhere — site, app,
-- SEO pages, chat — by RLS, so no page can forget the filter. Nobody browses them (admins
-- included — otherwise the admin would think they're still public); /admin/locations works
-- through its own security-definer function.
-- Views v_city_counts / v_developer_counts are security_invoker, so they follow this too.

drop policy if exists "public read projects" on public.projects;
create policy "public read projects" on public.projects for select
  using (country = 'EG');

drop policy if exists "public read unit_types" on public.unit_types;
create policy "public read unit_types" on public.unit_types for select
  using (exists (select 1 from public.projects p where p.id = unit_types.project_id));

drop policy if exists "public read project_media" on public.project_media;
create policy "public read project_media" on public.project_media for select
  using (exists (select 1 from public.projects p where p.id = project_media.project_id));

-- new imports: a project that arrives with no area and Reelly (Dubai) media is not Egypt
create or replace function public._project_area_canon()
returns trigger language plpgsql set search_path = public as $$
declare c text;
begin
  if new.area is not null then
    new.area := nullif(btrim(new.area), '');
    select canonical into c from public.area_aliases where alias = lower(new.area);
    if c is not null then new.area := c; end if;
  end if;
  if tg_op = 'INSERT' and new.area is null and coalesce(new.cover_image_url, '') ilike '%reelly%' then
    new.country := 'AE';
    new.location_source := coalesce(new.location_source, 'heuristic:reelly-import');
  end if;
  return new;
end $$;
