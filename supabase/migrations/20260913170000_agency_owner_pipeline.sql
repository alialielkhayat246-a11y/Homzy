-- Agency acquisition pipeline. Agency rows are exposed through secure RPCs so
-- phone/WhatsApp fields can be masked when owner.view_phone is not granted.

drop policy if exists owners_select on public.owners;
create policy owners_select on public.owners for select to authenticated using (
  (agency_id is null and owner_id = auth.uid())
  or public.stay_is_admin()
);

drop policy if exists owners_insert on public.owners;
create policy owners_insert on public.owners for insert to authenticated with check (
  (agency_id is null and owner_id = auth.uid())
  or public.stay_is_admin()
);

drop policy if exists owners_update on public.owners;
create policy owners_update on public.owners for update to authenticated
  using ((agency_id is null and owner_id = auth.uid()) or public.stay_is_admin())
  with check ((agency_id is null and owner_id = auth.uid()) or public.stay_is_admin());

drop policy if exists owners_delete on public.owners;
create policy owners_delete on public.owners for delete to authenticated using (
  (agency_id is null and owner_id = auth.uid())
  or public.stay_is_admin()
);

create or replace function public.agency_owner_scope_allowed(
  p_agency uuid, p_created_by uuid, p_assigned_to uuid, p_owner_id uuid, p_perm text)
returns boolean
language sql stable security definer set search_path to 'public' as $$
  select public.is_active_member(p_agency)
    and public.has_perm(p_agency, p_perm)
    and (
      public.has_perm(p_agency, 'owner.view.all')
      or auth.uid() in (p_created_by, p_assigned_to, p_owner_id)
    );
$$;

create or replace function public.agency_list_owners(p_agency uuid)
returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select case
    when not public.is_active_member(p_agency)
      or not public.has_perm(p_agency, 'owner.view')
      then '[]'::jsonb
    else coalesce((
      select jsonb_agg(
        to_jsonb(o)
        || jsonb_build_object(
          'phone', case when public.has_perm(p_agency, 'owner.view_phone') then o.phone else null end,
          'whatsapp', case when public.has_perm(p_agency, 'owner.view_phone') then o.whatsapp else null end
        )
        order by o.created_at desc
      )
      from public.owners o
      where o.agency_id = p_agency
        and o.deleted_at is null
        and (
          public.has_perm(p_agency, 'owner.view.all')
          or auth.uid() in (o.created_by, o.assigned_to, o.owner_id)
        )
    ), '[]'::jsonb)
  end;
$$;

create or replace function public.agency_create_owner(
  p_agency uuid,
  p_name text,
  p_phone text default null,
  p_whatsapp text default null,
  p_area text default null,
  p_property_type text default null,
  p_purpose text default null,
  p_asking_price numeric default null,
  p_property_ref text default null,
  p_source text default null,
  p_source_kind text default 'agent',
  p_assigned_to uuid default null,
  p_next_followup date default null,
  p_notes text default null)
returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare oid uuid; assignee_team uuid;
begin
  if not public.is_active_member(p_agency)
     or not public.has_perm(p_agency, 'owner.create') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if coalesce(length(trim(p_name)), 0) < 2 then
    raise exception 'Owner name required';
  end if;
  if p_source_kind not in ('company', 'agent') then
    raise exception 'Invalid source kind';
  end if;
  if p_source_kind = 'company' and not public.has_perm(p_agency, 'team.manage') then
    raise exception 'Only agency managers can mark a company-provided source'
      using errcode = '42501';
  end if;
  if p_purpose is not null and p_purpose not in ('sale', 'rent') then
    raise exception 'Invalid purpose';
  end if;
  if p_assigned_to is not null then
    if p_assigned_to <> auth.uid()
       and not public.has_perm(p_agency, 'team.manage') then
      raise exception 'Only agency managers can assign another member'
        using errcode = '42501';
    end if;
    select team_id into assignee_team
    from public.agency_members
    where agency_id = p_agency and user_id = p_assigned_to and status = 'active';
    if not found then
      raise exception 'Assignee must be an active agency member' using errcode = '23514';
    end if;
  end if;

  insert into public.owners(
    owner_id, agency_id, team_id, created_by, assigned_to, name, phone,
    whatsapp, area, property_type, purpose, asking_price, property_ref,
    source, source_kind, next_followup, notes
  ) values (
    auth.uid(), p_agency, assignee_team, auth.uid(), p_assigned_to, trim(p_name),
    nullif(trim(p_phone), ''), nullif(trim(p_whatsapp), ''), nullif(trim(p_area), ''),
    nullif(trim(p_property_type), ''), p_purpose, p_asking_price,
    nullif(trim(p_property_ref), ''), nullif(trim(p_source), ''), p_source_kind,
    p_next_followup, nullif(trim(p_notes), '')
  ) returning id into oid;

  insert into public.crm_events(type, entity, entity_id, actor_id, company_id, meta)
  values (
    'owner_created', 'owner', oid::text, auth.uid(), p_agency,
    jsonb_build_object('source', p_source, 'source_kind', p_source_kind,
                       'assigned_to', p_assigned_to)
  );
  if p_assigned_to is not null and p_assigned_to <> auth.uid() then
    insert into public.crm_notifications(user_id, type, title, body, data)
    values (
      p_assigned_to, 'owner_assigned', 'New owner assigned',
      'A property owner was assigned to you', jsonb_build_object('owner_id', oid)
    );
  end if;
  return oid;
