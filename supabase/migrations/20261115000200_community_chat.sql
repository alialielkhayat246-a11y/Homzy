-- Community as a WhatsApp-style group: plain chat messages next to request/unit cards, replies that quote
-- another message, and "deleted" messages that leave a placeholder.

alter table public.community_posts drop constraint if exists community_posts_kind_check;
alter table public.community_posts add constraint community_posts_kind_check check (kind in ('request', 'unit', 'message'));
alter table public.community_posts drop constraint if exists community_posts_status_check;
alter table public.community_posts add constraint community_posts_status_check check (status in ('open', 'closed', 'hidden', 'deleted'));
alter table public.community_posts alter column area_slug drop not null;
alter table public.community_posts drop constraint if exists community_posts_area_needed;
alter table public.community_posts add constraint community_posts_area_needed check (kind = 'message' or area_slug is not null);
alter table public.community_posts add column if not exists reply_to uuid references public.community_posts(id) on delete set null;

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
    insert into public.community_posts(author_id, kind, area_slug, body, reply_to, expires_at)
    values (uid, 'message', public._cm_slug(p->>'area'), body, rt.id, now() + interval '3650 days')
    returning community_posts.id into new_id;
  else
    a := public._cm_slug(p->>'area');
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
  -- a reply tells the person being replied to
  if rt.id is not null and rt.author_id <> uid then
    select coalesce(company, full_name, 'بروكر') into nm from public.profiles where id = uid;
    perform public._appt_notify(rt.author_id, 'community_reply', '↩️ ' || nm || ' رد عليك في جروب البروكرز',
      left(coalesce(nullif(body, ''), l.title, ''), 140), jsonb_build_object('post_id', new_id, 'url', '/community?post=' || new_id));
  end if;
  return jsonb_build_object('ok', true, 'id', new_id, 'match', coalesce(m, '{}'::jsonb));
end $$;

create or replace function public.community_post_set(p_id uuid, p_action text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p public.community_posts; adm boolean;
begin
  select * into p from public.community_posts where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  adm := exists (select 1 from public.profiles where id = uid and is_admin);
  if p.author_id <> uid and not adm then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_action = 'delete' then
    update public.community_posts set status = 'deleted', updated_at = now() where id = p_id;
  elsif p.kind = 'message' then
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  elsif p_action = 'close' then
    update public.community_posts set status = 'closed', closed_reason = nullif(trim(coalesce(p_reason, '')), ''), updated_at = now() where id = p_id;
  elsif p_action = 'reopen' or p_action = 'renew' then
    if p.status in ('hidden', 'deleted') and not adm then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    update public.community_posts set status = 'open', closed_reason = null, expires_at = now() + interval '30 days', updated_at = now() where id = p_id;
    perform public._cm_match(p_id);
  elsif p_action = 'hide' and adm then
    update public.community_posts set status = 'hidden', updated_at = now() where id = p_id;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- the chat stream, newest first (the page reverses it). Kind/area filters apply to cards only;
-- with a filter on, plain messages are left out. p_after fetches only what arrived since the last load.
create or replace function public.community_chat(p_kinds text[] default null, p_areas text[] default null,
                                                 p_before timestamptz default null, p_after timestamptz default null,
                                                 p_post uuid default null, p_limit int default 50)
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
       and (p.status <> 'hidden' or p.author_id = uid)
       and (p_kinds is null or cardinality(p_kinds) = 0 or p.kind = any(p_kinds))
       and (p_areas is null or cardinality(p_areas) = 0 or (p.kind <> 'message' and exists (select 1 from unnest(p_areas) z
              where public._cm_area_ok(z, p.area_slug) or public._cm_area_ok(p.area_slug, z))))
       and (p_before is null or p.created_at < p_before)
       and (p_after is null or p.created_at > p_after or p.updated_at > p_after)
     order by p.created_at desc
     limit least(coalesce(p_limit, 50), 100)) x), '[]'::jsonb);
end $$;
grant execute on function public.community_chat(text[], text[], timestamptz, timestamptz, uuid, int) to authenticated;
revoke execute on function public.community_chat(text[], text[], timestamptz, timestamptz, uuid, int) from anon;

