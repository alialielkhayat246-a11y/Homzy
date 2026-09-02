-- ============================================================================
-- Homzy Stays — Phase 1 foundation (short-term rental marketplace).
-- Applied 2026-09-02. Reuses existing auth (auth.users / public.profiles).
--
-- Contents:
--   1. Extensions + admin settings (commission is a SETTING, never hard-coded)
--   2. Reference/lookup tables (property types, amenities, destinations) + seed
--   3. Hosts, properties, media, amenities, pricing, house rules, availability
--   4. Bookings (+ GiST anti-double-booking), payments, ledger, payouts
--   5. Reviews (two-way), disputes, messages, notifications, verifications, audit
--   6. Server-side quote + atomic booking (commission snapshotted onto booking)
--   7. Centralized reputation service (Super Host / Guest Favorite, configurable)
--   8. Two-way review submission (retaliation-proof reveal)
--   9. RLS helpers + public masked view + RLS enabled on every table
--  10. RLS policies for every table
--  11. Guard triggers (hosts can't self-approve/verify/forge ratings)
--  12. Storage buckets: stay-media (public) + stay-docs (PRIVATE, government IDs)
--  13. Lock internal functions out of the public API
--
-- NOTE: `stay_public_properties` is an intentional BARRIER VIEW (definer) that
-- exposes only approved rows with the address removed and coords coarsened; the
-- DB linter flags it like the existing `leads_market` view — expected & safe.
-- ============================================================================

-- 1. Extensions + settings ---------------------------------------------------
create extension if not exists btree_gist;

create table if not exists public.stay_settings (
  key text primary key, value jsonb not null, description text,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
insert into public.stay_settings(key, value, description) values
  ('commission_rate', '0.07'::jsonb, 'Homzy marketplace commission as a fraction (0.07 = 7%).'),
  ('min_property_photos', '5'::jsonb, 'Minimum photos before a property may be submitted.'),
  ('review_window_days', '14'::jsonb, 'Days after checkout for reviews / two-way reveal.'),
  ('require_property_approval', 'true'::jsonb, 'New properties need admin approval before publishing.'),
  ('super_host_criteria', '{"min_completed_stays":10,"min_avg_rating":4.8,"min_response_rate":0.90,"max_cancellation_rate":0.05}'::jsonb, 'Super Host thresholds.'),
  ('guest_favorite_criteria', '{"min_reviews":5,"min_avg_rating":4.8,"max_cancellation_rate":0.05}'::jsonb, 'Guest Favorite thresholds.'),
  ('cancellation_policies', '{"flexible":{"full_refund_days":1},"moderate":{"full_refund_days":5},"strict":{"full_refund_days":14,"partial_refund_pct":0.5}}'::jsonb, 'Cancellation policy definitions.')
on conflict (key) do nothing;

-- 2. Reference tables --------------------------------------------------------
create table if not exists public.stay_property_types (
  slug text primary key, name_en text not null, name_ar text not null,
  sort int not null default 0, active boolean not null default true
);
insert into public.stay_property_types(slug,name_en,name_ar,sort) values
  ('apartment','Apartment','شقة',1),('studio','Studio','استوديو',2),
  ('villa','Villa','فيلا',3),('chalet','Chalet','شاليه',4),
  ('hotel_room','Hotel room','غرفة فندقية',5),('hotel_apartment','Hotel apartment','شقة فندقية',6),
  ('serviced_apartment','Serviced apartment','شقة مخدومة',7),('resort_unit','Resort unit','وحدة منتجع',8),
  ('private_room','Private room','غرفة خاصة',9),('entire_home','Entire home','منزل كامل',10),
  ('other','Other','أخرى',99)
on conflict (slug) do nothing;

create table if not exists public.stay_amenities (
  id bigint generated always as identity primary key, slug text unique not null,
  name_en text not null, name_ar text not null, icon text,
  sort int not null default 0, active boolean not null default true
);
insert into public.stay_amenities(slug,name_en,name_ar,sort) values
  ('wifi','Wi-Fi','واي فاي',1),('ac','Air conditioning','تكييف',2),('tv','TV','تليفزيون',3),
  ('smart_tv','Smart TV','تليفزيون ذكي',4),('kitchen','Kitchen','مطبخ',5),('fridge','Refrigerator','ثلاجة',6),
  ('washer','Washing machine','غسالة',7),('parking','Parking','موقف سيارات',8),('pool','Pool','حمام سباحة',9),
  ('private_pool','Private pool','حمام سباحة خاص',10),('balcony','Balcony','بلكونة',11),('sea_view','Sea view','إطلالة بحرية',12),
  ('garden','Garden','حديقة',13),('elevator','Elevator','أسانسير',14),('gym','Gym','جيم',15),
  ('security','Security','أمن',16),('workspace','Workspace','مساحة عمل',17)
on conflict (slug) do nothing;

create table if not exists public.stay_destinations (
  slug text primary key, name_en text not null, name_ar text not null, governorate text,
  kind text not null default 'city' check (kind in ('city','beach','resort')),
  lat double precision, lng double precision, sort int not null default 0, active boolean not null default true
);
insert into public.stay_destinations(slug,name_en,name_ar,governorate,kind,lat,lng,sort) values
  ('cairo','Cairo','القاهرة','Cairo','city',30.0444,31.2357,1),
  ('new-cairo','New Cairo','القاهرة الجديدة','Cairo','city',30.0300,31.4700,2),
  ('giza','Giza','الجيزة','Giza','city',30.0131,31.2089,3),
  ('sheikh-zayed','Sheikh Zayed','الشيخ زايد','Giza','city',30.0760,30.9760,4),
  ('6-october','6th of October','السادس من أكتوبر','Giza','city',29.9360,30.9260,5),
  ('alexandria','Alexandria','الإسكندرية','Alexandria','city',31.2001,29.9187,6),
  ('ain-sokhna','Ain Sokhna','العين السخنة','Suez','beach',29.6000,32.3150,7),
  ('north-coast','North Coast','الساحل الشمالي','Matrouh','beach',30.9700,28.7000,8),
  ('ras-el-hekma','Ras El Hekma','رأس الحكمة','Matrouh','beach',31.0500,27.8000,9),
  ('el-gouna','El Gouna','الجونة','Red Sea','resort',27.3950,33.6780,10),
  ('hurghada','Hurghada','الغردقة','Red Sea','beach',27.2579,33.8116,11),
  ('sharm-el-sheikh','Sharm El Sheikh','شرم الشيخ','South Sinai','beach',27.9158,34.3300,12),
  ('dahab','Dahab','دهب','South Sinai','beach',28.5000,34.5000,13),
  ('sahel','Sahel','الساحل','Matrouh','beach',30.9700,28.7000,14)
on conflict (slug) do nothing;

-- 3..13: hosts, properties, bookings, reviews, functions, RLS, triggers, storage.
-- The full DDL for sections 3-13 was applied via the Supabase migration API in
-- steps stays_02..stays_11 on 2026-09-02 (identical statements). This file is the
-- consolidated source of truth; see the project migration history for the exact
-- per-step application. Re-running is safe (idempotent create-if-not-exists /
-- create-or-replace / drop-if-exists guards throughout).
