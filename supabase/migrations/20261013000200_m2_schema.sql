-- M2: Roam v1 schema. Every v1 entity from SPEC "Data model"; no tables for deferred features
-- (guides, list sharing, imports, leaderboards, trending, city scores, push).

create extension if not exists unaccent with schema extensions;

-- Enums -------------------------------------------------------------------------------------
create type public.experience_category as enum ('food_drink', 'outdoors', 'day_trips', 'culture', 'nightlife', 'activities', 'stays');
create type public.sentiment as enum ('liked', 'fine', 'disliked');
create type public.activity_type as enum ('rating', 'revisit', 'rerank');
create type public.notification_type as enum ('follow', 'like', 'comment');
create type public.media_state as enum ('staged', 'attached', 'deleting');
create type public.media_purpose as enum ('visit', 'avatar');
create type public.report_reason as enum ('incorrect_place_category', 'spam', 'inappropriate', 'other');
create type public.report_target as enum ('experience', 'activity', 'comment', 'media', 'member');
create type public.setup_checkpoint as enum ('profile_created', 'optional_details', 'complete');
create type public.place_provider as enum ('mapkit', 'fixture');
create type public.provider_status as enum ('active', 'unavailable');
create type public.deletion_state as enum ('pending', 'processing', 'completed', 'failed');

-- Reference data: the seven independent rankings ------------------------------------------
create table public.categories (
  id public.experience_category primary key,
  title text not null,
  sort_order smallint not null unique
);
insert into public.categories (id, title, sort_order) values
  ('food_drink', 'Food & Drink', 1), ('outdoors', 'Outdoors', 2), ('day_trips', 'Day Trips', 3),
  ('culture', 'Culture', 4), ('nightlife', 'Nightlife', 5), ('activities', 'Activities', 6), ('stays', 'Stays', 7);

-- Geography (counts/filters only; no score aggregates) --------------------------------------
create table public.countries (
  code char(2) primary key check (code ~ '^[A-Z]{2}$'),
  name text not null,
  source text not null default 'provider'
);

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  -- country|region|locality, lower-case and accent-folded (see app_private.city_key)
  city_key text not null unique,
  name text not null,
  region text,
  country_code char(2) not null references public.countries (code),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  source text not null default 'mapkit',
  source_version text not null default 'mapkit-ios18',
  created_at timestamptz not null default now()
);

-- Places and experiences (one Experience per resolved place) ---------------------------------
create table public.places (
  id uuid primary key default gen_random_uuid(),
  provider public.place_provider not null,
  provider_place_id text,
  name text not null check (char_length(name) between 1 and 300),
  normalized_name text not null,
  address text,
  normalized_address text,
  locality text,
  region text,
  country_code char(2) references public.countries (code),
  country_name text,
  city_id uuid references public.cities (id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  lat6 numeric(9, 6) generated always as (round(latitude::numeric, 6)) stored,
  lon6 numeric(9, 6) generated always as (round(longitude::numeric, 6)) stored,
  phone text,
  website text,
  provider_category text,
  time_zone text,
  is_locality boolean not null default false,
  status public.provider_status not null default 'active',
  -- No provider identity: kept distinct and flagged for future transactional reconciliation.
  needs_reconciliation boolean not null default false,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index places_provider_identity on public.places (provider, provider_place_id) where provider_place_id is not null;
create unique index places_fallback_identity on public.places (provider, normalized_name, normalized_address, lat6, lon6)
  where provider_place_id is null and not is_locality and normalized_address is not null;
create unique index places_locality_identity on public.places (provider, city_id)
  where provider_place_id is null and is_locality and city_id is not null;
create index places_geo on public.places (latitude, longitude);

create table public.experiences (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null unique references public.places (id),
  category public.experience_category,
  category_source text not null default 'suggested' check (category_source in ('suggested', 'confirmed')),
  category_locked_at timestamptz,
  created_at timestamptz not null default now(),
  check (category_locked_at is null or category is not null)
);

-- Profiles ----------------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique check (handle ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 50 and display_name = btrim(display_name)),
  bio text not null default '' check (char_length(bio) <= 160),
  avatar_path text,
  home_city_id uuid references public.cities (id) on delete set null,
  setup_checkpoint public.setup_checkpoint not null default 'profile_created',
  has_seen_been_intro boolean not null default false,
  -- Set when account deletion is requested: hides the member and blocks writes immediately.
  deactivated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  distance_unit text not null default 'km' check (distance_unit in ('km', 'mi')),
  haptics_enabled boolean not null default true,
  notify_follows boolean not null default true,
  notify_likes boolean not null default true,
  notify_comments boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Memories ----------------------------------------------------------------------------------
create table public.visits (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id),
  visit_date date,
  date_precision text not null default 'day' check (date_precision in ('day', 'unknown')),
  time_zone text,
  public_note text not null default '' check (char_length(public_note) <= 5000),
  source_operation_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((visit_date is null) = (date_precision = 'unknown'))
);
create index visits_owner_experience on public.visits (owner_id, experience_id);
create index visits_experience on public.visits (experience_id);

create table public.private_notes (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 10000),
  updated_at timestamptz not null default now(),
  primary key (owner_id, experience_id)
);

