begin;
alter table public.crm_offers add column if not exists broker_info jsonb not null default '{}';
create table public.crm_offer_shares (
  token uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.crm_offers(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default now()+interval '7 days'
);
alter table public.crm_offer_shares enable row level security;
revoke all on public.crm_offer_shares from anon,authenticated;
create index crm_offer_shares_owner_idx on public.crm_offer_shares(owner_id,offer_id);

create function public.crm_share_sales_offer(p_offer uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result public.crm_offer_shares;
begin
  if auth.uid() is null or not exists(select 1 from public.crm_offers o join public.clients c on c.id=o.lead_id
    where o.id=p_offer and o.owner_id=auth.uid() and c.owner_id=auth.uid()) then
    raise exception 'Offer not found' using errcode='42501'; end if;
  -- A broker explicitly publishes their business contact with this offer.
  update public.crm_offers set broker_info=coalesce((select jsonb_build_object(
    'name',coalesce(to_jsonb(p)->>'name',to_jsonb(p)->>'full_name'),
    'company',to_jsonb(p)->>'company','phone',to_jsonb(p)->>'phone') from public.profiles p where p.id=auth.uid()),'{}')
    where id=p_offer;
  insert into public.crm_offer_shares(offer_id,owner_id) values(p_offer,auth.uid()) returning * into result;
  return to_jsonb(result);
end $$;

create function public.crm_read_sales_offer(p_token uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',o.id,'language',o.language,'client_name',o.client_name,
    'items',o.items,'broker_info',o.broker_info,'created_at',o.created_at)
  from public.crm_offer_shares s join public.crm_offers o on o.id=s.offer_id
    join public.clients c on c.id=o.lead_id and c.owner_id=o.owner_id
  where s.token=p_token and s.expires_at>now();
$$;

create function public.crm_revoke_sales_offer(p_offer uuid)
returns void language sql security definer set search_path=public as $$
  delete from public.crm_offer_shares where offer_id=p_offer and owner_id=auth.uid();
$$;
revoke all on function public.crm_share_sales_offer(uuid) from public,anon;
revoke all on function public.crm_read_sales_offer(uuid) from public;
revoke all on function public.crm_revoke_sales_offer(uuid) from public,anon;
grant execute on function public.crm_share_sales_offer(uuid),public.crm_revoke_sales_offer(uuid) to authenticated;
grant execute on function public.crm_read_sales_offer(uuid) to anon,authenticated;
commit;
