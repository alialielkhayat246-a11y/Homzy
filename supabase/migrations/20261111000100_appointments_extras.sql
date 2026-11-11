-- Viewing appointments — extras:
--   * in-person or video viewings (video link made at booking time, shown once confirmed)
--   * client "on my way" / "arrived" signals to the broker
--   * no-show status; clients with 2+ no-shows/late cancellations in 90 days
--     must have a verified phone to book on their own
--   * post-viewing feedback (interest + broker rating) that warms the CRM lead
--   * waiting list for fully booked listings, pinged when a slot frees up
--   * private iCal feed of the broker's appointments

alter table public.appointments drop constraint if exists appointments_status_check;
alter table public.appointments add constraint appointments_status_check
  check (status in ('pending', 'confirmed', 'rejected', 'cancelled', 'completed', 'no_show'));
alter table public.appointments
  add column if not exists kind text not null default 'in_person' check (kind in ('in_person', 'video')),
  add column if not exists video_url text,
  add column if not exists client_signal text check (client_signal in ('on_the_way', 'arrived')),
  add column if not exists client_signal_at timestamptz;

alter table public.appt_settings
  add column if not exists allow_video boolean not null default true,
  add column if not exists ical_token uuid not null default gen_random_uuid();

create table if not exists public.appointment_feedback (
  appointment_id uuid primary key references public.appointments(id) on delete cascade,
  client_id      uuid not null,
  broker_id      uuid not null,
  listing_id     uuid,
  interest       smallint not null check (interest between 1 and 5),   -- how much the client liked the property
  broker_rating  smallint not null check (broker_rating between 1 and 5),
  comment        text,
  created_at     timestamptz not null default now()
);
create index if not exists appointment_feedback_broker_idx on public.appointment_feedback(broker_id);
create index if not exists appointment_feedback_listing_idx on public.appointment_feedback(listing_id);

create table if not exists public.appt_waitlist (
  id          bigserial primary key,
  listing_id  uuid not null references public.listings(id) on delete cascade,
  client_id   uuid not null,
  name        text not null,
  phone       text not null,
  created_at  timestamptz not null default now(),
  notified_at timestamptz,
  unique (listing_id, client_id)
);

alter table public.appointment_feedback enable row level security;
alter table public.appt_waitlist        enable row level security;
drop policy if exists appointment_feedback_parties on public.appointment_feedback;
create policy appointment_feedback_parties on public.appointment_feedback for select to authenticated
  using (client_id = auth.uid() or broker_id = auth.uid());
drop policy if exists appt_waitlist_parties on public.appt_waitlist;
create policy appt_waitlist_parties on public.appt_waitlist for select to authenticated
  using (client_id = auth.uid() or exists (select 1 from public.listings l where l.id = listing_id and l.owner_id = auth.uid()));

-- the cfg row type gained columns: rebuild the default row
create or replace function public._appt_cfg(p_broker uuid)
returns public.appt_settings language plpgsql stable security definer set search_path = public as $$
declare c public.appt_settings;
begin
  select * into c from public.appt_settings where broker_id = p_broker;
  if not found then
    c.broker_id := p_broker; c.daily_limit := 2; c.slot_minutes := 60; c.pending_hold_hours := 24;
    c.min_notice_hours := 2; c.horizon_days := 30; c.updated_at := now(); c.allow_video := true; c.ical_token := null;
  end if;
  return c;
end $$;

-- tell people waiting on a listing that a slot opened (at most once a day each)
create or replace function public._appt_waitlist_ping(p_listing uuid)
returns void language plpgsql security definer set search_path = public as $$
declare w record; t text;
begin
  if p_listing is null then return; end if;
  select title into t from public.listings where id = p_listing;
  for w in select * from public.appt_waitlist where listing_id = p_listing
            and (notified_at is null or notified_at < now() - interval '1 day') loop
    perform public._appt_notify(w.client_id, 'appt_waitlist', 'اتفتح ميعاد معاينة 🎉',
      'فيه ميعاد اتفتح لمعاينة "' || coalesce(t, '') || '" — احجزه قبل ما يتاخد.',
      jsonb_build_object('listing_id', p_listing, 'url', '/listing/' || p_listing || '#book'));
    update public.appt_waitlist set notified_at = now() where id = w.id;
  end loop;
