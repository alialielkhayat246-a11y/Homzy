-- Tesla Developments catalog, extracted from the "TESLA Dev-REMAX Everest"
-- WhatsApp group. Idempotent: re-running replaces Tesla's projects.
-- Paste into the Supabase SQL editor and Run.
do $$
declare dev_id uuid; proj_id uuid;
begin
  insert into public.developers (name, slug, about, track_record, phone)
  values (
    'Tesla Developments',
    'tesla-developments',
    'Egyptian real-estate developer active in 6th of October, Hadayek October, and Badr City. Owners: Eng. Ahmed Basher and Yasser Saleh, with 15+ years of experience in real-estate development.',
    'Delivered Green Town (Hadayek October). Current portfolio: Green City, Green Plaza, Green Life, El Mokhabrat (immediate delivery), and the new launch Tesla Residence on Wahat Road.',
    '01115498784'
  )
  on conflict (slug) do update set about = excluded.about,
    track_record = excluded.track_record, phone = excluded.phone
  returning id into dev_id;

  delete from public.projects where developer_id = dev_id;

  -- 1) Tesla Residence -----------------------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'Tesla Residence', '6th of October – Wahat Road (in front of MSA University)',
    'New launch on Wahat Road directly in front of MSA University. 26 acres, G+5, 20% footprint / 80% facilities. Price per m² starts around 31,000–34,000.',
    '3 years', 'new launch',
    'Landscape, water features, swimming pools, underground parking, commercial mall. Semi-finished. Installments up to 11–12 years.')
  returning id into proj_id;
  insert into public.unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, down_payment, installment_years, payment_plan, finishing, delivery) values
   (proj_id, 'apartment', 2, 94, 103, 3426000, 4122000, '10–11%', 11, '10% DP + 5% on delivery, or 11% DP + 2% on delivery — installments up to 11 years', 'Semi-finished', '3 years'),
   (proj_id, 'apartment', 3, 121, 166, 4106000, 6063000, '10–11%', 11, '10% DP + 5% on delivery, or 11% DP + 2% on delivery — installments up to 11 years', 'Semi-finished', '3 years'),
   (proj_id, 'apartment', 4, 153, 186, 5590000, 7395000, '10–11%', 11, '10% DP + 5% on delivery, or 11% DP + 2% on delivery — installments up to 11 years', 'Semi-finished', '3 years'),
   (proj_id, 'hotel apartment', null, 42, null, 3225000, null, '10%', 12, 'Hotel/serviced apartments. 10% DP, installments up to 12 years. EOI 20,000 EGP refundable. Price/m² from 75,000.', 'Fully finished + furnished', '3 years');

  -- 2) Green City ----------------------------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'Green City', 'Hadayek October (6th of October)',
    '12 acres, G+5, construction ~80%, viewable on site. Price per m² from 25,000–34,000.',
    '6 months – 1 year', 'under construction',
    'Commercial mall, landscape, artificial lakes, mosque, smart gates (QR), 24/7 security, elevators, Italian-style facades.')
  returning id into proj_id;
  insert into public.unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, down_payment, installment_years, payment_plan, finishing, delivery) values
   (proj_id, 'apartment', 2, 139, 140, 4170000, 4480000, '15%', 8, '15% DP + 10% after 1 year + 5% after 2 years — installments up to 8 years', 'Semi-finished', '6 months – 1 year'),
   (proj_id, 'apartment', 3, 135, 226, 4170000, 7684000, '15%', 8, '15% DP + 10% after 1 year + 5% after 2 years — installments up to 8 years', 'Semi-finished', '6 months – 1 year'),
   (proj_id, 'penthouse', 5, 266, 289, 8470000, 9583000, '15%', 8, '15% DP + 10% after 1 year + 5% after 2 years — installments up to 8 years', 'Semi-finished', '6 months – 1 year');

  -- 3) Green Plaza ---------------------------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'Green Plaza', '6th of October – 4th District (next to El Bostan Compound)',
    '8 acres, 16 residential buildings G+5 (4 units/floor), 600 m² commercial area. Price per m² from 25,000.',
    '2 years', 'under construction',
    'Commercial / medical / administrative malls, landscape, lakes, smart gates (QR), Italian facades, elevators, 24/7 security.')
  returning id into proj_id;
  insert into public.unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, down_payment, installment_years, payment_plan, finishing, delivery) values
   (proj_id, 'apartment', null, 99, 200, null, null, '15%', 6, '15% DP + 10% on delivery — installments up to 6 years. Price/m² from 25,000.', 'Semi-finished', '2 years');

  -- 4) El Mokhabrat (Tesla Buildings) -------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'El Mokhabrat (Tesla Buildings)', 'Hadayek October – Mokhabrat Land (Italian district / touristic walkway)',
    '50 buildings, G+4, 2 units per floor. Immediate delivery — inspect and receive on the spot. Cash price/m² 18,000; 3-year installment price/m² 24,000.',
    'Immediate', 'ready',
    'Elevators, full utilities (electricity, gas, water). 3 bedrooms / 3 bathrooms / reception. Ground + private garden or typical floors.')
  returning id into proj_id;
  insert into public.unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, down_payment, installment_years, payment_plan, finishing, delivery) values
   (proj_id, 'apartment', 3, 147, 150, 3600000, 3768000, '30%', 3, '30% DP, installments up to 3 years. Cash price/m² 18,000 (25% cash discount). Garage 100,000.', 'Red brick / semi-finished', 'Immediate');

  -- 5) Green Life ----------------------------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'Green Life', 'Badr City – 4th District (near Orabi axis)',
    '8 acres, construction ~85%. Price per m² from 13,000.',
    '6 months', 'under construction',
    'Gated community in Badr City. Flexible short installment plan.')
  returning id into proj_id;
  insert into public.unit_types (project_id, type, bedrooms, size_from, size_to, price_from, price_to, down_payment, installment_years, payment_plan, finishing, delivery) values
   (proj_id, 'apartment', null, 100, 200, null, null, '30%', 3, '30% DP, installments up to 3 years. Price/m² from 13,000.', 'Semi-finished', '6 months');

  -- 6) Green Town (delivered showcase) ------------------------------------
  insert into public.projects (developer_id, name, area, description, delivery, status, amenities)
  values (dev_id, 'Green Town', 'Hadayek October',
    'Delivered and inhabited community — 8 acres, semi-finished. Part of the developer track record.',
    'Delivered', 'ready', '8 acres, semi-finished units.')
  returning id into proj_id;

end $$;
