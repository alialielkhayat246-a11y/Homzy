-- Marketplace tables: user listings, media, favorites, and listing-scoped
-- messaging. Named listing_conversations / listing_messages to avoid colliding
-- with the existing AI chat-memory tables (conversations / messages).
create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  purpose text not null default 'sale',          -- sale | rent
  type text not null default 'apartment',        -- apartment | duplex | villa | ...
  price numeric,
  currency text not null default 'EGP',
  area text,
  address text,
  bedrooms int,
  bathrooms int,
  floor int,
  size_sqm numeric,
  status text not null default 'pending',         -- pending | active | inactive | sold
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists listings_status_idx on public.listings(status);
create index if not exists listings_owner_idx  on public.listings(owner_id);
create index if not exists listings_area_idx    on public.listings(area);

create table if not exists public.listing_media (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  url text not null,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists listing_media_listing_idx on public.listing_media(listing_id);

create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists favorites_user_listing_uniq on public.favorites(user_id, listing_id) where listing_id is not null;
create unique index if not exists favorites_user_project_uniq on public.favorites(user_id, project_id) where project_id is not null;

create table if not exists public.listing_conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  last_message text,
  last_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists listing_conversations_uniq on public.listing_conversations(listing_id, buyer_id);
create index if not exists listing_conversations_buyer_idx  on public.listing_conversations(buyer_id);
create index if not exists listing_conversations_seller_idx on public.listing_conversations(seller_id);

create table if not exists public.listing_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.listing_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists listing_messages_conversation_idx on public.listing_messages(conversation_id, created_at);
