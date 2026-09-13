
-- Global, expandable permission catalog (§4: add perms later without redesign).
create table if not exists public.permissions (
  key         text primary key,
  category    text not null,
  name_en     text not null,
  name_ar     text not null,
  sort        int  not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.permissions enable row level security;

-- Everyone signed-in may READ the catalog (needed to render role editors).
drop policy if exists perm_read on public.permissions;
create policy perm_read on public.permissions for select to authenticated using (true);
-- Only platform admins may change the catalog.
drop policy if exists perm_admin on public.permissions;
create policy perm_admin on public.permissions for all to authenticated
  using (public.stay_is_admin()) with check (public.stay_is_admin());

insert into public.permissions (key, category, name_en, name_ar, sort) values
  ('lead.view',        'leads','View leads','عرض العملاء',10),
  ('lead.view.all',    'leads','View all agency leads','عرض كل عملاء الوكالة',11),
  ('lead.create',      'leads','Create leads','إضافة عملاء',12),
  ('lead.edit',        'leads','Edit leads','تعديل العملاء',13),
  ('lead.delete',      'leads','Delete leads','حذف العملاء',14),
  ('lead.assign',      'leads','Assign leads','توزيع العملاء',15),
  ('owner.view',       'owners','View owners','عرض الملاك',20),
  ('owner.view.all',   'owners','View all agency owners','عرض كل ملاك الوكالة',21),
  ('owner.create',     'owners','Create owners','إضافة ملاك',22),
  ('owner.edit',       'owners','Edit owners','تعديل الملاك',23),
  ('owner.delete',     'owners','Delete owners','حذف الملاك',24),
  ('owner.view_phone', 'owners','View owner phone numbers','عرض أرقام الملاك',25),
  ('property.view',    'properties','View properties','عرض الوحدات',30),
  ('property.create',  'properties','Create properties','إضافة وحدات',31),
  ('property.edit',    'properties','Edit properties','تعديل الوحدات',32),
  ('property.delete',  'properties','Delete properties','حذف الوحدات',33),
  ('property.publish', 'properties','Publish properties','نشر الوحدات',34),
  ('deal.view',        'deals','View deals','عرض الصفقات',40),
  ('deal.view.all',    'deals','View all agency deals','عرض كل صفقات الوكالة',41),
  ('deal.create',      'deals','Create deals','إضافة صفقات',42),
  ('deal.edit',        'deals','Edit deals','تعديل الصفقات',43),
  ('deal.close',       'deals','Close deals','إغلاق الصفقات',44),
  ('task.view',        'tasks','View tasks','عرض المهام',50),
  ('task.create',      'tasks','Create tasks','إضافة مهام',51),
  ('task.assign',      'tasks','Assign tasks','توزيع المهام',52),
  ('team.view',        'team','View team members','عرض أعضاء الفريق',60),
  ('team.manage',      'team','Manage team members','إدارة أعضاء الفريق',61),
  ('report.view',      'reports','View reports','عرض التقارير',70),
  ('commission.view',  'commissions','View commissions','عرض العمولات',80),
  ('commission.manage','commissions','Manage commissions','إدارة العمولات',81),
  ('agency.settings',  'settings','Manage agency settings','إدارة إعدادات الوكالة',90)
on conflict (key) do update
  set category=excluded.category, name_en=excluded.name_en, name_ar=excluded.name_ar, sort=excluded.sort;
