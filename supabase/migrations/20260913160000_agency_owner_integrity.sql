-- Keep agencies.owner_id as the single source of truth for agency ownership.
-- The owner role is reserved for that user and cannot be assigned through RBAC.

do $$
declare a record;
begin
  for a in select id from public.agencies loop
    perform public.agency_seed_default_roles(a.id);
  end loop;
end $$;

update public.roles
set is_system = true
where key = 'owner';

update public.agency_members m
set role = 'admin',
    role_id = r_admin.id
from public.agencies a
join public.roles r_admin
  on r_admin.agency_id = a.id and r_admin.key = 'admin'
where m.agency_id = a.id
  and m.user_id <> a.owner_id
  and (
    m.role = 'owner'
    or exists(
      select 1 from public.roles r_current
      where r_current.id = m.role_id and r_current.key = 'owner'
    )
  );

insert into public.agency_members(
  agency_id, user_id, role, role_id, status, joined_at, created_by
)
select a.id, a.owner_id, 'owner', r.id, 'active', now(), a.owner_id
from public.agencies a
join public.roles r on r.agency_id = a.id and r.key = 'owner'
on conflict (agency_id, user_id) do update
set role = 'owner',
    role_id = excluded.role_id,
    status = 'active',
    suspended_at = null;

create unique index if not exists agency_members_one_owner
  on public.agency_members(agency_id)
  where role = 'owner';

create or replace function public.agency_member_integrity_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  canonical_owner uuid;
  previous_owner uuid;
  selected_role text;
  selected_role_agency uuid;
  selected_team_agency uuid;
begin
  if TG_OP = 'DELETE' then
    select owner_id into canonical_owner
    from public.agencies
    where id = OLD.agency_id;
    if canonical_owner = OLD.user_id then
      raise exception 'Cannot remove the agency owner' using errcode = '23514';
    end if;
    return OLD;
  end if;

  if TG_OP = 'UPDATE' then
    select owner_id into previous_owner
    from public.agencies
    where id = OLD.agency_id;
    if previous_owner = OLD.user_id
       and (NEW.agency_id is distinct from OLD.agency_id
            or NEW.user_id is distinct from OLD.user_id) then
      raise exception 'Agency owner membership cannot be moved'
        using errcode = '23514';
    end if;
  end if;

  select owner_id into canonical_owner
  from public.agencies
  where id = NEW.agency_id;
  if canonical_owner is null then
    raise exception 'Agency not found' using errcode = '23503';
  end if;

  if NEW.role_id is not null then
    select agency_id, key into selected_role_agency, selected_role
    from public.roles
    where id = NEW.role_id;
    if selected_role_agency is distinct from NEW.agency_id then
      raise exception 'Role must belong to the member agency' using errcode = '23514';
    end if;
  end if;

  if NEW.team_id is not null then
    select agency_id into selected_team_agency
    from public.teams
    where id = NEW.team_id;
    if selected_team_agency is distinct from NEW.agency_id then
      raise exception 'Team must belong to the member agency' using errcode = '23514';
    end if;
  end if;

  if NEW.user_id = canonical_owner then
    if NEW.role <> 'owner' or selected_role is distinct from 'owner'
       or NEW.status <> 'active' then
      raise exception 'Agency owner membership must stay active with the owner role'
        using errcode = '23514';
    end if;
  elsif NEW.role = 'owner' or selected_role = 'owner' then
    raise exception 'Owner role is reserved for the agency owner'
      using errcode = '23514';
  end if;
  return NEW;
end $$;

drop trigger if exists agency_member_integrity_guard_trg
  on public.agency_members;
create trigger agency_member_integrity_guard_trg
before insert or update or delete on public.agency_members
for each row execute function public.agency_member_integrity_guard();

create or replace function public.agency_owner_role_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if TG_OP = 'DELETE' and OLD.key = 'owner' then
    raise exception 'Agency owner role cannot be deleted' using errcode = '23514';
  end if;
  if TG_OP = 'UPDATE' then
    if OLD.key = 'owner'
       and (NEW.agency_id is distinct from OLD.agency_id
            or NEW.key is distinct from 'owner'
            or NEW.is_system is distinct from true) then
      raise exception 'Agency owner role cannot be reassigned'
        using errcode = '23514';
    end if;
    if OLD.key <> 'owner' and NEW.key = 'owner' then
      raise exception 'Owner is a reserved role key' using errcode = '23514';
    end if;
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $$;

drop trigger if exists agency_owner_role_guard_trg on public.roles;
create trigger agency_owner_role_guard_trg
before update or delete on public.roles
for each row execute function public.agency_owner_role_guard();

