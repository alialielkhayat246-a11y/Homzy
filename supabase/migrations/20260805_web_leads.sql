-- Web chat leads: a website visitor's advisor conversation, saved so the client
-- can resume it (client-side by session id) and the broker can follow it up.
--
-- Privacy model: anonymous visitors NEVER read the table. They save through the
-- SECURITY DEFINER function upsert_web_lead() only. Signed-in brokers (the
-- `authenticated` role) can SELECT the collected leads.

create table if not exists public.web_leads (
  session_id text primary key,
  name       text,
  phone      text,
  context    text,
  messages   jsonb not null default '[]'::jsonb,
  lang       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.web_leads enable row level security;

-- Broker (any signed-in Supabase user) can read the leads. No anon SELECT.
drop policy if exists web_leads_auth_select on public.web_leads;
create policy web_leads_auth_select on public.web_leads
  for select to authenticated using (true);

create index if not exists web_leads_updated_idx on public.web_leads (updated_at desc);

-- Anonymous upsert path (no direct table write policy needed; runs as owner).
create or replace function public.upsert_web_lead(
  p_session_id text,
  p_name       text,
  p_phone      text,
  p_context    text,
  p_messages   jsonb,
  p_lang       text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_session_id is null or length(p_session_id) < 4 then
    raise exception 'invalid session';
  end if;
  insert into public.web_leads (session_id, name, phone, context, messages, lang, updated_at)
  values (p_session_id, p_name, p_phone, p_context, coalesce(p_messages, '[]'::jsonb), p_lang, now())
  on conflict (session_id) do update set
    name       = coalesce(excluded.name, web_leads.name),
    phone      = coalesce(excluded.phone, web_leads.phone),
    context    = coalesce(excluded.context, web_leads.context),
    messages   = excluded.messages,
    lang       = excluded.lang,
    updated_at = now();
end;
$$;

revoke all on function public.upsert_web_lead(text,text,text,text,jsonb,text) from public;
grant execute on function public.upsert_web_lead(text,text,text,text,jsonb,text) to anon, authenticated;