end $$;

create or replace function public._appt_expire()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select * from public.appointments
            where status = 'pending' and hold_expires_at <= now() for update skip locked loop
    update public.appointments set status = 'cancelled', cancelled_by = 'system', status_reason = 'expired',
           closed_at = now(), updated_at = now() where id = r.id;
    insert into public.appointment_events(appointment_id, actor_role, action, from_status, to_status)
    values (r.id, 'system', 'expired', 'pending', 'cancelled');
    perform public._appt_notify(r.client_id, 'appt_expired', 'طلب المعاينة انتهى',
      'البروكر مارَدّش على طلب معاينة "' || coalesce(r.listing_title, '') || '" يوم ' || public._appt_when(r.starts_at)
      || ' في الوقت المحدد، فالميعاد اتلغى. تقدر تحجز ميعاد تاني.',
      jsonb_build_object('appointment_id', r.id, 'url', '/my-bookings'));
    perform public._appt_notify(r.broker_id, 'appt_expired', 'طلب معاينة انتهى من غير رد',
      coalesce(r.client_name, '') || ' — ' || coalesce(r.listing_title, '') || ' — ' || public._appt_when(r.starts_at),
      jsonb_build_object('appointment_id', r.id, 'url', '/appointments?id=' || r.id));
    perform public._appt_waitlist_ping(r.listing_id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- no-shows + client cancellations close to the time (< 24h) in the last 90 days
create or replace function public._appt_strikes(p_client uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.appointments
   where client_id = p_client and created_at > now() - interval '90 days'
     and (status = 'no_show'
          or (status = 'cancelled' and cancelled_by = 'client' and closed_at > starts_at - interval '24 hours'));
$$;

drop function if exists public.appt_book(uuid, timestamptz, text, text, text);
create or replace function public.appt_book(p_listing uuid, p_starts_at timestamptz, p_name text,
                                            p_phone text, p_notes text default null, p_kind text default 'in_person')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); l public.listings%rowtype; c public.appt_settings; e timestamptz; d date;
  err text; aid uuid; hold timestamptz; lead uuid; v_phone text; agency uuid; kind text;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'login_required'); end if;
  select * into l from public.listings where id = p_listing and status = 'active';
  if not found then return jsonb_build_object('ok', false, 'error', 'listing_unavailable'); end if;
  if l.owner_id = uid then return jsonb_build_object('ok', false, 'error', 'own_listing'); end if;
  if coalesce(length(trim(p_name)), 0) < 2 then return jsonb_build_object('ok', false, 'error', 'name_required'); end if;
  v_phone := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(v_phone) < 10 or length(v_phone) > 15 then return jsonb_build_object('ok', false, 'error', 'phone_invalid'); end if;
  if public._appt_strikes(uid) >= 2
     and not exists (select 1 from public.profiles where id = uid and phone_verified_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'verify_phone'); end if;
  if exists (select 1 from public.appointments where client_id = uid and listing_id = p_listing
             and status in ('pending', 'confirmed') and starts_at > now()) then
    return jsonb_build_object('ok', false, 'error', 'already_booked'); end if;
  if (select count(*) from public.appointments where client_id = uid and status = 'pending' and hold_expires_at > now()) >= 3 then
    return jsonb_build_object('ok', false, 'error', 'too_many_pending'); end if;

  c := public._appt_cfg(l.owner_id);
  kind := case when p_kind = 'video' and c.allow_video then 'video' else 'in_person' end;
  e := p_starts_at + make_interval(mins => c.slot_minutes);
  d := (p_starts_at at time zone 'Africa/Cairo')::date;
  perform public._appt_expire();
  perform pg_advisory_xact_lock(hashtextextended(l.owner_id::text || d::text, 0));
  err := public._appt_slot_problem(p_listing, l.owner_id, p_starts_at, e);
  if err is not null then return jsonb_build_object('ok', false, 'error', err); end if;

  select id into lead from public.clients
   where owner_id = l.owner_id and right(regexp_replace(coalesce(clients.phone, ''), '\D', '', 'g'), 10) = right(v_phone, 10)
     and deleted_at is null limit 1;
  if lead is null then
    select agency_id into agency from public.agency_members where user_id = l.owner_id and status = 'active' limit 1;
    insert into public.clients(owner_id, agency_id, name, phone, whatsapp, purpose, type, area, stage, source, notes, created_by)
    values (l.owner_id, agency, trim(p_name), p_phone, p_phone, l.purpose, l.type, l.area, 'viewing', 'viewing_booking',
            'طلب معاينة: ' || coalesce(l.title, ''), uid)
    returning id into lead;
  end if;

  hold := least(now() + make_interval(hours => c.pending_hold_hours), p_starts_at);
  begin
    insert into public.appointments(listing_id, listing_title, broker_id, client_id, lead_id, client_name, client_phone,
                                    client_notes, starts_at, ends_at, local_day, status, hold_expires_at, kind, video_url)
    values (p_listing, l.title, l.owner_id, uid, lead, trim(p_name), p_phone, nullif(trim(coalesce(p_notes, '')), ''),
            p_starts_at, e, d, 'pending', hold, kind,
            case when kind = 'video' then 'https://meet.jit.si/Homzy-' || substr(md5(gen_random_uuid()::text), 1, 12) end)
    returning id into aid;
  exception when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'slot_taken');
  end;
  delete from public.appt_waitlist where listing_id = p_listing and client_id = uid;
  insert into public.appointment_events(appointment_id, actor_id, actor_role, action, to_status, to_start)
  values (aid, uid, 'client', 'requested', 'pending', p_starts_at);
  perform public._appt_notify(l.owner_id, 'appt_request',
    case when kind = 'video' then 'طلب معاينة فيديو جديد 🎥' else 'طلب معاينة جديد' end,
    trim(p_name) || ' عايز يعاين "' || coalesce(l.title, '') || '" يوم ' || public._appt_when(p_starts_at)
    || ' — أكّد أو ارفض قبل ' || public._appt_when(hold),
    jsonb_build_object('appointment_id', aid, 'url', '/appointments?id=' || aid));
  return jsonb_build_object('ok', true, 'id', aid, 'status', 'pending', 'hold_expires_at', hold, 'starts_at', p_starts_at, 'kind', kind);
