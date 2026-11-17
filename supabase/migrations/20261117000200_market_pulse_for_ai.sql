-- "Market pulse" for the chat: the newest developer updates from the WhatsApp groups
-- for the client's area (or across Egypt), not only for the 6 matched projects.
-- Same tier rule as project_intel_for_ai: clients get public items only; brokers and
-- admins also get broker/ai items. Egypt-only (projects.country) and never expired.
create or replace function public.market_pulse_for_ai(p_areas text[] default null, p_days int default 45,
                                                      p_limit int default 20)
returns table(project text, project_ar text, area text, location text, developer text, tier text,
              category text, content_ar text, observed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.name, p.name_ar, p.area, p.location, coalesce(d.name, d2.name), i.tier, i.category, i.content_ar, i.observed_at
  from public.project_intel i
  left join public.projects p on p.id = i.project_id
  left join public.developers d on d.id = p.developer_id
  left join public.developers d2 on d2.id = i.developer_id
  where i.status = 'active'
    and (i.expires_at is null or i.expires_at > now())
    and i.observed_at > now() - make_interval(days => greatest(1, least(p_days, 120)))
    and (i.tier = 'public' or public.is_broker() or public.is_admin_user())
    and (p.id is null or p.country = 'EG')
    and (p_areas is null or cardinality(p_areas) = 0 or p.area = any(p_areas))
  order by i.observed_at desc
  limit greatest(1, least(p_limit, 40))
$$;
revoke all on function public.market_pulse_for_ai(text[], int, int) from public;
grant execute on function public.market_pulse_for_ai(text[], int, int) to anon, authenticated;