create table public.media (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  purpose public.media_purpose not null,
  visit_id uuid references public.visits (id) on delete set null,
  bucket text not null check (bucket in ('visit-media', 'avatars')),
  object_path text not null unique,
  position smallint not null default 0 check (position between 0 and 5),
  state public.media_state not null default 'staged',
  byte_size integer not null check (byte_size between 1 and 3145728),
  width integer not null check (width between 1 and 2048),
  height integer not null check (height between 1 and 2048),
  created_at timestamptz not null default now(),
  attached_at timestamptz,
  check (state <> 'attached' or purpose = 'avatar' or visit_id is not null)
);
create index media_visit on public.media (visit_id);
create index media_owner_state on public.media (owner_id, state, created_at);

-- Rankings ----------------------------------------------------------------------------------
create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id),
  category public.experience_category not null,
  sentiment public.sentiment not null,
  -- Tie group index inside (owner, category, sentiment): 0 = best. Equal values are ties.
  group_position integer not null check (group_position >= 0),
  score numeric(3, 1) not null check (score between 0 and 10),
  rank integer not null check (rank >= 1),
  first_rated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, experience_id)
);
create index ratings_owner_category on public.ratings (owner_id, category, sentiment, group_position);
create index ratings_experience on public.ratings (experience_id);

create table public.category_revisions (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  category public.experience_category not null,
  version bigint not null default 0,
  scoring_version text not null default 'roam-category-v1',
  updated_at timestamptz not null default now(),
  primary key (owner_id, category)
);

create table public.bookmarks (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid not null references public.experiences (id) on delete cascade,
  saved_at timestamptz not null default now(),
  primary key (owner_id, experience_id)
);
create index bookmarks_experience on public.bookmarks (experience_id);

-- Social ------------------------------------------------------------------------------------
create table public.activities (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  type public.activity_type not null,
  experience_id uuid not null references public.experiences (id),
  -- Deleting the referenced Visit or Rating removes the activity (SPEC lifecycle rules).
  visit_id uuid references public.visits (id) on delete cascade,
  rating_id uuid references public.ratings (id) on delete cascade,
  category public.experience_category not null,
  score_snapshot numeric(3, 1) check (score_snapshot between 0 and 10),
  rank_snapshot integer check (rank_snapshot >= 1),
  sentiment_snapshot public.sentiment,
  published_at timestamptz not null default now(),
  source_operation_id uuid not null,
  unique (author_id, source_operation_id)
);
create index activities_published on public.activities (published_at desc, id desc);
create index activities_author on public.activities (author_id, published_at desc, id desc);
create index activities_experience on public.activities (experience_id, published_at desc);
create index activities_rating on public.activities (rating_id);
create index activities_visit on public.activities (visit_id);

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee on public.follows (followee_id);

create table public.likes (
  actor_id uuid not null references public.profiles (id) on delete cascade,
  activity_id uuid not null references public.activities (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (actor_id, activity_id)
);
create index likes_activity on public.likes (activity_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000 and btrim(body) <> ''),
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  unique (author_id, operation_id)
);
create index comments_activity on public.comments (activity_id, created_at, id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  type public.notification_type not null,
  activity_id uuid references public.activities (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  event_key text not null unique,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (recipient_id <> actor_id)
);
create index notifications_recipient on public.notifications (recipient_id, created_at desc, id desc);

-- Safety ------------------------------------------------------------------------------------
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked on public.blocks (blocked_id);

create table public.mutes (
  muter_id uuid not null references public.profiles (id) on delete cascade,
  muted_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

create table public.reports (
  -- The client's operation UUID, so a retried report is stored once.
  id uuid primary key,
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  target_id uuid not null,
  reason public.report_reason not null,
  body text check (char_length(body) <= 1000),
  status text not null default 'received' check (status in ('received', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now()
);
create index reports_reporter on public.reports (reporter_id, created_at desc);

-- Server-only bookkeeping (never exposed through the Data API) ------------------------------
create table app_private.mutation_receipts (
  actor_id uuid not null references auth.users (id) on delete cascade,
  operation_id uuid not null,
  intent text not null,
  intent_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_id, operation_id)
);

create table app_private.account_deletion_jobs (
  id uuid primary key default gen_random_uuid(),
  -- No foreign key: the job record outlives the deleted auth user.
  user_id uuid not null unique,
  state public.deletion_state not null default 'pending',
  apple_revocation text not null default 'pending'
    check (apple_revocation in ('pending', 'not_applicable', 'completed', 'not_configured', 'failed')),
  storage_cleanup text not null default 'pending' check (storage_cleanup in ('pending', 'completed', 'failed')),
  attempts integer not null default 0,
  last_error text,
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table app_private.storage_cleanup (
  id bigint generated always as identity primary key,
  bucket text not null,
  object_path text not null,
  reason text not null,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  unique (bucket, object_path)
);
