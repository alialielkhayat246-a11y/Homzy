
-- Permissions the current user holds in an agency (for UI gating).
create or replace function public.my_perms(p_agency uuid)
 returns text[] language sql stable security definer set search_path to 'public' as $$
  select case
    when p_agency is null then array[]::text[]
    when public.stay_is_admin()
      or exists(select 1 from public.agencies a where a.id=p_agency and a.owner_id=auth.uid())
      then (select array_agg(key) from public.permissions)
    else coalesce((
      select array_agg(distinct rp.permission_key)
      from public.agency_members m
      join public.role_permissions rp on rp.role_id=m.role_id
      where m.agency_id=p_agency and m.user_id=auth.uid() and m.status='active'
    ), array[]::text[])
  end;
$$;

-- Full team roster with profile + role + team + light stats (gated by team.view).
create or replace function public.agency_team_roster(p_agency uuid)
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(row order by is_owner desc, joined_at), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'user_id', m.user_id, 'name', p.full_name, 'phone', p.phone, 'email', p.email,
      'avatar', p.avatar_url, 'status', m.status, 'title', m.title,
      'role_key', r.key, 'role_ar', r.name_ar, 'role_en', r.name_en,
      'team_id', m.team_id, 'team_name', t.name,
      'is_owner', (a.owner_id = m.user_id), 'joined_at', m.joined_at,
      'leads', (select count(*) from public.clients c where c.assigned_to=m.user_id and c.agency_id=p_agency),
      'deals', (select count(*) from public.crm_deals d where d.owner_id=m.user_id and d.agency_id=p_agency)
    ) as row, (a.owner_id = m.user_id) as is_owner, m.joined_at as joined_at
    from public.agency_members m
    join public.agencies a on a.id=m.agency_id
    left join public.roles r on r.id=m.role_id
    left join public.teams t on t.id=m.team_id
    left join public.profiles p on p.id=m.user_id
    where m.agency_id=p_agency and public.has_perm(p_agency,'team.view')
  ) s;
$$;

-- Find an existing Homzy user by phone/email to invite (gated by team.manage).
create or replace function public.agency_lookup_user(p_agency uuid, p_query text)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare digits text; hit record;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  digits := regexp_replace(coalesce(p_query,''),'[^0-9]','','g');
  if length(digits) >= 10 then digits := right(digits,10); else digits := null; end if;
  select p.id, p.full_name, p.phone, p.email into hit
  from public.profiles p
  where (digits is not null and p.phone like '%'||digits||'%')
     or (p_query like '%@%' and lower(p.email)=lower(trim(p_query)))
  limit 1;
  if hit.id is null then return null; end if;
  return jsonb_build_object('id',hit.id,'name',hit.full_name,'phone',hit.phone,'email',hit.email);
end $$;

-- Teams
create or replace function public.agency_create_team(p_agency uuid, p_name text, p_leader uuid default null)
 returns uuid language plpgsql security definer set search_path to 'public' as $$
declare tid uuid;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  insert into public.teams(agency_id,name,leader_id) values (p_agency,trim(p_name),p_leader) returning id into tid;
  return tid;
end $$;

create or replace function public.agency_set_member_team(p_agency uuid, p_user uuid, p_team uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  update public.agency_members set team_id=p_team where agency_id=p_agency and user_id=p_user;
end $$;

create or replace function public.agency_set_member_role(p_agency uuid, p_user uuid, p_role_key text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare rid uuid; legacy text;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if exists(select 1 from public.agencies a where a.id=p_agency and a.owner_id=p_user) then
    raise exception 'The agency owner role cannot be changed';
  end if;
  select id into rid from public.roles where agency_id=p_agency and key=p_role_key;
  if rid is null then raise exception 'Unknown role %', p_role_key; end if;
  legacy := case when p_role_key='owner' then 'owner' when p_role_key='admin' then 'admin' else 'agent' end;
  update public.agency_members set role_id=rid, role=legacy where agency_id=p_agency and user_id=p_user;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('role_changed','agency_member',p_user::text,auth.uid(),p_agency,jsonb_build_object('role',p_role_key));
end $$;

create or replace function public.agency_remove_member(p_agency uuid, p_user uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if exists(select 1 from public.agencies a where a.id=p_agency and a.owner_id=p_user) then
    raise exception 'Cannot remove the agency owner';
  end if;
  delete from public.agency_members where agency_id=p_agency and user_id=p_user;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('member_removed','agency_member',p_user::text,auth.uid(),p_agency,'{}'::jsonb);
end $$;

-- Custom roles + permission editing (gated by team.manage)
create or replace function public.agency_create_role(
  p_agency uuid, p_key text, p_name_ar text, p_name_en text, p_perms text[])
 returns uuid language plpgsql security definer set search_path to 'public' as $$
declare rid uuid; k text;
begin
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  insert into public.roles(agency_id,key,name_ar,name_en,is_system,rank)
    values (p_agency, lower(regexp_replace(trim(p_key),'[^a-zA-Z0-9_]+','_','g')), trim(p_name_ar), trim(p_name_en), false, 100)
    returning id into rid;
  foreach k in array coalesce(p_perms,array[]::text[]) loop
    insert into public.role_permissions(role_id,permission_key) values (rid,k) on conflict do nothing;
  end loop;
  return rid;
end $$;

create or replace function public.agency_set_role_perms(p_role uuid, p_perms text[])
 returns void language plpgsql security definer set search_path to 'public' as $$
declare aid uuid; rkey text; k text;
begin
  select agency_id, key into aid, rkey from public.roles where id=p_role;
  if aid is null then raise exception 'Role not found'; end if;
  if not public.has_perm(aid,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  if rkey='owner' then raise exception 'Owner keeps full access'; end if;
  delete from public.role_permissions where role_id=p_role;
  foreach k in array coalesce(p_perms,array[]::text[]) loop
    insert into public.role_permissions(role_id,permission_key) values (p_role,k) on conflict do nothing;
  end loop;
end $$;
