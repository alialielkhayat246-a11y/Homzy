-- Automatic content review for marketplace listings.
--
-- A listing can only be public ('active') once its CURRENT content (title,
-- description, photos) has been approved. Publishing — from the web, the
-- mobile app or AXIS ONE — puts it in 'pending' with moderation_status
-- 'queued'; the backend reviews it with Gemini (photos + text) and calls
-- listing_moderation_apply: approve -> 'active', reject -> 'rejected' (with
-- the reason shown to the broker), unsure -> stays 'pending' as 'manual' for
-- an admin. Any later edit of the text or photos re-queues it. Brokers can't
-- write the moderation_* columns themselves.

alter table public.listings
  add column if not exists moderation_status text,      -- queued | approved | rejected | manual
  add column if not exists moderation_reason text,
  add column if not exists moderation_hash text,        -- content hash that was approved
  add column if not exists moderation_flags jsonb,
  add column if not exists moderated_at timestamptz;

create index if not exists listings_moderation_queue_idx
  on public.listings(moderation_status) where moderation_status in ('queued','manual');

create or replace function public.listing_content_hash(p_id uuid, p_title text, p_description text)
returns text language sql stable security definer set search_path = public as $$
  select md5(coalesce(p_title,'') || '|' || coalesce(p_description,'') || '|' ||
             coalesce((select string_agg(url, ',' order by url) from public.listing_media where listing_id = p_id), ''));
$$;

create or replace function public._listing_moderation_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('hz.mod_ok', true) = '1' then
    return new;                                   -- the reviewer itself
  end if;
  if coalesce(auth.role(), '') <> 'service_role' then
    if tg_op = 'INSERT' then
      new.moderation_status := null; new.moderation_reason := null; new.moderation_hash := null;
      new.moderation_flags := null; new.moderated_at := null;
    else
      new.moderation_status := old.moderation_status; new.moderation_reason := old.moderation_reason;
      new.moderation_hash := old.moderation_hash; new.moderation_flags := old.moderation_flags;
      new.moderated_at := old.moderated_at;
    end if;
  end if;
  -- going (or staying) public needs an approval of exactly this content
  if new.status = 'active' and (
       tg_op = 'INSERT' or old.status is distinct from 'active'
       or new.title is distinct from old.title or new.description is distinct from old.description) then
    if new.moderation_status is distinct from 'approved'
       or new.moderation_hash is distinct from public.listing_content_hash(new.id, new.title, new.description) then
      new.status := 'pending';
      new.moderation_status := 'queued';
      new.moderation_reason := null;
    end if;
  end if;
  -- a listing sent straight to 'pending' (e.g. AXIS ONE) also gets reviewed
  if tg_op = 'INSERT' and new.status = 'pending' and new.moderation_status is null then
    new.moderation_status := 'queued';
  end if;
  return new;
end $$;

drop trigger if exists trg_listing_moderation on public.listings;
create trigger trg_listing_moderation before insert or update on public.listings
  for each row execute function public._listing_moderation_guard();

-- photos added/removed on a public (or waiting) listing -> review again
create or replace function public._listing_media_requeue()
returns trigger language plpgsql security definer set search_path = public as $$
declare lid uuid := coalesce(new.listing_id, old.listing_id);
begin
  perform set_config('hz.mod_ok', '1', true);
  update public.listings
     set status = case when status = 'active' then 'pending' else status end,
         moderation_status = 'queued', moderation_reason = null
   where id = lid and status in ('active', 'pending');
  perform set_config('hz.mod_ok', '', true);
  return null;
end $$;

drop trigger if exists trg_listing_media_requeue on public.listing_media;
create trigger trg_listing_media_requeue after insert or delete on public.listing_media
  for each row execute function public._listing_media_requeue();

