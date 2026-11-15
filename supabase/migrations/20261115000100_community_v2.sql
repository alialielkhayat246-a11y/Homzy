-- Broker community v2: one feed of structured cards (client requests / available units) instead of a chat
-- room per area, automatic matching against every broker's listings, collaborations that reveal phones only
-- after both sides agree, comments, reports, a daily digest — and developer updates in their own tab.

-- ---------------------------------------------------------------------------
-- Areas: one list for posts, listings and broker work areas (cluster = neighbouring areas that count as one)
-- ---------------------------------------------------------------------------
create table if not exists public.community_areas (
  slug text primary key,
  label_ar text not null,
  grp text not null,
  cluster text
);
create table if not exists public.community_area_alias (
  alias text primary key,
  slug text not null references public.community_areas(slug)
);
alter table public.community_areas enable row level security;
alter table public.community_area_alias enable row level security;
drop policy if exists community_areas_read on public.community_areas;
create policy community_areas_read on public.community_areas for select using (true);

insert into public.community_areas(slug, label_ar, grp, cluster) values
('new-cairo','القاهرة الجديدة','cairo','new-cairo'),
('tagamoa-1','التجمع الأول','cairo','new-cairo'),
('tagamoa-3','التجمع الثالث','cairo','new-cairo'),
('tagamoa-5','التجمع الخامس','cairo','new-cairo'),
('rehab','الرحاب','cairo','new-cairo'),
('madinaty','مدينتي','cairo',null),
('shorouk','الشروق','cairo',null),
('obour','العبور','cairo',null),
('badr','بدر','cairo',null),
('new-capital','العاصمة الإدارية','cairo',null),
('mostakbal','مدينة المستقبل','cairo',null),
('nasr-city','مدينة نصر','cairo',null),
('heliopolis','مصر الجديدة','cairo',null),
('sheraton','شيراتون','cairo',null),
('nozha','النزهة','cairo',null),
('almaza','الماظة','cairo',null),
('maadi','المعادي','cairo','maadi'),
('degla-maadi','دجلة المعادي','cairo','maadi'),
('zahraa-maadi','زهراء المعادي','cairo','maadi'),
('mokattam','المقطم','cairo',null),
('katameya','القطامية','cairo','new-cairo'),
('downtown','وسط البلد','cairo',null),
('garden-city','جاردن سيتي','cairo',null),
('zamalek','الزمالك','cairo',null),
('manial','المنيل','cairo',null),
('abbassia','العباسية','cairo',null),
('zaher','الظاهر','cairo',null),
('masr-qadima','مصر القديمة','cairo',null),
('sayeda-zeinab','السيدة زينب','cairo',null),
('helwan','حلوان','cairo',null),
('maasara','المعصرة','cairo',null),
('15-may','15 مايو','cairo',null),
('ain-shams','عين شمس','cairo',null),
('matareya','المطرية','cairo',null),
('zeitoun','الزيتون','cairo',null),
('hadayek-qobba','حدائق القبة','cairo',null),
('shubra','شبرا','cairo',null),
('rod-el-farag','روض الفرج','cairo',null),
('boulaq','بولاق أبو العلا','cairo',null),
('marg','المرج','cairo',null),
('dar-salam','دار السلام','cairo',null),
('basatin','البساتين','cairo',null),
('khalifa','الخليفة','cairo',null),
('mohandessin','المهندسين','giza',null),
('dokki','الدقي','giza',null),
('agouza','العجوزة','giza',null),
('haram','الهرم','giza',null),
('faisal','فيصل','giza',null),
('talbia','الطالبية','giza',null),
('omraneya','العمرانية','giza',null),
('imbaba','إمبابة','giza',null),
('boulaq-dakrour','بولاق الدكرور','giza',null),
('warraq','الوراق','giza',null),
('moneeb','المنيب','giza',null),
('oseem','أوسيم','giza',null),
('kerdasa','كرداسة','giza',null),
('abu-rawash','أبو رواش','giza',null),
('6-october','6 أكتوبر','giza','october'),
('new-october','أكتوبر الجديدة','giza','october'),
('sheikh-zayed','الشيخ زايد','giza','zayed'),
('new-zayed','زايد الجديدة','giza','zayed'),
('sphinx','سفنكس','giza',null),
('hadayek-october','حدائق أكتوبر','giza','october'),
('hadayek-ahram','حدائق الأهرام','giza',null),
('dreamland','دريم لاند','giza',null),
('beverly-hills','بيفرلي هيلز','giza',null),
('rabwa','الرابية','giza',null),
('hosary','الحصري','giza',null),
('motamayez','الحي المتميز','giza',null),
('badrashen','البدرشين','giza',null),
('hawamdeya','الحوامدية','giza',null),
('ayat','العياط','giza',null),
('saft-laban','صفط اللبن','giza',null),
('mansheyet-qanater','منشأة القناطر','giza',null),
('smouha','سموحة','alex',null),
('roushdy','رشدي','alex',null),
('sidi-gaber','سيدي جابر','alex',null),
('stanley','ستانلي','alex',null),
('san-stefano','سان ستيفانو','alex',null),
('gleem','جليم','alex',null),
('sporting','سبورتنج','alex',null),
('cleopatra','كليوباترا','alex',null),
('camp-caesar','كامب شيزار','alex',null),
('ibrahimia','الإبراهيمية','alex',null),
('raml-station','محطة الرمل','alex',null),
('miami','ميامي','alex',null),
('mandara','المندرة','alex',null),
('montazah','المنتزه','alex',null),
('asafra','العصافرة','alex',null),
('sidi-bishr','سيدي بشر','alex',null),
('louran','لوران','alex',null),
('bacos','باكوس','alex',null),
('fleming','فلمنج','alex',null),
('saba-pasha','سابا باشا','alex',null),
('bolkly','بولكلي','alex',null),
('kafr-abdo','كفر عبده','alex',null),
('zizinia','زيزينيا','alex',null),
('seyouf','السيوف','alex',null),
('abu-qir','أبو قير','alex',null),
('maamoura','المعمورة','alex',null),
('agami','العجمي','alex',null),
('bitash','البيطاش','alex',null),
('hanoville','الهانوفيل','alex',null),
('abu-talat','أبو تلات','alex',null),
('borg-el-arab','برج العرب','alex',null),
('amreya','العامرية','alex',null),
('max','المكس','alex',null),
('dekheila','الدخيلة','alex',null),
('anfoushi','الأنفوشي','alex',null),
('mansheya','المنشية','alex',null),
('attarin','العطارين','alex',null),
('moharram-bek','محرم بك','alex',null),
('wardian','الورديان','alex',null),
('karmouz','كرموز','alex',null),
('ras-el-tin','رأس التين','alex',null),
('cairo','القاهرة','cairo',null),
('giza','الجيزة','giza',null),
('alex','الإسكندرية','alex',null),
('north-coast','الساحل الشمالي','coast','north-coast'),
('new-alamein','العلمين الجديدة','coast','north-coast'),
('ras-el-hekma','رأس الحكمة','coast','north-coast'),
('sokhna','العين السخنة','coast',null),
('galala','الجلالة','coast',null),
('ras-sudr','رأس سدر','coast',null),
('hurghada','الغردقة','coast','red-sea'),
('red-sea','البحر الأحمر','coast','red-sea')
on conflict (slug) do update set label_ar = excluded.label_ar, grp = excluded.grp, cluster = excluded.cluster;

