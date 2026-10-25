-- Security hardening (2026-10-26).
-- 1) Internal / batch functions are no longer callable through the public API.
revoke execute on function public.import_byit_projects(jsonb) from public, anon, authenticated;
revoke execute on function public.import_resale(jsonb) from public, anon, authenticated;
revoke execute on function public.enrich_catalog(jsonb) from public, anon, authenticated;
revoke execute on function public.crm_notify(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.crm_score_lead(uuid) from public, anon, authenticated;
revoke execute on function public.agency_seed_default_roles(uuid) from public, anon, authenticated;
revoke execute on function public._log_unit_price() from public, anon, authenticated;
alter function public.touch_conversation() set search_path = public;
alter function public.mask_phone(text) set search_path = public;
alter function public.crm_phone_tail(text) set search_path = public;

-- 2) The shared server secret was committed to the public repo, so it was rotated.
--    The database keeps only the sha256 of the new secret; every secret-gated RPC
--    (payments, push, stays cron, WhatsApp inbound) now calls _check_cron_key().
--    (Applied in place on the live DB by rewriting each function's guard
--     "p_key is null or p_key <> '<old literal>'" -> "not public._check_cron_key(p_key)".)
create or replace function public._check_cron_key(p_key text) returns boolean
language sql immutable security definer set search_path = public as $$
  select p_key is not null and encode(sha256(convert_to(p_key,'utf8')),'hex') = '57e0beccf8f731b6346d722ee161b6f99f0e0834a5e6e4ff8e2662b88288435c'
$$;
revoke execute on function public._check_cron_key(text) from public, anon, authenticated;
