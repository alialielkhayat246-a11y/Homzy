-- Leads marketplace: brokers browse leads (phone masked), and spend wallet
-- credit to unlock (reveal) a lead's phone.
--
-- Privacy: brokers CANNOT read web_leads directly (revoked). They read the
-- masked `leads_market` view; the real number is returned only by unlock_lead()
-- after a paid unlock, which deducts wallet credit and records the purchase.

alter table public.web_leads add column if not exists req jsonb;

create table if not exists public.broker_wallets(
  broker_id  uuid primary key references auth.users(id) on delete cascade,
  balance    numeric not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.broker_wallets enable row level security;
drop policy if exists bw_self_select on public.broker_wallets;
create policy bw_self_select on public.broker_wallets for select to authenticated using (broker_id = auth.uid());

create table if not exists public.lead_unlocks(
  id bigint generated always as identity primary key,
  broker_id uuid not null references auth.users(id) on delete cascade,
  lead_session text not null references public.web_leads(session_id) on delete cascade,
  price numeric not null default 0,
  created_at timestamptz not null default now(),
  unique(broker_id, lead_session)
);
alter table public.lead_unlocks enable row level security;
drop policy if exists lu_self_select on public.lead_unlocks;
create policy lu_self_select on public.lead_unlocks for select to authenticated using (broker_id = auth.uid());

create table if not exists public.wallet_transactions(
  id bigint generated always as identity primary key,
  broker_id uuid not null references auth.users(id) on delete cascade,
  amount numeric not null, kind text not null, note text,
  created_at timestamptz not null default now()
);
alter table public.wallet_transactions enable row level security;
drop policy if exists wt_self_select on public.wallet_transactions;
create policy wt_self_select on public.wallet_transactions for select to authenticated using (broker_id = auth.uid());

create table if not exists public.lead_market_config(id int primary key default 1 check (id = 1), price numeric not null default 50);
insert into public.lead_market_config(id, price) values (1, 50) on conflict (id) do nothing;

create or replace function public.mask_phone(p text) returns text language sql immutable as $$
  select case when p is null or length(regexp_replace(p,'\D','','g')) < 8 then null
    else left(regexp_replace(p,'\s','','g'),4) || '•••••' || right(regexp_replace(p,'\s','','g'),3) end;
$$;

revoke select on public.web_leads from authenticated;

drop view if exists public.leads_market;
create view public.leads_market with (security_invoker = false) as
  select l.session_id, l.name, l.context, l.req, l.lang, l.created_at,
    exists(select 1 from public.lead_unlocks u where u.lead_session=l.session_id and u.broker_id=auth.uid()) as unlocked,
    case when exists(select 1 from public.lead_unlocks u where u.lead_session=l.session_id and u.broker_id=auth.uid())
         then l.phone else public.mask_phone(l.phone) end as phone
  from public.web_leads l
  where l.phone is not null and length(regexp_replace(l.phone,'\D','','g')) >= 8;
grant select on public.leads_market to authenticated;

create or replace function public.unlock_lead(p_session text)
returns json language plpgsql security definer set search_path = public as $$
declare v_broker uuid := auth.uid(); v_price numeric; v_bal numeric; v_phone text;
begin
  if v_broker is null then raise exception 'not_authenticated'; end if;
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

create or replace function public.admin_topup(p_broker uuid, p_amount numeric, p_note text default 'manual')
returns numeric language plpgsql security definer set search_path = public as $$
declare v_bal numeric;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and is_admin=true) then raise exception 'not_admin'; end if;
  insert into broker_wallets(broker_id) values (p_broker) on conflict (broker_id) do nothing;
  update broker_wallets set balance=balance+p_amount, updated_at=now() where broker_id=p_broker returning balance into v_bal;
  insert into wallet_transactions(broker_id, amount, kind, note) values (p_broker, p_amount, 'topup', p_note);
  return v_bal;
end; $$;
grant execute on function public.admin_topup(uuid, numeric, text) to authenticated;

-- lead-save RPC also stores structured requirements now
drop function if exists public.upsert_web_lead(text,text,text,text,jsonb,text);
create or replace function public.upsert_web_lead(
  p_session_id text, p_name text, p_phone text, p_context text,
  p_messages jsonb, p_lang text, p_req jsonb default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_session_id is null or length(p_session_id) < 4 then raise exception 'invalid session'; end if;
  insert into public.web_leads (session_id, name, phone, context, messages, lang, req, updated_at)
  values (p_session_id, p_name, p_phone, p_context, coalesce(p_messages,'[]'::jsonb), p_lang, p_req, now())
  on conflict (session_id) do update set
    name=coalesce(excluded.name, web_leads.name), phone=coalesce(excluded.phone, web_leads.phone),
    context=coalesce(excluded.context, web_leads.context), messages=excluded.messages,
    lang=excluded.lang, req=coalesce(excluded.req, web_leads.req), updated_at=now();
end; $$;
revoke all on function public.upsert_web_lead(text,text,text,text,jsonb,text,jsonb) from public;
grant execute on function public.upsert_web_lead(text,text,text,text,jsonb,text,jsonb) to anon, authenticated;
