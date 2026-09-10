begin;
-- Keep customer-authorized marketplace telemetry separate from broker-authored
-- CRM interactions. Revoking consent immediately hides historical telemetry.
create table public.crm_behavior_links (
  id uuid primary key default gen_random_uuid(),
  invite uuid not null unique default gen_random_uuid(),
  lead_id uuid not null references public.clients(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete cascade,
  accepted_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz not null default now()+interval '7 days'
);
alter table public.crm_behavior_links enable row level security;
create policy crm_behavior_link_read on public.crm_behavior_links for select to authenticated
  using(actor_id=auth.uid() or (owner_id=auth.uid() and exists(select 1 from public.clients c where c.id=lead_id and c.owner_id=auth.uid())));
revoke all on public.crm_behavior_links from anon,authenticated;
grant select on public.crm_behavior_links to authenticated;

create table public.crm_behavior_events (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.crm_behavior_links(id) on delete cascade,
  lead_id uuid not null references public.clients(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('viewed','saved','favorite_removed','search','inquiry','shared')),
  listing_id uuid references public.listings(id) on delete set null,
  -- Stable deduplication identity survives deletion of the referenced listing.
  listing_key uuid not null,
  body text,
  meta jsonb not null default '{}',
  minute_bucket bigint not null,
  created_at timestamptz not null default now()
);
create index crm_behavior_lead_time_idx on public.crm_behavior_events(lead_id,created_at desc);
create index crm_behavior_actor_time_idx on public.crm_behavior_events(actor_id,created_at desc);
create unique index crm_behavior_dedup_idx on public.crm_behavior_events(actor_id,lead_id,kind,
  listing_key,minute_bucket);
alter table public.crm_behavior_events enable row level security;
create policy crm_behavior_event_read on public.crm_behavior_events for select to authenticated using (
  actor_id=auth.uid() or (owner_id=auth.uid() and exists(select 1 from public.crm_behavior_links b
    join public.clients c on c.id=b.lead_id where b.id=link_id and b.revoked_at is null
      and b.accepted_at is not null and c.owner_id=auth.uid()))
);
revoke all on public.crm_behavior_events from anon,authenticated;
grant select on public.crm_behavior_events to authenticated;

create function public.crm_invite_behavior(p_lead uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid;
begin
  if auth.uid() is null or not exists(select 1 from public.clients where id=p_lead and owner_id=auth.uid()) then
    raise exception 'Client not found' using errcode='42501'; end if;
  insert into public.crm_behavior_links(lead_id,owner_id) values(p_lead,auth.uid()) returning invite into result;
  return result;
end $$;

create function public.crm_accept_behavior(p_invite uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  update public.crm_behavior_links b set actor_id=auth.uid(),accepted_at=now()
    where invite=p_invite and actor_id is null and revoked_at is null and expires_at>now()
      and owner_id<>auth.uid() and exists(select 1 from public.clients c where c.id=b.lead_id and c.owner_id=b.owner_id);
  if not found then raise exception 'Invitation expired or unavailable'; end if;
end $$;

create function public.crm_revoke_behavior(p_link uuid)
returns void language sql security definer set search_path=public as $$
  update public.crm_behavior_links set revoked_at=now() where id=p_link and (actor_id=auth.uid() or owner_id=auth.uid());
$$;

create function public.crm_track_behavior(p_kind text,p_listing uuid default null,p_meta jsonb default '{}')
returns void language plpgsql security definer set search_path=public as $$
declare b public.crm_behavior_links; title text; clean jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if p_kind not in ('viewed','saved','favorite_removed','search','inquiry','shared')
     or jsonb_typeof(p_meta)<>'object' or octet_length(p_meta::text)>4000 then raise exception 'Invalid event'; end if;
  if (select count(*) from public.crm_behavior_events where actor_id=auth.uid() and created_at>now()-interval '1 day')>=500 then return; end if;
  if p_listing is not null then
    select l.title into title from public.listings l where l.id=p_listing and l.status='active';
    if not found then return; end if;
  end if;
  select coalesce(jsonb_object_agg(key,value),'{}') into clean from jsonb_each(p_meta)
    where key in ('query','area','type','budget_min','budget_max');
  for b in select bl.* from public.crm_behavior_links bl join public.clients c on c.id=bl.lead_id
      where bl.actor_id=auth.uid() and bl.accepted_at is not null and bl.revoked_at is null and c.owner_id=bl.owner_id
  loop
    insert into public.crm_behavior_events(link_id,lead_id,owner_id,actor_id,kind,listing_id,listing_key,body,meta,minute_bucket)
      values(b.id,b.lead_id,b.owner_id,auth.uid(),p_kind,p_listing,coalesce(p_listing,'00000000-0000-0000-0000-000000000000'::uuid),title,clean,floor(extract(epoch from now())/60))
      on conflict do nothing;
  end loop;
end $$;
revoke all on function public.crm_invite_behavior(uuid),public.crm_accept_behavior(uuid),public.crm_revoke_behavior(uuid),public.crm_track_behavior(text,uuid,jsonb) from public,anon;
grant execute on function public.crm_invite_behavior(uuid),public.crm_accept_behavior(uuid),public.crm_revoke_behavior(uuid),public.crm_track_behavior(text,uuid,jsonb) to authenticated;

create function public.crm_track_favorite_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if TG_OP='DELETE' then
    if old.user_id=auth.uid() and old.listing_id is not null then perform public.crm_track_behavior('favorite_removed',old.listing_id,'{}'); end if;
    return old;
  end if;
  if new.user_id=auth.uid() and new.listing_id is not null then perform public.crm_track_behavior('saved',new.listing_id,'{}'); end if;
  return new;
end $$;
revoke all on function public.crm_track_favorite_change() from public,anon,authenticated;
create trigger crm_behavior_favorites after insert or delete on public.favorites for each row execute function public.crm_track_favorite_change();
commit;
