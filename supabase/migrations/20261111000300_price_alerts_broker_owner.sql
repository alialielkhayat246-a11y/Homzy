-- Price alerts for saved projects/units, listing view tracking, the owner report
-- (a private link a broker sends the property owner), and the broker public profile.

-- ---------------------------------------------------------------------------
-- 1) Price alerts: a price change on a project (unit_price_history) or a listing
--    notifies everyone who saved it — at most one alert per item per user per 20h.
-- ---------------------------------------------------------------------------
create or replace function public._price_fmt(n numeric)
returns text language sql immutable as $$ select to_char(round(n), 'FM999,999,999,999') $$;

create or replace function public._price_alert_project()
returns trigger language plpgsql security definer set search_path = public as $$
declare pname text; pct numeric; f record;
begin
  if new.project_id is null or new.old_price_from is null or new.new_price_from is null
     or new.old_price_from <= 0 or new.old_price_from = new.new_price_from then return new; end if;
  select coalesce(nullif(name_ar, ''), name) into pname from public.projects where id = new.project_id;
  pct := round(100.0 * (new.new_price_from - new.old_price_from) / new.old_price_from, 1);
  for f in select distinct fv.user_id from public.favorites fv
            where fv.project_id = new.project_id
              and not exists (select 1 from public.crm_notifications n
                               where n.user_id = fv.user_id and n.type = 'price_alert'
                                 and n.data->>'project_id' = new.project_id::text
                                 and n.created_at > now() - interval '20 hours') loop
    perform public._appt_notify(f.user_id, 'price_alert',
      case when pct < 0 then '📉 السعر نزل في ' else '📈 السعر اتغيّر في ' end || coalesce(pname, 'مشروع محفوظ'),
      'بداية الأسعار من ' || public._price_fmt(new.old_price_from) || ' لـ ' || public._price_fmt(new.new_price_from)
      || ' ج (' || case when pct > 0 then '+' else '' end || pct || '%)',
      jsonb_build_object('project_id', new.project_id, 'url', '/project/' || new.project_id));
  end loop;
  return new;
end $$;
drop trigger if exists trg_price_alert on public.unit_price_history;
create trigger trg_price_alert after insert on public.unit_price_history
  for each row execute function public._price_alert_project();

create or replace function public._price_alert_listing()
returns trigger language plpgsql security definer set search_path = public as $$
declare pct numeric; f record;
begin
  if new.status <> 'active' or old.price is null or new.price is null or old.price <= 0 then return new; end if;
  pct := round(100.0 * (new.price - old.price) / old.price, 1);
  for f in select distinct fv.user_id from public.favorites fv
            where fv.listing_id = new.id and fv.user_id <> new.owner_id
              and not exists (select 1 from public.crm_notifications n
                               where n.user_id = fv.user_id and n.type = 'price_alert'
                                 and n.data->>'listing_id' = new.id::text
                                 and n.created_at > now() - interval '20 hours') loop
    perform public._appt_notify(f.user_id, 'price_alert',
      case when pct < 0 then '📉 السعر نزل: ' else '📈 السعر اتغيّر: ' end || coalesce(new.title, 'وحدة محفوظة'),
      'من ' || public._price_fmt(old.price) || ' لـ ' || public._price_fmt(new.price)
      || ' ج (' || case when pct > 0 then '+' else '' end || pct || '%)',
      jsonb_build_object('listing_id', new.id, 'url', '/listing/' || new.id));
  end loop;
  return new;
end $$;
drop trigger if exists trg_listing_price_alert on public.listings;
create trigger trg_listing_price_alert after update of price on public.listings
  for each row when (old.price is distinct from new.price) execute function public._price_alert_listing();

-- ---------------------------------------------------------------------------
-- 2) Listing views (one ping per visitor session, sent from the /listing page)
-- ---------------------------------------------------------------------------
create table if not exists public.listing_views (
  id bigserial primary key,
  listing_id uuid not null references public.listings(id) on delete cascade,
  viewer_id uuid,
  source text,
  created_at timestamptz not null default now()
);
create index if not exists listing_views_listing_idx on public.listing_views(listing_id, created_at desc);
alter table public.listing_views enable row level security;   -- no policies: read/write only via the functions below

create or replace function public.listing_view_ping(p_listing uuid, p_source text default null)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); own uuid;
begin
  select owner_id into own from public.listings where id = p_listing and status = 'active';
  if not found or own = uid then return; end if;
  -- a signed-in visitor counts once a day; anonymous visitors are de-duplicated per session by the page
  if uid is not null and exists (select 1 from public.listing_views where listing_id = p_listing and viewer_id = uid
                                  and created_at > now() - interval '1 day') then return; end if;
  insert into public.listing_views(listing_id, viewer_id, source) values (p_listing, uid, left(p_source, 40));
