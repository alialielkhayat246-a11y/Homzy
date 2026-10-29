-- Launch plan line-up + everything the team plans promise:
--   Pro 599 · Team 1,999 (5 seats) · Company 4,999 (15 seats) · Enterprise (contact)
--   * agency members inherit the owner's team plan (current_plan)
--   * seat limits enforced on agency_members
--   * shared monthly AI pool per agency (seats × ai_monthly_per_seat)
--   * AI message top-ups (500 for 199 EGP, 30 days)
--   * clients created by an agency member belong to the agency
--   * manager performance report (agency_performance)

-- 1) Plans --------------------------------------------------------------------
alter table public.plan_limits add column if not exists extra_seat_price numeric not null default 0;
alter table public.plan_limits add column if not exists ai_monthly_per_seat int
  check (ai_monthly_per_seat is null or ai_monthly_per_seat >= 0);
alter table public.plan_limits add column if not exists contact_only boolean not null default false;

update public.plan_limits set sort = 0 where plan = 'free';

update public.plan_limits set name_ar='احترافي', name_en='Pro', price_monthly=599, price_yearly=5990,
  team_seats=1, extra_seat_price=0, ai_daily_messages=40, ai_monthly_per_seat=null, sort=2, active=true,
  max_listings=null, max_clients=null, leads_included=0,
  features='{"voice":true,"ai_sales":true,"branded_pdf":true,"logo_watermark":true,"analytics":true,"featured":false,"team":false}'
where plan='pro';

insert into public.plan_limits(plan,name_ar,name_en,price_monthly,price_yearly,max_listings,max_clients,leads_included,
  stays_commission_rate,team_seats,features,sort,active,ai_daily_messages,extra_seat_price,ai_monthly_per_seat,contact_only)
select 'team','فريق','Team',1999,19990,null,null,0,stays_commission_rate,5,
  '{"voice":true,"ai_sales":true,"branded_pdf":true,"logo_watermark":true,"analytics":true,"featured":false,"team":true}',
  3,true,null,349,900,false
from public.plan_limits where plan='pro'
on conflict (plan) do nothing;

update public.plan_limits set name_ar='شركة', name_en='Company', price_monthly=4999, price_yearly=49990,
  team_seats=15, extra_seat_price=299, ai_daily_messages=null, ai_monthly_per_seat=900, sort=4, active=true,
  max_listings=null, max_clients=null, leads_included=0, contact_only=false,
  features='{"voice":true,"ai_sales":true,"branded_pdf":true,"logo_watermark":true,"analytics":true,"featured":false,"team":true}'
where plan='business';

insert into public.plan_limits(plan,name_ar,name_en,price_monthly,price_yearly,max_listings,max_clients,leads_included,
  stays_commission_rate,team_seats,features,sort,active,ai_daily_messages,extra_seat_price,ai_monthly_per_seat,contact_only)
select 'enterprise','مؤسسات','Enterprise',0,0,null,null,0,stays_commission_rate,30,
  '{"voice":true,"ai_sales":true,"branded_pdf":true,"logo_watermark":true,"analytics":true,"featured":false,"team":true}',
  5,true,null,0,600,true
from public.plan_limits where plan='pro'
on conflict (plan) do nothing;

alter table public.subscriptions add column if not exists seats int check (seats is null or seats >= 1);

-- 2) Agency plan inheritance + seats ---------------------------------------------
-- The best team-type subscription among the agencies the user is an active member of.
create or replace function public._agency_sub(p_uid uuid)
returns table(agency_id uuid, owner_id uuid, plan text, seats int, ai_pool int)
language sql stable security definer set search_path = public as $$
  select a.id, a.owner_id, s.plan,
         coalesce(s.seats, pl.team_seats),
         case when pl.ai_monthly_per_seat is null then null
              else coalesce(s.seats, pl.team_seats,
                     (select count(*)::int from public.agency_members x where x.agency_id=a.id and x.status='active'))
                   * pl.ai_monthly_per_seat end
  from public.agency_members m
  join public.agencies a on a.id = m.agency_id
  join public.subscriptions s on s.user_id = a.owner_id
  join public.plan_limits pl on pl.plan = s.plan
  where m.user_id = p_uid and m.status = 'active'
    and s.plan in ('team','business','enterprise')
    and s.status in ('active','trialing')
    and (s.current_period_end is null or s.current_period_end > now())
  order by pl.sort desc
  limit 1;
$$;
revoke execute on function public._agency_sub(uuid) from public, anon, authenticated;