-- English / catalog spellings (broker work areas and projects.area use these)
insert into public.community_area_alias(alias, slug) values
('new cairo','new-cairo'),('5th settlement','tagamoa-5'),('fifth settlement','tagamoa-5'),('tagamoa','new-cairo'),('6th settlement','new-cairo'),
('new capital','new-capital'),('mostakbal city','mostakbal'),('shorouk','shorouk'),('shorouk city','shorouk'),('obour','obour'),('new obour','obour'),
('badr city','badr'),('sheikh zayed','sheikh-zayed'),('zayed','sheikh-zayed'),('new zayed','new-zayed'),('6th of october','6-october'),
('6 october','6-october'),('october','6-october'),('october gardens','hadayek-october'),('hadayek october','hadayek-october'),('new october','new-october'),
('north coast','north-coast'),('new alamein','new-alamein'),('ras el hekma','ras-el-hekma'),('ain sokhna','sokhna'),('sokhna','sokhna'),('galala','galala'),
('red sea','red-sea'),('hurghada','hurghada'),('el gouna','red-sea'),('soma bay','red-sea'),('sahl hasheesh','red-sea'),('makadi bay','red-sea'),
('ras sudr','ras-sudr'),('ras sudar','ras-sudr'),('ras sedr','ras-sudr'),('alexandria','alex'),('maadi','maadi'),('el maadi','maadi'),
('zahraa el maadi','zahraa-maadi'),('nasr city','nasr-city'),('naser city','nasr-city'),('heliopolis','heliopolis'),('new heliopolis','heliopolis'),
('sheraton','sheraton'),('mokattam','mokattam'),('el mokatam','mokattam'),('kattameya','katameya'),('old cairo','masr-qadima'),('madinaty','madinaty'),
('rehab','rehab'),('التجمع','new-cairo'),('أكتوبر','6-october'),('اكتوبر','6-october'),('زايد','sheikh-zayed'),('الساحل','north-coast'),('السخنة','sokhna')
on conflict (alias) do update set slug = excluded.slug;

alter table public.listings add column if not exists region_slug text references public.community_areas(slug);

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('request', 'unit')),
  area_slug text not null references public.community_areas(slug),
  purpose text check (purpose in ('sale', 'rent')),
  prop_type text,
  budget_min numeric check (budget_min is null or budget_min >= 0),
  budget_max numeric check (budget_max is null or budget_max >= 0),
  price numeric check (price is null or price >= 0),
  bedrooms int check (bedrooms is null or bedrooms between 0 and 20),
  delivery text check (delivery is null or delivery in ('ready', 'under_construction')),
  listing_id uuid references public.listings(id) on delete set null,
  body text not null default '' check (length(body) <= 1500),
  status text not null default 'open' check (status in ('open', 'closed', 'hidden')),
  closed_reason text,
  expires_at timestamptz not null default now() + interval '30 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists community_posts_feed_idx on public.community_posts(status, created_at desc);
