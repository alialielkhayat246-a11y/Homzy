-- Additive upgrade. Requires the deployed CRM phase 2/3 schema (whose checked-in
-- historical files currently contain comments, not replayable DDL).
begin;

-- Fail before changing anything if the deployed CRM baseline is incomplete.
do $$
declare missing text;
begin
  select string_agg(r.tbl || '.' || r.col, ', ') into missing from (values
    ('clients','owner_id'),('clients','budget_min'),('clients','budget_max'),('clients','next_followup'),('clients','source'),
    ('crm_deals','owner_id'),('crm_deals','value'),('crm_deals','expected_close'),('crm_deals','actual_close'),
    ('crm_tasks','meta'),('crm_tasks','completed_at'),('crm_tasks','due_at'),
    ('crm_lead_activities','actor_id'),('crm_lead_activities','meta'),
    ('crm_viewings','scheduled_at'),('listings','id'),('listing_media','sort'),
    ('profiles','full_name'),('profiles','company'),('profiles','phone'),
    ('plan_limits','features'),('projects','id'),('developers','id'),('favorites','listing_id')
  ) r(tbl,col) where not exists(select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name=r.tbl and c.column_name=r.col);
  if missing is not null then raise exception 'CRM baseline missing columns: %',missing; end if;
  if to_regprocedure('public.crm_log_activity(uuid,text,text,jsonb)') is null
     or to_regprocedure('public.current_plan(uuid)') is null then
    raise exception 'Restore the deployed CRM activity and subscription functions before this migration'; end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('clients','crm_deals','crm_tasks','crm_lead_activities') and not c.relrowsecurity) then
    raise exception 'CRM baseline RLS must be enabled before upgrading'; end if;
end $$;

alter table public.clients add column if not exists custom jsonb not null default '{}';
alter table public.crm_deals add column if not exists probability numeric not null default 0;
alter table public.crm_deals add column if not exists notes text;
alter table public.crm_deals add column if not exists listing_id uuid references public.listings(id) on delete set null;
alter table public.crm_deals add constraint crm_sales_probability_range check (probability between 0 and 100);
alter table public.crm_deals add constraint crm_sales_lost_reason_required
  check (status<>'lost' or length(trim(coalesce(lost_reason,'')))>0) not valid;
create index if not exists crm_sales_client_followup_idx on public.clients(owner_id, next_followup);
create index if not exists crm_sales_activity_time_idx on public.crm_lead_activities(lead_id, created_at desc);

create table if not exists public.crm_offers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  lead_id uuid not null references public.clients(id) on delete cascade,
  language text not null check (language in ('ar','en')),
  client_name text not null,
  broker_info jsonb not null default '{}',
  items jsonb not null check (jsonb_typeof(items) = 'array'),
  created_at timestamptz not null default now()
);
create index if not exists crm_offers_owner_lead_idx on public.crm_offers(owner_id,lead_id,created_at desc);
alter table public.crm_offers enable row level security;
create policy crm_offers_read on public.crm_offers for select to authenticated
  using (owner_id=auth.uid() and exists(select 1 from public.clients c where c.id=lead_id and c.owner_id=auth.uid()));
-- Immutable, source-verified snapshots can only be created through the RPC.
revoke all on public.crm_offers from anon, authenticated;
grant select on public.crm_offers to authenticated;