end $$;

create or replace function public.appt_action(p_id uuid, p_action text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a public.appointments%rowtype; role text; ns text;
begin
  select * into a from public.appointments where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  role := case when a.broker_id = uid then 'broker' when a.client_id = uid then 'client' end;
  if role is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_action in ('confirm', 'reject', 'complete', 'no_show') and role <> 'broker' then
    return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  if p_action = 'confirm' then
    if a.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
    if a.hold_expires_at <= now() or a.starts_at <= now() then
      perform public._appt_expire(); return jsonb_build_object('ok', false, 'error', 'expired'); end if;
    ns := 'confirmed';
  elsif p_action = 'reject' then
    if a.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
    ns := 'rejected';
  elsif p_action in ('complete', 'no_show') then
    if a.status <> 'confirmed' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
    if a.starts_at > now() + interval '1 hour' then return jsonb_build_object('ok', false, 'error', 'not_started'); end if;
    ns := case when p_action = 'complete' then 'completed' else 'no_show' end;
  elsif p_action = 'cancel' then
    if a.status not in ('pending', 'confirmed') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
    ns := 'cancelled';
  else
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;

  update public.appointments set
    status = ns, updated_at = now(),
    confirmed_at = case when ns = 'confirmed' then now() else confirmed_at end,
    closed_at = case when ns in ('rejected', 'cancelled', 'completed', 'no_show') then now() else closed_at end,
    hold_expires_at = case when ns = 'confirmed' then null else hold_expires_at end,
    status_reason = case when ns in ('rejected', 'cancelled') then nullif(trim(coalesce(p_reason, '')), '') else status_reason end,
    cancelled_by = case when ns = 'cancelled' then role else cancelled_by end
  where id = p_id;
  insert into public.appointment_events(appointment_id, actor_id, actor_role, action, from_status, to_status, note)
  values (p_id, uid, role, ns, a.status, ns, p_reason);
  perform public._appt_plan_reminders(p_id);
  perform public._appt_sync_viewing(p_id);

  if ns = 'confirmed' then
    perform public._appt_notify(a.client_id, 'appt_confirmed', 'تم تأكيد ميعاد المعاينة ✅',
      'معاينة "' || coalesce(a.listing_title, '') || '" يوم ' || public._appt_when(a.starts_at)
      || case when a.kind = 'video' then ' — معاينة فيديو، اللينك في «حجوزاتي»' else '' end,
      jsonb_build_object('appointment_id', p_id, 'url', '/my-bookings'));
    perform public._appt_notify(a.broker_id, 'appt_confirmed', 'أكّدت معاينة',
      a.client_name || ' — ' || coalesce(a.listing_title, '') || ' — ' || public._appt_when(a.starts_at),
      jsonb_build_object('appointment_id', p_id, 'url', '/appointments?id=' || p_id));
  elsif ns = 'rejected' then
    perform public._appt_notify(a.client_id, 'appt_rejected', 'طلب المعاينة اترفض',
      'معاينة "' || coalesce(a.listing_title, '') || '" يوم ' || public._appt_when(a.starts_at)
      || coalesce(' — ' || nullif(trim(coalesce(p_reason, '')), ''), '') || '. تقدر تختار ميعاد تاني.',
      jsonb_build_object('appointment_id', p_id, 'url', '/my-bookings'));
    perform public._appt_waitlist_ping(a.listing_id);
  elsif ns = 'cancelled' then
    perform public._appt_notify(case when role = 'broker' then a.client_id else a.broker_id end, 'appt_cancelled',
      'ميعاد معاينة اتلغى',
      coalesce(a.listing_title, '') || ' — ' || public._appt_when(a.starts_at)
      || case when role = 'client' then ' — ألغاه ' || a.client_name else ' — ألغاه البروكر' end
      || coalesce(' — ' || nullif(trim(coalesce(p_reason, '')), ''), ''),
      jsonb_build_object('appointment_id', p_id, 'url', case when role = 'broker' then '/my-bookings' else '/appointments?id=' || p_id end));
    perform public._appt_waitlist_ping(a.listing_id);
  elsif ns = 'completed' then
    perform public._appt_notify(a.client_id, 'appt_feedback', 'إيه رأيك في المعاينة؟ ⭐',
      'قيّم معاينة "' || coalesce(a.listing_title, '') || '" في ثانيتين — رأيك بيساعدنا نرشّحلك الأنسب.',
      jsonb_build_object('appointment_id', p_id, 'url', '/my-bookings?rate=' || p_id));
  end if;
  return jsonb_build_object('ok', true, 'status', ns);
end $$;

-- client: "on my way" / "arrived" on the day of a confirmed viewing
create or replace function public.appt_client_signal(p_id uuid, p_signal text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.appointments%rowtype;
begin
  select * into a from public.appointments where id = p_id and client_id = auth.uid();
  if not found then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_signal not in ('on_the_way', 'arrived') then return jsonb_build_object('ok', false, 'error', 'bad_action'); end if;
  if a.status <> 'confirmed' or now() < a.starts_at - interval '4 hours' or now() > a.ends_at + interval '1 hour' then
    return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  update public.appointments set client_signal = p_signal, client_signal_at = now(), updated_at = now() where id = p_id;
  insert into public.appointment_events(appointment_id, actor_id, actor_role, action, note)
  values (p_id, auth.uid(), 'client', p_signal, null);
  perform public._appt_notify(a.broker_id, 'appt_signal',
    case when p_signal = 'on_the_way' then '🚗 العميل في الطريق' else '📍 العميل وصل' end,
    a.client_name || ' — ' || coalesce(a.listing_title, '') || ' — ' || public._appt_when(a.starts_at),
    jsonb_build_object('appointment_id', p_id, 'url', '/appointments?id=' || p_id));
  return jsonb_build_object('ok', true);
end $$;

-- client feedback after a completed viewing; warms/cools the broker's lead
create or replace function public.appt_feedback_submit(p_id uuid, p_interest int, p_broker_rating int, p_comment text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.appointments%rowtype; temp text;
begin
  select * into a from public.appointments where id = p_id and client_id = auth.uid();
  if not found then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if a.status <> 'completed' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_interest not between 1 and 5 or p_broker_rating not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'bad_rating'); end if;
  insert into public.appointment_feedback(appointment_id, client_id, broker_id, listing_id, interest, broker_rating, comment)
  values (p_id, a.client_id, a.broker_id, a.listing_id, p_interest, p_broker_rating, nullif(trim(coalesce(p_comment, '')), ''))
  on conflict (appointment_id) do nothing;
  if not found then return jsonb_build_object('ok', false, 'error', 'already_rated'); end if;
  temp := case when p_interest >= 5 then 'very_hot' when p_interest = 4 then 'hot' when p_interest = 3 then 'warm' else 'cold' end;
  if a.lead_id is not null then
    update public.clients set temperature = temp, updated_at = now() where id = a.lead_id;
    insert into public.crm_lead_activities(lead_id, actor_id, kind, body, meta)
    values (a.lead_id, auth.uid(), 'viewing_feedback',
            'رأي العميل بعد المعاينة: اهتمام ' || p_interest || '/5' || coalesce(' — ' || nullif(trim(coalesce(p_comment, '')), ''), ''),
            jsonb_build_object('appointment_id', p_id, 'interest', p_interest, 'broker_rating', p_broker_rating));
  end if;
  perform public._appt_notify(a.broker_id, 'appt_feedback_in', 'وصلك تقييم معاينة ⭐',
    a.client_name || ' — ' || coalesce(a.listing_title, '') || ': اهتمام ' || p_interest || '/5، تقييمك ' || p_broker_rating || '/5',
    jsonb_build_object('appointment_id', p_id, 'url', '/appointments?id=' || p_id));
  return jsonb_build_object('ok', true, 'temperature', temp);
end $$;

-- waiting list for a listing with no free time
create or replace function public.appt_waitlist_join(p_listing uuid, p_name text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l public.listings%rowtype;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'login_required'); end if;
  select * into l from public.listings where id = p_listing and status = 'active';
  if not found then return jsonb_build_object('ok', false, 'error', 'listing_unavailable'); end if;
  if l.owner_id = uid then return jsonb_build_object('ok', false, 'error', 'own_listing'); end if;
  if length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) < 10 then return jsonb_build_object('ok', false, 'error', 'phone_invalid'); end if;
  insert into public.appt_waitlist(listing_id, client_id, name, phone) values (p_listing, uid, trim(p_name), p_phone)
  on conflict (listing_id, client_id) do update set name = excluded.name, phone = excluded.phone, notified_at = null;
  perform public._appt_notify(l.owner_id, 'appt_waitlist_join', 'عميل مستني ميعاد معاينة',
    trim(p_name) || ' (' || p_phone || ') عايز يعاين "' || coalesce(l.title, '') || '" ومفيش مواعيد فاضية — زوّد مواعيدك أو كلّمه.',
    jsonb_build_object('listing_id', p_listing, 'url', '/appointments'));
  return jsonb_build_object('ok', true);
end $$;

-- private iCal feed (the token is the secret)
create or replace function public.appt_ical(p_token uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'starts_at', a.starts_at, 'ends_at', a.ends_at, 'status', a.status,
           'title', coalesce(a.listing_title, ''), 'client', a.client_name, 'phone', a.client_phone, 'kind', a.kind,
           'video_url', a.video_url, 'location', concat_ws(' — ', l.area, l.address), 'updated_at', a.updated_at)), '[]'::jsonb)
    from public.appt_settings s
    join public.appointments a on a.broker_id = s.broker_id
    left join public.listings l on l.id = a.listing_id
   where s.ical_token = p_token and a.status in ('pending', 'confirmed', 'completed')
     and a.starts_at > now() - interval '30 days';
