-- Secondary-market (resale) asking prices aggregated from external portals
-- (RE/MAX Egypt first) to power the price estimator. Public-read; writes go
-- through the SECURITY DEFINER import_resale() RPC used by the fetchers.
create table if not exists public.resale_listings (
  id uuid primary key default gen_random_uuid(),
  source text not null,             -- 'remax' | 'propertyfinder'
  external_id text not null,
  purpose text not null default 'sale',
  type text,
  area text,                        -- canonical area (matches catalog)
  region text,                      -- raw source region string
  price numeric,
  size_sqm numeric,
  bedrooms int,
  url text,
  fetched_at timestamptz not null default now(),
  unique (source, external_id)
);
create index if not exists resale_area_type_idx on public.resale_listings(area, type);

alter table public.resale_listings enable row level security;
create policy resale_public_read on public.resale_listings for select using (true);

create or replace function public.import_resale(items jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  insert into public.resale_listings
    (source, external_id, purpose, type, area, region, price, size_sqm, bedrooms, url)
  select i->>'source', i->>'external_id', coalesce(nullif(i->>'purpose',''),'sale'),
         nullif(i->>'type',''), nullif(i->>'area',''), nullif(i->>'region',''),
         nullif(i->>'price','')::numeric, nullif(i->>'size_sqm','')::numeric,
         nullif(i->>'bedrooms','')::int, nullif(i->>'url','')
  from jsonb_array_elements(items) i
  where i->>'external_id' is not null
  on conflict (source, external_id) do update set
    purpose = excluded.purpose, type = excluded.type, area = excluded.area,
    region = excluded.region, price = excluded.price, size_sqm = excluded.size_sqm,
    bedrooms = excluded.bedrooms, url = excluded.url, fetched_at = now();
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.import_resale(jsonb) to anon, authenticated;
