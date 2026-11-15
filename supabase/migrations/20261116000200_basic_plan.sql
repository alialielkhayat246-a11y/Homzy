-- "Basic" plan: everything a single broker needs (CRM, listings, community, appointments, PDF offers)
-- without the AI features, at a lower price. plan_limits.features.ai = false switches every AI action off
-- (ai_consume refuses it with no_ai) and AI top-ups can't be bought on it.

insert into public.plan_limits(plan, name_ar, name_en, price_monthly, price_yearly, max_listings, max_clients, leads_included,
                               team_seats, ai_daily_messages, ai_monthly_per_seat, extra_seat_price, contact_only, active, sort,
                               stays_commission_rate, features)
values ('basic', 'أساسي', 'Basic', 249, 2490, null, null, 0, 1, 0, null, 0, false, true, 1,
        (select stays_commission_rate from public.plan_limits where plan = 'pro'),
        '{"ai":false,"team":false,"voice":false,"ai_sales":false,"featured":false,"analytics":true,"branded_pdf":true,"logo_watermark":true}')
on conflict (plan) do update set name_ar = excluded.name_ar, name_en = excluded.name_en, price_monthly = excluded.price_monthly,
  price_yearly = excluded.price_yearly, ai_daily_messages = 0, active = true, sort = 1, features = excluded.features;
update public.plan_limits set features = features || '{"ai":true}' where plan in ('pro', 'team', 'business', 'enterprise');

create or replace function public._plan_has_ai(p_plan text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (features->>'ai')::boolean from public.plan_limits where plan = p_plan), true);
$$;