$$;

create or replace function public.appt_ical_token(p_reset boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); t uuid;
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  insert into public.appt_settings(broker_id) values (uid) on conflict (broker_id) do nothing;
  if p_reset then update public.appt_settings set ical_token = gen_random_uuid() where broker_id = uid; end if;
  select ical_token into t from public.appt_settings where broker_id = uid;
  return t;
end $$;

-- the lists carry the new fields
create or replace function public.appt_broker_list(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  perform public._appt_expire();
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
      select a.id, a.listing_id, coalesce(l.title, a.listing_title) as listing_title, l.area, l.address, l.lat, l.lng,
             (select m.url from public.listing_media m where m.listing_id = a.listing_id order by m.sort limit 1) as cover,
             a.lead_id, a.viewing_id, a.broker_id, a.client_name, a.client_phone, a.client_notes, a.broker_notes, a.starts_at, a.ends_at,
             a.status, a.status_reason, a.cancelled_by, a.hold_expires_at, a.created_at, a.confirmed_at,
             a.kind, a.video_url, a.client_signal, a.client_signal_at,
             f.interest, f.broker_rating, f.comment as feedback_comment
        from public.appointments a
        left join public.listings l on l.id = a.listing_id
        left join public.appointment_feedback f on f.appointment_id = a.id
       where a.broker_id = uid
         and (p_from is null or a.starts_at >= p_from) and (p_to is null or a.starts_at < p_to)
    ) x), '[]'::jsonb);
