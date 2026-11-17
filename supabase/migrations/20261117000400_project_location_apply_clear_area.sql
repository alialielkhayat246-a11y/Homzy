-- A strongly contradicted area (the evidence says the project is clearly elsewhere, but
-- doesn't literally name the new area) is removed until an admin decides: the chat must
-- not keep offering a project in an area it isn't in. The old value stays in the audit.
create or replace function public.project_location_apply(p_key text, p_project uuid, p_result jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare pr public.projects; act text := coalesce(p_result->>'action', 'review');
        clr boolean := coalesce((p_result->>'clear_area')::boolean, false);
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
    area = case when act in ('applied', 'changed') then p_result->>'area'
                when act = 'review' and clr then null else area end,
    country = case when act in ('applied', 'changed', 'country', 'same') and coalesce(p_result->>'country', '') <> ''
                   then p_result->>'country' else country end,
    location = case when act in ('applied', 'changed', 'same', 'country') and coalesce(p_result->>'location_ar', '') <> ''
                    then p_result->>'location_ar' else location end,
    location_verified_at = now(),
    location_source = case when act in ('applied', 'changed', 'same', 'country') then p_result->>'source'
                           when act = 'review' and clr then 'doubt' else location_source end
  where id = p_project;
  return act;
end $$;
