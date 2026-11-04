-- Team invite links: the company owner (or anyone with team.manage) creates a
-- link per role; a salesperson opens it, signs up with name/phone/password and
-- joins the company directly — as a broker, skipping the company-details and
-- plan steps (they use the company's plan). Seats are enforced by the existing
-- _agency_seat_guard trigger.

create table if not exists public.agency_invites (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null references public.agencies(id) on delete cascade,
  code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  role_key text not null default 'agent',
  team_id uuid references public.teams(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  uses int not null default 0
);
create index if not exists agency_invites_agency_idx on public.agency_invites(agency_id);
alter table public.agency_invites enable row level security;
drop policy if exists agency_invites_manage_read on public.agency_invites;
create policy agency_invites_manage_read on public.agency_invites for select to authenticated
  using (public.has_perm(agency_id, 'team.manage'));
revoke insert, update, delete on public.agency_invites from anon, authenticated;

-- Create a link (a new link for the same role replaces the old one).
create or replace function public.agency_create_invite(p_agency uuid, p_role_key text default 'agent', p_team uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if p_role_key = 'owner' or not exists(select 1 from public.roles where agency_id=p_agency and key=p_role_key) then
    raise exception 'Unknown role %', p_role_key; end if;
  if p_team is not null and not exists(select 1 from public.teams where id=p_team and agency_id=p_agency) then
    raise exception 'Team must belong to the agency' using errcode='23514'; end if;
  update public.agency_invites set revoked_at = now()
   where agency_id = p_agency and role_key = p_role_key and revoked_at is null
     and team_id is not distinct from p_team;
  insert into public.agency_invites(agency_id, role_key, team_id, created_by)
    values (p_agency, p_role_key, p_team, auth.uid()) returning code into v_code;
  return jsonb_build_object('ok', true, 'code', v_code);
end $$;

create or replace function public.agency_revoke_invite(p_invite uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_agency uuid;
begin
  select agency_id into v_agency from public.agency_invites where id = p_invite;
  if v_agency is null or not public.has_perm(v_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  update public.agency_invites set revoked_at = now() where id = p_invite and revoked_at is null;
end $$;

-- What the join page shows (works signed-out). No member data is exposed.
create or replace function public.invite_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare i record; v_used int; v_lim int;
begin
  select inv.*, a.name agency_name, a.logo_url, r.name_ar, r.name_en into i
    from public.agency_invites inv join public.agencies a on a.id = inv.agency_id
    left join public.roles r on r.agency_id = inv.agency_id and r.key = inv.role_key
   where inv.code = upper(trim(p_code));
  if not found or i.revoked_at is not null then return jsonb_build_object('ok',false,'error','invalid'); end if;
  select count(*) into v_used from public.agency_members where agency_id = i.agency_id and status = 'active';
  v_lim := public.agency_seat_limit(i.agency_id);
  return jsonb_build_object('ok',true,'agency',i.agency_name,'logo',i.logo_url,
    'role_ar',i.name_ar,'role_en',i.name_en,'seats_full', v_lim is not null and v_used >= v_lim);
end $$;
grant execute on function public.invite_info(text) to anon, authenticated;

-- Join with a link. Becomes a broker; already-members just get re-activated.
create or replace function public.accept_invite(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); i record; rid uuid; v_owner uuid;
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  select * into i from public.agency_invites where code = upper(trim(p_code)) and revoked_at is null;
  if not found then return jsonb_build_object('ok',false,'error','invalid'); end if;
  select owner_id into v_owner from public.agencies where id = i.agency_id;
  if v_owner = uid then return jsonb_build_object('ok',true,'agency_id',i.agency_id,'owner',true); end if;
  select id into rid from public.roles where agency_id = i.agency_id and key = i.role_key;
  begin
    insert into public.agency_members(agency_id,user_id,role,role_id,team_id,status,joined_at,created_by)
    values (i.agency_id, uid, case when i.role_key='admin' then 'admin' else 'agent' end, rid, i.team_id, 'active', now(), i.created_by)
    on conflict (agency_id,user_id) do update set role=excluded.role, role_id=excluded.role_id,
      team_id=coalesce(excluded.team_id, agency_members.team_id), status='active', suspended_at=null;
  exception when others then
    if sqlerrm like 'SEAT_LIMIT%' then
      insert into public.crm_notifications(user_id,type,title,body,data) values (v_owner,'team_seats_full',
        'مقاعد الفريق خلصت','حد حاول ينضم لفريقك برابط الدعوة والمقاعد مكتملة — زوّد المقاعد من صفحة الباقات.',
        jsonb_build_object('agency_id',i.agency_id));
      return jsonb_build_object('ok',false,'error','seats_full');
    end if;
    raise;
  end;
  update public.profiles set role = 'broker', onboarded = true, terms_accepted_at = coalesce(terms_accepted_at, now()) where id = uid;
  update public.agency_invites set uses = uses + 1 where id = i.id;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('member_joined_invite','agency_member',uid::text,uid,i.agency_id,jsonb_build_object('role',i.role_key));
  return jsonb_build_object('ok',true,'agency_id',i.agency_id);
end $$;
revoke execute on function public.accept_invite(text) from public, anon;
grant execute on function public.accept_invite(text) to authenticated;

-- Adding an existing account by phone/email also makes it a broker account
-- (a client account added to a team could not see the CRM before).
create or replace function public.agency_add_member(p_agency uuid, p_user uuid, p_role_key text default 'agent', p_team uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare rid uuid; legacy text;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if p_role_key='owner' or exists(select 1 from public.agencies where id=p_agency and owner_id=p_user) then raise exception 'Owner role cannot be assigned manually' using errcode='42501'; end if;
  select id into rid from public.roles where agency_id=p_agency and key=p_role_key;
  if rid is null then raise exception 'Unknown role %',p_role_key; end if;
  if p_team is not null and not exists(select 1 from public.teams where id=p_team and agency_id=p_agency) then raise exception 'Team must belong to the agency' using errcode='23514'; end if;
  legacy:=case when p_role_key='admin' then 'admin' else 'agent' end;
  insert into public.agency_members(agency_id,user_id,role,role_id,team_id,status,joined_at,created_by)
  values(p_agency,p_user,legacy,rid,p_team,'active',now(),auth.uid())
  on conflict(agency_id,user_id) do update set role=excluded.role,role_id=excluded.role_id,team_id=excluded.team_id,status='active',suspended_at=null;
  update public.profiles set role='broker', onboarded=true where id=p_user and role is distinct from 'broker';
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
  values('member_added','agency_member',p_user::text,auth.uid(),p_agency,jsonb_build_object('role',p_role_key));
end $$;

-- Team trials get the seats the company asked for on the pricing page
-- (otherwise an 8-person company on a 5-seat plan could only invite 4).
create or replace function public.start_trial(p_plan text, p_seats int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record; v_seats int;
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if p_plan not in ('pro','team','business') then return jsonb_build_object('ok',false,'error','bad_plan'); end if;
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
end $$;
drop function if exists public.start_trial(text);
