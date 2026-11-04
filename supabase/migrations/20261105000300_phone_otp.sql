-- Phone verification by a one-time code sent on WhatsApp (SMS fallback later).
-- Brokers must verify their phone; clients verify the phone they leave on a
-- viewing / "contact me" request. Codes are stored hashed, expire in 10 min,
-- allow 5 tries, 1 send per minute and 5 sends per phone per day. Only the
-- backend (holding PUSH_CRON_TOKEN) can issue a code, so a browser can never
-- read one back.

alter table public.profiles add column if not exists phone_verified_at timestamptz;
alter table public.web_leads add column if not exists phone_verified boolean not null default false;

create table if not exists public.phone_otps (
  phone text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  sends_day date not null default current_date,
  sends int not null default 0,
  last_sent_at timestamptz,
  verified_at timestamptz
);
alter table public.phone_otps enable row level security;
revoke all on public.phone_otps from anon, authenticated;

-- 01xxxxxxxxx / +20 1x / 201x / 1x → 201xxxxxxxxx (same as the sign-up form).
create or replace function public._norm_eg_phone(p text)
returns text language sql immutable as $$
  select case
    when d ~ '^00' then substr(d, 3)
    when d ~ '^0' then '20' || substr(d, 2)
    when d ~ '^20' then d
    else '20' || d end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') d) x;
$$;

create or replace function public.phone_otp_issue(p_key text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text := public._norm_eg_phone(p_phone); r record; v_code text;
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden'; end if;
  if v_phone !~ '^201[0125][0-9]{8}$' then return jsonb_build_object('ok',false,'error','bad_phone'); end if;
  select * into r from public.phone_otps where phone = v_phone for update;
  if found and r.last_sent_at > now() - interval '60 seconds' then
    return jsonb_build_object('ok',false,'error','wait','retry_in', 60 - extract(epoch from now() - r.last_sent_at)::int); end if;
  if found and r.sends_day = current_date and r.sends >= 5 then
    return jsonb_build_object('ok',false,'error','daily_limit'); end if;
  v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.phone_otps(phone, code_hash, expires_at, attempts, sends_day, sends, last_sent_at, verified_at)
  values (v_phone, encode(extensions.digest(v_code || ':' || v_phone, 'sha256'), 'hex'), now() + interval '10 minutes', 0, current_date, 1, now(), null)
  on conflict (phone) do update set code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0,
    sends = case when phone_otps.sends_day = current_date then phone_otps.sends + 1 else 1 end,
    sends_day = current_date, last_sent_at = now(), verified_at = null;
  return jsonb_build_object('ok', true, 'phone', v_phone, 'code', v_code);
end $$;
revoke execute on function public.phone_otp_issue(text, text) from public;
grant execute on function public.phone_otp_issue(text, text) to anon, authenticated;   -- key-gated

-- Check a code. A signed-in user whose profile phone matches gets marked verified.
create or replace function public.phone_otp_verify(p_phone text, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text := public._norm_eg_phone(p_phone); r record; uid uuid := auth.uid();
begin
  select * into r from public.phone_otps where phone = v_phone for update;
  if not found or r.expires_at < now() then return jsonb_build_object('ok',false,'error','expired'); end if;
  if r.attempts >= 5 then return jsonb_build_object('ok',false,'error','too_many'); end if;
  if r.code_hash <> encode(extensions.digest(regexp_replace(coalesce(p_code,''),'[^0-9]','','g') || ':' || v_phone, 'sha256'), 'hex') then
    update public.phone_otps set attempts = attempts + 1 where phone = v_phone;
    return jsonb_build_object('ok',false,'error','wrong','left', 4 - r.attempts); end if;
  update public.phone_otps set verified_at = now(), expires_at = now() - interval '1 second' where phone = v_phone;   -- one use
  if uid is not null then
    perform set_config('hz.otp_ok', '1', true);   -- lets _guard_profile_phone accept this one change
    update public.profiles set phone_verified_at = now()
     where id = uid and public._norm_eg_phone(phone) = v_phone;
  end if;
  return jsonb_build_object('ok', true, 'phone', v_phone);
end $$;
grant execute on function public.phone_otp_verify(text, text) to anon, authenticated;

-- A lead's phone counts as verified when that phone passed a code in the last 2 hours.
create or replace function public._web_lead_phone_verified()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.phone_verified := coalesce(new.phone, '') <> '' and exists(
    select 1 from public.phone_otps o
     where o.phone = public._norm_eg_phone(new.phone) and o.verified_at > now() - interval '2 hours');
  return new;
end $$;
drop trigger if exists trg_web_lead_phone_verified on public.web_leads;
create trigger trg_web_lead_phone_verified before insert or update of phone on public.web_leads
  for each row execute function public._web_lead_phone_verified();

-- Changing your phone means verifying again; the flag is never set from the API.
create or replace function public._guard_profile_phone()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then new.phone_verified_at := null;
    elsif new.phone is distinct from old.phone then new.phone_verified_at := null;
    elsif new.phone_verified_at is distinct from old.phone_verified_at
          and current_setting('hz.otp_ok', true) is distinct from '1' then
      new.phone_verified_at := old.phone_verified_at;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_profile_phone on public.profiles;
create trigger trg_guard_profile_phone before insert or update on public.profiles
  for each row execute function public._guard_profile_phone();
