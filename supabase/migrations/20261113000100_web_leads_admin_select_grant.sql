-- /inbox reads web_leads as the signed-in admin; RLS (web_leads_admin_select) already limits rows to admins,
-- but the authenticated role was missing the SELECT privilege itself, so the inbox always failed.
grant select on public.web_leads to authenticated;
