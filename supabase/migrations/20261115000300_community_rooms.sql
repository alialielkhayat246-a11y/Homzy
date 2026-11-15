-- Community rooms: a general group plus one group per area (like WhatsApp chats). A chat message belongs to
-- the room it was written in (area_slug, null = general); request/unit cards show in the general room and in
-- every room whose area covers theirs. Unread counts come from each broker's last-read time per room.

create table if not exists public.community_room_reads (
  user_id uuid not null references public.profiles(id) on delete cascade,
  room text not null,                      -- area slug, or '' for the general room
  read_at timestamptz not null default now(),
  primary key (user_id, room)
);
alter table public.community_room_reads enable row level security;

-- does post p belong in room r ('' = general)
create or replace function public._cm_in_room(p public.community_posts, r text)
returns boolean language sql stable set search_path = public as $$
  select case
    when coalesce(r, '') = '' then p.kind <> 'message' or p.area_slug is null
    when p.kind = 'message' then p.area_slug = r
    else public._cm_area_ok(r, p.area_slug) or public._cm_area_ok(p.area_slug, r) end;
$$;

drop function if exists public.community_chat(text[], text[], timestamptz, timestamptz, uuid, int);
create or replace function public.community_chat(p_kinds text[] default null, p_areas text[] default null,
                                                 p_before timestamptz default null, p_after timestamptz default null,
                                                 p_post uuid default null, p_limit int default 50, p_room text default '')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select p.id, p.kind, p.area_slug, a.label_ar as area_label, p.purpose, p.prop_type, p.budget_min, p.budget_max, p.price,
           p.bedrooms, p.delivery, p.listing_id, p.status, p.closed_reason, p.created_at, p.updated_at,
           case when p.status = 'deleted' then null else p.body end as body,
           p.author_id = uid as mine, p.kind <> 'message' and p.expires_at <= now() as expired,
           jsonb_build_object('id', pr.id, 'name', pr.full_name, 'company', pr.company, 'logo', pr.company_logo_url,
             'verified', pr.phone_verified_at is not null,
             'collabs_won', (select count(*) from public.community_collabs c
                              where c.status = 'won' and (c.requester_id = pr.id or c.owner_id = pr.id))) as author,
           case when p.reply_to is not null then (select jsonb_build_object('id', q.id, 'kind', q.kind,
                 'body', case when q.status in ('deleted', 'hidden') then null else left(q.body, 140) end,
                 'name', coalesce(qa.company, qa.full_name), 'mine', q.author_id = uid)
               from public.community_posts q join public.profiles qa on qa.id = q.author_id where q.id = p.reply_to) end as reply,
           case when p.listing_id is not null and p.status <> 'deleted' then (select jsonb_build_object('title', l.title, 'price', l.price,
                 'size', l.size_sqm, 'cover', (select m.url from public.listing_media m where m.listing_id = l.id order by m.sort limit 1))
               from public.listings l where l.id = p.listing_id and l.status = 'active') end as listing,
           (select c.status from public.community_collabs c where c.post_id = p.id and c.requester_id = uid order by c.created_at desc limit 1) as my_collab,
           case when p.author_id = uid and p.kind <> 'message' then (select count(*) from public.community_collabs c where c.post_id = p.id and c.status = 'pending') end as collab_pending,
           case when p.kind = 'request' then (select count(*) from public.community_matches m where m.request_id = p.id and m.broker_id = uid) end as my_matches,
           case when p.author_id = uid and p.kind = 'request' then (select count(*) from public.community_matches m where m.request_id = p.id) end as total_matches
      from public.community_posts p
      left join public.community_areas a on a.slug = p.area_slug
      join public.profiles pr on pr.id = p.author_id
     where (p_post is null or p.id = p_post)
       and (p_post is not null or public._cm_in_room(p, p_room))
       and (p.status <> 'hidden' or p.author_id = uid)
       and (p_kinds is null or cardinality(p_kinds) = 0 or p.kind = any(p_kinds))
       and (p_areas is null or cardinality(p_areas) = 0 or (p.kind <> 'message' and exists (select 1 from unnest(p_areas) z
              where public._cm_area_ok(z, p.area_slug) or public._cm_area_ok(p.area_slug, z))))
       and (p_before is null or p.created_at < p_before)
       and (p_after is null or p.created_at > p_after or p.updated_at > p_after)
     order by p.created_at desc
     limit least(coalesce(p_limit, 50), 100)) x), '[]'::jsonb);
end $$;
grant execute on function public.community_chat(text[], text[], timestamptz, timestamptz, uuid, int, text) to authenticated;
revoke execute on function public.community_chat(text[], text[], timestamptz, timestamptz, uuid, int, text) from anon;

-- the chat list: the general room, the broker's work areas, rooms they opened before, and any room with posts
create or replace function public.community_rooms()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); mine text[];
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  mine := public.community_my_areas();
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.pinned desc, x.last_at desc nulls last, x.label) from (
    select r.room, coalesce(a.label_ar, 'كل البروكرز') as label, a.grp,
           (r.room = '' or r.room = any(mine)) as pinned,
           lp.created_at as last_at,
           case when lp.id is null then null
                when lp.status = 'deleted' then '🚫 رسالة اتمسحت'
                else case lp.kind when 'request' then '🔔 ' when 'unit' then '🏠 ' else '' end || left(coalesce(lp.body, ''), 80) end as last_text,
           case when lp.id is null then null when lp.author_id = uid then 'إنت' else coalesce(la.company, la.full_name) end as last_who,
           (select count(*) from public.community_posts q
             where q.author_id <> uid and q.status not in ('hidden', 'deleted') and public._cm_in_room(q, r.room)
               and q.created_at > coalesce(rd.read_at, now() - interval '7 days')) as unread
      from (select '' as room
            union select unnest(mine)
            union select room from public.community_room_reads where user_id = uid
            union select distinct area_slug from public.community_posts where kind = 'message' and area_slug is not null and status <> 'deleted'
            union select distinct area_slug from public.community_posts where kind <> 'message' and status = 'open' and expires_at > now()) r
      left join public.community_areas a on a.slug = r.room
      left join public.community_room_reads rd on rd.user_id = uid and rd.room = r.room
      left join lateral (select q.* from public.community_posts q
                          where q.status <> 'hidden' and public._cm_in_room(q, r.room)
                          order by q.created_at desc limit 1) lp on true
      left join public.profiles la on la.id = lp.author_id
     where r.room = '' or a.slug is not null) x), '[]'::jsonb);
end $$;

create or replace function public.community_room_read(p_room text)
returns void language sql security definer set search_path = public as $$
  insert into public.community_room_reads(user_id, room, read_at) values (auth.uid(), coalesce(p_room, ''), now())
  on conflict (user_id, room) do update set read_at = now();
$$;

grant execute on function public.community_rooms(), public.community_room_read(text) to authenticated;
revoke execute on function public.community_rooms(), public.community_room_read(text) from anon;
