-- Rollup views for the Discover section (cities + developers with counts).
create or replace view public.v_city_counts
with (security_invoker = true) as
select p.area,
       count(distinct p.id) as projects,
       count(u.id)          as units
from public.projects p
left join public.unit_types u on u.project_id = p.id
where p.area is not null and p.area <> ''
group by p.area;

create or replace view public.v_developer_counts
with (security_invoker = true) as
select d.id, d.name, d.logo_url,
       count(distinct p.id) as projects
from public.developers d
join public.projects p on p.developer_id = d.id
group by d.id, d.name, d.logo_url
having count(distinct p.id) > 0;

grant select on public.v_city_counts to anon, authenticated;
grant select on public.v_developer_counts to anon, authenticated;
