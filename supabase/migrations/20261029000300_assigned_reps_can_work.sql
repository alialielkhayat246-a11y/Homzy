-- Team plans: a sales rep must be able to work the clients assigned to them (and a
-- manager with lead.edit + lead.view.all any agency client) — not only clients
-- they created. One shared check, swapped into the CRM functions' owner guards.
create or replace function public.crm_can_work_lead(p_lead uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.stay_is_admin() or exists(
    select 1 from public.clients c
    where c.id = p_lead and (
      c.owner_id = auth.uid()
      or (c.assigned_to = auth.uid() and public.is_active_member(c.agency_id))
      or (c.agency_id is not null and public.has_perm(c.agency_id, 'lead.edit')
          and public.has_perm(c.agency_id, 'lead.view.all'))));
$$;
revoke execute on function public.crm_can_work_lead(uuid) from public, anon;
grant execute on function public.crm_can_work_lead(uuid) to authenticated;

do $$
declare r record; d text; n text;
  reps text[][] := array[
    ['crm_create_sales_offer', 'from public.clients where id=p_lead and owner_id=auth.uid();', 'from public.clients where id=p_lead and public.crm_can_work_lead(id);'],
    ['crm_invite_behavior', 'not exists(select 1 from public.clients where id=p_lead and owner_id=auth.uid())', 'not public.crm_can_work_lead(p_lead)'],
    ['crm_sales_schedule_followup', 'not exists(select 1 from public.clients where id=p_lead and owner_id=auth.uid())', 'not public.crm_can_work_lead(p_lead)'],
    ['crm_sales_move_stage', 'where id=p_lead and owner_id=auth.uid() for update', 'where id=p_lead and public.crm_can_work_lead(id) for update'],
    ['crm_save_sales_profile', 'where id=p_lead and owner_id=auth.uid() for update', 'where id=p_lead and public.crm_can_work_lead(id) for update'],
    ['crm_sales_search', 'where owner_id=auth.uid() and to_tsvector', 'where (owner_id=auth.uid() or assigned_to=auth.uid()) and to_tsvector'],
    ['crm_log_activity', 'if c.owner_id <> uid and not stay_is_admin() then', 'if not public.crm_can_work_lead(p_lead) then'],
    ['crm_log_interaction', 'if not (v_owner = auth.uid() or public.stay_is_admin()) then', 'if not public.crm_can_work_lead(p_lead) then'],
    ['crm_schedule_viewing', 'if not (v_owner = auth.uid() or public.stay_is_admin()) then', 'if not public.crm_can_work_lead(p_lead) then'],
    ['crm_schedule_viewing', 'values (p_lead, v_owner, p_title', 'values (p_lead, auth.uid(), p_title'],
    ['crm_log_outbound', 'if v_owner is not null and v_owner <> uid and not public.stay_is_admin() then', 'if v_owner is not null and not public.crm_can_work_lead(p_lead) then']
  ];
  i int; pos int;
begin
  -- Only the FIRST occurrence is replaced (crm_sales_search also has a deals clause).
  for i in 1 .. array_length(reps, 1) loop
    for r in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname = reps[i][1] loop
      d := pg_get_functiondef(r.oid);
      pos := position(reps[i][2] in d);
      if pos = 0 then
        if position(reps[i][3] in d) = 0 then
          raise exception 'pattern not found in %: %', reps[i][1], reps[i][2];
        end if;
        continue;
      end if;
      n := overlay(d placing reps[i][3] from pos for length(reps[i][2]));
      execute n;
    end loop;
  end loop;
end $$;

revoke execute on function public.agency_seat_limit(uuid) from anon;
