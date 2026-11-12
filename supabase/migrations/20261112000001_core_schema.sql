-- ReSky core schema
-- Run with: supabase db push   (or paste into the Supabase SQL editor in order)

create extension if not exists unaccent with schema extensions;
create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.user_role as enum ('user', 'moderator', 'founder');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.presence_status as enum ('online', 'away', 'dnd', 'invisible', 'offline');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Profiles (publicly readable identity) and private account data
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null check (char_length(display_name) between 1 and 40),
  status_message text not null default '' check (char_length(status_message) <= 140),
  presence public.presence_status not null default 'online',
  last_seen_at timestamptz not null default now(),
  role public.user_role not null default 'user',
  accent_color text check (accent_color is null or accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  theme_id text not null default 'classic_blue',
  border_id text not null default 'none',
  decoration_id text,
  avatar_asset_id uuid,
  banner_asset_id uuid,
  background_asset_id uuid,
  profile_visibility text not null default 'everyone' check (profile_visibility in ('everyone', 'contacts')),
  suspended_until timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));

create table if not exists public.account_private (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  date_of_birth date,
  suspension_reason text,
  notify_messages boolean not null default true,
  notify_calls boolean not null default true,
  notify_contact_status boolean not null default true,
  notify_sounds boolean not null default true,
  show_previews boolean not null default true,
  read_receipts_enabled boolean not null default true,
  typing_enabled boolean not null default true,
  online_visible boolean not null default true,
  terms_accepted_at timestamptz
);

-- Subscription entitlements: written ONLY by the service role (edge functions).
create table if not exists public.entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  plus_expires_at timestamptz,
  product_id text,
  original_transaction_id text unique,
  environment text,
  auto_renew boolean,
  revoked boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Uploaded profile artwork. Rows are created ONLY by the register-profile-asset
-- edge function, which inspects the file and decides is_animated server-side.
create table if not exists public.profile_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('avatar', 'banner', 'background', 'theme_art')),
  path text not null,
  static_path text,            -- first-frame still used when an animated asset is locked
  is_animated boolean not null default false,
  mime_type text not null,
  byte_size integer not null,
  created_at timestamptz not null default now()
);
create index if not exists profile_assets_user_idx on public.profile_assets (user_id);

alter table public.profiles
  drop constraint if exists profiles_avatar_fk,
  add constraint profiles_avatar_fk foreign key (avatar_asset_id) references public.profile_assets(id) on delete set null,
  drop constraint if exists profiles_banner_fk,
  add constraint profiles_banner_fk foreign key (banner_asset_id) references public.profile_assets(id) on delete set null,
  drop constraint if exists profiles_background_fk,
  add constraint profiles_background_fk foreign key (background_asset_id) references public.profile_assets(id) on delete set null;

-- Cosmetic catalogue (themes, borders, decorations). Founder manages it.
create table if not exists public.cosmetic_items (
  id text primary key,
  kind text not null check (kind in ('theme', 'border', 'decoration')),
  name text not null,
  is_premium boolean not null default false,
  is_released boolean not null default true,
  founder_only boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Contacts and blocking
-- ---------------------------------------------------------------------------
create table if not exists public.contacts (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  contact_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('requested', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  check (owner_id <> contact_id)
);
create index if not exists contacts_contact_idx on public.contacts (contact_id);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- ---------------------------------------------------------------------------
-- Conversations and messages
-- ---------------------------------------------------------------------------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text check (title is null or char_length(title) <= 60),
  direct_key text unique,              -- "<smaller uuid>:<larger uuid>" for 1:1 chats
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  shared_read_at timestamptz,          -- only advanced when the reader has read receipts on
  muted boolean not null default false,
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx on public.conversation_members (user_id);

create table if not exists public.messages (
  id uuid primary key,                 -- generated by the client so retries are idempotent
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  kind text not null default 'text' check (kind in ('text', 'image', 'video', 'audio', 'file', 'system')),
  body text check (body is null or char_length(body) <= 4000),
  attachment_path text,
  attachment_meta jsonb,
  reply_to uuid references public.messages(id) on delete set null,
  forwarded_from uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  search_vector tsvector generated always as (to_tsvector('simple', coalesce(body, ''))) stored
);
create index if not exists messages_conv_created_idx on public.messages (conversation_id, created_at desc);
create index if not exists messages_search_idx on public.messages using gin (search_vector);

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

-- ---------------------------------------------------------------------------
-- Calls
-- ---------------------------------------------------------------------------
create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete set null,
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('voice', 'video')),
  status text not null default 'ringing' check (status in ('ringing', 'active', 'ended', 'missed', 'declined')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer generated always as (
    case when answered_at is not null and ended_at is not null
      then greatest(0, extract(epoch from (ended_at - answered_at))::integer) end
  ) stored
);
create index if not exists calls_caller_idx on public.calls (caller_id, created_at desc);
create index if not exists calls_callee_idx on public.calls (callee_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Devices, push tokens, moderation
-- ---------------------------------------------------------------------------
create table if not exists public.user_devices (
  id uuid primary key,                 -- per-install id generated on device
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_name text not null,
  platform text not null default 'ios',
  app_version text,
  push_token text,
  push_environment text check (push_environment in ('sandbox', 'production')),
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists user_devices_user_idx on public.user_devices (user_id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid references public.profiles(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  asset_id uuid references public.profile_assets(id) on delete set null,
  category text not null check (category in ('username', 'display_name', 'profile', 'message', 'image', 'harassment', 'spam', 'other')),
  details text check (details is null or char_length(details) <= 1000),
  snapshot jsonb,                      -- copy of the reported content taken at report time
  status text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  resolved_by uuid references public.profiles(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  details jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.banned_terms (
  term text primary key,
  match_mode text not null default 'contains' check (match_mode in ('contains', 'exact'))
);

create table if not exists public.reserved_usernames (
  name text primary key
);

-- Login rate limiting (service role only)
create table if not exists public.login_attempts (
  id bigint generated always as identity primary key,
  key text not null,
  attempted_at timestamptz not null default now()
);
create index if not exists login_attempts_key_idx on public.login_attempts (key, attempted_at desc);
