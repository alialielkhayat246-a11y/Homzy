-- Team leaders see their own team's records, not the whole agency's.
-- New "*.view.team" permissions sit next to "*.view.all": a role holding the
-- team one sees records whose responsible member (assignee, else creator) is in
-- a team the caller leads or belongs to. Team Leader moves from view.all to
-- view.team; owners can still grant view.all from Roles & permissions.

insert into public.permissions(key, category, name_en, name_ar, sort) values
  ('lead.view.team',  'leads',  'View own team''s leads',  'عرض عملاء فريقه فقط', 11),
  ('owner.view.team', 'owners', 'View own team''s owners', 'عرض ملاك فريقه فقط',  21),
  ('deal.view.team',  'deals',  'View own team''s deals',  'عرض صفقات فريقه فقط', 41)
on conflict (key) do nothing;

-- teams the caller leads or is a member of
create or replace function public.my_team_ids(p_agency uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select t.id from public.teams t where t.agency_id = p_agency and t.leader_id = auth.uid()
  union
  select m.team_id from public.agency_members m
   where m.agency_id = p_agency and m.user_id = auth.uid() and m.status = 'active' and m.team_id is not null;
$$;

-- caller holds p_perm and the record belongs to one of the caller's teams,
-- either directly (p_team) or through one of the given members
create or replace function public.team_scope_ok(p_agency uuid, p_perm text, p_team uuid, p_users uuid[])
returns boolean language sql stable security definer set search_path = public as $$
  select p_agency is not null and public.has_perm(p_agency, p_perm) and (
    p_team in (select public.my_team_ids(p_agency))
    or exists (select 1 from public.agency_members m
                where m.agency_id = p_agency and m.user_id = any(p_users)
                  and m.team_id in (select public.my_team_ids(p_agency))));
$$;

create or replace function public.lead_agency(p_lead uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select agency_id from public.clients where id = p_lead;
$$;

-- leads
drop policy if exists clients_select on public.clients;
create policy clients_select on public.clients for select to authenticated using (
  ((owner_id = auth.uid()) and ((agency_id is null) or is_active_member(agency_id)))
  or ((assigned_to = auth.uid()) and is_active_member(agency_id))
  or has_perm(agency_id, 'lead.view.all')
  or team_scope_ok(agency_id, 'lead.view.team', team_id, array[coalesce(assigned_to, owner_id)])
  or stay_is_admin());

drop policy if exists la_read on public.lead_assignments;
create policy la_read on public.lead_assignments for select to authenticated using (
  (assigned_to = auth.uid()) or (assigned_by = auth.uid())
  or has_perm(agency_id, 'lead.view.all')
  or team_scope_ok(agency_id, 'lead.view.team', null, array[assigned_to]));

create or replace function public.crm_can_work_lead(p_lead uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.stay_is_admin() or exists(
    select 1 from public.clients c
    where c.id = p_lead and (
      c.owner_id = auth.uid()
      or (c.assigned_to = auth.uid() and public.is_active_member(c.agency_id))
      or (c.agency_id is not null and public.has_perm(c.agency_id, 'lead.edit')
          and (public.has_perm(c.agency_id, 'lead.view.all')
               or public.team_scope_ok(c.agency_id, 'lead.view.team', c.team_id, array[coalesce(c.assigned_to, c.owner_id)])))));
$$;

-- deals: team leaders could only see their own; now they see their team's
drop policy if exists deals_team_read on public.crm_deals;
create policy deals_team_read on public.crm_deals for select to authenticated using (
  team_scope_ok(coalesce(agency_id, lead_agency(lead_id)), 'deal.view.team', team_id, array[owner_id]));

-- owners (agency owner records are served through these RPCs)
create or replace function public.agency_owner_scope_allowed(p_agency uuid, p_created_by uuid, p_assigned_to uuid, p_owner_id uuid, p_perm text)
returns boolean language sql stable security definer set search_path = public as $$
select public.is_active_member(p_agency) and public.has_perm(p_agency,p_perm) and (public.has_perm(p_agency,'owner.view.all')
  or auth.uid() in (p_created_by,p_assigned_to,p_owner_id)
  or public.team_scope_ok(p_agency,'owner.view.team',null,array[p_created_by,p_assigned_to,p_owner_id]));
$$;

create or replace function public.agency_list_owners(p_agency uuid)
returns jsonb language sql stable security definer set search_path = public as $$
select case when not public.is_active_member(p_agency) or not public.has_perm(p_agency,'owner.view') then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('phone',case when public.has_perm(p_agency,'owner.view_phone') then o.phone else null end,'whatsapp',case when public.has_perm(p_agency,'owner.view_phone') then o.whatsapp else null end) order by o.created_at desc) from public.owners o where o.agency_id=p_agency and o.deleted_at is null and (public.has_perm(p_agency,'owner.view.all') or auth.uid() in (o.created_by,o.assigned_to,o.owner_id) or public.team_scope_ok(p_agency,'owner.view.team',o.team_id,array[o.created_by,o.assigned_to,o.owner_id]))),'[]'::jsonb) end;
$$;

