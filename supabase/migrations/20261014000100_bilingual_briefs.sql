-- Bilingual briefs: Arabic twins for developer + project descriptive text,
-- plus where each brief came from (official site) and when.
alter table public.developers
  add column if not exists about_ar text,
  add column if not exists track_record_ar text,
  add column if not exists brief_source text,
  add column if not exists brief_updated_at timestamptz;

alter table public.projects
  add column if not exists description_ar text,
  add column if not exists amenities_ar text,
  add column if not exists brief_source text,
  add column if not exists brief_updated_at timestamptz;
