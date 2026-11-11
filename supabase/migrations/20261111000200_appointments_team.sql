-- Viewing appointments, part 3: team calendar for managers / team leaders, reassigning a
-- viewing to another broker, and "did it turn into a deal" for the report.

-- brokers whose appointments the caller may see: agency-wide with lead.view.all,
-- the caller's own team(s) with lead.view.team. Always includes the caller.
create or replace function public._appt_team_brokers()
returns table(broker_id uuid, agency_id uuid) language sql stable security definer set search_path = public as $$
  select auth.uid(), null::uuid where auth.uid() is not null
  union
  select m.user_id, m.agency_id
    from public.agency_members m
   where m.status = 'active' and m.agency_id in (select public.my_agency_ids())
     and (public.has_perm(m.agency_id, 'lead.view.all')
          or (public.has_perm(m.agency_id, 'lead.view.team') and m.team_id in (select public.my_team_ids(m.agency_id))));
$$;

-- shared row shape for the broker list and the team list
create or replace function public._appt_rows(p_brokers uuid[], p_from timestamptz, p_to timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at), '[]'::jsonb) from (
    select a.id, a.listing_id, coalesce(l.title, a.listing_title) as listing_title, l.area, l.address, l.lat, l.lng,
           (select m.url from public.listing_media m where m.listing_id = a.listing_id order by m.sort limit 1) as cover,
           a.lead_id, a.viewing_id, a.broker_id, coalesce(p.full_name, p.company) as broker_name,
           a.client_name, a.client_phone, a.client_notes, a.broker_notes, a.starts_at, a.ends_at,
           a.status, a.status_reason, a.cancelled_by, a.hold_expires_at, a.created_at, a.confirmed_at,
           a.kind, a.video_url, a.client_signal, a.client_signal_at,
           f.interest, f.broker_rating, f.comment as feedback_comment,
           exists (select 1 from public.crm_deals d where d.lead_id = a.lead_id and d.status = 'won') as deal_won
      from public.appointments a
      left join public.listings l on l.id = a.listing_id
      left join public.profiles p on p.id = a.broker_id
      left join public.appointment_feedback f on f.appointment_id = a.id
     where a.broker_id = any(p_brokers)
       and (p_from is null or a.starts_at >= p_from) and (p_to is null or a.starts_at < p_to)
  ) x;
$$;
revoke all on function public._appt_rows(uuid[], timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public._appt_team_brokers() from public, anon;

create or replace function public.appt_broker_list(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  perform public._appt_expire();
  return public._appt_rows(array[uid], p_from, p_to);
end $$;

-- team view: { brokers: [{id, name, team, me}], can_reassign, appts: [...] }
create or replace function public.appt_team_list(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ids uuid[]; br jsonb;
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  perform public._appt_expire();
  select array_agg(distinct broker_id) into ids from public._appt_team_brokers();
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.full_name, p.company, 'Broker'),
           'team', (select t.name from public.agency_members m join public.teams t on t.id = m.team_id
                     where m.user_id = p.id and m.status = 'active' limit 1),
           'me', p.id = uid) order by p.id <> uid, coalesce(p.full_name, p.company)), '[]'::jsonb)
    into br from public.profiles p where p.id = any(ids);
  return jsonb_build_object(
    'brokers', br,
    'can_reassign', exists (select 1 from public.agency_members m where m.user_id = uid and m.status = 'active'
                             and public.has_perm(m.agency_id, 'lead.assign')),
    'appts', public._appt_rows(ids, p_from, p_to));
end $$;