end $$;

create or replace function public.agency_set_owner_stage(
  p_owner uuid, p_stage text, p_status text default null, p_notes text default null)
returns void
language plpgsql security definer set search_path to 'public' as $$
declare rec public.owners%rowtype; old_stage text;
begin
  select * into rec from public.owners where id = p_owner and deleted_at is null;
  if rec.id is null then raise exception 'Owner not found'; end if;
  if not public.agency_owner_scope_allowed(
    rec.agency_id, rec.created_by, rec.assigned_to, rec.owner_id, 'owner.edit'
  ) then raise exception 'Not allowed' using errcode = '42501'; end if;
  old_stage := rec.stage;
  update public.owners
  set stage = p_stage,
      status = coalesce(p_status, status),
      notes = coalesce(nullif(trim(p_notes), ''), notes),
      last_contact = case when p_stage in ('contacted','interested') then now() else last_contact end,
      updated_at = now()
  where id = p_owner;
  insert into public.crm_events(type, entity, entity_id, actor_id, company_id, meta)
  values (
    'owner_stage_changed', 'owner', p_owner::text, auth.uid(), rec.agency_id,
    jsonb_build_object('from', old_stage, 'to', p_stage, 'status', p_status)
  );
end $$;

create or replace function public.agency_assign_owner(
  p_owner uuid, p_assignee uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path to 'public' as $$
declare rec public.owners%rowtype; assignee_team uuid; old_assignee uuid;
begin
  select * into rec from public.owners where id = p_owner and deleted_at is null;
  if rec.id is null then raise exception 'Owner not found'; end if;
  if not public.is_active_member(rec.agency_id)
     or not public.has_perm(rec.agency_id, 'team.manage') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if p_assignee is not null then
    select team_id into assignee_team
    from public.agency_members
    where agency_id = rec.agency_id and user_id = p_assignee and status = 'active';
    if not found then
      raise exception 'Assignee must be an active agency member' using errcode = '23514';
    end if;
  end if;
  old_assignee := rec.assigned_to;
  update public.owners
  set assigned_to = p_assignee, team_id = assignee_team, updated_at = now()
  where id = p_owner;
  insert into public.crm_events(type, entity, entity_id, actor_id, company_id, meta)
  values (
    case when old_assignee is null then 'owner_assigned' else 'owner_reassigned' end,
    'owner', p_owner::text, auth.uid(), rec.agency_id,
    jsonb_build_object('from', old_assignee, 'to', p_assignee, 'reason', p_reason)
  );
  if p_assignee is not null and p_assignee <> auth.uid() then
    insert into public.crm_notifications(user_id, type, title, body, data)
    values (
      p_assignee, 'owner_assigned', 'Owner assignment updated',
      'A property owner was assigned to you', jsonb_build_object('owner_id', p_owner)
    );
  end if;
end $$;

revoke all on function public.agency_owner_scope_allowed(uuid,uuid,uuid,uuid,text) from public, anon;
revoke all on function public.agency_list_owners(uuid) from public, anon;
revoke all on function public.agency_create_owner(uuid,text,text,text,text,text,text,numeric,text,text,text,uuid,date,text) from public, anon;
revoke all on function public.agency_set_owner_stage(uuid,text,text,text) from public, anon;
revoke all on function public.agency_assign_owner(uuid,uuid,text) from public, anon;
grant execute on function public.agency_list_owners(uuid) to authenticated;
grant execute on function public.agency_create_owner(uuid,text,text,text,text,text,text,numeric,text,text,text,uuid,date,text) to authenticated;
grant execute on function public.agency_set_owner_stage(uuid,text,text,text) to authenticated;
grant execute on function public.agency_assign_owner(uuid,uuid,text) to authenticated;
