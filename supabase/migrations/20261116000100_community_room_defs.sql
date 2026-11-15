-- Ali's room layout: a fixed list of chat rooms. Several areas share one room (New Cairo = the Settlements +
-- Rehab; Nasr City + Heliopolis + Almaza; Haram + Faisal; Mohandessin + Dokki + Agouza; all of Alexandria),
-- and the areas he dropped are inactive (no room, not offered when posting).

create table if not exists public.community_room_defs (
  slug text primary key,
  label_ar text not null,
  grp text not null,
  sort int not null default 100
);
alter table public.community_room_defs enable row level security;
drop policy if exists community_room_defs_read on public.community_room_defs;
create policy community_room_defs_read on public.community_room_defs for select using (true);
grant select on public.community_room_defs to authenticated;

insert into public.community_room_defs(slug, label_ar, grp, sort) values
('new-cairo','القاهرة الجديدة (التجمع والرحاب)','cairo',10),('new-capital','العاصمة الإدارية','cairo',11),('mostakbal','مدينة المستقبل','cairo',12),
('madinaty','مدينتي','cairo',13),('shorouk','الشروق','cairo',14),('obour','العبور','cairo',15),('badr','بدر','cairo',16),
('nasr-heliopolis','مدينة نصر ومصر الجديدة والماظة','cairo',17),('sheraton','شيراتون','cairo',18),('nozha','النزهة','cairo',19),
('katameya','القطامية','cairo',20),('mokattam','المقطم','cairo',21),('maadi','المعادي','cairo',22),('degla-maadi','دجلة المعادي','cairo',23),
('zahraa-maadi','زهراء المعادي','cairo',24),('downtown','وسط البلد','cairo',25),('garden-city','جاردن سيتي','cairo',26),('zamalek','الزمالك','cairo',27),
('manial','المنيل','cairo',28),('masr-qadima','مصر القديمة','cairo',29),('hadayek-qobba','حدائق القبة','cairo',30),('helwan','حلوان','cairo',31),
('15-may','15 مايو','cairo',32),
('6-october','6 أكتوبر','giza',40),('sheikh-zayed','الشيخ زايد','giza',41),('hadayek-october','حدائق أكتوبر','giza',42),
('new-october','أكتوبر الجديدة','giza',43),('hadayek-ahram','حدائق الأهرام','giza',44),('haram-faisal','الهرم وفيصل','giza',45),
('mohandessin','المهندسين والدقي والعجوزة','giza',46),('giza','الجيزة','giza',47),
('alex','الإسكندرية','alex',60),
('north-coast','الساحل الشمالي','coast',70),('new-alamein','العلمين الجديدة','coast',71),('ras-el-hekma','رأس الحكمة','coast',72),
('sokhna','العين السخنة','coast',73),('galala','الجلالة','coast',74),('ras-sudr','رأس سدر','coast',75),('hurghada','الغردقة','coast',76),
('red-sea','البحر الأحمر','coast',77)
on conflict (slug) do update set label_ar = excluded.label_ar, grp = excluded.grp, sort = excluded.sort;

alter table public.community_areas add column if not exists room text references public.community_room_defs(slug);
alter table public.community_areas add column if not exists active boolean not null default true;

