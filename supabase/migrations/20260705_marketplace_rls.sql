-- RLS for the marketplace + a public 'listings' storage bucket for photos.
alter table public.listings              enable row level security;
alter table public.listing_media         enable row level security;
alter table public.favorites             enable row level security;
alter table public.listing_conversations enable row level security;
alter table public.listing_messages      enable row level security;

-- listings: anyone reads active; owner reads/manages own
create policy listings_read_active on public.listings for select
  using (status = 'active' or owner_id = auth.uid());
create policy listings_insert_own on public.listings for insert
  with check (owner_id = auth.uid());
create policy listings_update_own on public.listings for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy listings_delete_own on public.listings for delete
  using (owner_id = auth.uid());

-- listing_media follows its listing
create policy media_read on public.listing_media for select
  using (exists (select 1 from public.listings l where l.id = listing_media.listing_id
                 and (l.status = 'active' or l.owner_id = auth.uid())));
create policy media_write on public.listing_media for all
  using (exists (select 1 from public.listings l where l.id = listing_media.listing_id and l.owner_id = auth.uid()))
  with check (exists (select 1 from public.listings l where l.id = listing_media.listing_id and l.owner_id = auth.uid()));

-- favorites: private to the user
create policy favorites_own on public.favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- conversations + messages: only the two participants
create policy conv_participants on public.listing_conversations for select
  using (auth.uid() in (buyer_id, seller_id));
create policy conv_insert on public.listing_conversations for insert
  with check (auth.uid() = buyer_id);
create policy conv_update on public.listing_conversations for update
  using (auth.uid() in (buyer_id, seller_id));

create policy msg_read on public.listing_messages for select
  using (exists (select 1 from public.listing_conversations c where c.id = listing_messages.conversation_id
                 and auth.uid() in (c.buyer_id, c.seller_id)));
create policy msg_insert on public.listing_messages for insert
  with check (sender_id = auth.uid() and exists (
    select 1 from public.listing_conversations c where c.id = listing_messages.conversation_id
      and auth.uid() in (c.buyer_id, c.seller_id)));
create policy msg_update_read on public.listing_messages for update
  using (exists (select 1 from public.listing_conversations c where c.id = listing_messages.conversation_id
                 and auth.uid() in (c.buyer_id, c.seller_id)));

insert into storage.buckets (id, name, public)
values ('listings', 'listings', true)
on conflict (id) do nothing;

create policy listing_photos_read on storage.objects for select
  using (bucket_id = 'listings');
create policy listing_photos_insert on storage.objects for insert
  with check (bucket_id = 'listings' and auth.role() = 'authenticated');
create policy listing_photos_modify on storage.objects for update
  using (bucket_id = 'listings' and owner = auth.uid());
create policy listing_photos_delete on storage.objects for delete
  using (bucket_id = 'listings' and owner = auth.uid());
