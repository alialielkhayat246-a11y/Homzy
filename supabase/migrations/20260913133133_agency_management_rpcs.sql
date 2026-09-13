
-- Seed the 7 default roles + their permission grants for a fresh agency (§3/§4).
create or replace function public.agency_seed_default_roles(p_agency uuid)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare r record; rid uuid;
begin
  for r in
    select * from (values
      ('owner',      'Agency Owner','مالك الوكالة',       1),
      ('admin',      'Admin / Manager','مدير',             2),
      ('team_leader','Team Leader','قائد فريق',            3),
      ('agent',      'Broker / Sales Agent','بروكر / مبيعات',4),
      ('acquisition','Acquisition Agent','مسؤول توريد',    5),
      ('call_center','Call Center','كول سنتر',             6),
      ('coordinator','Coordinator','منسّق',                7)
    ) as t(key,en,ar,rank)
  loop
    insert into public.roles(agency_id,key,name_en,name_ar,is_system,rank)
    values (p_agency, r.key, r.en, r.ar, true, r.rank)
    on conflict (agency_id,key) do update set name_en=excluded.name_en, name_ar=excluded.name_ar
    returning id into rid;

    delete from public.role_permissions where role_id = rid;

    if r.key in ('owner','admin') then
      insert into public.role_permissions(role_id,permission_key)
        select rid, key from public.permissions;
    elsif r.key = 'team_leader' then
      insert into public.role_permissions(role_id,permission_key) values
        (rid,'lead.view'),(rid,'lead.view.all'),(rid,'lead.create'),(rid,'lead.edit'),(rid,'lead.assign'),
        (rid,'owner.view'),(rid,'owner.view.all'),(rid,'owner.create'),(rid,'owner.edit'),(rid,'owner.view_phone'),
        (rid,'property.view'),(rid,'property.create'),(rid,'property.edit'),(rid,'property.publish'),
        (rid,'deal.view'),(rid,'deal.view.all'),(rid,'deal.create'),(rid,'deal.edit'),(rid,'deal.close'),
        (rid,'task.view'),(rid,'task.create'),(rid,'task.assign'),
        (rid,'team.view'),(rid,'report.view'),(rid,'commission.view');
    elsif r.key = 'agent' then
      insert into public.role_permissions(role_id,permission_key) values
        (rid,'lead.view'),(rid,'lead.create'),(rid,'lead.edit'),
        (rid,'owner.view'),(rid,'owner.create'),(rid,'owner.edit'),
        (rid,'property.view'),(rid,'property.create'),(rid,'property.edit'),
        (rid,'deal.view'),(rid,'deal.create'),(rid,'deal.edit'),(rid,'deal.close'),
        (rid,'task.view'),(rid,'task.create');
    elsif r.key = 'acquisition' then
      insert into public.role_permissions(role_id,permission_key) values
        (rid,'owner.view'),(rid,'owner.create'),(rid,'owner.edit'),(rid,'owner.view_phone'),
        (rid,'property.view'),(rid,'property.create'),(rid,'property.edit'),(rid,'property.publish'),
        (rid,'lead.view'),(rid,'task.view'),(rid,'task.create');
    elsif r.key = 'call_center' then
      insert into public.role_permissions(role_id,permission_key) values
        (rid,'lead.view'),(rid,'lead.create'),(rid,'task.view'),(rid,'task.create');
    elsif r.key = 'coordinator' then
      insert into public.role_permissions(role_id,permission_key) values
        (rid,'lead.view'),(rid,'owner.view'),(rid,'property.view'),(rid,'deal.view'),
        (rid,'task.view'),(rid,'task.create'),(rid,'task.assign');
    end if;
  end loop;
end $$;

-- Create an agency workspace; caller becomes Agency Owner (§1).
create or replace function public.create_agency(
  p_name text, p_logo text default null, p_phone text default null,
  p_email text default null, p_address text default null, p_description text default null)
 returns uuid language plpgsql security definer set search_path to 'public' as $$