create or replace function public.current_plan(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select plan from public._agency_sub(p_uid)),
    (select s.plan from public.subscriptions s
      where s.user_id = p_uid and s.status in ('active','trialing')
        and (s.current_period_end is null or s.current_period_end > now())),
    'free');
$$;

-- Active seats an agency may have (NULL = unlimited). No team plan = owner only.
create or replace function public.agency_seat_limit(p_agency uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare s record;
begin
  select sub.plan, sub.seats, pl.team_seats into s
  from public.agencies a
  join public.subscriptions sub on sub.user_id = a.owner_id
  join public.plan_limits pl on pl.plan = sub.plan
  where a.id = p_agency and sub.plan in ('team','business','enterprise')
    and sub.status in ('active','trialing')
    and (sub.current_period_end is null or sub.current_period_end > now());
  if not found then return 1; end if;
  return coalesce(s.seats, s.team_seats);
end $$;

create or replace function public._agency_seat_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_lim int; v_cnt int;
begin
  if new.status = 'active' and (tg_op = 'INSERT' or old.status is distinct from 'active'
                                or old.agency_id is distinct from new.agency_id) then
    v_lim := public.agency_seat_limit(new.agency_id);
    if v_lim is not null then
      select count(*) into v_cnt from public.agency_members
        where agency_id = new.agency_id and status = 'active' and user_id <> new.user_id;
      if v_cnt + 1 > v_lim then
        raise exception 'SEAT_LIMIT:%', v_lim using errcode = 'P0001';
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_agency_seat_guard on public.agency_members;
create trigger trg_agency_seat_guard before insert or update on public.agency_members
  for each row execute function public._agency_seat_guard();

-- Seats in use / allowed for the team page.
create or replace function public.agency_seats(p_agency uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'used', (select count(*) from public.agency_members where agency_id = p_agency and status = 'active'),
    'limit', public.agency_seat_limit(p_agency))
  where public.is_active_member(p_agency) or public.stay_is_admin();
$$;
revoke execute on function public.agency_seats(uuid) from public, anon;
grant execute on function public.agency_seats(uuid) to authenticated;

-- 3) Clients added by an agency member belong to the agency ---------------------
create or replace function public._client_default_agency()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.agency_id is null and auth.uid() is not null then
    new.agency_id := public.my_primary_agency();
  end if;
  return new;
end $$;
drop trigger if exists trg_client_default_agency on public.clients;
create trigger trg_client_default_agency before insert on public.clients
  for each row execute function public._client_default_agency();

-- 4) Trials: switching plan during an active trial keeps the same end date ------
create or replace function public.start_trial(p_plan text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if p_plan not in ('pro','team','business') then return jsonb_build_object('ok',false,'error','bad_plan'); end if;
  select * into s from subscriptions where user_id = uid;
  if found and s.status = 'trialing' and s.current_period_end > now() then
    update subscriptions set plan = p_plan, updated_at = now() where user_id = uid;
    return jsonb_build_object('ok',true,'plan',p_plan,'trial_end',s.current_period_end,'switched',true);
  end if;
  if found and s.status = 'active' and (s.current_period_end is null or s.current_period_end > now()) then
    return jsonb_build_object('ok',false,'error','already_subscribed'); end if;
  if found and s.trial_end is not null then
    return jsonb_build_object('ok',false,'error','trial_used'); end if;
  insert into subscriptions(user_id,plan,status,billing_cycle,trial_end,current_period_end,provider)
    values (uid,p_plan,'trialing','monthly',now()+interval '14 days',now()+interval '14 days','trial')
  on conflict (user_id) do update set plan=excluded.plan, status='trialing',
    trial_end=excluded.trial_end, current_period_end=excluded.current_period_end, provider='trial', updated_at=now();
  return jsonb_build_object('ok',true,'plan',p_plan,'trial_end',(now()+interval '14 days'));
end $$;

-- 5) AI top-ups -----------------------------------------------------------------
create table if not exists public.ai_topup_packs (
  key text primary key,
  messages int not null check (messages > 0),
  price numeric not null check (price > 0),
  valid_days int not null default 30,
  name_ar text, name_en text,
  active boolean not null default true
);
insert into public.ai_topup_packs(key,messages,price,valid_days,name_ar,name_en)
  values ('p500',500,199,30,'500 رسالة ذكاء اصطناعي','500 AI messages')
