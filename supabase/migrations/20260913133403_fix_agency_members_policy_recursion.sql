
-- The old policy self-referenced agency_members inline -> infinite recursion.
drop policy if exists agmem_read on public.agency_members;
drop policy if exists agmem_read_team on public.agency_members;

-- Definer-based read (my_agency_ids bypasses RLS): a user sees their own row and
-- every member of any agency they belong to.
create policy agmem_read on public.agency_members for select to authenticated
  using (user_id = auth.uid() or agency_id in (select public.my_agency_ids()));