create or replace function public.agency_owner_immutable_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if NEW.owner_id is distinct from OLD.owner_id then
    raise exception 'Agency ownership cannot be changed without an ownership transfer'
      using errcode = '23514';
  end if;
  return NEW;
end $$;

drop trigger if exists agency_owner_immutable_guard_trg on public.agencies;
create trigger agency_owner_immutable_guard_trg
before update of owner_id on public.agencies
for each row execute function public.agency_owner_immutable_guard();

create or replace function public.agency_add_member(
  p_agency uuid, p_user uuid, p_role_key text default 'agent', p_team uuid default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare rid uuid; legacy text;
begin
  if not public.has_perm(p_agency, 'team.manage') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if p_role_key = 'owner'
     or exists(select 1 from public.agencies where id = p_agency and owner_id = p_user) then
    raise exception 'Owner role cannot be assigned manually' using errcode = '42501';
  end if;
  select id into rid from public.roles
  where agency_id = p_agency and key = p_role_key;
  if rid is null then raise exception 'Unknown role %', p_role_key; end if;
  if p_team is not null and not exists(
    select 1 from public.teams where id = p_team and agency_id = p_agency
  ) then
    raise exception 'Team must belong to the agency' using errcode = '23514';
  end if;
  legacy := case when p_role_key = 'admin' then 'admin' else 'agent' end;
  insert into public.agency_members(
    agency_id, user_id, role, role_id, team_id, status, joined_at, created_by
  ) values (p_agency, p_user, legacy, rid, p_team, 'active', now(), auth.uid())
  on conflict (agency_id, user_id) do update
    set role = excluded.role, role_id = excluded.role_id,
        team_id = excluded.team_id, status = 'active', suspended_at = null;
  insert into public.crm_events(type, entity, entity_id, actor_id, company_id, meta)
  values ('member_added', 'agency_member', p_user::text, auth.uid(), p_agency,
          jsonb_build_object('role', p_role_key));
end $$;

create or replace function public.agency_set_member_role(
  p_agency uuid, p_user uuid, p_role_key text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare rid uuid; legacy text;
begin
  if not public.has_perm(p_agency, 'team.manage') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if p_role_key = 'owner'
     or exists(select 1 from public.agencies where id = p_agency and owner_id = p_user) then
    raise exception 'Owner role cannot be assigned or changed manually'
      using errcode = '42501';
  end if;
  select id into rid from public.roles
  where agency_id = p_agency and key = p_role_key;
  if rid is null then raise exception 'Unknown role %', p_role_key; end if;
  legacy := case when p_role_key = 'admin' then 'admin' else 'agent' end;
  update public.agency_members set role_id = rid, role = legacy
  where agency_id = p_agency and user_id = p_user;
  if not found then raise exception 'Agency member not found'; end if;
  insert into public.crm_events(type, entity, entity_id, actor_id, company_id, meta)
  values ('role_changed', 'agency_member', p_user::text, auth.uid(), p_agency,
          jsonb_build_object('role', p_role_key));
end $$;

create or replace function public.agency_create_team(
  p_agency uuid, p_name text, p_leader uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare tid uuid;
begin
  if not public.has_perm(p_agency, 'team.manage') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if coalesce(length(trim(p_name)), 0) < 2 then
    raise exception 'Team name required';
  end if;
  if p_leader is not null and not exists(
    select 1 from public.agency_members
    where agency_id = p_agency and user_id = p_leader and status = 'active'
  ) then
    raise exception 'Team leader must be an active agency member'
      using errcode = '23514';
  end if;
  insert into public.teams(agency_id, name, leader_id)
  values (p_agency, trim(p_name), p_leader) returning id into tid;
  return tid;
end $$;

create or replace function public.agency_set_member_team(
  p_agency uuid, p_user uuid, p_team uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.has_perm(p_agency, 'team.manage') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if p_team is not null and not exists(
    select 1 from public.teams where id = p_team and agency_id = p_agency
  ) then
    raise exception 'Team must belong to the agency' using errcode = '23514';
  end if;
  update public.agency_members set team_id = p_team
  where agency_id = p_agency and user_id = p_user;
  if not found then raise exception 'Agency member not found'; end if;
end $$;

revoke all on function public.agency_member_integrity_guard() from public;
revoke all on function public.agency_owner_role_guard() from public;
revoke all on function public.agency_owner_immutable_guard() from public;
grant execute on function public.agency_add_member(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.agency_set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.agency_create_team(uuid, text, uuid) to authenticated;
grant execute on function public.agency_set_member_team(uuid, uuid, uuid) to authenticated;