create or replace function public.ai_consume(p_kind text DEFAULT 'chat'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_kind text := left(coalesce(nullif(p_kind, ''), 'chat'), 20);
  v_plan text; v_lim int; v_used int := 0; v_ok boolean; v_left int;
  v_ag uuid; v_owner uuid; v_pool int; v_credit uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', true, 'counted', false);
  end if;
  v_plan := public.current_plan(v_uid);
  -- plans without AI (Basic): refuse outright, no top-up credits either
  if v_plan <> 'free' and not public._plan_has_ai(v_plan) then
    return jsonb_build_object('ok', false, 'no_ai', true, 'used', 0, 'limit', 0, 'left', 0, 'pool', false, 'trial_ended', false);
  end if;
  select a.agency_id, a.owner_id, a.ai_pool into v_ag, v_owner, v_pool from public._agency_sub(v_uid) a;

  if v_ag is not null then
    v_lim := v_pool;
    if v_pool is null then
      v_ok := true;
    else
      select coalesce(sum(u.used), 0) into v_used
        from public.ai_usage u
        join public.agency_members m on m.user_id = u.user_id and m.agency_id = v_ag
        where u.day >= date_trunc('month', public._ai_today())::date;
      v_ok := v_used < v_pool;
      v_left := greatest(v_pool - v_used - 1, 0);
    end if;
  else
    select ai_daily_messages into v_lim from public.plan_limits where plan = v_plan;
    if v_lim is null then
      v_ok := true;
    else
      select coalesce((select used from public.ai_usage where user_id = v_uid and day = public._ai_today()), 0)
        into v_used;
      v_ok := v_used < v_lim;
      v_left := greatest(v_lim - v_used - 1, 0);
    end if;
  end if;

  if not v_ok and v_plan <> 'free' then
    select c.id into v_credit from public.ai_credits c
      where c.user_id in (v_uid, coalesce(v_owner, v_uid)) and c.remaining > 0 and c.expires_at > now()
      order by c.expires_at limit 1 for update skip locked;
    if v_credit is not null then
      update public.ai_credits set remaining = remaining - 1 where id = v_credit;
      v_ok := true; v_kind := 'credit';
      select coalesce(sum(remaining), 0) into v_left from public.ai_credits
        where user_id in (v_uid, coalesce(v_owner, v_uid)) and remaining > 0 and expires_at > now();
    end if;
  end if;

  if not v_ok then
    return jsonb_build_object('ok', false, 'used', v_used, 'limit', v_lim, 'left', 0,
      'pool', v_ag is not null, 'trial_ended', v_plan = 'free');
  end if;

  insert into public.ai_usage as u (user_id, day, used, by_kind)
    values (v_uid, public._ai_today(), 1, jsonb_build_object(v_kind, 1))
  on conflict (user_id, day) do update
    set used = u.used + 1,
        by_kind = u.by_kind || jsonb_build_object(v_kind, coalesce((u.by_kind->>v_kind)::int, 0) + 1);

  return jsonb_build_object('ok', true, 'counted', true, 'limit', v_lim, 'left', v_left,
    'pool', v_ag is not null, 'credit', v_kind = 'credit');
end $function$;

CREATE OR REPLACE FUNCTION public.start_trial(p_plan text, p_seats integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); s record; v_seats int;
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if p_plan not in ('basic','pro','team','business') then return jsonb_build_object('ok',false,'error','bad_plan'); end if;
  if p_plan in ('team','business') and p_seats is not null then
    select greatest(team_seats, least(p_seats, 100)) into v_seats from plan_limits where plan = p_plan;
  end if;
  select * into s from subscriptions where user_id = uid;
  if found and s.status = 'trialing' and s.current_period_end > now() then
    update subscriptions set plan = p_plan, seats = v_seats, updated_at = now() where user_id = uid;
    return jsonb_build_object('ok',true,'plan',p_plan,'trial_end',s.current_period_end,'switched',true);
  end if;
  if found and s.status = 'active' and (s.current_period_end is null or s.current_period_end > now()) then
    return jsonb_build_object('ok',false,'error','already_subscribed'); end if;
  if found and s.trial_end is not null then
    return jsonb_build_object('ok',false,'error','trial_used'); end if;
  insert into subscriptions(user_id,plan,status,billing_cycle,trial_end,current_period_end,provider,seats)
    values (uid,p_plan,'trialing','monthly',now()+interval '14 days',now()+interval '14 days','trial',v_seats)
  on conflict (user_id) do update set plan=excluded.plan, status='trialing', seats=excluded.seats,
    trial_end=excluded.trial_end, current_period_end=excluded.current_period_end, provider='trial', updated_at=now();
  return jsonb_build_object('ok',true,'plan',p_plan,'trial_end',(now()+interval '14 days'));
end $function$;

CREATE OR REPLACE FUNCTION public._price_for(p_kind text, p_ref jsonb, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl record; pk record; v_cycle text; v_seats int; v_amt numeric;
begin
  if p_kind = 'subscription' then
    v_cycle := coalesce(p_ref->>'cycle', 'monthly');
    select * into pl from plan_limits where plan = p_ref->>'plan' and plan in ('basic','pro','team','business');
    if not found or v_cycle not in ('monthly','yearly') then raise exception 'bad_plan'; end if;
    v_amt := case when v_cycle = 'yearly' then pl.price_yearly else pl.price_monthly end;
    if pl.plan in ('team','business') then
      v_seats := coalesce(nullif(p_ref->>'seats','')::int, pl.team_seats);
      if v_seats < pl.team_seats or v_seats > 500 then raise exception 'bad_seats'; end if;
      v_amt := v_amt + (v_seats - pl.team_seats) * pl.extra_seat_price * (case when v_cycle = 'yearly' then 10 else 1 end);
    end if;
    return jsonb_build_object('amount', v_amt,
      'ref', jsonb_strip_nulls(jsonb_build_object('plan', pl.plan, 'cycle', v_cycle, 'seats', v_seats)));
  elsif p_kind = 'ai_credits' then
    select * into pk from ai_topup_packs where key = p_ref->>'pack' and active;
    if not found then raise exception 'pack_not_found'; end if;
    if public.current_plan(p_uid) = 'free' then raise exception 'subscription_required'; end if;
    if not public._plan_has_ai(public.current_plan(p_uid)) then raise exception 'ai_not_in_plan'; end if;
    return jsonb_build_object('amount', pk.price, 'ref', jsonb_build_object('pack', pk.key));
  end if;
  raise exception 'bad_kind';
end $function$;

CREATE OR REPLACE FUNCTION public.admin_set_subscription(p_uid uuid, p_plan text, p_status text, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not stay_is_admin() then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  if p_plan not in ('free','basic','pro','team','business') then return jsonb_build_object('ok',false,'error','bad_plan'); end if;
  insert into subscriptions(user_id,plan,status,current_period_end,provider)
    values (p_uid,p_plan,p_status,
      case when p_status in ('active','trialing') then now()+(p_days||' days')::interval else null end,'admin')
  on conflict (user_id) do update set plan=excluded.plan, status=excluded.status,
    current_period_end=excluded.current_period_end, provider='admin', updated_at=now();
  return jsonb_build_object('ok',true);
end $function$;
