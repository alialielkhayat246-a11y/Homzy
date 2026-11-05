-- Chat knowledge: Arabic developer names (so "بالم هيلز" / "تطوير مصر" are recognised)
-- and developer-level WhatsApp updates for the advisor, with the same tiering as
-- project_intel_for_ai (clients: public only; brokers/admins: all tiers).

alter table public.developers add column if not exists name_ar text;

create or replace function public.developer_intel_for_ai(p_developer_ids uuid[])
returns table(developer_id uuid, tier text, category text, content_ar text, observed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select i.developer_id, i.tier, i.category, i.content_ar, i.observed_at
  from project_intel i
  where i.developer_id = any(p_developer_ids) and i.project_id is null and i.status = 'active'
    and (i.expires_at is null or i.expires_at > now())
    and (i.tier = 'public' or public.is_broker() or public.is_admin_user())
  order by i.observed_at desc
  limit 20
$$;
grant execute on function public.developer_intel_for_ai(uuid[]) to anon, authenticated;
