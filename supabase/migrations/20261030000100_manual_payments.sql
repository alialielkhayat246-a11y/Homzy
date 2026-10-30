-- Manual payments (InstaPay / mobile wallet / bank transfer) until a card gateway
-- is live: the broker pays Homzy directly, submits the transfer reference (and an
-- optional screenshot), an admin approves, and the SAME settlement code as the
-- gateway activates the subscription / top-up.

-- 1) Where to pay (one row, edited by admins, readable by everyone).
create table if not exists public.manual_pay_settings (
  id int primary key default 1 check (id = 1),
  active boolean not null default false,
  instapay text, wallet text, bank text,
  note_ar text, note_en text,
  updated_at timestamptz not null default now()
);
insert into public.manual_pay_settings(id) values (1) on conflict do nothing;
alter table public.manual_pay_settings enable row level security;
drop policy if exists mps_read on public.manual_pay_settings;
create policy mps_read on public.manual_pay_settings for select to anon, authenticated using (true);
drop policy if exists mps_admin_write on public.manual_pay_settings;
create policy mps_admin_write on public.manual_pay_settings for update to authenticated
  using (public.is_admin_user()) with check (public.is_admin_user());

-- 2) Payment requests.
create table if not exists public.manual_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('subscription','ai_credits')),
  ref jsonb not null,
  amount numeric not null check (amount > 0),
  method text not null check (method in ('instapay','wallet','bank')),
  reference text not null,
  proof_path text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  intent_id uuid,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid
);
create index if not exists manual_payments_status_idx on public.manual_payments(status, created_at desc);
alter table public.manual_payments enable row level security;
drop policy if exists mp_own_read on public.manual_payments;
create policy mp_own_read on public.manual_payments for select to authenticated
  using (user_id = auth.uid() or public.is_admin_user());
revoke insert, update, delete on public.manual_payments from anon, authenticated;

-- 3) Private bucket for transfer screenshots: users write/read their own folder, admins read all.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
drop policy if exists payproof_insert_own on storage.objects;
create policy payproof_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists payproof_read on storage.objects;
create policy payproof_read on storage.objects for select to authenticated
  using (bucket_id = 'payment-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin_user()));

-- 4) Server-side price (same rules as backend/payments.py — never trust the client).
create or replace function public._price_for(p_kind text, p_ref jsonb, p_uid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pl record; pk record; v_cycle text; v_seats int; v_amt numeric;
begin
  if p_kind = 'subscription' then
    v_cycle := coalesce(p_ref->>'cycle', 'monthly');
    select * into pl from plan_limits where plan = p_ref->>'plan' and plan in ('pro','team','business');
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
    return jsonb_build_object('amount', pk.price, 'ref', jsonb_build_object('pack', pk.key));
  end if;
  raise exception 'bad_kind';
end $$;
revoke execute on function public._price_for(text, jsonb, uuid) from public, anon, authenticated;

-- 5) Settlement shared by the gateway webhook and manual approval.
create or replace function public._pay_settle_core(p_intent uuid, p_provider_ref text, p_provider text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pi record; bk record; cur record; pk record; v_plan text; v_cycle text; v_seats int;
        v_start timestamptz; v_end timestamptz; v_amt numeric; v_bid uuid;
begin
  select * into pi from pay_intents where id = p_intent;
  if not found then return jsonb_build_object('ok',false,'error','intent_not_found'); end if;
  if pi.status = 'paid' then return jsonb_build_object('ok',true,'already',true); end if;
  update pay_intents set status='paid', provider_order_id=coalesce(p_provider_ref,provider_order_id), paid_at=now() where id=p_intent;

  if pi.kind = 'booking' then
    v_bid := (pi.ref->>'booking_id')::uuid;
    select * into bk from stay_bookings where id = v_bid;
    if found and bk.status = 'payment_pending' then
      insert into stay_payments(booking_id,provider,provider_ref,method,amount,currency,status)
        values (v_bid,p_provider,p_provider_ref,p_provider,bk.total_amount,bk.currency,'paid');
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
      values (pi.user_id,v_plan,'active',v_cycle,v_end,p_provider,p_provider_ref,v_seats)
    on conflict (user_id) do update set plan=excluded.plan, status='active',
      billing_cycle=excluded.billing_cycle, current_period_end=excluded.current_period_end,
      provider=excluded.provider, provider_ref=excluded.provider_ref, seats=excluded.seats, updated_at=now();
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
    insert into wallet_transactions(broker_id,amount,kind,note) values (pi.user_id,v_amt,'topup',initcap(p_provider)||' top-up');
  end if;

  return jsonb_build_object('ok',true,'kind',pi.kind);
end $$;
revoke execute on function public._pay_settle_core(uuid, text, text) from public, anon, authenticated;

create or replace function public.pay_settle(p_key text, p_intent uuid, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden'; end if;
  return public._pay_settle_core(p_intent, p_provider_ref, 'paymob');
end $$;

-- 6) Broker: submit a manual payment.
create or replace function public.manual_pay_request(p_kind text, p_ref jsonb, p_method text,
                                                     p_reference text, p_proof text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_price jsonb; v_id uuid;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if not (select active from manual_pay_settings where id = 1) then
    return jsonb_build_object('ok',false,'error','manual_disabled'); end if;
  if p_method not in ('instapay','wallet','bank') then return jsonb_build_object('ok',false,'error','bad_method'); end if;
  if length(trim(coalesce(p_reference,''))) < 3 or length(p_reference) > 80 then
    return jsonb_build_object('ok',false,'error','bad_reference'); end if;
  if p_proof is not null and split_part(p_proof, '/', 1) <> v_uid::text then
    return jsonb_build_object('ok',false,'error','bad_proof'); end if;
  if (select count(*) from manual_payments where user_id = v_uid and status = 'pending') >= 3 then
    return jsonb_build_object('ok',false,'error','too_many_pending'); end if;
  begin
    v_price := public._price_for(p_kind, p_ref, v_uid);
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm);
  end;
  insert into manual_payments(user_id,kind,ref,amount,method,reference,proof_path)
    values (v_uid,p_kind,v_price->'ref',(v_price->>'amount')::numeric,p_method,trim(p_reference),p_proof)
    returning id into v_id;
  insert into crm_notifications(user_id,type,title,body,data)
    select p.id,'manual_payment','طلب دفع جديد',
           'طلب دفع '||(v_price->>'amount')||' ج.م بانتظار المراجعة',jsonb_build_object('payment_id',v_id)
    from profiles p where p.is_admin;
  return jsonb_build_object('ok',true,'id',v_id,'amount',(v_price->>'amount')::numeric);
end $$;
revoke execute on function public.manual_pay_request(text,jsonb,text,text,text) from public, anon;
grant execute on function public.manual_pay_request(text,jsonb,text,text,text) to authenticated;

-- 7) Admin: list + approve / reject.
create or replace function public.admin_manual_pay_list(p_status text default 'pending')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin_user() then raise exception 'Not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(r order by r->>'created_at' desc) from (
    select jsonb_build_object('id',m.id,'kind',m.kind,'ref',m.ref,'amount',m.amount,'method',m.method,
      'reference',m.reference,'proof_path',m.proof_path,'status',m.status,'admin_note',m.admin_note,
      'created_at',m.created_at,'decided_at',m.decided_at,
      'name',p.full_name,'phone',p.phone,'email',p.email,'company',p.company,
      'current_plan',public.current_plan(m.user_id)) r
    from manual_payments m left join profiles p on p.id = m.user_id
    where p_status = 'all' or m.status = p_status
    order by m.created_at desc limit 200) s), '[]'::jsonb);