declare aid uuid; owner_role uuid;
begin
  if coalesce(length(trim(p_name)),0) < 2 then raise exception 'Agency name required'; end if;
  insert into public.agencies(name,owner_id,logo_url,phone,email,address,description)
    values (trim(p_name),auth.uid(),p_logo,p_phone,p_email,p_address,p_description)
    returning id into aid;

  perform public.agency_seed_default_roles(aid);
  select id into owner_role from public.roles where agency_id=aid and key='owner';

  insert into public.agency_members(agency_id,user_id,role,role_id,status,joined_at,created_by)
    values (aid,auth.uid(),'owner',owner_role,'active',now(),auth.uid())
  on conflict do nothing;

  -- Example, fully-configurable commission rules (§14 — not hardcoded).
  insert into public.commission_rules(agency_id,key,label_en,label_ar,applies_to,agent_pct) values
    (aid,'company_owner_lead','Company-provided lead','عميل من الشركة','company_owner_lead',20),
    (aid,'agent_sourced','Agent-sourced property','وحدة من توريد الموظف','agent_sourced',35)
  on conflict (agency_id,key) do nothing;

  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('agency_created','agency',aid::text,auth.uid(),aid,jsonb_build_object('name',p_name));
  return aid;
end $$;

-- Add an existing Homzy user to the agency (§2). Maps the legacy role text so the
-- existing agency-admin overlay keeps working.
create or replace function public.agency_add_member(
  p_agency uuid, p_user uuid, p_role_key text default 'agent', p_team uuid default null)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare rid uuid; legacy text;
begin
  if not (public.has_perm(p_agency,'team.manage')) then
    raise exception 'Not allowed' using errcode='42501';
  end if;
  select id into rid from public.roles where agency_id=p_agency and key=p_role_key;
  if rid is null then raise exception 'Unknown role %', p_role_key; end if;
  legacy := case when p_role_key='owner' then 'owner' when p_role_key='admin' then 'admin' else 'agent' end;
  insert into public.agency_members(agency_id,user_id,role,role_id,team_id,status,joined_at,created_by)
    values (p_agency,p_user,legacy,rid,p_team,'active',now(),auth.uid())
  on conflict (agency_id,user_id) do update
    set role=excluded.role, role_id=excluded.role_id, team_id=excluded.team_id,
        status='active', suspended_at=null;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('member_added','agency_member',p_user::text,auth.uid(),p_agency,jsonb_build_object('role',p_role_key));
end $$;

-- Suspend / reactivate / deactivate a member (§2, §28-M immediate access removal).
create or replace function public.agency_set_member_status(
  p_agency uuid, p_user uuid, p_status text)
 returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if p_status not in ('active','inactive','suspended','pending') then raise exception 'Bad status'; end if;
  if not public.has_perm(p_agency,'team.manage') then raise exception 'Not allowed' using errcode='42501'; end if;
  -- Never let an admin lock out the agency owner.
  if exists(select 1 from public.agencies a where a.id=p_agency and a.owner_id=p_user) and p_status<>'active' then
    raise exception 'Cannot suspend the agency owner';
  end if;
  update public.agency_members
    set status=p_status, suspended_at=case when p_status='suspended' then now() else null end
    where agency_id=p_agency and user_id=p_user;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('member_status',' agency_member',p_user::text,auth.uid(),p_agency,jsonb_build_object('status',p_status));
end $$;

-- Assign / reassign a lead, recording history (§6). Every reassignment is logged.
create or replace function public.agency_assign_lead(
  p_lead uuid, p_assignee uuid, p_reason text default null)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare aid uuid;
begin
  select agency_id into aid from public.clients where id=p_lead;
  if aid is null then aid := public.my_primary_agency(); end if;
  if aid is null then raise exception 'Lead is not in an agency workspace'; end if;
  if not public.has_perm(aid,'lead.assign') then raise exception 'Not allowed' using errcode='42501'; end if;
  update public.lead_assignments set unassigned_at=now()
    where lead_id=p_lead and unassigned_at is null;
  insert into public.lead_assignments(lead_id,agency_id,assigned_to,assigned_by,reason)
    values (p_lead,aid,p_assignee,auth.uid(),p_reason);
  update public.clients set assigned_to=p_assignee, agency_id=coalesce(agency_id,aid), updated_at=now()
    where id=p_lead;
  insert into public.crm_events(type,entity,entity_id,actor_id,company_id,meta)
    values ('lead_assigned','lead',p_lead::text,auth.uid(),aid,jsonb_build_object('to',p_assignee,'reason',p_reason));
  insert into public.crm_notifications(user_id,type,title,body,data)
    values (p_assignee,'lead_assigned','New lead assigned','You have a new lead',jsonb_build_object('lead_id',p_lead));
end $$;
