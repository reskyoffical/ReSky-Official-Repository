-- ReSky row level security, storage buckets, realtime and seed data

alter table public.profiles enable row level security;
alter table public.account_private enable row level security;
alter table public.entitlements enable row level security;
alter table public.profile_assets enable row level security;
alter table public.cosmetic_items enable row level security;
alter table public.contacts enable row level security;
alter table public.blocks enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.calls enable row level security;
alter table public.user_devices enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.banned_terms enable row level security;
alter table public.reserved_usernames enable row level security;
alter table public.login_attempts enable row level security;
-- banned_terms, reserved_usernames, login_attempts, moderation_actions: no policies
-- => only the service role and SECURITY DEFINER functions can touch them.

-- Profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Private account data
drop policy if exists account_private_own on public.account_private;
create policy account_private_own on public.account_private for select to authenticated using (user_id = auth.uid());

-- Entitlements: readable by owner, writable only by the service role
drop policy if exists entitlements_own on public.entitlements;
create policy entitlements_own on public.entitlements for select to authenticated using (user_id = auth.uid());

-- Profile assets: readable by signed-in users; deletable by owner; created by edge function only
drop policy if exists profile_assets_select on public.profile_assets;
create policy profile_assets_select on public.profile_assets for select to authenticated using (true);
drop policy if exists profile_assets_delete on public.profile_assets;
create policy profile_assets_delete on public.profile_assets for delete to authenticated using (user_id = auth.uid());

-- Cosmetics: released items for everyone; founder also sees unreleased previews
drop policy if exists cosmetics_select on public.cosmetic_items;
create policy cosmetics_select on public.cosmetic_items for select to authenticated
  using ((is_released and not founder_only) or public.is_founder()
         or (founder_only and exists (select 1 from public.profiles where id = auth.uid() and role = 'founder')));

-- Contacts / blocks
drop policy if exists contacts_select on public.contacts;
create policy contacts_select on public.contacts for select to authenticated
  using (owner_id = auth.uid() or contact_id = auth.uid());
drop policy if exists blocks_select on public.blocks;
create policy blocks_select on public.blocks for select to authenticated using (blocker_id = auth.uid());
drop policy if exists blocks_delete on public.blocks;
create policy blocks_delete on public.blocks for delete to authenticated using (blocker_id = auth.uid());

-- Conversations
drop policy if exists conversations_select on public.conversations;
create policy conversations_select on public.conversations for select to authenticated using (public.is_member(id));
drop policy if exists members_select on public.conversation_members;
create policy members_select on public.conversation_members for select to authenticated using (public.is_member(conversation_id));
drop policy if exists members_update_own on public.conversation_members;
create policy members_update_own on public.conversation_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member(conversation_id));

-- Messages
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select to authenticated using (public.is_member(conversation_id));
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.can_post(conversation_id));

-- Reactions
drop policy if exists reactions_select on public.message_reactions;
create policy reactions_select on public.message_reactions for select to authenticated
  using (public.is_member((select m.conversation_id from public.messages m where m.id = message_id)));
drop policy if exists reactions_insert on public.message_reactions;
create policy reactions_insert on public.message_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.can_post((select m.conversation_id from public.messages m where m.id = message_id)));
drop policy if exists reactions_delete on public.message_reactions;
create policy reactions_delete on public.message_reactions for delete to authenticated using (user_id = auth.uid());

-- Calls (writes go through RPCs)
drop policy if exists calls_select on public.calls;
create policy calls_select on public.calls for select to authenticated using (auth.uid() in (caller_id, callee_id));

-- Devices / sessions
drop policy if exists devices_all on public.user_devices;
create policy devices_all on public.user_devices for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Reports
drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_staff());

-- Column-level hardening on members (only these columns are user-editable)
revoke update on public.conversation_members from authenticated;
grant update (muted) on public.conversation_members to authenticated;

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 52428800, null)
on conflict (id) do update set public = false, file_size_limit = 52428800;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile', 'profile', true, 10485760, array['image/png', 'image/jpeg', 'image/gif', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 10485760,
  allowed_mime_types = array['image/png', 'image/jpeg', 'image/gif', 'image/webp'];

-- media/<conversation_id>/<file>: only conversation members
drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists media_insert on storage.objects;
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_post(((storage.foldername(name))[1])::uuid));

