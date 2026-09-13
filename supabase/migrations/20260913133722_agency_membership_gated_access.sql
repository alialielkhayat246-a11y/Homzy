
-- ===== CLIENTS: consolidate; agency-row access requires ACTIVE membership (§28-M).
drop policy if exists clients_own          on public.clients;
drop policy if exists clients_select_own   on public.clients;
drop policy if exists clients_insert_own   on public.clients;
drop policy if exists clients_update_own   on public.clients;
drop policy if exists clients_delete_own   on public.clients;
drop policy if exists clients_agency_read  on public.clients;
drop policy if exists clients_agency_perm_read   on public.clients;
drop policy if exists clients_agency_perm_update on public.clients;

create policy clients_select on public.clients for select to authenticated using (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'lead.view.all')
  or public.stay_is_admin()
);
create policy clients_insert on public.clients for insert to authenticated with check (
  owner_id = auth.uid() and (agency_id is null or public.is_active_member(agency_id))
);
create policy clients_update on public.clients for update to authenticated using (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'lead.edit')
) with check (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'lead.edit')
);
create policy clients_delete on public.clients for delete to authenticated using (
  (owner_id = auth.uid() and (agency_id is null or public.is_active_member(agency_id)))
  or public.has_perm(agency_id,'lead.delete')
);

-- ===== OWNERS: same membership gating on the personal-access paths.
drop policy if exists owners_select on public.owners;
create policy owners_select on public.owners for select to authenticated using (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (created_by = auth.uid() and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'owner.view.all')
  or public.stay_is_admin()
);
drop policy if exists owners_update on public.owners;
create policy owners_update on public.owners for update to authenticated using (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'owner.edit')
) with check (
  (owner_id = auth.uid()   and (agency_id is null or public.is_active_member(agency_id)))
  or (assigned_to = auth.uid() and public.is_active_member(agency_id))
  or public.has_perm(agency_id,'owner.edit')
);
drop policy if exists owners_delete on public.owners;
create policy owners_delete on public.owners for delete to authenticated using (
  (owner_id = auth.uid() and (agency_id is null or public.is_active_member(agency_id)))
  or public.has_perm(agency_id,'owner.delete')
);