on conflict (key) do nothing;
alter table public.ai_topup_packs enable row level security;
drop policy if exists ai_topup_packs_read on public.ai_topup_packs;
create policy ai_topup_packs_read on public.ai_topup_packs for select to anon, authenticated using (active);

create table if not exists public.ai_credits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  pack text references public.ai_topup_packs(key),
  amount int not null,
  remaining int not null check (remaining >= 0),
  expires_at timestamptz not null,
  intent_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists ai_credits_user_idx on public.ai_credits(user_id, expires_at);
alter table public.ai_credits enable row level security;
drop policy if exists ai_credits_own_read on public.ai_credits;
create policy ai_credits_own_read on public.ai_credits for select to authenticated
  using (user_id = auth.uid() or public.is_admin_user());
revoke insert, update, delete on public.ai_credits from anon, authenticated;

alter table public.pay_intents drop constraint if exists pay_intents_kind_check;
alter table public.pay_intents add constraint pay_intents_kind_check
  check (kind = any (array['booking','subscription','wallet','ai_credits']));

-- 6) AI allowance: personal daily limit, or the agency's shared monthly pool;
--    when used up, top-up credits (own, then the agency owner's) are used.
create or replace function public.ai_consume(p_kind text default 'chat')
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.ai_usage_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_plan text; v_ag uuid; v_owner uuid; v_pool int; v_pool_used int;
begin
  if v_uid is null then return null; end if;
  v_plan := public.current_plan(v_uid);
  select a.agency_id, a.owner_id, a.ai_pool into v_ag, v_owner, v_pool from public._agency_sub(v_uid) a;
  if v_ag is not null then
    select coalesce(sum(u.used), 0) into v_pool_used from public.ai_usage u
      join public.agency_members m on m.user_id = u.user_id and m.agency_id = v_ag
      where u.day >= date_trunc('month', public._ai_today())::date;
  end if;
  return jsonb_build_object(
    'plan', v_plan,
    'used', coalesce((select used from public.ai_usage where user_id = v_uid and day = public._ai_today()), 0),
    'limit', case when v_ag is null then (select ai_daily_messages from public.plan_limits where plan = v_plan) end,
    'pool', v_ag is not null, 'pool_limit', v_pool, 'pool_used', v_pool_used,
    'credits', (select coalesce(sum(remaining), 0) from public.ai_credits
                where user_id in (v_uid, coalesce(v_owner, v_uid)) and remaining > 0 and expires_at > now()));
end $$;
revoke execute on function public.ai_consume(text), public.ai_usage_today() from public, anon;
grant execute on function public.ai_consume(text), public.ai_usage_today() to authenticated;

-- 7) Payments: seats + top-ups ----------------------------------------------------
create or replace function public.pay_settle(p_key text, p_intent uuid, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pi record; bk record; cur record; pk record; v_plan text; v_cycle text; v_seats int;
        v_start timestamptz; v_end timestamptz; v_amt numeric; v_bid uuid;
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden'; end if;
  select * into pi from pay_intents where id = p_intent;
  if not found then return jsonb_build_object('ok',false,'error','intent_not_found'); end if;
  if pi.status = 'paid' then return jsonb_build_object('ok',true,'already',true); end if;
  update pay_intents set status='paid', provider_order_id=coalesce(p_provider_ref,provider_order_id), paid_at=now() where id=p_intent;

  if pi.kind = 'booking' then
    v_bid := (pi.ref->>'booking_id')::uuid;
    select * into bk from stay_bookings where id = v_bid;
    if found and bk.status = 'payment_pending' then
      insert into stay_payments(booking_id,provider,provider_ref,method,amount,currency,status)
        values (v_bid,'paymob',p_provider_ref,'paymob',bk.total_amount,bk.currency,'paid');
      update stay_bookings set status='confirmed', updated_at=now() where id=v_bid;
      insert into stay_transactions(booking_id,kind,amount,currency,party,party_id,note) values
        (v_bid,'charge',bk.total_amount,bk.currency,'guest',bk.guest_id,'Booking charge'),
        (v_bid,'commission',bk.commission_amount,bk.currency,'homzy',null,'Homzy commission'),
        (v_bid,'host_earning',bk.host_net,bk.currency,'host',bk.host_id,'Host net earning');
      insert into stay_notifications(user_id,type,title,body,data) values
        (bk.host_id,'booking_confirmed','حجز جديد مؤكد','عندك حجز جديد مؤكد لوحدتك.',jsonb_build_object('booking_id',v_bid)),
        (bk.guest_id,'booking_confirmed','تم تأكيد الحجز','رحلتك اتأكدت — استمتع بإقامتك!',jsonb_build_object('booking_id',v_bid));
    end if;

  elsif pi.kind = 'subscription' then
    v_plan := pi.ref->>'plan'; v_cycle := coalesce(pi.ref->>'cycle','monthly');
    v_seats := nullif(pi.ref->>'seats','')::int;
    select * into cur from subscriptions where user_id = pi.user_id;
    v_start := now();
    if found and cur.plan = v_plan and cur.status in ('active','trialing') and cur.current_period_end > now() then
      v_start := cur.current_period_end;
    end if;
    v_end := v_start + case when v_cycle='yearly' then interval '1 year' else interval '1 month' end;
    insert into subscriptions(user_id,plan,status,billing_cycle,current_period_end,provider,provider_ref,seats)
      values (pi.user_id,v_plan,'active',v_cycle,v_end,'paymob',p_provider_ref,v_seats)
    on conflict (user_id) do update set plan=excluded.plan, status='active',
      billing_cycle=excluded.billing_cycle, current_period_end=excluded.current_period_end,
      provider='paymob', provider_ref=excluded.provider_ref, seats=excluded.seats, updated_at=now();
    perform public._grant_referral_month(pi.user_id);

  elsif pi.kind = 'ai_credits' then
    select * into pk from ai_topup_packs where key = pi.ref->>'pack';
    if found then
      insert into ai_credits(user_id,pack,amount,remaining,expires_at,intent_id)
        values (pi.user_id,pk.key,pk.messages,pk.messages,now() + make_interval(days => pk.valid_days),pi.id);
    end if;

  elsif pi.kind = 'wallet' then
    v_amt := (pi.ref->>'amount')::numeric;
    insert into broker_wallets(broker_id,balance,updated_at) values (pi.user_id,v_amt,now())
      on conflict (broker_id) do update set balance = broker_wallets.balance + v_amt, updated_at=now();
    insert into wallet_transactions(broker_id,amount,kind,note) values (pi.user_id,v_amt,'topup','Paymob top-up');
  end if;

  return jsonb_build_object('ok',true,'kind',pi.kind);
end $$;

-- 8) Manager performance report -------------------------------------------------
create or replace function public.agency_performance(p_agency uuid, p_since timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_perm(p_agency, 'report.view') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(r order by (r->>'won_value')::numeric desc, (r->>'leads_new')::int desc)
    from (
      select jsonb_build_object(
        'user_id', m.user_id,
        'name', coalesce(p.full_name, p.phone, p.email),
        'role_ar', ro.name_ar, 'role_en', ro.name_en, 'team', t.name,
        'leads_total', (select count(*) from public.clients c where c.agency_id = p_agency and c.deleted_at is null
                          and coalesce(c.assigned_to, c.owner_id) = m.user_id),
        'leads_new', (select count(*) from public.clients c where c.agency_id = p_agency and c.deleted_at is null
                          and coalesce(c.assigned_to, c.owner_id) = m.user_id and c.created_at >= p_since),
        'activities', (select count(*) from public.crm_lead_activities a
                          join public.clients c on c.id = a.lead_id and c.agency_id = p_agency
                          where a.actor_id = m.user_id and a.created_at >= p_since),
        'viewings', (select count(*) from public.crm_viewings v
                          join public.clients c on c.id = v.lead_id and c.agency_id = p_agency
                          where v.owner_id = m.user_id and v.created_at >= p_since),
        'deals_open', (select count(*) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status in ('open','negotiation','reservation')),
        'won', (select count(*) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status = 'won' and coalesce(d.actual_close::timestamptz, d.updated_at) >= p_since),
        'won_value', (select coalesce(sum(d.value), 0) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status = 'won' and coalesce(d.actual_close::timestamptz, d.updated_at) >= p_since),
        'ai_used', (select coalesce(sum(u.used), 0) from public.ai_usage u
                          where u.user_id = m.user_id and u.day >= p_since::date)
      ) as r
      from public.agency_members m
      left join public.profiles p on p.id = m.user_id
      left join public.roles ro on ro.id = m.role_id
      left join public.teams t on t.id = m.team_id
      where m.agency_id = p_agency and m.status = 'active'
    ) s), '[]'::jsonb);
end $$;
revoke execute on function public.agency_performance(uuid, timestamptz) from public, anon;
grant execute on function public.agency_performance(uuid, timestamptz) to authenticated;
