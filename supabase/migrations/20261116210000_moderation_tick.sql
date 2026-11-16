-- A dependable heartbeat for the listing content review.
--
-- The review already runs when a broker publishes from the website, and a GitHub Actions
-- schedule was meant to catch everything else — app and AXIS ONE listings, and any review that
-- failed first time. In practice GitHub throttles scheduled workflows on a quiet repository:
-- a "*/10 * * * *" schedule actually fired four times in twenty-four hours. On 16 Nov 2026 five
-- AXIS ONE listings sat invisible all day because of it, while the owner believed they were live.
--
-- pg_cron runs inside the database and keeps to its schedule, which is why notifications already
-- use it. The endpoint only touches listings that are already queued, so an empty queue costs one
-- HTTP call and no model tokens.
select cron.unschedule('moderation-tick') where exists (select 1 from cron.job where jobname = 'moderation-tick');

select cron.schedule('moderation-tick', '*/5 * * * *', $job$
  select net.http_post(
    url := 'https://homzy-ai.com/api/moderation/run?limit=3',
    body := '{}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 50000)
$job$);
