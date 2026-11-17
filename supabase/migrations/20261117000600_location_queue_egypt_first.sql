-- The audit's daily Gemini quota goes to Egyptian projects first: the hidden non-Egypt
-- projects are only checked when asked for by id.
create or replace function public.project_location_queue(p_key text, p_limit int default 1, p_project uuid default null,
                                                         p_shard int default 0, p_mod int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._check_cron_key(p_key) then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(x) from (
      select jsonb_build_object(
        'id', p.id, 'name', p.name, 'name_ar', p.name_ar, 'area', p.area, 'country', p.country,
        'location', p.location, 'developer', d.name,
        'description', left(coalesce(p.description, p.description_ar, ''), 1500),
        'cover', p.cover_image_url,
        'images', (select coalesce(jsonb_agg(m.url), '[]'::jsonb) from (
                     select url from public.project_media m where m.project_id = p.id and m.kind = 'image'
                      order by m.created_at limit 2) m),
        'brochure', (select m.url from public.project_media m where m.project_id = p.id and m.kind = 'brochure'
                      order by m.created_at limit 1),
        'whatsapp', (select coalesce(jsonb_agg(t.txt), '[]'::jsonb) from (
                     select left(u.message_text, 600) txt from public.catalog_updates u
                      where u.project_id = p.id and u.message_text is not null
                      order by u.message_at desc nulls last limit 6) t)
      ) x
      from public.projects p left join public.developers d on d.id = p.developer_id
      where (p_project is not null and p.id = p_project)
         or (p_project is null and p.location_verified_at is null and p.country = 'EG'
             and mod(abs(hashtext(p.id::text)), greatest(p_mod, 1)) = p_shard)
      order by (p.area is null), p.created_at
      limit greatest(1, least(p_limit, 20))
    ) q), '[]'::jsonb);
end $$;
revoke all on function public.project_location_queue(text, int, uuid, int, int) from public;
grant execute on function public.project_location_queue(text, int, uuid, int, int) to anon, authenticated;
