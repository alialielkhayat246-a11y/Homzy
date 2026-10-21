-- Project intelligence from the developer WhatsApp groups, split by who may see it:
--   public : clients (site, client-mode advisor)   — e.g. "new phase launched", "delivery started"
--            (prices themselves are public too, but they live in unit_types, per type and size)
--   broker : brokers + broker-mode advisor          — limited-time offers, inventory, EOI dates
--   ai     : the advisor only (never shown as text) — unconfirmed info, contradictions, demand signals
-- Commissions are never stored (Ali's rule) — enforced here too.
create table if not exists public.project_intel (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  project_id uuid references public.projects(id) on delete cascade,
  developer_id uuid references public.developers(id) on delete set null,
  tier text not null check (tier in ('public','broker','ai')),
  category text not null default 'other'
    check (category in ('launch','new_phase','price','payment_plan','offer','inventory','delivery','construction','brochure','event','other')),
  content_ar text not null,
  data jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  expires_at timestamptz,
  confidence text not null default 'medium' check (confidence in ('high','medium','low')),
  source_count int not null default 1,
  source_update_id uuid references public.catalog_updates(id) on delete set null,
  fingerprint text unique,
  status text not null default 'active' check (status in ('active','hidden'))
);
create index if not exists project_intel_project_idx on public.project_intel(project_id, tier, observed_at desc);
alter table public.project_intel enable row level security;

drop policy if exists project_intel_public_read on public.project_intel;
create policy project_intel_public_read on public.project_intel for select to anon, authenticated
  using (tier = 'public' and status = 'active' and (expires_at is null or expires_at > now()));
drop policy if exists project_intel_broker_read on public.project_intel;
create policy project_intel_broker_read on public.project_intel for select to authenticated
  using (tier in ('public','broker') and status = 'active' and (expires_at is null or expires_at > now())
         and (public.is_broker() or public.is_admin_user()));
drop policy if exists project_intel_admin_all on public.project_intel;
create policy project_intel_admin_all on public.project_intel for all to authenticated
  using (public.is_admin_user()) with check (public.is_admin_user());

-- Intel for the advisor. Public tier for everyone; broker + ai tiers only when the
-- CALLER's JWT belongs to a broker/admin (the backend forwards the user's token).
create or replace function public.project_intel_for_ai(p_project_ids uuid[])
returns table(project_id uuid, tier text, category text, content_ar text, data jsonb, observed_at timestamptz, confidence text)
language sql stable security definer set search_path = public as $$
  select i.project_id, i.tier, i.category, i.content_ar, i.data, i.observed_at, i.confidence
  from project_intel i
  where i.project_id = any(p_project_ids) and i.status = 'active'
    and (i.expires_at is null or i.expires_at > now())
    and (i.tier = 'public' or public.is_broker() or public.is_admin_user())
  order by i.observed_at desc
  limit 60
$$;
grant execute on function public.project_intel_for_ai(uuid[]) to anon, authenticated;