create index if not exists community_posts_author_idx on public.community_posts(author_id, created_at desc);

create table if not exists public.community_comments (
  id bigserial primary key,
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(body) between 1 and 800),
  created_at timestamptz not null default now()
);
create index if not exists community_comments_post_idx on public.community_comments(post_id, created_at);

create table if not exists public.community_collabs (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete set null,
  message text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled', 'won', 'lost')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz
);
create unique index if not exists community_collabs_open_uq on public.community_collabs(post_id, requester_id)
  where status in ('pending', 'accepted');

create table if not exists public.community_reports (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (post_id, reporter_id)
);

create table if not exists public.community_matches (
  id bigserial primary key,
  request_id uuid not null references public.community_posts(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete cascade,
  unit_post_id uuid references public.community_posts(id) on delete cascade,
  broker_id uuid not null references public.profiles(id) on delete cascade,
  notified_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists community_matches_listing_uq on public.community_matches(request_id, listing_id) where listing_id is not null;
create unique index if not exists community_matches_unit_uq on public.community_matches(request_id, unit_post_id) where unit_post_id is not null and listing_id is null;

-- reads go through the functions below; brokers may select posts/comments directly only so realtime can push changes
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_collabs enable row level security;
alter table public.community_reports enable row level security;
alter table public.community_matches enable row level security;
drop policy if exists community_posts_brokers on public.community_posts;
create policy community_posts_brokers on public.community_posts for select to authenticated
  using ((status <> 'hidden' or author_id = auth.uid())
         and exists (select 1 from public.profiles pr where pr.id = auth.uid() and pr.role = 'broker'));
drop policy if exists community_comments_brokers on public.community_comments;
create policy community_comments_brokers on public.community_comments for select to authenticated
  using (exists (select 1 from public.profiles pr where pr.id = auth.uid() and pr.role = 'broker'));
drop policy if exists community_collabs_parties on public.community_collabs;
create policy community_collabs_parties on public.community_collabs for select to authenticated
  using (auth.uid() in (requester_id, owner_id));
grant select on public.community_posts, public.community_comments, public.community_collabs, public.community_areas to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.community_posts; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.community_comments; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.community_collabs; exception when duplicate_object then null; end;
end $$;

-- ---------------------------------------------------------------------------
-- Matching helpers
-- ---------------------------------------------------------------------------
-- any area spelling (slug, Arabic label, catalog/English name) -> community slug
create or replace function public._cm_slug(p text)
returns text language sql stable set search_path = public as $$
  select coalesce(
    (select slug from public.community_areas where slug = trim(p)),
    (select slug from public.community_area_alias where alias = lower(trim(p))),
    (select slug from public.community_areas where label_ar = trim(p)));
$$;

-- the community area of a listing: explicit region, its area text, its catalog project, or a label in its text
create or replace function public._cm_listing_region(l public.listings)
returns text language sql stable set search_path = public as $$
  select coalesce(
    (select slug from public.community_areas where slug = l.region_slug),
    public._cm_slug(l.area),
    (select public._cm_slug(pr.area) from public.projects pr
      where pr.name_ar = l.area or lower(pr.name) = lower(l.area) limit 1),
    (select a.slug from public.community_areas a
      where concat_ws(' ', l.area, l.address, l.title) like '%' || a.label_ar || '%'
      order by length(a.label_ar) desc limit 1));
$$;

-- does an offer in area u satisfy a request for area r (same area, same cluster, or the whole governorate)
create or replace function public._cm_area_ok(r text, u text)
returns boolean language sql stable set search_path = public as $$
  select r is not null and u is not null and (
    r = u
    or exists (select 1 from public.community_areas x join public.community_areas y on y.cluster = x.cluster
                where x.slug = r and y.slug = u and x.cluster is not null)
    or exists (select 1 from public.community_areas y where y.slug = u and y.grp = r));
$$;

create or replace function public._cm_fits(r public.community_posts, u_area text, u_type text, u_purpose text,
                                           u_price numeric, u_beds int)
returns boolean language sql stable set search_path = public as $$
  select public._cm_area_ok(r.area_slug, u_area)
     and (r.purpose is null or u_purpose is null or r.purpose = u_purpose)
     and (r.prop_type is null or r.prop_type = 'other' or u_type is null or u_type = r.prop_type
          or (r.prop_type in ('apartment','duplex','penthouse','studio') and u_type in ('apartment','duplex','penthouse','studio')))
     and (r.budget_max is null or u_price is null or u_price <= r.budget_max * 1.1)
     and (r.budget_min is null or u_price is null or u_price >= r.budget_min * 0.8)
     and (r.bedrooms is null or u_beds is null or u_beds between r.bedrooms and r.bedrooms + 1);
$$;

create or replace function public._cm_is_broker(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p and role = 'broker');
$$;

create or replace function public._cm_type_ar(t text)
returns text language sql immutable as $$
  select case t when 'apartment' then 'شقة' when 'villa' then 'فيلا' when 'townhouse' then 'تاون هاوس'
    when 'twinhouse' then 'توين هاوس' when 'duplex' then 'دوبلكس' when 'penthouse' then 'بنتهاوس' when 'studio' then 'ستوديو'
    when 'chalet' then 'شاليه' when 'office' then 'مكتب' when 'shop' then 'محل' when 'clinic' then 'عيادة'
    when 'land' then 'أرض' else 'وحدة' end;
$$;

-- ---------------------------------------------------------------------------
-- Matching: request <-> listings / unit posts; notifies the right brokers
-- ---------------------------------------------------------------------------
create or replace function public._cm_match(p_post uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.community_posts; lbl text; b record; nb int := 0; nm int := 0; nw int := 0; r public.community_posts;
begin
  select * into p from public.community_posts where id = p_post;
  if not found or p.status <> 'open' then return '{}'::jsonb; end if;
  select label_ar into lbl from public.community_areas where slug = p.area_slug;

  if p.kind = 'request' then
    insert into public.community_matches(request_id, listing_id, broker_id)
    select p.id, l.id, l.owner_id from public.listings l
     where l.status = 'active' and l.owner_id <> p.author_id and public._cm_is_broker(l.owner_id)
       and public._cm_fits(p, public._cm_listing_region(l), l.type, l.purpose, l.price, l.bedrooms)
    on conflict do nothing;
    insert into public.community_matches(request_id, unit_post_id, listing_id, broker_id)
    select p.id, u.id, u.listing_id, u.author_id from public.community_posts u
     where u.kind = 'unit' and u.status = 'open' and u.expires_at > now() and u.author_id <> p.author_id
       and public._cm_fits(p, u.area_slug, u.prop_type, u.purpose, u.price, u.bedrooms)
    on conflict do nothing;
    for b in select broker_id, count(*) n from public.community_matches where request_id = p.id and notified_at is null group by broker_id loop
      perform public._appt_notify(b.broker_id, 'community_match', '🎯 طلب عميل يناسب وحداتك',
        'بروكر عنده عميل عايز ' || public._cm_type_ar(p.prop_type) || ' في ' || coalesce(lbl, '') || ' — عندك ' || b.n
        || case when b.n = 1 then ' وحدة مناسبة' else ' وحدات مناسبة' end || '. اعرض تعاون من الكارت.',
        jsonb_build_object('post_id', p.id, 'url', '/community?post=' || p.id));
      nb := nb + 1; nm := nm + b.n;
    end loop;
    update public.community_matches set notified_at = now() where request_id = p.id and notified_at is null;
    -- brokers who work in this area (and had no match) hear about the request too
    for b in select pr.id from public.profiles pr
              where pr.role = 'broker' and pr.id <> p.author_id and pr.work_areas is not null
                and exists (select 1 from unnest(pr.work_areas) w where public._cm_area_ok(public._cm_slug(w), p.area_slug)
                                                                   or public._cm_area_ok(p.area_slug, public._cm_slug(w)))
                and not exists (select 1 from public.community_matches m where m.request_id = p.id and m.broker_id = pr.id) loop
      perform public._appt_notify(b.id, 'community_new', '🔔 طلب عميل جديد في ' || coalesce(lbl, 'منطقتك'),
        public._cm_type_ar(p.prop_type) || ' ' || case when p.purpose = 'rent' then 'للإيجار' else 'للبيع' end
        || coalesce(' — لحد ' || public._price_fmt(p.budget_max) || ' ج', '') || '. لو عندك المناسب اعرض تعاون.',
        jsonb_build_object('post_id', p.id, 'url', '/community?post=' || p.id));
      nw := nw + 1;
    end loop;
  else
    -- a new unit: tell the authors of open requests it fits
    for r in select * from public.community_posts q
              where q.kind = 'request' and q.status = 'open' and q.expires_at > now() and q.author_id <> p.author_id
                and public._cm_fits(q, p.area_slug, p.prop_type, p.purpose, p.price, p.bedrooms) loop
      insert into public.community_matches(request_id, unit_post_id, listing_id, broker_id, notified_at)
      values (r.id, p.id, p.listing_id, p.author_id, now()) on conflict do nothing;
      if found then
        perform public._appt_notify(r.author_id, 'community_match', '🏠 وحدة جديدة تناسب طلب عميلك',
          public._cm_type_ar(p.prop_type) || ' في ' || coalesce(lbl, '') || coalesce(' — ' || public._price_fmt(p.price) || ' ج', '')
          || '. افتح الكارت واعرض تعاون.', jsonb_build_object('post_id', p.id, 'url', '/community?post=' || p.id));
        nb := nb + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('brokers', nb, 'units', nm, 'area_brokers', nw);
end $$;

-- a listing that goes live is checked against open requests
create or replace function public._cm_listing_live()
returns trigger language plpgsql security definer set search_path = public as $$
declare r public.community_posts; reg text;
begin
  if new.status <> 'active' or (tg_op = 'UPDATE' and old.status = 'active' and old.price is not distinct from new.price) then return new; end if;
  if not public._cm_is_broker(new.owner_id) then return new; end if;
  reg := public._cm_listing_region(new);
  for r in select * from public.community_posts q
            where q.kind = 'request' and q.status = 'open' and q.expires_at > now() and q.author_id <> new.owner_id
              and public._cm_fits(q, reg, new.type, new.purpose, new.price, new.bedrooms) loop
    insert into public.community_matches(request_id, listing_id, broker_id, notified_at)
    values (r.id, new.id, new.owner_id, now()) on conflict do nothing;
    if found then
      perform public._appt_notify(r.author_id, 'community_match', '🏠 وحدة اتنشرت تناسب طلب عميلك',
        coalesce(new.title, 'وحدة') || coalesce(' — ' || public._price_fmt(new.price) || ' ج', ''),
        jsonb_build_object('post_id', r.id, 'listing_id', new.id, 'url', '/community?post=' || r.id));
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_cm_listing_live on public.listings;
create trigger trg_cm_listing_live after insert or update of status, price on public.listings
  for each row execute function public._cm_listing_live();

-- ---------------------------------------------------------------------------
-- Posts
-- ---------------------------------------------------------------------------
create or replace function public.community_post_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text := p->>'kind'; a text; l public.listings; new_id uuid; body text; m jsonb;
begin
  if uid is null or not public._cm_is_broker(uid) then return jsonb_build_object('ok', false, 'error', 'brokers_only'); end if;
  if (select count(*) from public.community_posts where author_id = uid and created_at > now() - interval '1 day') >= 15 then
    return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  if k not in ('request', 'unit') then return jsonb_build_object('ok', false, 'error', 'bad_kind'); end if;
  body := left(trim(coalesce(p->>'body', '')), 1500);
  a := public._cm_slug(p->>'area');
  if nullif(p->>'listing_id', '') is not null then
    select * into l from public.listings where id = (p->>'listing_id')::uuid and owner_id = uid and status = 'active';
    if not found then return jsonb_build_object('ok', false, 'error', 'listing_not_yours'); end if;
    a := coalesce(a, public._cm_listing_region(l));
  end if;
  if a is null then return jsonb_build_object('ok', false, 'error', 'area_required'); end if;
  if length(body) < 3 and l.id is null then return jsonb_build_object('ok', false, 'error', 'body_required'); end if;
  insert into public.community_posts(author_id, kind, area_slug, purpose, prop_type, budget_min, budget_max, price,
                                     bedrooms, delivery, listing_id, body)
  values (uid, k, a,
          coalesce(nullif(p->>'purpose', ''), l.purpose, 'sale'),
          coalesce(nullif(p->>'prop_type', ''), l.type),
          case when k = 'request' then nullif(p->>'budget_min', '')::numeric end,
          case when k = 'request' then nullif(p->>'budget_max', '')::numeric end,
          case when k = 'unit' then coalesce(nullif(p->>'price', '')::numeric, l.price) end,
          coalesce(nullif(p->>'bedrooms', '')::int, l.bedrooms),
          nullif(p->>'delivery', ''),
          l.id, coalesce(nullif(body, ''), l.title))
  returning community_posts.id into new_id;
  m := public._cm_match(new_id);
  return jsonb_build_object('ok', true, 'id', new_id, 'match', m);
end $$;

create or replace function public.community_post_set(p_id uuid, p_action text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p public.community_posts; adm boolean;
begin
  select * into p from public.community_posts where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  adm := exists (select 1 from public.profiles where id = uid and is_admin);
  if p.author_id <> uid and not adm then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_action = 'close' then
    update public.community_posts set status = 'closed', closed_reason = nullif(trim(coalesce(p_reason, '')), ''), updated_at = now() where id = p_id;
  elsif p_action = 'reopen' or p_action = 'renew' then
    if p.status = 'hidden' and not adm then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    update public.community_posts set status = 'open', closed_reason = null, expires_at = now() + interval '30 days', updated_at = now() where id = p_id;
    perform public._cm_match(p_id);
  elsif p_action = 'hide' and adm then
    update public.community_posts set status = 'hidden', updated_at = now() where id = p_id;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- the feed: newest first; areas filter matches clusters/governorates too
create or replace function public.community_feed(p_kind text default null, p_areas text[] default null, p_q text default null,
                                                 p_mine boolean default false, p_closed boolean default false,
                                                 p_post uuid default null, p_before timestamptz default null, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select p.id, p.kind, p.area_slug, a.label_ar as area_label, p.purpose, p.prop_type, p.budget_min, p.budget_max, p.price,
           p.bedrooms, p.delivery, p.body, p.status, p.closed_reason, p.expires_at, p.created_at, p.listing_id,
           p.author_id = uid as mine, p.expires_at <= now() as expired,
           jsonb_build_object('id', pr.id, 'name', pr.full_name, 'company', pr.company, 'logo', pr.company_logo_url,
             'verified', pr.phone_verified_at is not null,
             'rating', (select round(avg(f.broker_rating), 1) from public.appointment_feedback f
                         join public.appointments ap on ap.id = f.appointment_id where ap.broker_id = pr.id),
             'collabs_won', (select count(*) from public.community_collabs c
                              where c.status = 'won' and (c.requester_id = pr.id or c.owner_id = pr.id))) as author,
           case when p.listing_id is not null then (select jsonb_build_object('title', l.title, 'price', l.price, 'size', l.size_sqm,
                 'status', l.status, 'cover', (select m.url from public.listing_media m where m.listing_id = l.id order by m.sort limit 1))
               from public.listings l where l.id = p.listing_id) end as listing,
           (select count(*) from public.community_comments c where c.post_id = p.id) as comments,
           (select c.status from public.community_collabs c where c.post_id = p.id and c.requester_id = uid order by c.created_at desc limit 1) as my_collab,
           case when p.author_id = uid then (select count(*) from public.community_collabs c where c.post_id = p.id and c.status = 'pending') end as collab_pending,
           case when p.kind = 'request' then (select count(*) from public.community_matches m where m.request_id = p.id and m.broker_id = uid) end as my_matches,
           case when p.author_id = uid and p.kind = 'request' then (select count(*) from public.community_matches m where m.request_id = p.id) end as total_matches
      from public.community_posts p
      join public.community_areas a on a.slug = p.area_slug
      join public.profiles pr on pr.id = p.author_id
     where (p_post is null or p.id = p_post)
       and (p.status <> 'hidden' or p.author_id = uid)
       and (p_post is not null or p_mine or (p.status = 'open' and p.expires_at > now()) or (p_closed and p.status = 'closed'))
       and (not p_mine or p.author_id = uid)
       and (p_kind is null or p.kind = p_kind)
       and (p_areas is null or cardinality(p_areas) = 0 or exists (select 1 from unnest(p_areas) z
              where public._cm_area_ok(z, p.area_slug) or public._cm_area_ok(p.area_slug, z)))
       and (p_q is null or p.body ilike '%' || p_q || '%' or a.label_ar ilike '%' || p_q || '%')
       and (p_before is null or p.created_at < p_before)
     order by p.created_at desc
     limit least(coalesce(p_limit, 30), 60)) x), '[]'::jsonb);
end $$;

-- units that fit a request: the caller's own listings (to offer) and, for the author, everyone's
create or replace function public.community_post_matches(p_post uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); p public.community_posts;
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  select * into p from public.community_posts where id = p_post;
  if not found then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('listing_id', l.id, 'title', coalesce(l.title, u.body), 'price', coalesce(l.price, u.price),
             'area', coalesce(l.area, ca.label_ar), 'bedrooms', coalesce(l.bedrooms, u.bedrooms), 'unit_post_id', m.unit_post_id,
             'mine', m.broker_id = uid, 'broker', coalesce(pr.company, pr.full_name),
             'cover', (select md.url from public.listing_media md where md.listing_id = l.id order by md.sort limit 1)) order by m.created_at desc)
      from public.community_matches m
      left join public.listings l on l.id = m.listing_id
      left join public.community_posts u on u.id = m.unit_post_id
      left join public.community_areas ca on ca.slug = u.area_slug
      left join public.profiles pr on pr.id = m.broker_id
     where m.request_id = p_post and (m.broker_id = uid or p.author_id = uid)
       and (l.id is null or l.status = 'active')), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------
