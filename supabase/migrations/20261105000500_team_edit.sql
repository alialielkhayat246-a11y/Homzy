-- Teams can be renamed / get a new leader after creation, and whoever is made a
-- team's leader while still a plain Broker becomes a Team Leader (team-scoped view).

create or replace function public._promote_team_leader(p_agency uuid, p_leader uuid)
returns void language sql security definer set search_path = public as $$
  update public.agency_members m set role_id = tl.id
    from public.roles tl, public.roles cur
   where m.agency_id = p_agency and m.user_id = p_leader
     and tl.agency_id = p_agency and tl.key = 'team_leader'
     and cur.id = m.role_id and cur.key = 'agent';
$$;
revoke all on function public._promote_team_leader(uuid, uuid) from public, anon, authenticated;

create or replace function public.agency_create_team(p_agency uuid, p_name text, p_leader uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if coalesce(length(trim(p_name)),0)<2 then raise exception 'Team name required'; end if;
  if p_leader is not null and not exists(select 1 from public.agency_members where agency_id=p_agency and user_id=p_leader and status='active') then raise exception 'Team leader must be an active agency member' using errcode='23514'; end if;
  insert into public.teams(agency_id,name,leader_id) values(p_agency,trim(p_name),p_leader) returning id into tid;
  if p_leader is not null then perform public._promote_team_leader(p_agency, p_leader); end if;
  return tid;
end $$;

create or replace function public.agency_update_team(p_agency uuid, p_team uuid, p_name text, p_leader uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if coalesce(length(trim(p_name)),0)<2 then raise exception 'Team name required'; end if;
  if p_leader is not null and not exists(select 1 from public.agency_members where agency_id=p_agency and user_id=p_leader and status='active') then raise exception 'Team leader must be an active agency member' using errcode='23514'; end if;
  update public.teams set name = trim(p_name), leader_id = p_leader, updated_at = now() where id = p_team and agency_id = p_agency;
  if not found then raise exception 'Team not found'; end if;
  if p_leader is not null then perform public._promote_team_leader(p_agency, p_leader); end if;
end $$;
grant execute on function public.agency_update_team(uuid, uuid, text, uuid) to authenticated;