end $$;

create or replace function public.appt_my_list()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  perform public._appt_expire();
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.starts_at desc) from (
      select a.id, a.listing_id, coalesce(l.title, a.listing_title) as listing_title, l.area, l.address, l.lat, l.lng,
             l.price, l.size_sqm, l.bedrooms, l.bathrooms, l.purpose,
             (select m.url from public.listing_media m where m.listing_id = a.listing_id order by m.sort limit 1) as cover,
             a.starts_at, a.ends_at, a.status, a.status_reason, a.cancelled_by, a.hold_expires_at, a.created_at,
             a.client_notes, a.kind, a.client_signal,
             case when a.status = 'confirmed' then a.video_url end as video_url,
             coalesce(p.company, p.full_name) as broker_name, a.broker_id,
             case when a.status = 'confirmed' then coalesce(p.whatsapp, p.phone) end as broker_phone,
             f.interest, f.broker_rating
        from public.appointments a
        left join public.listings l on l.id = a.listing_id
        left join public.profiles p on p.id = a.broker_id
        left join public.appointment_feedback f on f.appointment_id = a.id
       where a.client_id = uid
    ) x), '[]'::jsonb);
end $$;

-- the booking widget needs to know whether video viewings are offered
create or replace function public.appt_listing_options(p_listing uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('allow_video', (public._appt_cfg(l.owner_id)).allow_video,
                            'slot_minutes', (public._appt_cfg(l.owner_id)).slot_minutes)
    from public.listings l where l.id = p_listing and l.status = 'active';
$$;

create or replace function public.appt_get_settings()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c public.appt_settings;
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  c := public._appt_cfg(uid);
  return jsonb_build_object(
    'daily_limit', c.daily_limit, 'slot_minutes', c.slot_minutes, 'pending_hold_hours', c.pending_hold_hours,
    'min_notice_hours', c.min_notice_hours, 'horizon_days', c.horizon_days, 'allow_video', c.allow_video,
    'hours', coalesce((select jsonb_agg(jsonb_build_object('weekday', weekday, 'start', to_char(start_time, 'HH24:MI'),
                                                           'end', to_char(end_time, 'HH24:MI')) order by weekday, start_time)
                         from public.appt_availability where broker_id = uid and listing_id is null), '[]'::jsonb),
    'blackouts', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'start', to_char(start_time, 'HH24:MI'),
                                                               'end', to_char(end_time, 'HH24:MI'), 'note', note) order by day)
                             from public.appt_blackouts where broker_id = uid and listing_id is null and day >= current_date), '[]'::jsonb));