create or replace function public.community_comment_add(p_post uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p public.community_posts; nm text;
begin
  if uid is null or not public._cm_is_broker(uid) then return jsonb_build_object('ok', false, 'error', 'brokers_only'); end if;
  select * into p from public.community_posts where id = p_post and status <> 'hidden';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if length(trim(coalesce(p_body, ''))) < 1 then return jsonb_build_object('ok', false, 'error', 'body_required'); end if;
  insert into public.community_comments(post_id, author_id, body) values (p_post, uid, left(trim(p_body), 800));
  if p.author_id <> uid then
    select coalesce(company, full_name, 'بروكر') into nm from public.profiles where id = uid;
    perform public._appt_notify(p.author_id, 'community_comment', '💬 تعليق جديد على ' || case when p.kind = 'request' then 'طلبك' else 'وحدتك' end,
      nm || ': ' || left(trim(p_body), 120), jsonb_build_object('post_id', p_post, 'url', '/community?post=' || p_post));
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.community_comments_list(p_post uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'body', c.body, 'created_at', c.created_at, 'mine', c.author_id = uid,
            'author', jsonb_build_object('id', pr.id, 'name', pr.full_name, 'company', pr.company)) order by c.created_at)
     from public.community_comments c join public.profiles pr on pr.id = c.author_id where c.post_id = p_post), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Collaborations: phones are shared only after the post owner accepts
