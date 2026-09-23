-- Google Play UGC safety controls for marketplace messaging and AI responses.
-- Blocking is enforced in the database so a modified client cannot bypass it.

alter table public.profiles
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists community_guidelines_accepted_at timestamptz;

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks(blocked_id, blocker_id);

alter table public.user_blocks enable row level security;

drop policy if exists user_blocks_read_involved on public.user_blocks;
create policy user_blocks_read_involved on public.user_blocks for select
  to authenticated
  using (auth.uid() in (blocker_id, blocked_id));

drop policy if exists user_blocks_insert_own on public.user_blocks;
create policy user_blocks_insert_own on public.user_blocks for insert
  to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists user_blocks_delete_own on public.user_blocks;
create policy user_blocks_delete_own on public.user_blocks for delete
  to authenticated
  using (blocker_id = auth.uid());

create table if not exists public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete set null,
  target_type text not null check (target_type in ('user', 'message', 'ai_response', 'listing')),
  target_id text,
  conversation_id uuid references public.listing_conversations(id) on delete set null,
  reason text not null check (reason in ('spam', 'harassment', 'fraud', 'inappropriate', 'other')),
  details text,
  content_snapshot text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  resolution_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists moderation_reports_status_idx
  on public.moderation_reports(status, created_at desc);
create index if not exists moderation_reports_reporter_idx
  on public.moderation_reports(reporter_id, created_at desc);

alter table public.moderation_reports enable row level security;

drop policy if exists moderation_reports_read_own_or_admin on public.moderation_reports;
create policy moderation_reports_read_own_or_admin on public.moderation_reports for select
  to authenticated
  using (
    reporter_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true)
  );

drop policy if exists moderation_reports_admin_update on public.moderation_reports;
create policy moderation_reports_admin_update on public.moderation_reports for update
  to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- Called by the listing_messages INSERT policy. SECURITY DEFINER ensures that
-- a block created by the other participant is still visible to this check.
create or replace function public.can_send_listing_message(
  p_conversation uuid,
  p_sender uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_sender = auth.uid()
    and exists (
      select 1
      from public.listing_conversations c
      where c.id = p_conversation
        and p_sender in (c.buyer_id, c.seller_id)
        and not exists (
          select 1
          from public.user_blocks b
          where (b.blocker_id = c.buyer_id and b.blocked_id = c.seller_id)
             or (b.blocker_id = c.seller_id and b.blocked_id = c.buyer_id)
        )
    );
$$;

revoke all on function public.can_send_listing_message(uuid, uuid) from public, anon;
grant execute on function public.can_send_listing_message(uuid, uuid) to authenticated;

drop policy if exists msg_insert on public.listing_messages;
create policy msg_insert on public.listing_messages for insert
  to authenticated
  with check (public.can_send_listing_message(conversation_id, sender_id));

create or replace function public.report_listing_message(
  p_message uuid,
  p_reason text,
  p_details text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.listing_messages%rowtype;
  v_report uuid;
begin
  if p_reason not in ('spam', 'harassment', 'fraud', 'inappropriate', 'other') then
    raise exception 'invalid_report_reason';
  end if;

  select m.* into v_message
  from public.listing_messages m
  join public.listing_conversations c on c.id = m.conversation_id
  where m.id = p_message
    and auth.uid() in (c.buyer_id, c.seller_id);

  if not found or v_message.sender_id = auth.uid() then
    raise exception 'message_not_reportable';
  end if;

  insert into public.moderation_reports (
    reporter_id, reported_user_id, target_type, target_id,
    conversation_id, reason, details, content_snapshot
  ) values (
    auth.uid(), v_message.sender_id, 'message', v_message.id::text,
    v_message.conversation_id, p_reason, nullif(trim(p_details), ''),
    left(v_message.body, 4000)
  ) returning id into v_report;

  return v_report;
end;
$$;

create or replace function public.report_conversation_user(
  p_conversation uuid,
  p_reason text,
  p_details text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.listing_conversations%rowtype;
  v_other uuid;
  v_report uuid;
begin
  if p_reason not in ('spam', 'harassment', 'fraud', 'inappropriate', 'other') then
    raise exception 'invalid_report_reason';
  end if;

  select * into v_conversation
  from public.listing_conversations
  where id = p_conversation
    and auth.uid() in (buyer_id, seller_id);

  if not found then raise exception 'conversation_not_found'; end if;
  v_other := case when v_conversation.buyer_id = auth.uid()
                  then v_conversation.seller_id else v_conversation.buyer_id end;

  insert into public.moderation_reports (
    reporter_id, reported_user_id, target_type, target_id,
    conversation_id, reason, details
  ) values (
    auth.uid(), v_other, 'user', v_other::text,
    p_conversation, p_reason, nullif(trim(p_details), '')
  ) returning id into v_report;

  return v_report;
end;
$$;

create or replace function public.report_ai_content(
  p_content text,
  p_reason text,
  p_conversation text default null,
  p_details text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_report uuid;
begin
  if p_reason not in ('spam', 'harassment', 'fraud', 'inappropriate', 'other') then
    raise exception 'invalid_report_reason';
  end if;
  if nullif(trim(p_content), '') is null then raise exception 'content_required'; end if;

  insert into public.moderation_reports (
    reporter_id, target_type, target_id, reason, details, content_snapshot
  ) values (
    auth.uid(), 'ai_response', nullif(trim(p_conversation), ''), p_reason,
    nullif(trim(p_details), ''), left(p_content, 4000)
  ) returning id into v_report;
  return v_report;
end;
$$;

revoke all on function public.report_listing_message(uuid, text, text) from public, anon;
revoke all on function public.report_conversation_user(uuid, text, text) from public, anon;
revoke all on function public.report_ai_content(text, text, text, text) from public, anon;
grant execute on function public.report_listing_message(uuid, text, text) to authenticated;
grant execute on function public.report_conversation_user(uuid, text, text) to authenticated;
grant execute on function public.report_ai_content(text, text, text, text) to authenticated;

create or replace function public.admin_resolve_moderation_report(
  p_report uuid,
  p_status text,
  p_note text default null,
  p_remove_content boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_report public.moderation_reports%rowtype;
begin
  if not exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true
  ) then raise exception 'not_admin'; end if;
  if p_status not in ('reviewing', 'resolved', 'dismissed') then
    raise exception 'invalid_status';
  end if;

  select * into v_report from public.moderation_reports where id = p_report;
  if not found then raise exception 'report_not_found'; end if;

  if p_remove_content and v_report.target_type = 'message' and v_report.target_id is not null then
    delete from public.listing_messages where id = v_report.target_id::uuid;
  elsif p_remove_content and v_report.target_type = 'listing' and v_report.target_id is not null then
    update public.listings set status = 'inactive', updated_at = now()
    where id = v_report.target_id::uuid;
  end if;

  update public.moderation_reports
  set status = p_status,
      resolution_note = nullif(trim(p_note), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_report;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_resolve_moderation_report(uuid, text, text, boolean) from public, anon;
grant execute on function public.admin_resolve_moderation_report(uuid, text, text, boolean) to authenticated;