-- manager / team leader moves a viewing to another broker in the same agency (same time)
create or replace function public.appt_reassign(p_id uuid, p_broker uuid, p_reason text default null, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a public.appointments%rowtype; ag uuid; err text; old_name text; new_name text;
begin
  if uid is null then return jsonb_build_object('ok', false, 'error', 'login_required'); end if;
  select * into a from public.appointments where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if a.status not in ('pending', 'confirmed') or a.ends_at <= now() then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_broker = a.broker_id then return jsonb_build_object('ok', false, 'error', 'same_broker'); end if;
  -- both brokers must be in the caller's scope, inside one agency where the caller can assign
  select t1.agency_id into ag
    from public._appt_team_brokers() t1 join public._appt_team_brokers() t2 on t2.agency_id = t1.agency_id
   where t1.broker_id = a.broker_id and t2.broker_id = p_broker and public.has_perm(t1.agency_id, 'lead.assign')
   limit 1;
  if ag is null then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  perform pg_advisory_xact_lock(hashtextextended(p_broker::text || a.local_day::text, 0));
  err := public._appt_slot_problem(a.listing_id, p_broker, a.starts_at, a.ends_at);
  if err = 'too_soon' then err := null; end if;            -- an existing viewing may be close; that is fine
  if err is null and exists (select 1 from public.appt_blackouts b where b.listing_id = a.listing_id and b.day = a.local_day
       and (b.start_time is null or (b.start_time < (a.ends_at at time zone 'Africa/Cairo')::time
                                     and b.end_time > (a.starts_at at time zone 'Africa/Cairo')::time))) then
    err := 'owner_unavailable'; end if;
  -- a manager may override hours / daily limit, never a clash
  if err is not null and not (p_force and err in ('broker_unavailable', 'daily_limit')) then
    return jsonb_build_object('ok', false, 'error', err); end if;

  begin
    update public.appointments set broker_id = p_broker, updated_at = now() where id = p_id;
  exception when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'slot_taken');
  end;
  update public.appointment_reminders set status = 'cancelled'
   where appointment_id = p_id and user_id = a.broker_id and status = 'scheduled';
  perform public._appt_plan_reminders(p_id);
  if a.viewing_id is not null then update public.crm_viewings set owner_id = p_broker where id = a.viewing_id; end if;
  if a.lead_id is not null then
    begin perform public.agency_assign_lead(a.lead_id, p_broker, coalesce(p_reason, 'viewing reassigned'));
    exception when others then null; end;
  end if;

  select coalesce(full_name, company, '') into old_name from public.profiles where id = a.broker_id;
  select coalesce(full_name, company, '') into new_name from public.profiles where id = p_broker;
  insert into public.appointment_events(appointment_id, actor_id, actor_role, action, from_status, to_status, note)
  values (p_id, uid, 'manager', 'reassigned', a.status, a.status, old_name || ' → ' || new_name || coalesce(' — ' || nullif(trim(p_reason), ''), ''));
  perform public._appt_notify(p_broker, 'appt_assigned', 'اتحوّلتلك معاينة',
    a.client_name || ' — ' || coalesce(a.listing_title, '') || ' — ' || public._appt_when(a.starts_at)
    || case when a.status = 'pending' then ' — محتاجة تأكيدك' else '' end,
    jsonb_build_object('appointment_id', p_id, 'url', '/appointments?id=' || p_id));
  if a.broker_id <> uid then
    perform public._appt_notify(a.broker_id, 'appt_unassigned', 'معاينة اتنقلت لزميل',
      a.client_name || ' — ' || coalesce(a.listing_title, '') || ' — ' || public._appt_when(a.starts_at) || ' → ' || new_name,
      jsonb_build_object('appointment_id', p_id, 'url', '/appointments'));
  end if;
  perform public._appt_notify(a.client_id, 'appt_rescheduled', 'تغيير في البروكر اللي هيقابلك',
    'معاينة "' || coalesce(a.listing_title, '') || '" يوم ' || public._appt_when(a.starts_at) || ' — هيقابلك ' || new_name || ' بدل ' || old_name
    || '. نفس الميعاد.', jsonb_build_object('appointment_id', p_id, 'url', '/my-bookings'));
  return jsonb_build_object('ok', true, 'broker_id', p_broker);
end $$;

grant execute on function public.appt_team_list(timestamptz, timestamptz) to authenticated;
grant execute on function public.appt_reassign(uuid, uuid, text, boolean) to authenticated;
revoke execute on function public.appt_team_list(timestamptz, timestamptz) from anon;
revoke execute on function public.appt_reassign(uuid, uuid, text, boolean) from anon;