create or replace function public.crm_save_sales_profile(
  p_lead uuid, p_requirements jsonb, p_email text, p_whatsapp text, p_expected timestamptz
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare c public.clients;
begin
  select * into c from public.clients where id=p_lead and owner_id=auth.uid() for update;
  if not found then raise exception 'Client not found' using errcode='42501'; end if;
  if c.updated_at is distinct from p_expected then return jsonb_build_object('conflict',true); end if;
  if jsonb_typeof(p_requirements) <> 'object' or octet_length(p_requirements::text)>20000
     or length(p_email)>254 or length(p_whatsapp)>30 then raise exception 'Invalid profile'; end if;
  update public.clients set custom=coalesce(custom,'{}') || jsonb_build_object(
    'sales_requirements',p_requirements,'sales_contact',jsonb_build_object('email',p_email,'whatsapp',p_whatsapp)),
    purpose=p_requirements->>'purpose', type=p_requirements->>'type',
    area=(select string_agg(value, ', ') from jsonb_array_elements_text(coalesce(p_requirements->'locations','[]'))),
    bedrooms=(p_requirements->>'bedrooms')::int,
    budget=(p_requirements->>'budget_max')::numeric,
    budget_min=(p_requirements->>'budget_min')::numeric,
    budget_max=(p_requirements->>'budget_max')::numeric,
    updated_at=now()
  where id=p_lead;
  perform public.crm_log_activity(p_lead,'note','Client requirements reviewed and updated',jsonb_build_object('source','sales_profile'));
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.crm_create_sales_offer(p_lead uuid,p_listings uuid[],p_language text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.clients; result public.crm_offers; snapshots jsonb; broker_profile jsonb; n int;
begin
  select * into c from public.clients where id=p_lead and owner_id=auth.uid();
  if not found or auth.uid() is null then raise exception 'Client not found' using errcode='42501'; end if;
  if not exists(select 1 from public.plan_limits where plan=public.current_plan(auth.uid())
    and features->>'branded_pdf'='true') then
    raise exception 'Branded offers require an eligible subscription' using errcode='42501'; end if;
  n=cardinality(p_listings);
  if n is null or n<1 or n>8 or p_language not in ('ar','en') then raise exception 'Invalid offer'; end if;
  -- Only public active inventory is eligible. No private listing or contact columns
  -- enter the snapshot. Optional attributes are read as JSON for schema tolerance.
  select jsonb_agg(jsonb_build_object(
    'id',l.id,'title',l.title,'purpose',l.purpose,'type',l.type,'area',l.area,
    'price',l.price,'currency',l.currency,'bedrooms',l.bedrooms,'bathrooms',l.bathrooms,
    'size_sqm',l.size_sqm,'developer',to_jsonb(l)->'developer',
    'project',to_jsonb(l)->'project','down_payment_amount',to_jsonb(l)->'down_payment_amount',
    'installment_years',to_jsonb(l)->'installment_years','delivery',to_jsonb(l)->'delivery',
    'finishing',to_jsonb(l)->'finishing','amenities',to_jsonb(l)->'amenities',
    'images',(select coalesce(jsonb_agg(m.url order by m.sort),'[]') from public.listing_media m where m.listing_id=l.id)
  ) order by array_position(p_listings,l.id)) into snapshots
  from public.listings l where l.id=any(p_listings) and l.status='active';
  if coalesce(jsonb_array_length(snapshots),0)<>n then raise exception 'One or more properties are unavailable'; end if;
  select jsonb_build_object('name',p.full_name,'company',p.company,'phone',p.phone) into broker_profile
    from public.profiles p where p.id=auth.uid();
  insert into public.crm_offers(owner_id,lead_id,language,client_name,items,broker_info)
    values(auth.uid(),p_lead,p_language,c.name,snapshots,coalesce(broker_profile,'{}')) returning * into result;
  perform public.crm_log_activity(p_lead,'note','Property offer generated',jsonb_build_object('offer_id',result.id,'source','sales_offer'));
  return to_jsonb(result);
end $$;

create or replace function public.crm_sales_move_stage(p_lead uuid,p_stage text,p_reason text default null)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare c public.clients;
begin
  if p_stage not in ('new','contact','qualified','matching','viewing','offer_sent','negotiate','reservation','closed','lost') then
    raise exception 'Invalid stage'; end if;
  if p_stage='lost' and coalesce(length(trim(p_reason)),0)=0 then raise exception 'Lost reason required'; end if;
  select * into c from public.clients where id=p_lead and owner_id=auth.uid() for update;
  if not found then raise exception 'Client not found' using errcode='42501'; end if;
  if c.stage=p_stage then return jsonb_build_object('ok',true); end if;
  update public.clients set stage=p_stage,updated_at=now(),
    custom=coalesce(custom,'{}') || jsonb_build_object('lost_reason',case when p_stage='lost' then left(p_reason,2000) else null end)
    where id=p_lead;
  perform public.crm_log_activity(p_lead,'stage_change',c.stage || ' → ' || p_stage,
    jsonb_build_object('from',c.stage,'to',p_stage,'lost_reason',case when p_stage='lost' then p_reason else null end));
  return jsonb_build_object('ok',true);
end $$;

revoke all on function public.crm_save_sales_profile(uuid,jsonb,text,text,timestamptz) from public,anon;
revoke all on function public.crm_create_sales_offer(uuid,uuid[],text) from public,anon;
revoke all on function public.crm_sales_move_stage(uuid,text,text) from public,anon;
grant execute on function public.crm_save_sales_profile(uuid,jsonb,text,text,timestamptz) to authenticated;
grant execute on function public.crm_create_sales_offer(uuid,uuid[],text) to authenticated;
grant execute on function public.crm_sales_move_stage(uuid,text,text) to authenticated;
commit;