end $$;

create or replace function public.appt_save_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); h jsonb; b jsonb;
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  insert into public.appt_settings(broker_id, daily_limit, slot_minutes, pending_hold_hours, min_notice_hours, horizon_days, allow_video, updated_at)
  values (uid, coalesce((p->>'daily_limit')::int, 2), coalesce((p->>'slot_minutes')::int, 60),
          coalesce((p->>'pending_hold_hours')::int, 24), coalesce((p->>'min_notice_hours')::int, 2),
          coalesce((p->>'horizon_days')::int, 30), coalesce((p->>'allow_video')::boolean, true), now())
  on conflict (broker_id) do update set daily_limit = excluded.daily_limit, slot_minutes = excluded.slot_minutes,
    pending_hold_hours = excluded.pending_hold_hours, min_notice_hours = excluded.min_notice_hours,
    horizon_days = excluded.horizon_days, allow_video = excluded.allow_video, updated_at = now();
  if p ? 'hours' then
    delete from public.appt_availability where broker_id = uid and listing_id is null;
    for h in select * from jsonb_array_elements(p->'hours') loop
      insert into public.appt_availability(broker_id, listing_id, weekday, start_time, end_time)
      values (uid, null, (h->>'weekday')::smallint, (h->>'start')::time, (h->>'end')::time);
    end loop;
  end if;
  if p ? 'blackouts' then
    delete from public.appt_blackouts where broker_id = uid and listing_id is null;
    for b in select * from jsonb_array_elements(p->'blackouts') loop
      insert into public.appt_blackouts(broker_id, listing_id, day, start_time, end_time, note)
      values (uid, null, (b->>'day')::date, nullif(b->>'start', '')::time, nullif(b->>'end', '')::time, b->>'note');
    end loop;
  end if;
  return public.appt_get_settings();
