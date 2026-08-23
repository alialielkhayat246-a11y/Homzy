-- Broker registration + phone/OTP auth support.
-- profiles.role is constrained to ('user','broker'); brokers additionally have
-- company + commercial_reg. The client/broker header switch shows only for
-- role='broker'; only brokers can buy leads.

alter table public.profiles add column if not exists commercial_reg text;

-- Populate role/phone/company/commercial_reg from signup metadata (passed via
-- supabase-js signInWithOtp options.data). Default role = 'user' (matches the
-- profiles_role_check constraint: role in ('user','broker')).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
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
  return new;
end; $$;

-- Only brokers can unlock/buy a lead.
create or replace function public.unlock_lead(p_session text)
returns json language plpgsql security definer set search_path = public as $$
declare v_broker uuid := auth.uid(); v_price numeric; v_bal numeric; v_phone text;
begin
  if v_broker is null then raise exception 'not_authenticated'; end if;
  if not exists(select 1 from profiles where id = v_broker and role = 'broker') then
    raise exception 'not_broker';
  end if;
  select phone into v_phone from web_leads where session_id = p_session;
  if v_phone is null then raise exception 'lead_not_found'; end if;
  if exists(select 1 from lead_unlocks where broker_id=v_broker and lead_session=p_session) then
    return json_build_object('phone', v_phone, 'already', true);
  end if;
  select price into v_price from lead_market_config where id=1;
  insert into broker_wallets(broker_id) values (v_broker) on conflict (broker_id) do nothing;
  select balance into v_bal from broker_wallets where broker_id=v_broker for update;
  if coalesce(v_bal,0) < v_price then raise exception 'insufficient_balance'; end if;
  update broker_wallets set balance=balance-v_price, updated_at=now() where broker_id=v_broker;
  insert into lead_unlocks(broker_id, lead_session, price) values (v_broker, p_session, v_price);
  insert into wallet_transactions(broker_id, amount, kind, note) values (v_broker, -v_price, 'spend', 'unlock '||p_session);
  return json_build_object('phone', v_phone, 'already', false);
end; $$;
grant execute on function public.unlock_lead(text) to authenticated;