-- ---------------------------------------------------------------------------
create or replace function public.community_collab_request(p_post uuid, p_msg text default null, p_listing uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); p public.community_posts; nm text; cid uuid;
begin
  if uid is null or not public._cm_is_broker(uid) then return jsonb_build_object('ok', false, 'error', 'brokers_only'); end if;
  select * into p from public.community_posts where id = p_post and status = 'open';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  if p.author_id = uid then return jsonb_build_object('ok', false, 'error', 'own_post'); end if;
  if exists (select 1 from public.community_collabs where post_id = p_post and requester_id = uid and status in ('pending', 'accepted')) then
    return jsonb_build_object('ok', false, 'error', 'already'); end if;
  if p_listing is not null and not exists (select 1 from public.listings where id = p_listing and owner_id = uid) then p_listing := null; end if;
  insert into public.community_collabs(post_id, requester_id, owner_id, message, listing_id)
  values (p_post, uid, p.author_id, nullif(left(trim(coalesce(p_msg, '')), 500), ''), p_listing) returning id into cid;
  select coalesce(company, full_name, 'بروكر') into nm from public.profiles where id = uid;
  perform public._appt_notify(p.author_id, 'community_collab', '🤝 ' || nm || ' عايز يتعاون معاك',
    'على ' || case when p.kind = 'request' then 'طلب عميلك' else 'وحدتك' end || coalesce(': «' || left(trim(p_msg), 100) || '»', '') || ' — وافق عشان أرقامكم تظهر لبعض.',
    jsonb_build_object('collab_id', cid, 'post_id', p_post, 'url', '/community?tab=collabs'));
  return jsonb_build_object('ok', true, 'id', cid);