end $$;
grant execute on function public.listing_view_ping(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Owner report: a secret per-listing link (no client names or phones in it)
-- ---------------------------------------------------------------------------
create table if not exists public.owner_report_tokens (
  listing_id uuid primary key references public.listings(id) on delete cascade,
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);
alter table public.owner_report_tokens enable row level security;

create or replace function public.owner_report_link(p_listing uuid, p_reset boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); t text;
begin
  if uid is null or not exists (select 1 from public.listings where id = p_listing and owner_id = uid) then
    raise exception 'forbidden' using errcode = '42501'; end if;
  if p_reset then delete from public.owner_report_tokens where listing_id = p_listing; end if;
  insert into public.owner_report_tokens(listing_id) values (p_listing) on conflict (listing_id) do nothing;
  select token into t from public.owner_report_tokens where listing_id = p_listing;
  return t;
end $$;
grant execute on function public.owner_report_link(uuid, boolean) to authenticated;
revoke execute on function public.owner_report_link(uuid, boolean) from anon;

create or replace function public.owner_report(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lid uuid; l public.listings%rowtype; b public.profiles%rowtype;
begin
  select listing_id into lid from public.owner_report_tokens where token = p_token;
  if lid is null then return null; end if;
  select * into l from public.listings where id = lid;
  select * into b from public.profiles where id = l.owner_id;
  return jsonb_build_object(
    'listing', jsonb_build_object('id', l.id, 'title', l.title, 'area', l.area, 'price', l.price, 'purpose', l.purpose,
                                  'status', l.status, 'created_at', l.created_at, 'size_sqm', l.size_sqm, 'bedrooms', l.bedrooms,
                                  'cover', (select m.url from public.listing_media m where m.listing_id = lid order by m.sort limit 1)),
    'broker', jsonb_build_object('name', coalesce(b.company, b.full_name), 'person', b.full_name,
                                 'phone', coalesce(b.whatsapp, b.phone), 'logo', b.company_logo_url),
    'views', jsonb_build_object(
       'total', (select count(*) from public.listing_views where listing_id = lid),
       'd7', (select count(*) from public.listing_views where listing_id = lid and created_at > now() - interval '7 days'),
       'd30', (select count(*) from public.listing_views where listing_id = lid and created_at > now() - interval '30 days'),
       'weekly', (select coalesce(jsonb_agg(jsonb_build_object('week', w, 'n', n) order by w), '[]'::jsonb) from (
                    select date_trunc('week', created_at at time zone 'Africa/Cairo')::date w, count(*) n
                      from public.listing_views where listing_id = lid and created_at > now() - interval '8 weeks' group by 1) x)),
    'saves', (select count(*) from public.favorites where listing_id = lid),
    'viewings', jsonb_build_object(
       'requests', (select count(*) from public.appointments where listing_id = lid),
       'confirmed', (select count(*) from public.appointments where listing_id = lid and confirmed_at is not null),
       'completed', (select count(*) from public.appointments where listing_id = lid and status = 'completed'),
       'upcoming', (select count(*) from public.appointments where listing_id = lid and status = 'confirmed' and starts_at > now()),
       'video', (select count(*) from public.appointments where listing_id = lid and kind = 'video' and status = 'completed')),
    'interest', (select jsonb_build_object('avg', round(avg(f.interest), 1), 'n', count(*))
                   from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id where a.listing_id = lid),
    'comments', (select coalesce(jsonb_agg(jsonb_build_object('interest', f.interest, 'comment', f.comment, 'at', f.created_at)
                                           order by f.created_at desc), '[]'::jsonb)
                   from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id
                  where a.listing_id = lid and nullif(trim(f.comment), '') is not null),
    'generated_at', now());
end $$;
grant execute on function public.owner_report(text) to anon, authenticated;

-- monthly nudge (1st of the month, 11:00 Cairo): send owners their report
create or replace function public._owner_report_reminders()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select owner_id, count(*) n from public.listings where status = 'active' group by owner_id loop
    perform public._appt_notify(r.owner_id, 'owner_report', '📊 ابعت تقرير الشهر لأصحاب الوحدات',
      'عندك ' || r.n || ' وحدة نشطة. من «وحداتي» دوس «📊 تقرير للمالك» وابعته على واتساب — المالك هيشوف المشاهدات والمعاينات وآراء العملاء.',
      jsonb_build_object('url', '/my-listings'));
  end loop;
end $$;
select cron.unschedule('owner-report-monthly') where exists (select 1 from cron.job where jobname = 'owner-report-monthly');
select cron.schedule('owner-report-monthly', '0 9 1 * *', 'select public._owner_report_reminders()');

-- ---------------------------------------------------------------------------
-- 4) Broker public profile (/broker/{id})
-- ---------------------------------------------------------------------------
create or replace function public.broker_public_profile(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.profiles%rowtype;
begin
  select * into b from public.profiles where id = p_id and role = 'broker';
  if not found then return null; end if;
  return jsonb_build_object(
    'id', b.id, 'name', b.full_name, 'company', b.company, 'logo', b.company_logo_url, 'avatar', b.avatar_url,
    'phone', coalesce(b.whatsapp, b.phone), 'work_areas', b.work_areas, 'since', b.created_at,
    'verified', b.phone_verified_at is not null,
    'rating', (select jsonb_build_object('avg', round(avg(f.broker_rating), 1), 'n', count(*))
                 from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id
                where a.broker_id = p_id),
    'viewings_done', (select count(*) from public.appointments where broker_id = p_id and status = 'completed'),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object('rating', x.broker_rating, 'comment', x.comment, 'at', x.created_at)), '[]'::jsonb)
                  from (select f.broker_rating, f.comment, f.created_at
                          from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id
                         where a.broker_id = p_id and nullif(trim(f.comment), '') is not null
                         order by f.created_at desc limit 6) x),
    'listings', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
                   select l.id, l.title, l.price, l.area, l.purpose, l.type, l.bedrooms, l.size_sqm, l.created_at,
                          (select m.url from public.listing_media m where m.listing_id = l.id order by m.sort limit 1) as cover
                     from public.listings l where l.owner_id = p_id and l.status = 'active'
                    order by l.created_at desc limit 30) x),
    'listings_count', (select count(*) from public.listings where owner_id = p_id and status = 'active'));
end $$;
grant execute on function public.broker_public_profile(uuid) to anon, authenticated;
