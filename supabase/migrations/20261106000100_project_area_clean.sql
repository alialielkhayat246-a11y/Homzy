-- Keep projects.area a short area name ("6th of October"), never a full address.
-- WhatsApp updates sometimes carry "6th of October – 4th District (next to …)";
-- that broke area filters and /area pages. The detail moves to projects.location.
create or replace function public._project_area_clean()
returns trigger language plpgsql as $$
declare short text;
begin
  if new.area ~ '( – | - | — |\(|,)' then
    short := btrim(regexp_replace(split_part(split_part(split_part(new.area, ' – ', 1), ' — ', 1), ' - ', 1), '\s*[\(,].*$', ''));
    if short <> '' and short <> new.area then
      new.location := coalesce(nullif(new.location, ''), new.area);
      new.area := short;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_project_area_clean on public.projects;
create trigger trg_project_area_clean before insert or update of area on public.projects
  for each row execute function public._project_area_clean();
