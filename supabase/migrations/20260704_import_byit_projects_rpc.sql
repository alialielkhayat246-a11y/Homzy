-- import_byit_projects(items jsonb): insert byit compounds that aren't in the
-- catalog yet (existing external_id 'byit-<id>' are skipped, never duplicated).
-- Reuses developers by name; inserts project, its unit grid and media. Computes
-- the actual EGP down-payment amount per unit from price × down_payment%.
create or replace function public.import_byit_projects(items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  it jsonb; u jsonb;
  dev_id uuid; proj_id uuid;
  ins_projects int := 0; ins_units int := 0;
  orig_dp text; pct numeric; amt numeric; dp_field text; plan text; img text;
begin
  for it in select value from jsonb_array_elements(items)
  loop
    if exists (select 1 from projects where external_id = it->>'ext') then
      continue;
    end if;

    dev_id := null;
    if coalesce(it->>'dev_name','') <> '' then
      select id into dev_id from developers where name = it->>'dev_name' limit 1;
      if dev_id is null then
        insert into developers (name, logo_url, phone)
        values (it->>'dev_name', nullif(it->>'dev_logo',''), nullif(it->>'dev_phone',''))
        returning id into dev_id;
      end if;
    end if;

    insert into projects (external_id, developer_id, name, name_ar, area, delivery, status, cover_image_url)
    values (it->>'ext', dev_id, it->>'name', nullif(it->>'name_ar',''), nullif(it->>'area',''),
            nullif(it->>'delivery',''), nullif(it->>'status',''), nullif(it->>'cover',''))
    returning id into proj_id;
    ins_projects := ins_projects + 1;

    for u in select value from jsonb_array_elements(coalesce(it->'units','[]'::jsonb))
    loop
      orig_dp := nullif(u->>'down_payment','');
      dp_field := orig_dp;
      plan := nullif(u->>'payment_plan','');
      if orig_dp ~ '^[0-9.]+%$' and (u->>'price_from') is not null then
        pct := replace(orig_dp,'%','')::numeric;
        amt := round((u->>'price_from')::numeric * pct / 100);
        dp_field := orig_dp || ' (≈ ' || to_char(amt,'FM999,999,999') || ' EGP)';
        if plan is not null then
          plan := replace(plan, orig_dp || ' down payment',
                          orig_dp || ' down payment (≈ ' || to_char(amt,'FM999,999,999') || ' EGP)');
        end if;
      end if;
      insert into unit_types (project_id, type, bedrooms, size_from, price_from,
                              down_payment, installment_years, delivery, finishing, payment_plan, currency)
      values (proj_id, u->>'type', nullif(u->>'bedrooms','')::int, nullif(u->>'size_from','')::numeric,
              nullif(u->>'price_from','')::numeric, dp_field, nullif(u->>'installment_years','')::int,
              nullif(u->>'delivery',''), nullif(u->>'finishing',''), plan, 'EGP');
      ins_units := ins_units + 1;
    end loop;

    if nullif(it->>'pdf','') is not null then
      insert into project_media (project_id, kind, url) values (proj_id, 'brochure', it->>'pdf');
    end if;
    for img in select value#>>'{}' from jsonb_array_elements(coalesce(it->'imgs','[]'::jsonb))
    loop
      if nullif(img,'') is not null then
        insert into project_media (project_id, kind, url) values (proj_id, 'image', img);
      end if;
    end loop;
  end loop;

  return jsonb_build_object('projects', ins_projects, 'units', ins_units);
end;
$$;

grant execute on function public.import_byit_projects(jsonb) to anon, authenticated;