-- profile/<user_id>/<file>: owner writes, public reads (bucket is public)
drop policy if exists profile_insert on storage.objects;
create policy profile_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'profile' and (storage.foldername(name))[1] = auth.uid()::text and not public.is_suspended());
drop policy if exists profile_update on storage.objects;
create policy profile_update on storage.objects for update to authenticated
  using (bucket_id = 'profile' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists profile_delete on storage.objects;
create policy profile_delete on storage.objects for delete to authenticated
  using (bucket_id = 'profile' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['messages', 'calls', 'message_reactions', 'conversation_members'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Seed: reserved names, starter blocklist, cosmetics
-- ---------------------------------------------------------------------------
insert into public.reserved_usernames (name) values
  ('admin'), ('administrator'), ('moderator'), ('mod_team'), ('resky'), ('founder'), ('support'),
  ('official'), ('staff'), ('system'), ('security'), ('helpdesk'), ('root'), ('owner'), ('skype'), ('microsoft')
on conflict do nothing;

-- Starter list only. Extend it from the admin dashboard SQL or a maintained
-- blocklist (e.g. LDNOOBW) before launch. Short words that appear inside normal
-- words are set to 'exact' to avoid false positives.
insert into public.banned_terms (term, match_mode) values
  ('nigger', 'contains'), ('nigga', 'contains'), ('faggot', 'contains'), ('fagot', 'contains'),
  ('retard', 'contains'), ('tranny', 'contains'), ('chink', 'contains'), ('spic', 'exact'),
  ('kike', 'contains'), ('wetback', 'contains'), ('paki', 'exact'), ('gook', 'exact'),
  ('coon', 'exact'), ('dyke', 'exact'), ('raghead', 'contains'), ('beaner', 'contains'),
  ('hitler', 'contains'), ('nazi', 'exact'), ('kkk', 'exact'), ('heilhitler', 'contains'),
  ('rape', 'exact'), ('rapist', 'contains'), ('pedo', 'exact'), ('pedophile', 'contains'),
  ('killyourself', 'contains'), ('kys', 'exact'), ('iwillkillyou', 'contains'),
  ('porn', 'contains'), ('pussy', 'contains'), ('cunt', 'contains'), ('cock', 'exact'),
  ('dick', 'exact'), ('penis', 'contains'), ('vagina', 'contains'), ('blowjob', 'contains'),
  ('handjob', 'contains'), ('dildo', 'contains'), ('cum', 'exact'), ('sex', 'exact'),
  ('fuck', 'contains'), ('shit', 'contains'), ('bitch', 'contains'), ('whore', 'contains'),
  ('slut', 'contains'), ('motherfucker', 'contains'), ('asshole', 'contains'), ('bastard', 'contains')
on conflict do nothing;

insert into public.cosmetic_items (id, kind, name, is_premium, is_released, founder_only, payload, sort_order) values
  ('classic_blue', 'theme', 'Classic Blue', false, true,  false, '{"primary":"#00AFF0","background":"#EAF6FD","bubble":"#D9F1FD","dark":false}', 0),
  ('dark_mode',    'theme', 'Dark Mode',    false, true,  false, '{"primary":"#1E9BF0","background":"#0E1621","bubble":"#173149","dark":true}', 1),
  ('sunset',       'theme', 'Sunset',       true,  true,  false, '{"primary":"#F0743E","background":"#FFF3EA","bubble":"#FFE0C7","dark":false}', 2),
  ('green_nature', 'theme', 'Green Nature', true,  true,  false, '{"primary":"#3FA535","background":"#F1F9EA","bubble":"#DDF2CF","dark":false}', 3),
  ('neon',         'theme', 'Neon',         true,  true,  false, '{"primary":"#B44CFF","background":"#0D0A16","bubble":"#2A1840","dark":true}', 4),
  ('winter',       'theme', 'Winter',       true,  true,  false, '{"primary":"#2E9BE0","background":"#EEF7FD","bubble":"#DCEFFB","dark":false}', 5),
  ('minimalist',   'theme', 'Minimalist',   true,  true,  false, '{"primary":"#1E88E5","background":"#F6F9FC","bubble":"#EAF2FB","dark":false}', 6),
  ('retro',        'theme', 'Retro',        true,  true,  false, '{"primary":"#2A6EDB","background":"#EEF3FC","bubble":"#DCE8FA","dark":false}', 7),
  ('none',         'border', 'No border',      false, true,  false, '{}', 0),
  ('classic_blue', 'border', 'Classic Blue',   false, true,  false, '{"colors":["#00AFF0"]}', 1),
  ('online_green', 'border', 'Online Green',   false, true,  false, '{"colors":["#7FBA00"]}', 2),
  ('rainbow',      'border', 'Rainbow Ring',   true,  true,  false, '{"colors":["#FF5F6D","#FFC371","#7FBA00","#00AFF0","#8E44AD"],"animated":true}', 3),
  ('glow_cloud',   'border', 'Glow Cloud',     true,  true,  false, '{"colors":["#FFFFFF","#00AFF0"],"glow":true,"animated":true}', 4),
  ('founder_gold', 'border', 'Founder Gold',   true,  true,  true,  '{"colors":["#FFD86B","#F5A623","#FFF4C2"],"glow":true,"animated":true}', 99),
  ('sparkles',     'decoration', 'Sparkles',   true,  true,  false, '{"symbol":"sparkles"}', 1),
  ('clouds',       'decoration', 'Drifting Clouds', true, true, false, '{"symbol":"cloud.fill"}', 2),
  ('hearts',       'decoration', 'Hearts',     true,  true,  false, '{"symbol":"heart.fill"}', 3)
on conflict (id) do nothing;