end $$;

create or replace function public.community_collab_set(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c public.community_collabs; nm text; other uuid;
begin
  select * into c from public.community_collabs where id = p_id;
  if not found or uid not in (c.requester_id, c.owner_id) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status in ('accepted', 'declined') and (uid <> c.owner_id or c.status <> 'pending') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_status = 'cancelled' and c.status not in ('pending', 'accepted') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_status in ('won', 'lost') and c.status <> 'accepted' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  if p_status not in ('accepted', 'declined', 'cancelled', 'won', 'lost') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  update public.community_collabs set status = p_status, updated_at = now(),
         responded_at = case when p_status in ('accepted', 'declined') then now() else responded_at end where id = p_id;
  other := case when uid = c.owner_id then c.requester_id else c.owner_id end;
  select coalesce(company, full_name, 'بروكر') into nm from public.profiles where id = uid;
  perform public._appt_notify(other, 'community_collab',
    case p_status when 'accepted' then '✅ ' || nm || ' وافق على التعاون' when 'declined' then nm || ' اعتذر عن التعاون'
      when 'won' then '🎉 التعاون مع ' || nm || ' اتقفل بصفقة' when 'lost' then 'التعاون مع ' || nm || ' اتقفل من غير صفقة'
      else nm || ' لغى طلب التعاون' end,
    case when p_status = 'accepted' then 'رقمه ظاهر دلوقتي في «تعاوناتي» — كلّمه على طول.' else '' end,
    jsonb_build_object('collab_id', p_id, 'url', '/community?tab=collabs'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.community_collabs_mine()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'updated_at' desc) from (
    select jsonb_build_object('id', c.id, 'status', c.status, 'message', c.message, 'created_at', c.created_at, 'updated_at', c.updated_at,
      'role', case when c.owner_id = uid then 'owner' else 'requester' end,
      'post', jsonb_build_object('id', p.id, 'kind', p.kind, 'body', p.body, 'area', a.label_ar, 'prop_type', p.prop_type,
                                 'budget_max', p.budget_max, 'price', p.price, 'status', p.status),
      'listing', case when c.listing_id is not null then (select jsonb_build_object('id', l.id, 'title', l.title, 'price', l.price)
                   from public.listings l where l.id = c.listing_id) end,
      'other', jsonb_build_object('id', o.id, 'name', o.full_name, 'company', o.company, 'verified', o.phone_verified_at is not null,
               'phone', case when c.status in ('accepted', 'won', 'lost') then coalesce(o.whatsapp, o.phone) end)) as x
      from public.community_collabs c
      join public.community_posts p on p.id = c.post_id
      join public.community_areas a on a.slug = p.area_slug
      join public.profiles o on o.id = case when c.owner_id = uid then c.requester_id else c.owner_id end
     where uid in (c.owner_id, c.requester_id)) s), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Reports: 3 different brokers hide a post until an admin looks at it
-- ---------------------------------------------------------------------------
create or replace function public.community_report(p_post uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; a record;
begin
  if uid is null or not public._cm_is_broker(uid) then return jsonb_build_object('ok', false, 'error', 'brokers_only'); end if;
  insert into public.community_reports(post_id, reporter_id, reason) values (p_post, uid, left(p_reason, 300)) on conflict do nothing;
  select count(*) into n from public.community_reports where post_id = p_post;
  if n >= 3 and exists (select 1 from public.community_posts where id = p_post and status <> 'hidden') then
    update public.community_posts set status = 'hidden', updated_at = now() where id = p_post;
    for a in select id from public.profiles where is_admin loop
      perform public._appt_notify(a.id, 'community_report', '⚑ بوست في الكميونتي اتخفى بعد 3 بلاغات',
        'راجعه وقرّر يرجع ولا لأ.', jsonb_build_object('post_id', p_post, 'url', '/community?post=' || p_post));
    end loop;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- Developer updates (separate tab): public + broker-tier items from the WhatsApp pipeline
-- ---------------------------------------------------------------------------
create or replace function public.community_dev_updates(p_category text default null, p_q text default null,
                                                        p_before timestamptz default null, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not public._cm_is_broker(uid) then raise exception 'brokers_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.observed_at desc) from (
    select i.id, i.category, i.content_ar, i.observed_at, i.tier, i.confidence,
           pj.id as project_id, coalesce(nullif(pj.name_ar, ''), pj.name) as project, pj.area as project_area,
           coalesce(nullif(d.name_ar, ''), d.name) as developer
      from public.project_intel i
      left join public.projects pj on pj.id = i.project_id
      left join public.developers d on d.id = coalesce(i.developer_id, pj.developer_id)
     where i.tier in ('public', 'broker') and i.status = 'active' and (i.expires_at is null or i.expires_at > now())
       and (p_category is null or i.category = p_category)
       and (p_q is null or i.content_ar ilike '%' || p_q || '%' or pj.name ilike '%' || p_q || '%' or pj.name_ar ilike '%' || p_q || '%'
            or d.name ilike '%' || p_q || '%' or d.name_ar ilike '%' || p_q || '%')
       and (p_before is null or i.observed_at < p_before)
     order by i.observed_at desc
     limit least(coalesce(p_limit, 30), 60)) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Daily digest (09:00 Cairo): what was posted in each broker's areas yesterday
-- ---------------------------------------------------------------------------
create or replace function public._cm_daily_digest()
returns void language plpgsql security definer set search_path = public as $$
declare b record; nr int; nu int;
begin
  for b in select id, work_areas from public.profiles where role = 'broker' and work_areas is not null and cardinality(work_areas) > 0 loop
    select count(*) filter (where kind = 'request'), count(*) filter (where kind = 'unit') into nr, nu
      from public.community_posts p
     where p.status = 'open' and p.created_at > now() - interval '1 day' and p.author_id <> b.id
       and exists (select 1 from unnest(b.work_areas) w where public._cm_area_ok(public._cm_slug(w), p.area_slug)
                                                         or public._cm_area_ok(p.area_slug, public._cm_slug(w)));
    if nr + nu > 0 then
      perform public._appt_notify(b.id, 'community_digest', '📬 الجديد في مناطقك',
        nr || ' طلب عميل و' || nu || ' وحدة اتنشروا امبارح في الكميونتي.', jsonb_build_object('url', '/community'));
    end if;
  end loop;
end $$;
select cron.unschedule('community-digest') where exists (select 1 from cron.job where jobname = 'community-digest');
select cron.schedule('community-digest', '0 7 * * *', 'select public._cm_daily_digest()');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant execute on function public.community_post_create(jsonb), public.community_post_set(uuid, text, text),
  public.community_feed(text, text[], text, boolean, boolean, uuid, timestamptz, int), public.community_post_matches(uuid),
  public.community_comment_add(uuid, text), public.community_comments_list(uuid),
  public.community_collab_request(uuid, text, uuid), public.community_collab_set(uuid, text), public.community_collabs_mine(),
  public.community_report(uuid, text), public.community_dev_updates(text, text, timestamptz, int) to authenticated;
revoke execute on function public.community_post_create(jsonb), public.community_post_set(uuid, text, text),
  public.community_feed(text, text[], text, boolean, boolean, uuid, timestamptz, int), public.community_post_matches(uuid),
  public.community_comment_add(uuid, text), public.community_comments_list(uuid),
  public.community_collab_request(uuid, text, uuid), public.community_collab_set(uuid, text), public.community_collabs_mine(),
  public.community_report(uuid, text), public.community_dev_updates(text, text, timestamptz, int),
  public._cm_match(uuid), public._cm_daily_digest() from anon;
revoke execute on function public._cm_match(uuid), public._cm_daily_digest() from authenticated;

-- broker public page: count collaborations closed with a deal
create or replace function public.broker_public_profile(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b public.profiles%rowtype;
begin
  select * into b from public.profiles where id = p_id and role = 'broker';
  if not found then return null; end if;
  return jsonb_build_object(
    'id', b.id, 'name', b.full_name, 'company', b.company, 'logo', b.company_logo_url, 'avatar', b.avatar_url,
    'phone', coalesce(b.whatsapp, b.phone), 'work_areas', b.work_areas, 'since', b.created_at,
    'verified', b.phone_verified_at is not null,
    'rating', (select jsonb_build_object('avg', round(avg(f.broker_rating), 1), 'n', count(*))
                 from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id
                where a.broker_id = p_id),
    'viewings_done', (select count(*) from public.appointments where broker_id = p_id and status = 'completed'),
    'collabs_won', (select count(*) from public.community_collabs c where c.status = 'won' and p_id in (c.requester_id, c.owner_id)),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object('rating', x.broker_rating, 'comment', x.comment, 'at', x.created_at)), '[]'::jsonb)
                  from (select f.broker_rating, f.comment, f.created_at
                          from public.appointment_feedback f join public.appointments a on a.id = f.appointment_id
                         where a.broker_id = p_id and nullif(trim(f.comment), '') is not null
                         order by f.created_at desc limit 6) x),
    'listings', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
                   select l.id, l.title, l.price, l.area, l.purpose, l.type, l.bedrooms, l.size_sqm, l.created_at,
                          (select m.url from public.listing_media m where m.listing_id = l.id order by m.sort limit 1) as cover
                     from public.listings l where l.owner_id = p_id and l.status = 'active'
                    order by l.created_at desc limit 30) x),
    'listings_count', (select count(*) from public.listings where owner_id = p_id and status = 'active'));
end $$;

-- the caller's work areas (profile) as community area slugs, for the feed's default filter
create or replace function public.community_my_areas()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct s) filter (where s is not null), '{}')
    from public.profiles p, unnest(coalesce(p.work_areas, '{}')) w, lateral (select public._cm_slug(w) s) x
   where p.id = auth.uid();
$$;
grant execute on function public.community_my_areas() to authenticated;
revoke execute on function public.community_my_areas() from anon;