end $$;

revoke all on function public._appt_waitlist_ping(uuid), public._appt_strikes(uuid) from public, anon, authenticated;
grant execute on function public.appt_book(uuid, timestamptz, text, text, text, text), public.appt_client_signal(uuid, text),
  public.appt_feedback_submit(uuid, int, int, text), public.appt_waitlist_join(uuid, text, text),
  public.appt_ical_token(boolean) to authenticated;
grant execute on function public.appt_ical(uuid), public.appt_listing_options(uuid) to anon, authenticated;

-- a no-show is logged as such on the CRM viewings log too
create or replace function public._appt_sync_viewing(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a public.appointments%rowtype; l public.listings%rowtype; vid bigint; st text;
begin
  select * into a from public.appointments where id = p_id;
  if not found then return; end if;
  st := case a.status when 'confirmed' then 'confirmed' when 'completed' then 'completed' when 'no_show' then 'no_show' else 'cancelled' end;
  if a.viewing_id is null then
    if a.status <> 'confirmed' then return; end if;
    select * into l from public.listings where id = a.listing_id;
    insert into public.crm_viewings(lead_id, owner_id, property_kind, property_ref, property_title, scheduled_at, location, status, notes)
    values (a.lead_id, a.broker_id, 'listing', a.listing_id::text, a.listing_title, a.starts_at,
            nullif(concat_ws(' — ', l.area, l.address), ''), st, a.client_notes)
    returning id into vid;
    update public.appointments set viewing_id = vid where id = p_id;
  else
    update public.crm_viewings set scheduled_at = a.starts_at, status = st where id = a.viewing_id;
  end if;
end $$;