-- Shared unit writer (internal). Price is per type AND size: a new price updates
-- the existing single-size row of the same type (+ bedrooms when given) whose size
-- is within 3% (min 3 m²) of the new size — range rows are never overwritten; an unseen size becomes a new row. Rows nobody updated keep
-- their last price — the newest price is the price. (p_replace kept for API
-- compatibility: when true and the update carries no size, it updates every row
-- of that type/bedrooms.)
create or replace function public._apply_units(p_project uuid, p_units jsonb, p_replace boolean)
returns int language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0; v_row uuid; v_size numeric; v_beds int; v_type text;
begin
  for x in select * from jsonb_array_elements(coalesce(p_units, '[]'::jsonb)) loop
    v_type := lower(coalesce(nullif(x->>'type',''), 'apartment'));
    v_beds := nullif(x->>'bedrooms','')::int;
    v_size := coalesce(nullif(x->>'size_from','')::numeric, nullif(x->>'size_to','')::numeric);
    v_row := null;
    if v_size is not null then
      select t.id into v_row from unit_types t
       where t.project_id = p_project and lower(t.type) = v_type
         and (v_beds is null or t.bedrooms is null or t.bedrooms = v_beds)
         and coalesce(t.size_from, t.size_to) is not null
         and t.size_to is null and abs(coalesce(t.size_from, t.size_to) - v_size) <= greatest(3, 0.03 * v_size)
       order by abs(coalesce(t.size_from, t.size_to) - v_size) limit 1;
    end if;
    if v_row is not null or (v_size is null and p_replace) then
      update unit_types t set
        price_from        = coalesce(nullif(x->>'price_from','')::numeric, t.price_from),
        price_to          = case when nullif(x->>'price_from','') is not null then nullif(x->>'price_to','')::numeric else t.price_to end,
        down_payment      = coalesce(nullif(x->>'down_payment',''), t.down_payment),
        installment_years = coalesce(nullif(x->>'installment_years','')::int, t.installment_years),
        payment_plan      = coalesce(nullif(x->>'payment_plan',''), t.payment_plan),
        finishing         = coalesce(nullif(x->>'finishing',''), t.finishing),
        delivery          = coalesce(nullif(x->>'delivery',''), t.delivery),
        bedrooms          = coalesce(t.bedrooms, v_beds)
      where (v_row is not null and t.id = v_row)
         or (v_row is null and t.project_id = p_project and lower(t.type) = v_type and (v_beds is null or t.bedrooms = v_beds));
    else
      insert into unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, currency,
                              down_payment, installment_years, payment_plan, finishing, delivery)
      values (p_project, v_type, v_beds,
              nullif(x->>'size_from','')::numeric, nullif(x->>'size_to','')::numeric,
              nullif(x->>'price_from','')::numeric, nullif(x->>'price_to','')::numeric, 'EGP',
              x->>'down_payment', nullif(x->>'installment_years','')::int, x->>'payment_plan',
              x->>'finishing', x->>'delivery');
    end if;
    n := n + 1;
  end loop;
  update projects set updated_at = now() where id = p_project;
  return n;
end $$;
revoke all on function public._apply_units(uuid, jsonb, boolean) from public, anon, authenticated;