update public.community_areas a set room = a.slug, active = true where exists (select 1 from public.community_room_defs d where d.slug = a.slug);
update public.community_areas set room = 'new-cairo' where slug in ('tagamoa-1', 'tagamoa-3', 'tagamoa-5', 'rehab');
update public.community_areas set room = 'nasr-heliopolis' where slug in ('nasr-city', 'heliopolis', 'almaza');
update public.community_areas set room = 'haram-faisal' where slug in ('haram', 'faisal');
update public.community_areas set room = 'mohandessin' where slug in ('mohandessin', 'dokki', 'agouza');
update public.community_areas set room = 'sheikh-zayed' where slug in ('new-zayed', 'beverly-hills', 'rabwa', 'sphinx');
update public.community_areas set room = '6-october' where slug in ('hosary', 'motamayez', 'dreamland');
update public.community_areas set room = 'alex' where grp = 'alex' and slug not in ('cairo', 'giza');
update public.community_areas set room = null, active = false
 where slug in ('basatin', 'khalifa', 'zeitoun', 'sayeda-zeinab', 'zaher', 'abbassia', 'marg', 'matareya', 'maasara', 'boulaq',
                'dar-salam', 'rod-el-farag', 'shubra', 'ain-shams', 'cairo',
                'talbia', 'omraneya', 'imbaba', 'boulaq-dakrour', 'warraq', 'moneeb', 'oseem', 'kerdasa', 'abu-rawash',
                'badrashen', 'hawamdeya', 'ayat', 'saft-laban', 'mansheyet-qanater');
-- neighbours that now share a room also match each other's requests
update public.community_areas set cluster = 'nasr-heliopolis' where slug in ('nasr-city', 'heliopolis', 'almaza');
update public.community_areas set cluster = 'haram-faisal' where slug in ('haram', 'faisal');
update public.community_areas set cluster = 'mohandessin' where slug in ('mohandessin', 'dokki', 'agouza');
update public.community_areas set cluster = 'zayed' where slug in ('beverly-hills', 'rabwa', 'sphinx');
update public.community_areas set cluster = 'october' where slug in ('hosary', 'motamayez', 'dreamland');
update public.community_areas set cluster = 'alex' where grp = 'alex' and slug not in ('cairo', 'giza');

-- chat messages carry their room (rooms may span several areas)
alter table public.community_posts add column if not exists room text references public.community_room_defs(slug);
update public.community_posts p set room = (select a.room from public.community_areas a where a.slug = p.area_slug)
 where p.kind = 'message' and p.area_slug is not null and p.room is null;

-- any slug (room, area, alias, label) -> the room it belongs to
create or replace function public._cm_room(p text)
returns text language sql stable set search_path = public as $$
  select coalesce((select slug from public.community_room_defs where slug = trim(p)),
                  (select room from public.community_areas where slug = public._cm_slug(p)));
$$;

create or replace function public._cm_in_room(p public.community_posts, r text)
returns boolean language sql stable set search_path = public as $$
  select case
    when coalesce(r, '') = '' then p.kind <> 'message' or p.room is null
    when p.kind = 'message' then p.room = r
    else (select a.room from public.community_areas a where a.slug = p.area_slug) = r end;
$$;

create or replace function public.community_post_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text := p->>'kind'; a text; l public.listings; new_id uuid; body text; m jsonb;
        rt public.community_posts; nm text;
