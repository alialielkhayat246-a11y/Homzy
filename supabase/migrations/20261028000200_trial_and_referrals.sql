-- No more free broker plan: every broker gets a 14-day Pro trial, then must
-- subscribe. Plus a referral programme: a broker whose invitee pays for a
-- subscription earns one free month (max 12 per year).

-- 1) Trial = 14 days (was 3 months). Existing trials keep their end date.
create or replace function public.start_trial(p_plan text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if p_plan not in ('pro','business') then return jsonb_build_object('ok',false,'error','bad_plan'); end if;
  if exists(select 1 from subscriptions where user_id=uid and status in ('active','trialing')
            and (current_period_end is null or current_period_end>now())) then
    return jsonb_build_object('ok',false,'error','already_subscribed'); end if;
  if exists(select 1 from subscriptions where user_id=uid and trial_end is not null) then
    return jsonb_build_object('ok',false,'error','trial_used'); end if;
  insert into subscriptions(user_id,plan,status,billing_cycle,trial_end,current_period_end,provider)
    values (uid,p_plan,'trialing','monthly',now()+interval '14 days',now()+interval '14 days','trial')
  on conflict (user_id) do update set plan=excluded.plan, status='trialing',
    trial_end=excluded.trial_end, current_period_end=excluded.current_period_end, provider='trial', updated_at=now();
  return jsonb_build_object('ok',true,'plan',p_plan,'trial_end',(now()+interval '14 days'));
end $$;

-- 2) Auto-start the trial whenever an account becomes a broker (sign-up as a
--    broker, or switching role later). Only if the user never had a subscription.
create or replace function public._auto_broker_trial()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'broker' and (tg_op = 'INSERT' or old.role is distinct from 'broker') then
    insert into public.subscriptions(user_id,plan,status,billing_cycle,trial_end,current_period_end,provider)
      values (new.id,'pro','trialing','monthly',now()+interval '14 days',now()+interval '14 days','trial')
    on conflict (user_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trg_auto_broker_trial on public.profiles;
create trigger trg_auto_broker_trial after insert or update of role on public.profiles
  for each row execute function public._auto_broker_trial();

-- Brokers who are on the old free plan today get the same 14 days, from now.
insert into public.subscriptions(user_id,plan,status,billing_cycle,trial_end,current_period_end,provider)
  select p.id,'pro','trialing','monthly',now()+interval '14 days',now()+interval '14 days','trial'
  from public.profiles p where p.role='broker'
    and not exists(select 1 from public.subscriptions s where s.user_id=p.id)
on conflict (user_id) do nothing;

-- 3) "free" now means "trial ended": hidden from pricing, no AI, no new units/clients.
update public.plan_limits
   set active=false, max_listings=0, max_clients=0, ai_daily_messages=0,
       name_ar='انتهت التجربة', name_en='Trial ended'
 where plan='free';

-- 4) Referrals.
alter table public.profiles add column if not exists referral_code text
  generated always as (upper(substr(md5(id::text), 1, 7))) stored;
create unique index if not exists profiles_referral_code_key on public.profiles(referral_code);

create table if not exists public.referrals (
  referred_id uuid primary key references auth.users(id) on delete cascade,
  referrer_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  rewarded_at timestamptz,
  check (referred_id <> referrer_id)
);
create index if not exists referrals_referrer_idx on public.referrals(referrer_id);
alter table public.referrals enable row level security;
drop policy if exists referrals_admin_read on public.referrals;
create policy referrals_admin_read on public.referrals for select to authenticated
  using (public.is_admin_user());
revoke insert, update, delete on public.referrals from anon, authenticated;