-- Admin apply now goes through the shared writer.
create or replace function public.apply_catalog_update(p_id uuid, p_replace boolean default false, p_create_project boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.catalog_updates; v_project uuid; n int;
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
    update project_intel set project_id = v_project where source_update_id = p_id and project_id is null;
  end if;
  n := public._apply_units(v_project, u.extracted->'units', p_replace);
  update catalog_updates set status = 'applied', project_id = v_project,
         reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('project_id', v_project, 'units_added', n);
end $$;
revoke all on function public.apply_catalog_update(uuid, boolean, boolean) from public, anon;
grant execute on function public.apply_catalog_update(uuid, boolean, boolean) to authenticated;

-- Ingest v2: queue row + intel rows + automatic price refresh.
-- Prices are public (clients see the latest price per type and size), so they are
-- applied WITHOUT admin review when: the reader marked it auto_apply (a price for a
-- known project, high confidence) AND every price is sane (100k–2bn EGP, and within
-- 1/3x–3x of the project's current prices if any). Everything else — new projects,
-- unsure matches, odd numbers — stays PENDING at /updates.
create or replace function public.wa_ingest_updates(p_secret text, p_rows jsonb, p_groups jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n_in int := 0; n_new int := 0; n_auto int := 0; n_intel int := 0;
        r jsonb; g jsonb; it jsonb; v_id uuid; v_proj uuid; v_dev uuid; ok boolean; cur_min numeric; cur_max numeric; x jsonb;
begin
  if encode(sha256(convert_to(coalesce(p_secret,''), 'utf8')), 'hex')
     <> '572b4929b91ac95e2df4f6d68300c4958fb5f83a8b522509a030bf7b9fadb233' then
    raise exception 'forbidden';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    n_in := n_in + 1;
    v_proj := nullif(r->>'project_id','')::uuid; v_dev := nullif(r->>'developer_id','')::uuid;
    v_id := null;
    insert into catalog_updates (group_name, sender, message_at, message_text, has_media, msg_hash,
                                 developer_id, project_id, project_name_raw, kind, summary_ar, extracted)
    values (r->>'group_name', r->>'sender', nullif(r->>'message_at','')::timestamptz, r->>'message_text',
            nullif(r->>'has_media',''), r->>'msg_hash', v_dev, v_proj, r->>'project_name_raw',
            coalesce(nullif(r->>'kind',''), 'other'), r->>'summary_ar', coalesce(r->'extracted', '{}'::jsonb))
    on conflict (msg_hash) do nothing
    returning id into v_id;
    if v_id is null then continue; end if;
    n_new := n_new + 1;

    -- intel rows (never commissions)
    for it in select * from jsonb_array_elements(coalesce(r->'intel', '[]'::jsonb)) loop
      if coalesce(it->>'content_ar','') = '' or (it->>'content_ar') ~* '(عمول|commission|كوميشن)' then continue; end if;
      insert into project_intel (project_id, developer_id, tier, category, content_ar, data, observed_at, expires_at,
                                 confidence, source_update_id, fingerprint)
      values (v_proj, v_dev, coalesce(it->>'tier','ai'), coalesce(nullif(it->>'category',''),'other'), it->>'content_ar',
              coalesce(it->'data','{}'::jsonb), coalesce(nullif(r->>'message_at','')::timestamptz, now()),
              nullif(it->>'expires_at','')::timestamptz, coalesce(nullif(it->>'confidence',''),'medium'), v_id,
              md5(coalesce(v_proj::text, v_dev::text, '') || '|' || coalesce(it->>'tier','ai') || '|' || lower(it->>'content_ar')))
      on conflict (fingerprint) do update set source_count = project_intel.source_count + 1,
             observed_at = greatest(project_intel.observed_at, excluded.observed_at);
      n_intel := n_intel + 1;
    end loop;

    -- automatic starting-price refresh
    if coalesce((r->>'auto_apply')::boolean, false) and v_proj is not null
       and jsonb_array_length(coalesce(r->'extracted'->'units','[]'::jsonb)) > 0 then
      select min(price_from), max(coalesce(price_to, price_from)) into cur_min, cur_max from unit_types where project_id = v_proj;
      ok := true;
      for x in select * from jsonb_array_elements(r->'extracted'->'units') loop
        if nullif(x->>'price_from','') is null or (x->>'price_from')::numeric not between 100000 and 2000000000
           or (cur_min is not null and ((x->>'price_from')::numeric < cur_min / 3 or (x->>'price_from')::numeric > cur_max * 3)) then
          ok := false;
        end if;
      end loop;
      if ok then
        perform public._apply_units(v_proj, r->'extracted'->'units', true);
        update catalog_updates set status = 'applied', reviewed_at = now(), review_note = 'auto: price update' where id = v_id;
        n_auto := n_auto + 1;
      end if;
    end if;
  end loop;
  for g in select * from jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) loop
    insert into wa_sync_state (group_name, developer_id, last_message_at, last_run_at)
    values (g->>'group_name', nullif(g->>'developer_id','')::uuid, nullif(g->>'last_message_at','')::timestamptz, now())
    on conflict (group_name) do update set
      last_run_at = now(),
      developer_id = coalesce(excluded.developer_id, wa_sync_state.developer_id),
      last_message_at = greatest(wa_sync_state.last_message_at, excluded.last_message_at);
  end loop;
  return jsonb_build_object('received', n_in, 'new', n_new, 'auto_applied', n_auto, 'intel', n_intel);
end $$;
revoke all on function public.wa_ingest_updates(text, jsonb, jsonb) from public;
grant execute on function public.wa_ingest_updates(text, jsonb, jsonb) to anon, authenticated;