-- what the reviewer needs (key-gated: pending listings aren't readable otherwise)
create or replace function public.listing_moderation_queue(p_key text, p_limit int default 10)
returns table(id uuid, title text, description text, photos text[], content_hash text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select l.id, l.title, l.description,
           coalesce(array(select m.url from public.listing_media m where m.listing_id = l.id
                          and coalesce(m.is_360, false) = false order by m.sort limit 12), '{}'),
           public.listing_content_hash(l.id, l.title, l.description)
    from public.listings l
    where l.moderation_status = 'queued'
    order by l.updated_at
    limit greatest(1, least(p_limit, 25));
end $$;

create or replace function public.listing_moderation_apply(p_key text, p_listing uuid, p_hash text,
                                                           p_verdict text, p_reason text, p_flags jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare l public.listings%rowtype;
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into l from public.listings where id = p_listing for update;
  if not found then return 'missing'; end if;
  if public.listing_content_hash(l.id, l.title, l.description) is distinct from p_hash then
    return 'stale';                               -- edited while we were looking; stays queued
  end if;
  perform set_config('hz.mod_ok', '1', true);
  if p_verdict = 'ok' then
    update public.listings set
      status = case when status = 'pending' then 'active' else status end,
      moderation_status = 'approved', moderation_reason = null, moderation_hash = p_hash,
      moderation_flags = p_flags, moderated_at = now()
    where id = p_listing;
  elsif p_verdict = 'reject' then
    update public.listings set status = 'rejected', moderation_status = 'rejected',
      moderation_reason = p_reason, moderation_hash = p_hash, moderation_flags = p_flags, moderated_at = now()
    where id = p_listing;
  else  -- unsure: a person decides
    update public.listings set moderation_status = 'manual', moderation_reason = p_reason,
      moderation_flags = p_flags, moderated_at = now()
    where id = p_listing;
  end if;
  perform set_config('hz.mod_ok', '', true);
  return p_verdict;
end $$;

-- admins: the listings the AI wasn't sure about, and the decision
create or replace function public.admin_listing_review_queue()
returns table(id uuid, title text, description text, price numeric, area text, owner_name text,
              photos text[], moderation_status text, moderation_reason text, moderation_flags jsonb, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin_user() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select l.id, l.title, l.description, l.price, l.area, coalesce(p.full_name, p.phone),
           coalesce(array(select m.url from public.listing_media m where m.listing_id = l.id order by m.sort), '{}'),
           l.moderation_status, l.moderation_reason, l.moderation_flags, l.updated_at
    from public.listings l left join public.profiles p on p.id = l.owner_id
    where l.moderation_status in ('manual', 'queued') or l.status = 'rejected'
    order by (l.moderation_status = 'manual') desc, l.updated_at desc
    limit 100;
end $$;

create or replace function public.admin_listing_decide(p_listing uuid, p_approve boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare l public.listings%rowtype;
begin
  if not public.is_admin_user() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into l from public.listings where id = p_listing for update;
  if not found then raise exception 'not found'; end if;
  perform set_config('hz.mod_ok', '1', true);
  update public.listings set
    status = case when p_approve then 'active' else 'rejected' end,
    moderation_status = case when p_approve then 'approved' else 'rejected' end,
    moderation_reason = case when p_approve then null else coalesce(p_reason, 'مرفوض بعد المراجعة') end,
    moderation_hash = public.listing_content_hash(l.id, l.title, l.description),
    moderated_at = now()
  where id = p_listing;
  perform set_config('hz.mod_ok', '', true);
end $$;

revoke all on function public.listing_moderation_queue(text, int) from public;
revoke all on function public.listing_moderation_apply(text, uuid, text, text, text, jsonb) from public;
grant execute on function public.listing_moderation_queue(text, int) to anon, authenticated;
grant execute on function public.listing_moderation_apply(text, uuid, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.admin_listing_review_queue() to authenticated;
grant execute on function public.admin_listing_decide(uuid, boolean, text) to authenticated;

-- what's public right now goes through the same review once (stays visible meanwhile)
select set_config('hz.mod_ok', '1', true);
update public.listings set moderation_status = 'queued' where status in ('active', 'pending') and moderation_status is null;
select set_config('hz.mod_ok', '', true);
