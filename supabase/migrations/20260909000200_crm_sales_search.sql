begin;
-- Built-in full-text indexing supports Arabic and English tokens without extensions.
create index if not exists crm_clients_search_idx on public.clients using gin
  (to_tsvector('simple',coalesce(name,'') || ' ' || coalesce(phone,'') || ' ' || coalesce(area,'')));
create index if not exists crm_deals_search_idx on public.crm_deals using gin
  (to_tsvector('simple',coalesce(customer_name,'') || ' ' || coalesce(property_title,'')));
create index if not exists crm_inventory_search_idx on public.listings using gin
  (to_tsvector('simple',coalesce(title,'') || ' ' || coalesce(area,'')));

create or replace function public.crm_sales_search(p_query text)
returns jsonb language sql stable security invoker set search_path=public as $$
  with query as (select plainto_tsquery('simple',left(p_query,100)) as q), results as (
    (select 'client' as kind,id::text,name as label,phone as detail from public.clients,query
      where owner_id=auth.uid() and to_tsvector('simple',coalesce(name,'') || ' ' || coalesce(phone,'') || ' ' || coalesce(area,'')) @@ q limit 20)
    union all
    (select 'deal',id::text,coalesce(property_title,customer_name),status from public.crm_deals,query
      where owner_id=auth.uid() and to_tsvector('simple',coalesce(customer_name,'') || ' ' || coalesce(property_title,'')) @@ q limit 20)
    union all
    (select 'property',id::text,title,area from public.listings,query
      where status='active' and to_tsvector('simple',coalesce(title,'') || ' ' || coalesce(area,'')) @@ q limit 20)
    union all
    (select 'project',id::text,coalesce(to_jsonb(p)->>'name',to_jsonb(p)->>'name_ar'),to_jsonb(p)->>'area'
      from public.projects p,query where to_tsvector('simple',coalesce(to_jsonb(p)->>'name','') || ' ' || coalesce(to_jsonb(p)->>'name_ar','')) @@ q limit 20)
    union all
    (select 'developer',id::text,coalesce(to_jsonb(d)->>'name',to_jsonb(d)->>'name_ar'),null
      from public.developers d,query where to_tsvector('simple',coalesce(to_jsonb(d)->>'name','') || ' ' || coalesce(to_jsonb(d)->>'name_ar','')) @@ q limit 20)
  ) select coalesce(jsonb_agg(to_jsonb(results)),'[]') from results where auth.uid() is not null;
$$;
revoke all on function public.crm_sales_search(text) from public,anon;
grant execute on function public.crm_sales_search(text) to authenticated;
commit;
