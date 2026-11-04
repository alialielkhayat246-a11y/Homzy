-- Broker onboarding: after choosing "broker / agency" the user fills a short
-- company step (independent broker vs brokerage company) before picking a plan.
-- A brokerage company gets its team (agency) created automatically.

alter table public.profiles add column if not exists broker_type text
  check (broker_type in ('independent','company'));
alter table public.profiles add column if not exists whatsapp text;
alter table public.profiles add column if not exists work_areas text[];
alter table public.profiles add column if not exists team_size int check (team_size between 1 and 1000);

create or replace function public.complete_broker_setup(
  p_type text, p_company text default null, p_logo text default null, p_whatsapp text default null,
  p_areas text[] default null, p_team_size int default null, p_commercial_reg text default null,
  p_address text default null, p_email text default null, p_terms boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_name text := nullif(trim(p_company), ''); v_agency uuid; v_phone text;
begin
  if uid is null then return jsonb_build_object('ok',false,'error','not_authenticated'); end if;
  if p_type not in ('independent','company') then return jsonb_build_object('ok',false,'error','bad_type'); end if;
  if not coalesce(p_terms,false) then return jsonb_build_object('ok',false,'error','terms_required'); end if;
  if p_type = 'company' then
    if coalesce(length(v_name),0) < 2 then return jsonb_build_object('ok',false,'error','company_required'); end if;
    if p_team_size is null or p_team_size < 1 then return jsonb_build_object('ok',false,'error','team_size_required'); end if;
  end if;

  update public.profiles set
    role = 'broker', onboarded = true, broker_type = p_type,
    company = coalesce(v_name, company),
    company_logo_url = coalesce(nullif(trim(p_logo),''), company_logo_url),
    whatsapp = nullif(regexp_replace(coalesce(p_whatsapp,''), '[^0-9+]', '', 'g'), ''),
    work_areas = nullif(p_areas, '{}'),
    team_size = case when p_type = 'company' then p_team_size else null end,
    commercial_reg = coalesce(nullif(trim(p_commercial_reg),''), commercial_reg),
    terms_accepted_at = coalesce(terms_accepted_at, now())
  where id = uid
  returning coalesce(whatsapp, phone) into v_phone;

  if p_type = 'company' then
    select id into v_agency from public.agencies where owner_id = uid order by created_at limit 1;
    if v_agency is null then
      v_agency := public.create_agency(v_name, nullif(trim(p_logo),''), v_phone,
                                       nullif(trim(p_email),''), nullif(trim(p_address),''), null);
    end if;
  end if;
  return jsonb_build_object('ok',true,'type',p_type,'agency_id',v_agency);
end $$;
revoke execute on function public.complete_broker_setup(text,text,text,text,text[],int,text,text,text,boolean) from public, anon;
grant execute on function public.complete_broker_setup(text,text,text,text,text[],int,text,text,text,boolean) to authenticated;

-- Security: the own-profile UPDATE policy only checks it is the user's row, and
-- the table grant covers every column — so anyone could PATCH is_admin=true on
-- themselves. Only the service role / SQL console may change admin flags now.
create or replace function public._guard_profile_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then new.is_admin := false;
    else new.is_admin := old.is_admin; new.id := old.id; new.created_at := old.created_at;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_profile_admin on public.profiles;
create trigger trg_guard_profile_admin before insert or update on public.profiles
  for each row execute function public._guard_profile_admin();
