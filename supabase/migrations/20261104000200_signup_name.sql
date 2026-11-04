-- Phone sign-up sends the name as metadata "name" (Google sends "full_name"),
-- but new profiles only read "full_name", so phone accounts were created
-- without a name. Read both, and backfill the accounts that lost it.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ref uuid;
begin
  insert into public.profiles (id, full_name, email, phone, role, company, commercial_reg)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name')), ''),
    new.email,
    coalesce(new.phone, new.raw_user_meta_data->>'phone'),
    case when new.raw_user_meta_data->>'role' = 'broker' then 'broker' else 'user' end,
    new.raw_user_meta_data->>'company',
    new.raw_user_meta_data->>'commercial_reg')
  on conflict (id) do nothing;
  if coalesce(new.raw_user_meta_data->>'ref','') <> '' then
    select id into v_ref from public.profiles
      where referral_code = upper(left(new.raw_user_meta_data->>'ref', 12)) and id <> new.id;
    if v_ref is not null then
      insert into public.referrals(referred_id, referrer_id) values (new.id, v_ref)
      on conflict do nothing;
    end if;
  end if;
  return new;
end; $$;

update public.profiles p
   set full_name = nullif(trim(u.raw_user_meta_data->>'name'), '')
  from auth.users u
 where u.id = p.id and p.full_name is null
   and coalesce(trim(u.raw_user_meta_data->>'name'), '') <> '';
