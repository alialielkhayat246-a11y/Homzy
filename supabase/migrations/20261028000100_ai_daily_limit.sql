-- Daily AI message allowance per plan (Gemini is paid per use).
-- plan_limits.ai_daily_messages: NULL = unlimited. Usage is counted per broker
-- per Cairo day for every plan (also unlimited ones) so real cost can be measured.

alter table public.plan_limits add column if not exists ai_daily_messages int
  check (ai_daily_messages is null or ai_daily_messages >= 0);
update public.plan_limits set ai_daily_messages = 40 where plan = 'pro';

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  used int not null default 0,
  by_kind jsonb not null default '{}'::jsonb,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
drop policy if exists ai_usage_own_read on public.ai_usage;
create policy ai_usage_own_read on public.ai_usage for select to authenticated
  using (user_id = auth.uid() or public.is_admin_user());
revoke insert, update, delete on public.ai_usage from anon, authenticated;

create or replace function public._ai_today() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'Africa/Cairo')::date;
$$;

-- Counts one AI message for the signed-in broker. Returns
-- {ok, used, limit, left}; ok=false means today's allowance is used up
-- (nothing is counted then).
create or replace function public.ai_consume(p_kind text default 'chat')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_lim int;
  v_used int;
  v_kind text := left(coalesce(nullif(p_kind, ''), 'chat'), 20);
begin
  if v_uid is null then
    return jsonb_build_object('ok', true, 'counted', false);
  end if;
  select ai_daily_messages into v_lim from public.plan_limits
    where plan = public.current_plan(v_uid);
  if v_lim is not null and v_lim <= 0 then
    return jsonb_build_object('ok', false, 'used', 0, 'limit', v_lim, 'left', 0);
  end if;

  insert into public.ai_usage as u (user_id, day, used, by_kind)
    values (v_uid, public._ai_today(), 1, jsonb_build_object(v_kind, 1))
  on conflict (user_id, day) do update
    set used = u.used + 1,
        by_kind = u.by_kind || jsonb_build_object(v_kind, coalesce((u.by_kind->>v_kind)::int, 0) + 1)
    where v_lim is null or u.used < v_lim
  returning used into v_used;

  if v_used is null then
    return jsonb_build_object('ok', false, 'used', v_lim, 'limit', v_lim, 'left', 0);
  end if;
  return jsonb_build_object('ok', true, 'counted', true, 'used', v_used, 'limit', v_lim,
    'left', case when v_lim is null then null else greatest(v_lim - v_used, 0) end);
end $$;

-- Today's usage for the signed-in broker (for the UI).
create or replace function public.ai_usage_today()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'used', coalesce((select used from public.ai_usage where user_id = auth.uid() and day = public._ai_today()), 0),
    'limit', (select ai_daily_messages from public.plan_limits where plan = public.current_plan(auth.uid())));
$$;

revoke execute on function public.ai_consume(text), public.ai_usage_today(), public._ai_today() from public, anon;
grant execute on function public.ai_consume(text), public.ai_usage_today() to authenticated;
