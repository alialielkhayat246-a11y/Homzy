-- enrich_catalog(items jsonb): bulk-apply byit payment terms onto the catalog.
-- Keyed by projects.external_id ('byit-<projectId>'). SECURITY DEFINER so it can
-- be called via PostgREST with the anon key during a one-off import. Only touches
-- rows that already exist; never inserts, never affects non-byit projects.
create or replace function public.enrich_catalog(items jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  update projects p
     set delivery = nullif(i->>'delivery',''),
         status   = nullif(i->>'status','')
    from jsonb_array_elements(items) i
   where p.external_id = i->>'ext';

  update unit_types u
     set down_payment      = nullif(i->>'dp',''),
         installment_years = nullif(i->>'inst','')::int,
         delivery          = coalesce(nullif(i->>'delivery',''), u.delivery),
         finishing         = coalesce(nullif(i->>'finishing',''), u.finishing),
         payment_plan      = nullif(i->>'plan','')
    from jsonb_array_elements(items) i
    join projects p on p.external_id = i->>'ext'
   where u.project_id = p.id;

  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.enrich_catalog(jsonb) to anon, authenticated;