-- performance: a team-scoped viewer only sees their team's members (and themselves)
create or replace function public.agency_performance(p_agency uuid, p_since timestamp with time zone)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_team_only boolean;
begin
  if not public.has_perm(p_agency, 'report.view') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  v_team_only := not public.has_perm(p_agency, 'lead.view.all') and public.has_perm(p_agency, 'lead.view.team');
  return coalesce((
    select jsonb_agg(r order by (r->>'won_value')::numeric desc, (r->>'leads_new')::int desc)
    from (
      select jsonb_build_object(
        'user_id', m.user_id,
        'name', coalesce(p.full_name, p.phone, p.email),
        'role_ar', ro.name_ar, 'role_en', ro.name_en, 'team', t.name,
        'leads_total', (select count(*) from public.clients c where c.agency_id = p_agency and c.deleted_at is null
                          and coalesce(c.assigned_to, c.owner_id) = m.user_id),
        'leads_new', (select count(*) from public.clients c where c.agency_id = p_agency and c.deleted_at is null
                          and coalesce(c.assigned_to, c.owner_id) = m.user_id and c.created_at >= p_since),
        'activities', (select count(*) from public.crm_lead_activities a
                          join public.clients c on c.id = a.lead_id and c.agency_id = p_agency
                          where a.actor_id = m.user_id and a.created_at >= p_since),
        'viewings', (select count(*) from public.crm_viewings v
                          join public.clients c on c.id = v.lead_id and c.agency_id = p_agency
                          where v.owner_id = m.user_id and v.created_at >= p_since),
        'deals_open', (select count(*) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status in ('open','negotiation','reservation')),
        'won', (select count(*) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status = 'won' and coalesce(d.actual_close::timestamptz, d.updated_at) >= p_since),
        'won_value', (select coalesce(sum(d.value), 0) from public.crm_deals d where d.owner_id = m.user_id
                          and (d.agency_id = p_agency or d.lead_id in (select id from public.clients where agency_id = p_agency))
                          and d.status = 'won' and coalesce(d.actual_close::timestamptz, d.updated_at) >= p_since),
        'ai_used', (select coalesce(sum(u.used), 0) from public.ai_usage u
                          where u.user_id = m.user_id and u.day >= p_since::date)
      ) as r
      from public.agency_members m
      left join public.profiles p on p.id = m.user_id
      left join public.roles ro on ro.id = m.role_id
      left join public.teams t on t.id = m.team_id
      where m.agency_id = p_agency and m.status = 'active'
        and (not v_team_only or m.user_id = auth.uid() or m.team_id in (select public.my_team_ids(p_agency)))
    ) s), '[]'::jsonb);
end $$;

-- existing Team Leader roles: view.all -> view.team
update public.role_permissions rp set permission_key = replace(rp.permission_key, '.view.all', '.view.team')
  from public.roles r
 where r.id = rp.role_id and r.key = 'team_leader'
   and rp.permission_key in ('lead.view.all', 'owner.view.all', 'deal.view.all');

-- owners/admins hold every permission
insert into public.role_permissions(role_id, permission_key)
select r.id, p.key from public.roles r cross join (values ('lead.view.team'),('owner.view.team'),('deal.view.team')) p(key)
 where r.key in ('owner','admin')
on conflict do nothing;

-- new agencies get the same Team Leader defaults
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.agency_seed_default_roles(uuid)'::regprocedure);
  n := replace(replace(replace(d, '(rid,''lead.view.all'')', '(rid,''lead.view.team'')'),
                                  '(rid,''owner.view.all'')', '(rid,''owner.view.team'')'),
                                  '(rid,''deal.view.all'')', '(rid,''deal.view.team'')');
  if n = d then raise exception 'seed roles: team_leader grants not found'; end if;
  execute n;
end $$;