-- Record who invited a new account (sign-up metadata "ref" = referral code).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ref uuid;
begin
  insert into public.profiles (id, full_name, email, phone, role, company, commercial_reg)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    coalesce(new.phone, new.raw_user_meta_data->>'phone'),
    case when new.raw_user_meta_data->>'role' = 'broker' then 'broker' else 'user' end,
    new.raw_user_meta_data->>'company',
    new.raw_user_meta_data->>'commercial_reg')
  on conflict (id) do nothing;
  if coalesce(new.raw_user_meta_data->>'ref','') <> '' then
    select id into v_ref from public.profiles
      where referral_code = upper(left(new.raw_user_meta_data->>'ref', 12)) and id <> new.id;
    if v_ref is not null then
      insert into public.referrals(referred_id, referrer_id) values (new.id, v_ref)
      on conflict do nothing;
    end if;
  end if;
  return new;
end; $$;

-- The signed-in broker's referral link stats.
create or replace function public.my_referrals()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', (select referral_code from public.profiles where id = auth.uid()),
    'signed_up', (select count(*) from public.referrals where referrer_id = auth.uid()),
    'paid', (select count(*) from public.referrals where referrer_id = auth.uid() and paid_at is not null),
    'months_earned', (select count(*) from public.referrals where referrer_id = auth.uid() and rewarded_at is not null));
$$;
revoke execute on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;

-- 5) Payments: a paid period now extends from the current end (paying during a
--    trial or after a referral month no longer loses days), and the first paid
--    subscription of an invited broker gives the inviter one free month.
create or replace function public._grant_referral_month(p_referred uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; s record;
begin
  select * into r from public.referrals where referred_id = p_referred for update;
  if not found or r.rewarded_at is not null then return; end if;
  update public.referrals set paid_at = coalesce(paid_at, now()) where referred_id = p_referred;
  if (select count(*) from public.referrals where referrer_id = r.referrer_id
        and rewarded_at > now() - interval '365 days') >= 12 then return; end if;
  select * into s from public.subscriptions where user_id = r.referrer_id;
  if found and s.status in ('active','trialing') and s.current_period_end > now() then
    update public.subscriptions set current_period_end = current_period_end + interval '30 days', updated_at = now()
      where user_id = r.referrer_id;
  else
    insert into public.subscriptions(user_id,plan,status,billing_cycle,current_period_end,provider)
      values (r.referrer_id,'pro','active','monthly',now()+interval '30 days','referral')
    on conflict (user_id) do update set plan='pro', status='active', billing_cycle='monthly',
      current_period_end=now()+interval '30 days', provider='referral', updated_at=now();
  end if;
  update public.referrals set rewarded_at = now() where referred_id = p_referred;
end $$;
revoke execute on function public._grant_referral_month(uuid) from public, anon, authenticated;

create or replace function public.pay_settle(p_key text, p_intent uuid, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pi record; bk record; cur record; v_plan text; v_cycle text; v_start timestamptz; v_end timestamptz; v_amt numeric; v_bid uuid;
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
    select * into cur from subscriptions where user_id = pi.user_id;
    v_start := now();
    if found and cur.plan = v_plan and cur.status in ('active','trialing') and cur.current_period_end > now() then
      v_start := cur.current_period_end;
    end if;
    v_end := v_start + case when v_cycle='yearly' then interval '1 year' else interval '1 month' end;
    insert into subscriptions(user_id,plan,status,billing_cycle,current_period_end,provider,provider_ref)
      values (pi.user_id,v_plan,'active',v_cycle,v_end,'paymob',p_provider_ref)
    on conflict (user_id) do update set plan=excluded.plan, status='active',
      billing_cycle=excluded.billing_cycle, current_period_end=excluded.current_period_end,
      provider='paymob', provider_ref=excluded.provider_ref, updated_at=now();
    perform public._grant_referral_month(pi.user_id);

  elsif pi.kind = 'wallet' then
    v_amt := (pi.ref->>'amount')::numeric;
    insert into broker_wallets(broker_id,balance,updated_at) values (pi.user_id,v_amt,now())
      on conflict (broker_id) do update set balance = broker_wallets.balance + v_amt, updated_at=now();
    insert into wallet_transactions(broker_id,amount,kind,note) values (pi.user_id,v_amt,'topup','Paymob top-up');
  end if;

  return jsonb_build_object('ok',true,'kind',pi.kind);
end $$;
