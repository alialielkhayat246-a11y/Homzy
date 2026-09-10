begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
-- Runs only in the rollback transaction, with synthetic records.
create temporary table crm_test_context as
select (select id from public.profiles where not coalesce(is_admin,false) order by id limit 1) as owner_uid,
 (select id from public.profiles where not coalesce(is_admin,false) order by id offset 1 limit 1) as actor_uid,
 gen_random_uuid() as lead_id, gen_random_uuid() as listing_id, gen_random_uuid() as offer_id;
grant select on crm_test_context to authenticated;
insert into public.clients(id,owner_id,name,phone,stage)
select lead_id,owner_uid,'CRM rollout validation','0000000000','new' from crm_test_context;
insert into public.listings(id,owner_id,title,purpose,type,price,currency,area,status)
select listing_id,owner_uid,'CRM rollout validation','sale','apartment',1000000,'EGP','New Cairo','active' from crm_test_context;
insert into public.crm_offers(id,owner_id,lead_id,language,client_name,items)
select offer_id,owner_uid,lead_id,'en','CRM rollout validation','[]' from crm_test_context;
select set_config('request.jwt.claim.sub',owner_uid::text,true) from crm_test_context;
set local role authenticated;
do $$
declare t record; r jsonb; invite_id uuid; share_id uuid; stamp timestamptz;
begin
 select * into t from crm_test_context;
 select updated_at into stamp from public.clients where id=t.lead_id;
 r=public.crm_save_sales_profile(t.lead_id,'{"purpose":"sale","type":"apartment","locations":["New Cairo"],"budget_max":1000000}',null,null,stamp);
 if r->>'ok' <> 'true' then raise exception 'Profile save failed'; end if;
 r=public.crm_save_sales_profile(t.lead_id,'{}',null,null,stamp-interval '1 day');
 if r->>'conflict' <> 'true' then raise exception 'Stale save accepted'; end if;
 perform public.crm_sales_move_stage(t.lead_id,'matching');
 if (select stage from public.clients where id=t.lead_id)<>'matching' then raise exception 'Stage failed'; end if;
 begin
   perform public.crm_sales_move_stage(t.lead_id,'lost');
   raise exception 'Lost reason not enforced';
 exception when raise_exception then
   if sqlerrm <> 'Lost reason required' then raise; end if;
 end;
 r=public.crm_sales_schedule_followup(t.lead_id,'meeting','CRM rollout validation',now(),'medium',15,current_date);
 if not exists(select 1 from public.crm_tasks where id=(r->>'task_id')::bigint and priority='normal') then raise exception 'Followup priority failed'; end if;
 if jsonb_array_length(public.crm_sales_search('validation'))=0 then raise exception 'Search failed'; end if;
 invite_id=public.crm_invite_behavior(t.lead_id);
 perform set_config('crm.test.invite',invite_id::text,true);
 r=public.crm_share_sales_offer(t.offer_id);
 share_id=(r->>'token')::uuid;
 perform set_config('crm.test.share',share_id::text,true);
 if public.crm_read_sales_offer(share_id) is null then raise exception 'Share read failed'; end if;
 -- A non-entitled account must be rejected before generating an offer.
 if not exists(select 1 from public.plan_limits where plan=public.current_plan(auth.uid()) and features->>'branded_pdf'='true') then
  begin
   perform public.crm_create_sales_offer(t.lead_id,array[t.listing_id],'en');
   raise exception 'Subscription check failed';
  exception when insufficient_privilege then null;
  end;
 else
  r=public.crm_create_sales_offer(t.lead_id,array[t.listing_id],'en');
  if jsonb_array_length(r->'items')<>1 then raise exception 'Snapshot failed'; end if;
 end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',actor_uid::text,true) from crm_test_context;
set local role authenticated;
do $$
declare t record;
begin
 select * into t from crm_test_context;
 if exists(select 1 from public.crm_offers where id=t.offer_id) then raise exception 'Cross-owner offer leaked'; end if;
 begin
  perform public.crm_sales_move_stage(t.lead_id,'closed');
  raise exception 'Cross-owner stage allowed';
 exception when insufficient_privilege then null;
 end;
 perform public.crm_track_behavior('viewed',t.listing_id,'{}');
 if exists(select 1 from public.crm_behavior_events where lead_id=t.lead_id) then raise exception 'Tracked without consent'; end if;
 perform public.crm_accept_behavior(current_setting('crm.test.invite')::uuid);
 perform public.crm_track_behavior('viewed',t.listing_id,'{}');
 perform public.crm_track_behavior('viewed',t.listing_id,'{}');
 if (select count(*) from public.crm_behavior_events where lead_id=t.lead_id and kind='viewed')<>1 then raise exception 'Deduplication failed'; end if;
 insert into public.favorites(user_id,listing_id) values(auth.uid(),t.listing_id);
 delete from public.favorites where user_id=auth.uid() and listing_id=t.listing_id;
 if (select count(*) from public.crm_behavior_events where lead_id=t.lead_id and kind in ('saved','favorite_removed'))<>2 then raise exception 'Favorite trigger failed'; end if;
 perform public.crm_revoke_behavior((select id from public.crm_behavior_links where invite=current_setting('crm.test.invite')::uuid));
 perform public.crm_track_behavior('shared',t.listing_id,'{}');
 if exists(select 1 from public.crm_behavior_events where lead_id=t.lead_id and kind='shared') then raise exception 'Tracked after revocation'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',owner_uid::text,true) from crm_test_context;
set local role authenticated;
do $$
begin
 if exists(select 1 from public.crm_behavior_events where lead_id=(select lead_id from crm_test_context)) then raise exception 'Revoked telemetry visible'; end if;
 perform public.crm_revoke_sales_offer((select offer_id from crm_test_context));
 if public.crm_read_sales_offer(current_setting('crm.test.share')::uuid) is not null then raise exception 'Revoked offer readable'; end if;
end $$;
reset role;
set local role anon;
do $$
begin
 if has_table_privilege('anon','public.crm_offers','SELECT') then raise exception 'Anonymous table access'; end if;
 if has_function_privilege('anon','public.crm_sales_search(text)','EXECUTE') then raise exception 'Anonymous CRM access'; end if;
end $$;
reset role;
select 'CRM runtime/RLS checks passed; transaction will roll back' as result;

rollback;
