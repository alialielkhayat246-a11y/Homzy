-- Cancelling no longer cuts access immediately: a cancelled subscription keeps
-- working until the end of the period that was already paid (or the trial end).
create or replace function public._sub_live(s public.subscriptions)
returns boolean language sql stable as $$
  select (s.status in ('active','trialing') and (s.current_period_end is null or s.current_period_end > now()))
      or (s.status = 'canceled' and s.current_period_end > now());
$$;

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
    and s.plan in ('team','business','enterprise') and public._sub_live(s)
  order by pl.sort desc
  limit 1;
$$;
revoke execute on function public._agency_sub(uuid) from public, anon, authenticated;

create or replace function public.current_plan(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select plan from public._agency_sub(p_uid)),
    (select s.plan from public.subscriptions s where s.user_id = p_uid and public._sub_live(s)),
    'free');
$$;

create or replace function public.agency_seat_limit(p_agency uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare s record;
begin
  select sub.plan, sub.seats, pl.team_seats into s
  from public.agencies a
  join public.subscriptions sub on sub.user_id = a.owner_id
  join public.plan_limits pl on pl.plan = sub.plan
  where a.id = p_agency and sub.plan in ('team','business','enterprise') and public._sub_live(sub);
  if not found then return 1; end if;
  return coalesce(s.seats, s.team_seats);
end $$;