begin
  if uid is null or not public._cm_is_broker(uid) then return jsonb_build_object('ok', false, 'error', 'brokers_only'); end if;
  if k not in ('request', 'unit', 'message') then return jsonb_build_object('ok', false, 'error', 'bad_kind'); end if;
  if k = 'message' then
    if (select count(*) from public.community_posts where author_id = uid and kind = 'message' and created_at > now() - interval '1 day') >= 300 then
      return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  elsif (select count(*) from public.community_posts where author_id = uid and kind <> 'message' and created_at > now() - interval '1 day') >= 15 then
    return jsonb_build_object('ok', false, 'error', 'too_many');
  end if;
  body := left(trim(coalesce(p->>'body', '')), 1500);
  if nullif(p->>'reply_to', '') is not null then
    select * into rt from public.community_posts where id = (p->>'reply_to')::uuid and status not in ('hidden', 'deleted');
  end if;
  if k = 'message' then
    if length(body) < 1 then return jsonb_build_object('ok', false, 'error', 'body_required'); end if;
    insert into public.community_posts(author_id, kind, room, body, reply_to, expires_at)
    values (uid, 'message', public._cm_room(nullif(p->>'area', '')), body, rt.id, now() + interval '3650 days')
    returning community_posts.id into new_id;
  else
    a := (select slug from public.community_areas where slug = public._cm_slug(p->>'area') and active);
    if nullif(p->>'listing_id', '') is not null then
      select * into l from public.listings where id = (p->>'listing_id')::uuid and owner_id = uid and status = 'active';
      if not found then return jsonb_build_object('ok', false, 'error', 'listing_not_yours'); end if;
      a := coalesce(a, public._cm_listing_region(l));
    end if;
    if a is null then return jsonb_build_object('ok', false, 'error', 'area_required'); end if;
    if length(body) < 3 and l.id is null then return jsonb_build_object('ok', false, 'error', 'body_required'); end if;
    insert into public.community_posts(author_id, kind, area_slug, purpose, prop_type, budget_min, budget_max, price,
                                       bedrooms, delivery, listing_id, body, reply_to)
    values (uid, k, a,
            coalesce(nullif(p->>'purpose', ''), l.purpose, 'sale'),
            coalesce(nullif(p->>'prop_type', ''), l.type),
            case when k = 'request' then nullif(p->>'budget_min', '')::numeric end,
            case when k = 'request' then nullif(p->>'budget_max', '')::numeric end,
            case when k = 'unit' then coalesce(nullif(p->>'price', '')::numeric, l.price) end,
            coalesce(nullif(p->>'bedrooms', '')::int, l.bedrooms),
            nullif(p->>'delivery', ''),
            l.id, coalesce(nullif(body, ''), l.title), rt.id)
    returning community_posts.id into new_id;
    m := public._cm_match(new_id);
  end if;
  if rt.id is not null and rt.author_id <> uid then
    select coalesce(company, full_name, 'بروكر') into nm from public.profiles where id = uid;
    perform public._appt_notify(rt.author_id, 'community_reply', '↩️ ' || nm || ' رد عليك في جروب البروكرز',
      left(coalesce(nullif(body, ''), l.title, ''), 140), jsonb_build_object('post_id', new_id, 'url', '/community?post=' || new_id));
  end if;
  return jsonb_build_object('ok', true, 'id', new_id, 'match', coalesce(m, '{}'::jsonb));
end $$;

-- the chat list: the general room, the rooms of the broker's work areas, rooms opened before, rooms with posts
create or replace function public.community_rooms()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); mine text[];
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct a.room) filter (where a.room is not null), '{}') into mine
    from public.community_areas a where a.slug = any(public.community_my_areas());
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.pinned desc, x.last_at desc nulls last, x.sort) from (
    select r.room, coalesce(d.label_ar, 'كل البروكرز') as label, d.grp, coalesce(d.sort, 0) as sort,
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
            union select distinct room from public.community_posts where kind = 'message' and room is not null and status <> 'deleted'
            union select distinct a.room from public.community_posts p join public.community_areas a on a.slug = p.area_slug
                   where p.kind <> 'message' and p.status = 'open' and p.expires_at > now() and a.room is not null) r
      left join public.community_room_defs d on d.slug = r.room
      left join public.community_room_reads rd on rd.user_id = uid and rd.room = r.room
      left join lateral (select q.* from public.community_posts q
                          where q.status <> 'hidden' and public._cm_in_room(q, r.room)
                          order by q.created_at desc limit 1) lp on true
      left join public.profiles la on la.id = lp.author_id
     where r.room = '' or d.slug is not null) x), '[]'::jsonb);
end $$;


-- community_chat also returns each post's room (so a notification link opens the right group)
create or replace function public.community_chat(p_kinds text[] default null, p_areas text[] default null,
                                                 p_before timestamptz default null, p_after timestamptz default null,
                                                 p_post uuid default null, p_limit int default 50, p_room text default '')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select p.id, p.kind, p.area_slug, a.label_ar as area_label, coalesce(p.room, a.room) as room, p.purpose, p.prop_type, p.budget_min, p.budget_max, p.price,
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
