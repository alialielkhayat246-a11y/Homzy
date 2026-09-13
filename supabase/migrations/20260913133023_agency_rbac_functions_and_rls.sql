
-- ============ RBAC helpers (SECURITY DEFINER to avoid RLS recursion) ============
create or replace function public.is_active_member(p_agency uuid)
 returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists(
    select 1 from public.agency_members
    where agency_id = p_agency and user_id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.my_primary_agency()
 returns uuid language sql stable security definer set search_path to 'public' as $$
  select m.agency_id
  from public.agency_members m
  left join public.agencies a on a.id = m.agency_id and a.owner_id = auth.uid()
  where m.user_id = auth.uid() and m.status = 'active'
  order by (a.id is not null) desc, m.joined_at asc
  limit 1;
$$;

-- Central permission check. True for platform admins, the agency owner, or an
-- ACTIVE member whose role grants the permission. Suspended/inactive members
-- fail immediately (§28-M).
create or replace function public.has_perm(p_agency uuid, p_perm text)
 returns boolean language sql stable security definer set search_path to 'public' as $$
  select
    p_agency is not null and (
      public.stay_is_admin()
      or exists(select 1 from public.agencies a where a.id = p_agency and a.owner_id = auth.uid())
      or exists(
        select 1
        from public.agency_members m
        join public.role_permissions rp on rp.role_id = m.role_id
        where m.agency_id = p_agency and m.user_id = auth.uid()
          and m.status = 'active' and rp.permission_key = p_perm
      )
    );
$$;

-- ============ OWNERS RLS (§5 isolation, §15 phone permission) ============
drop policy if exists owners_select on public.owners;
create policy owners_select on public.owners for select to authenticated using (
  owner_id = auth.uid() or created_by = auth.uid() or assigned_to = auth.uid()
  or public.has_perm(agency_id, 'owner.view.all')
);
drop policy if exists owners_insert on public.owners;
create policy owners_insert on public.owners for insert to authenticated with check (
  owner_id = auth.uid() and (agency_id is null or public.has_perm(agency_id, 'owner.create'))
);
drop policy if exists owners_update on public.owners;
create policy owners_update on public.owners for update to authenticated
  using (owner_id = auth.uid() or assigned_to = auth.uid() or public.has_perm(agency_id, 'owner.edit'))
  with check (owner_id = auth.uid() or assigned_to = auth.uid() or public.has_perm(agency_id, 'owner.edit'));
drop policy if exists owners_delete on public.owners;
create policy owners_delete on public.owners for delete to authenticated
  using (owner_id = auth.uid() or public.has_perm(agency_id, 'owner.delete'));

-- ============ TEAMS / ROLES / ROLE_PERMISSIONS RLS ============
drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams for select to authenticated
  using (public.is_active_member(agency_id) or public.has_perm(agency_id, 'team.view'));
drop policy if exists teams_manage on public.teams;
create policy teams_manage on public.teams for all to authenticated
  using (public.has_perm(agency_id, 'team.manage')) with check (public.has_perm(agency_id, 'team.manage'));

drop policy if exists roles_read on public.roles;
create policy roles_read on public.roles for select to authenticated
  using (public.is_active_member(agency_id) or public.has_perm(agency_id, 'team.view'));
drop policy if exists roles_manage on public.roles;
create policy roles_manage on public.roles for all to authenticated
  using (public.has_perm(agency_id, 'team.manage')) with check (public.has_perm(agency_id, 'team.manage'));

drop policy if exists rp_read on public.role_permissions;
create policy rp_read on public.role_permissions for select to authenticated using (
  exists(select 1 from public.roles r where r.id = role_id
         and (public.is_active_member(r.agency_id) or public.has_perm(r.agency_id, 'team.view')))
);
drop policy if exists rp_manage on public.role_permissions;
create policy rp_manage on public.role_permissions for all to authenticated using (
  exists(select 1 from public.roles r where r.id = role_id and public.has_perm(r.agency_id, 'team.manage'))
) with check (
  exists(select 1 from public.roles r where r.id = role_id and public.has_perm(r.agency_id, 'team.manage'))
);

-- ============ AGENCY_MEMBERS — add perm-based read/manage (keep existing) ======
drop policy if exists agmem_read_team on public.agency_members;
create policy agmem_read_team on public.agency_members for select to authenticated
  using (public.is_active_member(agency_id));
drop policy if exists agmem_manage_perm on public.agency_members;
create policy agmem_manage_perm on public.agency_members for all to authenticated
  using (public.has_perm(agency_id, 'team.manage')) with check (public.has_perm(agency_id, 'team.manage'));

-- ============ CLIENTS — add assignment / manager agency access (additive) =====
drop policy if exists clients_agency_perm_read on public.clients;
create policy clients_agency_perm_read on public.clients for select to authenticated
  using (assigned_to = auth.uid() or public.has_perm(agency_id, 'lead.view.all'));
drop policy if exists clients_agency_perm_update on public.clients;
create policy clients_agency_perm_update on public.clients for update to authenticated
  using (assigned_to = auth.uid() or public.has_perm(agency_id, 'lead.edit'))
  with check (assigned_to = auth.uid() or public.has_perm(agency_id, 'lead.edit'));

-- ============ LEAD ASSIGNMENTS RLS ============
drop policy if exists la_read on public.lead_assignments;
create policy la_read on public.lead_assignments for select to authenticated
  using (assigned_to = auth.uid() or assigned_by = auth.uid() or public.has_perm(agency_id, 'lead.view.all'));
drop policy if exists la_insert on public.lead_assignments;
create policy la_insert on public.lead_assignments for insert to authenticated
  with check (assigned_by = auth.uid() or public.has_perm(agency_id, 'lead.assign'));

-- ============ DEAL CONTRIBUTORS RLS + ≤100% guard (§14) ============
drop policy if exists dc_read on public.deal_contributors;
create policy dc_read on public.deal_contributors for select to authenticated using (
  user_id = auth.uid()
  or exists(select 1 from public.crm_deals d where d.id = deal_id
            and (d.owner_id = auth.uid() or public.has_perm(d.agency_id, 'commission.view')))
);
drop policy if exists dc_manage on public.deal_contributors;
create policy dc_manage on public.deal_contributors for all to authenticated using (
  exists(select 1 from public.crm_deals d where d.id = deal_id
         and (d.owner_id = auth.uid() or public.has_perm(d.agency_id, 'commission.manage')))
) with check (
  exists(select 1 from public.crm_deals d where d.id = deal_id
         and (d.owner_id = auth.uid() or public.has_perm(d.agency_id, 'commission.manage')))
);

create or replace function public.deal_contrib_guard()
 returns trigger language plpgsql set search_path to 'public' as $$
declare total numeric;
begin
  select coalesce(sum(share_pct),0) into total
    from public.deal_contributors
   where deal_id = coalesce(NEW.deal_id, OLD.deal_id)
     and id <> coalesce(NEW.id, -1);
  if TG_OP in ('INSERT','UPDATE') then total := total + coalesce(NEW.share_pct, 0); end if;
  if total > 100.0001 then
    raise exception 'Commission share for deal % exceeds 100%% (got %)',
      coalesce(NEW.deal_id, OLD.deal_id), total;
  end if;
  return coalesce(NEW, OLD);
end $$;
drop trigger if exists deal_contrib_guard_trg on public.deal_contributors;
create trigger deal_contrib_guard_trg before insert or update on public.deal_contributors
  for each row execute function public.deal_contrib_guard();

-- ============ COMMISSION RULES RLS ============
drop policy if exists cr_read on public.commission_rules;
create policy cr_read on public.commission_rules for select to authenticated
  using (public.is_active_member(agency_id) or public.has_perm(agency_id, 'commission.view'));
drop policy if exists cr_manage on public.commission_rules;
create policy cr_manage on public.commission_rules for all to authenticated
  using (public.has_perm(agency_id, 'commission.manage') or public.has_perm(agency_id, 'agency.settings'))
  with check (public.has_perm(agency_id, 'commission.manage') or public.has_perm(agency_id, 'agency.settings'));
