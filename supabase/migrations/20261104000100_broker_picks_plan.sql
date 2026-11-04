-- A new broker now picks a plan first: no automatic Pro trial on becoming a
-- broker. The 14-day trial starts from the pricing page (start_trial) on the
-- plan the broker chose, and that is the plan they continue on afterwards.
drop trigger if exists trg_auto_broker_trial on public.profiles;
drop function if exists public._auto_broker_trial();
