-- Auto-confirm new sign-ups so email delivery isn't required (Supabase's
-- built-in mailer isn't configured for this project). A BEFORE INSERT trigger
-- on auth.users stamps email_confirmed_at, so GoTrue returns a session straight
-- from /signup and the user is logged in with no confirmation email step.
--
-- Trade-off: emails aren't verified. Acceptable for launch; revisit if/when a
-- real SMTP sender (or OTP) is configured.
create or replace function public.auto_confirm_email()
returns trigger
language plpgsql
security definer
set search_path = auth, public
as $$
begin
  if new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists auto_confirm_new_users on auth.users;
create trigger auto_confirm_new_users
  before insert on auth.users
  for each row execute function public.auto_confirm_email();