end $$;
revoke execute on function public.admin_manual_pay_list(text) from public, anon;
grant execute on function public.admin_manual_pay_list(text) to authenticated;

create or replace function public.admin_manual_pay_decide(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m record; v_intent uuid; v_res jsonb;
begin
  if not public.is_admin_user() then raise exception 'Not allowed' using errcode = '42501'; end if;
  select * into m from manual_payments where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if m.status <> 'pending' then return jsonb_build_object('ok',false,'error','already_decided'); end if;
  if p_approve then
    insert into pay_intents(user_id, kind, ref, amount, provider) values (m.user_id, m.kind, m.ref, m.amount, 'manual') returning id into v_intent;
    v_res := public._pay_settle_core(v_intent, 'manual:' || m.method || ':' || m.reference, 'manual');
    update manual_payments set status='approved', intent_id=v_intent, admin_note=p_note, decided_at=now(), decided_by=auth.uid() where id=p_id;
    insert into crm_notifications(user_id,type,title,body,data) values (m.user_id,'payment_approved','تم تأكيد الدفع ✅',
      case when m.kind='subscription' then 'اشتراكك اتفعّل — شكرًا لثقتك في Homzy.' else 'رصيد رسايل الذكاء الاصطناعي اتضاف لحسابك.' end,
      jsonb_build_object('payment_id',p_id));
    return jsonb_build_object('ok',true,'settle',v_res);
  else
    update manual_payments set status='rejected', admin_note=p_note, decided_at=now(), decided_by=auth.uid() where id=p_id;
    insert into crm_notifications(user_id,type,title,body,data) values (m.user_id,'payment_rejected','مقدرناش نأكّد الدفع',
      coalesce(nullif(p_note,''),'راجع بيانات التحويل وابعت الطلب تاني، أو كلّمنا.'), jsonb_build_object('payment_id',p_id));
    return jsonb_build_object('ok',true,'rejected',true);
  end if;
end $$;
revoke execute on function public.admin_manual_pay_decide(uuid, boolean, text) from public, anon;
grant execute on function public.admin_manual_pay_decide(uuid, boolean, text) to authenticated;
