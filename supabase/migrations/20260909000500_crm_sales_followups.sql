begin;
-- Reuse existing tasks and their completion/notification flows. Detailed follow-up
-- types/reminders live in meta so older task-kind constraints remain compatible.
create function public.crm_sales_schedule_followup(p_lead uuid,p_kind text,p_title text,
  p_due timestamptz,p_priority text,p_reminder_minutes integer,p_local_day date)
returns jsonb language plpgsql security invoker set search_path=public as $$
declare task_id public.crm_tasks.id%type;
begin
  if auth.uid() is null or not exists(select 1 from public.clients where id=p_lead and owner_id=auth.uid()) then
    raise exception 'Client not found' using errcode='42501'; end if;
  if p_kind is null or p_priority is null or p_title is null or p_reminder_minutes is null
     or p_kind not in ('call','whatsapp','meeting','email','offer_followup','other')
     or p_priority not in ('low','medium','high') or length(trim(p_title)) not between 1 and 1000
     or p_due is null or p_local_day is null or p_reminder_minutes not in (0,15,60,1440)
     or abs(p_local_day-(p_due at time zone 'UTC')::date)>1 then raise exception 'Invalid follow-up'; end if;
  insert into public.crm_tasks(lead_id,owner_id,kind,title,due_at,priority,status,meta)
    values(p_lead,auth.uid(),case when p_kind in ('call','whatsapp') then p_kind else 'other' end,
      trim(p_title),p_due,case when p_priority='medium' then 'normal' else p_priority end,'open',jsonb_build_object('followup_type',p_kind,
      'reminder_at',p_due-make_interval(mins=>p_reminder_minutes),'local_day',p_local_day)) returning id into task_id;
  update public.clients set next_followup=p_local_day,updated_at=now() where id=p_lead and owner_id=auth.uid();
  return jsonb_build_object('ok',true,'task_id',task_id);
end $$;
revoke all on function public.crm_sales_schedule_followup(uuid,text,text,timestamptz,text,integer,date) from public,anon;
grant execute on function public.crm_sales_schedule_followup(uuid,text,text,timestamptz,text,integer,date) to authenticated;
commit;
