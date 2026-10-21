-- Every change to a unit's price/plan is kept, so automatic updates from the
-- WhatsApp groups can always be traced and reverted.
create table if not exists public.unit_price_history (
  id bigserial primary key,
  changed_at timestamptz not null default now(),
  unit_id uuid not null,
  project_id uuid,
  old_price_from numeric, new_price_from numeric,
  old_price_to numeric,   new_price_to numeric,
  old_down_payment text,  new_down_payment text,
  old_installment_years int, new_installment_years int,
  old_size_from numeric,  new_size_from numeric
);
alter table public.unit_price_history enable row level security;
drop policy if exists unit_price_history_admin on public.unit_price_history;
create policy unit_price_history_admin on public.unit_price_history for select to authenticated using (public.is_admin_user());

create or replace function public._log_unit_price() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.price_from, old.price_to, old.down_payment, old.installment_years, old.size_from)
     is distinct from (new.price_from, new.price_to, new.down_payment, new.installment_years, new.size_from) then
    insert into unit_price_history (unit_id, project_id, old_price_from, new_price_from, old_price_to, new_price_to,
                                    old_down_payment, new_down_payment, old_installment_years, new_installment_years,
                                    old_size_from, new_size_from)
    values (new.id, new.project_id, old.price_from, new.price_from, old.price_to, new.price_to,
            old.down_payment, new.down_payment, old.installment_years, new.installment_years, old.size_from, new.size_from);
  end if;
  return new;
end $$;
drop trigger if exists unit_types_price_history on public.unit_types;
create trigger unit_types_price_history after update on public.unit_types
  for each row execute function public._log_unit_price();
