-- ReSky helper functions, moderation, triggers and RPCs

-- ---------------------------------------------------------------------------
-- Moderation: normalisation and checks (server-side source of truth)
-- ---------------------------------------------------------------------------
create or replace function public.normalize_for_moderation(input text)
returns text language sql stable set search_path = public, extensions as $$
  select regexp_replace(
           regexp_replace(
             translate(
               translate(lower(extensions.unaccent(normalize(coalesce(input, ''), NFKC))),
                         'аеорсухкмтні', 'aeopcyxkmthi'),           -- common Cyrillic look-alikes
               '013457@$!|8+9', 'oieastaslibtg'),                    -- leetspeak substitutions
             '[^a-z]', '', 'g'),                                     -- drop separators/symbols
           '(.)\1+', '\1', 'g')                                      -- collapse repeated letters
$$;

create or replace function public.text_is_offensive(input text)
returns boolean language sql stable security definer set search_path = public as $$
  with n as (select public.normalize_for_moderation(input) as v)
  select exists (
    select 1 from public.banned_terms b, n
    where (b.match_mode = 'contains' and position(public.normalize_for_moderation(b.term) in n.v) > 0)
       or (b.match_mode = 'exact' and public.normalize_for_moderation(b.term) = n.v)
  )
$$;

-- Returns NULL when allowed, otherwise: 'format' | 'taken' | 'reserved' | 'offensive'
create or replace function public.username_problem(candidate text, for_user uuid default null, allow_reserved boolean default false)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  c text := lower(coalesce(candidate, ''));
  norm text := public.normalize_for_moderation(c);
begin
  if c !~ '^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$' or c ~ '[_.]{2,}' then
    return 'format';
  end if;
  if public.text_is_offensive(c) then
    return 'offensive';
  end if;
  if not allow_reserved and exists (
    select 1 from public.reserved_usernames r
    where position(public.normalize_for_moderation(r.name) in norm) > 0
  ) then
    return 'reserved';
  end if;
  if exists (
    select 1 from public.profiles p
    where lower(p.username) = c and p.id is distinct from for_user
  ) then
    return 'taken';
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- Role / entitlement helpers
-- ---------------------------------------------------------------------------
create or replace function public.current_aal()
returns text language sql stable as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1')
$$;

create or replace function public.has_verified_mfa(uid uuid)
returns boolean language sql stable security definer set search_path = public, auth as $$
  select exists (select 1 from auth.mfa_factors f where f.user_id = uid and f.status::text = 'verified')
$$;

-- Founder check used for ADMIN actions: role must be founder, and if the founder
-- has enrolled 2FA the current session must have completed it (aal2).
create or replace function public.is_founder(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = uid and p.role = 'founder')
     and (not public.has_verified_mfa(uid) or public.current_aal() = 'aal2')
$$;

create or replace function public.is_staff(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = uid and p.role in ('moderator', 'founder'))
     and (not public.has_verified_mfa(uid) or public.current_aal() = 'aal2')
$$;

-- Premium check. Founder is ALWAYS premium, enforced here on the server, keyed by
-- user id + role (never by username), so renaming the founder changes nothing.
create or replace function public.has_plus(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = uid and p.role = 'founder')
      or exists (select 1 from public.entitlements e
                 where e.user_id = uid and not e.revoked and e.plus_expires_at > now())
$$;

create or replace function public.is_member(conv uuid, uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_members m where m.conversation_id = conv and m.user_id = uid)
$$;

create or replace function public.is_suspended(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = uid and p.suspended_until > now())
$$;

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a))
$$;

create or replace function public.are_contacts(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.contacts where owner_id = a and contact_id = b and status = 'accepted')
$$;

create or replace function public.can_post(conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_member(conv)
     and not public.is_suspended()
     and not exists (
       select 1 from public.conversations c
       join public.conversation_members m on m.conversation_id = c.id and m.user_id <> auth.uid()
       where c.id = conv and not c.is_group and public.is_blocked_between(auth.uid(), m.user_id)
     )
$$;

-- ---------------------------------------------------------------------------
-- New user bootstrap (runs when Supabase Auth creates a user)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  uname text := lower(trim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  dname text := trim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  dob date;
  -- app_metadata can only be written with the service-role key (bootstrap script),
  -- never by a normal sign-up request.
  founder_bootstrap boolean := coalesce(new.raw_app_meta_data ->> 'bootstrap_role', '') = 'founder';
  problem text;
begin
  if dname = '' then dname := uname; end if;
  begin
    dob := nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date;
  exception when others then dob := null;
  end;

  if founder_bootstrap and exists (select 1 from public.profiles where role = 'founder') then
    raise exception 'founder_already_exists';
  end if;

  problem := public.username_problem(uname, new.id, founder_bootstrap);
  if problem is not null then
    raise exception 'username_%', problem;
  end if;
  if public.text_is_offensive(dname) then
    raise exception 'display_name_offensive';
  end if;
  if not founder_bootstrap and (dob is null or dob > (current_date - interval '13 years')) then
    raise exception 'age_requirement';
  end if;

  insert into public.profiles (id, username, display_name, role, border_id)
  values (new.id, uname, left(dname, 40),
          case when founder_bootstrap then 'founder'::public.user_role else 'user'::public.user_role end,
          case when founder_bootstrap then 'founder_gold' else 'none' end);
  insert into public.account_private (user_id, date_of_birth, terms_accepted_at)
  values (new.id, dob, now());
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Profile protection: users may edit their own profile, but never role,
-- username (use change_username), suspension, or locked cosmetics.
-- This trigger is SECURITY INVOKER on purpose: inside our SECURITY DEFINER
-- RPCs current_user is the owner (postgres) and those paths are trusted.
-- ---------------------------------------------------------------------------
create or replace function public.protect_profile()
returns trigger language plpgsql set search_path = public as $$
declare
  trusted boolean := current_user in ('postgres', 'supabase_admin', 'service_role')
                     or coalesce(auth.jwt() ->> 'role', '') = 'service_role';
  item record;
  asset record;
  aid uuid;
begin
  if trusted then return new; end if;

  if new.role is distinct from old.role then raise exception 'role_change_forbidden'; end if;
  if new.username is distinct from old.username then raise exception 'use_change_username'; end if;
  if new.suspended_until is distinct from old.suspended_until then raise exception 'forbidden'; end if;
  if new.id is distinct from old.id or new.created_at is distinct from old.created_at then raise exception 'forbidden'; end if;

  if new.display_name is distinct from old.display_name and public.text_is_offensive(new.display_name) then
    raise exception 'display_name_offensive';
  end if;
  if new.status_message is distinct from old.status_message and public.text_is_offensive(new.status_message) then
    raise exception 'status_offensive';
  end if;

  -- Cosmetic catalogue checks
  for item in
    select c.* from public.cosmetic_items c
    where c.id in (new.theme_id, new.border_id, coalesce(new.decoration_id, ''))
  loop
    if item.founder_only and old.role <> 'founder' then raise exception 'cosmetic_unavailable'; end if;
    if not item.is_released and old.role not in ('founder') then raise exception 'cosmetic_unavailable'; end if;
    if item.is_premium and not public.has_plus(new.id) then raise exception 'plus_required'; end if;
  end loop;
  if new.decoration_id is not null and not public.has_plus(new.id) then
    raise exception 'plus_required';
  end if;
  if new.accent_color is distinct from old.accent_color and new.accent_color is not null
     and not public.has_plus(new.id) then
    -- free users may pick from the standard palette; custom hex needs Plus
    if upper(new.accent_color) not in ('#00AFF0', '#7FBA00', '#FF8C00', '#E3008C', '#8E44AD', '#2C3E50') then
      raise exception 'plus_required';
    end if;
  end if;

  -- Uploaded artwork must belong to the user; animated artwork needs Plus
  foreach aid in array array[new.avatar_asset_id, new.banner_asset_id, new.background_asset_id] loop
    if aid is not null then
      select * into asset from public.profile_assets where id = aid;
      if not found or asset.user_id <> new.id then raise exception 'asset_not_owned'; end if;
      if asset.is_animated and not public.has_plus(new.id) then raise exception 'plus_required'; end if;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists protect_profile_trg on public.profiles;
create trigger protect_profile_trg before update on public.profiles
  for each row execute function public.protect_profile();

-- ---------------------------------------------------------------------------
-- Message triggers
-- ---------------------------------------------------------------------------
create or replace function public.before_message_insert()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user not in ('postgres', 'supabase_admin', 'service_role') then
    new.sender_id := auth.uid();
    new.created_at := now();
    new.edited_at := null;
    new.deleted_at := null;
    if new.kind = 'system' then raise exception 'forbidden'; end if;
  end if;
  if new.kind = 'text' and coalesce(trim(new.body), '') = '' then raise exception 'empty_message'; end if;
  if new.kind <> 'text' and new.kind <> 'system' and new.attachment_path is null then raise exception 'attachment_required'; end if;
  if new.attachment_path is not null and split_part(new.attachment_path, '/', 1) <> new.conversation_id::text then
    raise exception 'attachment_path_mismatch';
  end if;
  return new;
end $$;

drop trigger if exists before_message_insert_trg on public.messages;
create trigger before_message_insert_trg before insert on public.messages
  for each row execute function public.before_message_insert();

create or replace function public.after_message_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  update public.conversation_members set last_read_at = new.created_at
    where conversation_id = new.conversation_id and user_id = new.sender_id;
  return new;
end $$;

drop trigger if exists after_message_insert_trg on public.messages;
create trigger after_message_insert_trg after insert on public.messages
  for each row execute function public.after_message_insert();

-- ---------------------------------------------------------------------------
-- Public profile view (respects profile visibility)
-- ---------------------------------------------------------------------------
create or replace view public.profile_cards with (security_invoker = true) as
select
  p.id,
  p.username,
  p.display_name,
  case when vis.full then p.status_message else '' end as status_message,
  case
    when p.presence = 'invisible' then 'offline'
    when p.last_seen_at < now() - interval '3 minutes' then 'offline'
    else p.presence::text
  end as presence,
  p.last_seen_at,
  p.role::text as role,
  public.has_plus(p.id) as is_plus,
  p.accent_color,
  p.theme_id,
  p.border_id,
  case when vis.full then p.decoration_id end as decoration_id,
  case when av.is_animated and not public.has_plus(p.id) then av.static_path else av.path end as avatar_path,
  coalesce(av.is_animated and public.has_plus(p.id), false) as avatar_animated,
  case when vis.full then (case when bn.is_animated and not public.has_plus(p.id) then bn.static_path else bn.path end) end as banner_path,
  case when vis.full then coalesce(bn.is_animated and public.has_plus(p.id), false) else false end as banner_animated,
  case when vis.full then (case when bg.is_animated and not public.has_plus(p.id) then bg.static_path else bg.path end) end as background_path,
  case when vis.full then coalesce(bg.is_animated and public.has_plus(p.id), false) else false end as background_animated,
  p.created_at
from public.profiles p
left join public.profile_assets av on av.id = p.avatar_asset_id
left join public.profile_assets bn on bn.id = p.banner_asset_id
left join public.profile_assets bg on bg.id = p.background_asset_id
cross join lateral (
  select (p.profile_visibility = 'everyone' or p.id = auth.uid()
          or public.are_contacts(p.id, auth.uid()) or public.is_staff()) as full
) vis;

-- ---------------------------------------------------------------------------
-- RPCs: account
-- ---------------------------------------------------------------------------
create or replace function public.check_username(candidate text)
returns text language plpgsql stable security definer set search_path = public as $$
declare problem text;
begin
  problem := public.username_problem(candidate, auth.uid(),
             coalesce((select role = 'founder' from public.profiles where id = auth.uid()), false));
  return coalesce(problem, 'ok');
end $$;

create or replace function public.change_username(new_username text)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  is_f boolean;
  problem text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select role = 'founder' into is_f from public.profiles where id = uid;
  -- The founder may use reserved names (e.g. resky_founder) — role, not name, grants this.
  problem := public.username_problem(new_username, uid, coalesce(is_f, false));
  if problem is not null then raise exception 'username_%', problem; end if;
  update public.profiles set username = lower(new_username) where id = uid;
  return lower(new_username);
end $$;

create or replace function public.heartbeat(new_presence text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set last_seen_at = now(),
         presence = coalesce(new_presence::public.presence_status, presence)
   where id = auth.uid();
end $$;

create or replace function public.update_privacy(
  p_read_receipts boolean, p_typing boolean, p_online_visible boolean, p_profile_visibility text,
  p_notify_messages boolean, p_notify_calls boolean, p_notify_contact_status boolean,
  p_notify_sounds boolean, p_show_previews boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.account_private set
    read_receipts_enabled = p_read_receipts, typing_enabled = p_typing, online_visible = p_online_visible,
    notify_messages = p_notify_messages, notify_calls = p_notify_calls,
    notify_contact_status = p_notify_contact_status, notify_sounds = p_notify_sounds, show_previews = p_show_previews
  where user_id = auth.uid();
  update public.profiles set profile_visibility = p_profile_visibility,
    presence = case when not p_online_visible then 'invisible'::public.presence_status
                    when presence = 'invisible' then 'online'::public.presence_status else presence end
  where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: contacts
-- ---------------------------------------------------------------------------
create or replace function public.send_contact_request(target_username text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  target uuid;
begin
  if me is null or public.is_suspended(me) then raise exception 'forbidden'; end if;
  select id into target from public.profiles where lower(username) = lower(trim(target_username));
  -- Same response for "not found" and "blocked" to avoid leaking block status
  if target is null or target = me or public.is_blocked_between(me, target) then
    return 'not_found';
  end if;
  if exists (select 1 from public.contacts where owner_id = target and contact_id = me) then
    -- they already asked us: accept both ways
    insert into public.contacts (owner_id, contact_id, status) values (me, target, 'accepted')
      on conflict (owner_id, contact_id) do update set status = 'accepted';
    update public.contacts set status = 'accepted' where owner_id = target and contact_id = me;
    return 'accepted';
  end if;
  insert into public.contacts (owner_id, contact_id, status) values (me, target, 'requested')
    on conflict do nothing;
  return 'requested';
end $$;

create or replace function public.respond_contact_request(requester uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not exists (select 1 from public.contacts where owner_id = requester and contact_id = me) then
    raise exception 'no_request';
  end if;
  if accept then
    update public.contacts set status = 'accepted' where owner_id = requester and contact_id = me;
    insert into public.contacts (owner_id, contact_id, status) values (me, requester, 'accepted')
      on conflict (owner_id, contact_id) do update set status = 'accepted';
  else
    delete from public.contacts where owner_id = requester and contact_id = me;
  end if;
end $$;

create or replace function public.remove_contact(other uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.contacts
   where (owner_id = auth.uid() and contact_id = other) or (owner_id = other and contact_id = auth.uid());
$$;

create or replace function public.block_user(other uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), other) on conflict do nothing;
  perform public.remove_contact(other);
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: conversations & messages
-- ---------------------------------------------------------------------------
create or replace function public.create_direct_conversation(other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  k text;
  conv uuid;
begin
  if me is null or other = me then raise exception 'invalid'; end if;
  if not public.are_contacts(me, other) or public.is_blocked_between(me, other) then
    raise exception 'not_a_contact';
  end if;
  k := least(me::text, other::text) || ':' || greatest(me::text, other::text);
  select id into conv from public.conversations where direct_key = k;
  if conv is null then
    insert into public.conversations (is_group, direct_key, created_by) values (false, k, me) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me), (conv, other);
  end if;
  return conv;
end $$;

create or replace function public.create_group_conversation(group_title text, member_ids uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
  m uuid;
begin
  if me is null or public.is_suspended(me) then raise exception 'forbidden'; end if;
  if public.text_is_offensive(group_title) then raise exception 'title_offensive'; end if;
  insert into public.conversations (is_group, title, created_by) values (true, left(group_title, 60), me) returning id into conv;
  insert into public.conversation_members (conversation_id, user_id) values (conv, me);
  foreach m in array member_ids loop
    if public.are_contacts(me, m) and not public.is_blocked_between(me, m) then
      insert into public.conversation_members (conversation_id, user_id) values (conv, m) on conflict do nothing;
    end if;
  end loop;
  return conv;
end $$;

create or replace function public.leave_conversation(conv uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.conversation_members where conversation_id = conv and user_id = auth.uid();
$$;

create or replace function public.mark_read(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare receipts boolean;
begin
  select read_receipts_enabled into receipts from public.account_private where user_id = auth.uid();
  update public.conversation_members
     set last_read_at = now(),
         shared_read_at = case when coalesce(receipts, true) then now() else shared_read_at end
   where conversation_id = conv and user_id = auth.uid();
end $$;

create or replace function public.edit_message(msg uuid, new_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(new_body), '') = '' then raise exception 'empty_message'; end if;
  update public.messages set body = new_body, edited_at = now()
   where id = msg and sender_id = auth.uid() and deleted_at is null and kind = 'text';
  if not found then raise exception 'cannot_edit'; end if;
end $$;

create or replace function public.delete_message(msg uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.messages set body = null, attachment_path = null, attachment_meta = null, deleted_at = now()
   where id = msg and sender_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'cannot_delete'; end if;
end $$;

create or replace function public.forward_message(msg uuid, target_conv uuid, new_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare src public.messages;
begin
  select * into src from public.messages where id = msg;
  if src.id is null or not public.is_member(src.conversation_id) or not public.can_post(target_conv) then
    raise exception 'forbidden';
  end if;
  if src.deleted_at is not null then raise exception 'deleted'; end if;
  if src.attachment_path is not null then
    raise exception 'forward_attachments_client_side'; -- client re-uploads attachments into the target conversation
  end if;
  insert into public.messages (id, conversation_id, sender_id, kind, body, forwarded_from, created_at)
  values (new_id, target_conv, auth.uid(), src.kind, src.body, src.id, now());
end $$;

create or replace function public.search_messages(q text, max_results integer default 50)
returns setof public.messages language sql stable security definer set search_path = public as $$
  select m.* from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id and cm.user_id = auth.uid()
  where m.deleted_at is null
    and (m.search_vector @@ websearch_to_tsquery('simple', q) or m.body ilike '%' || q || '%')
  order by m.created_at desc
  limit least(max_results, 200);
$$;

create or replace function public.my_conversations()
returns table (
  id uuid, is_group boolean, title text, last_message_at timestamptz,
  unread_count bigint, last_body text, last_kind text, last_sender_id uuid,
  other_user_id uuid, muted boolean
) language sql stable security definer set search_path = public as $$
  select c.id, c.is_group, c.title, c.last_message_at,
    (select count(*) from public.messages m
      where m.conversation_id = c.id and m.created_at > me.last_read_at
        and m.sender_id is distinct from auth.uid() and m.deleted_at is null) as unread_count,
    lm.body, lm.kind, lm.sender_id,
    (select om.user_id from public.conversation_members om
      where om.conversation_id = c.id and om.user_id <> auth.uid() limit 1) as other_user_id,
    me.muted
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id
  left join lateral (
    select m.body, m.kind, m.sender_id from public.messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where me.user_id = auth.uid()
  order by c.last_message_at desc;
$$;

-- ---------------------------------------------------------------------------
-- RPCs: calls (signalling state; media flows through LiveKit)
-- ---------------------------------------------------------------------------
create or replace function public.start_call(callee uuid, call_kind text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
  cid uuid;
begin
  if me is null or public.is_suspended(me) then raise exception 'forbidden'; end if;
  if not public.are_contacts(me, callee) or public.is_blocked_between(me, callee) then raise exception 'not_a_contact'; end if;
  conv := public.create_direct_conversation(callee);
  -- auto-expire stale ringing calls
  update public.calls set status = 'missed', ended_at = now()
   where status = 'ringing' and created_at < now() - interval '60 seconds'
     and (caller_id in (me, callee) or callee_id in (me, callee));
  insert into public.calls (conversation_id, caller_id, callee_id, kind) values (conv, me, callee, call_kind)
  returning id into cid;
  return cid;
end $$;

create or replace function public.answer_call(call uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.calls set status = 'active', answered_at = now()
   where id = call and callee_id = auth.uid() and status = 'ringing';
  if not found then raise exception 'call_unavailable'; end if;
end $$;

create or replace function public.decline_call(call uuid)
returns void language sql security definer set search_path = public as $$
  update public.calls set status = 'declined', ended_at = now()
   where id = call and callee_id = auth.uid() and status = 'ringing';
$$;

create or replace function public.end_call(call uuid)
returns void language sql security definer set search_path = public as $$
  update public.calls
     set status = case when status = 'ringing' then 'missed' else 'ended' end,
         ended_at = now()
   where id = call and auth.uid() in (caller_id, callee_id) and status in ('ringing', 'active');
$$;

-- ---------------------------------------------------------------------------
-- RPCs: reporting
-- ---------------------------------------------------------------------------
create or replace function public.report_content(
  p_category text, p_target_user uuid default null, p_message uuid default null,
  p_asset uuid default null, p_details text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  snap jsonb;
begin
  if p_message is not null then
    if not public.is_member((select conversation_id from public.messages where id = p_message)) then
      raise exception 'forbidden';
    end if;
    select jsonb_build_object('body', m.body, 'kind', m.kind, 'attachment_path', m.attachment_path,
                              'sender_id', m.sender_id, 'created_at', m.created_at)
      into snap from public.messages m where m.id = p_message;
    if p_target_user is null then
      select sender_id into p_target_user from public.messages where id = p_message;
    end if;
  elsif p_target_user is not null then
    select jsonb_build_object('username', p.username, 'display_name', p.display_name,
                              'status_message', p.status_message)
      into snap from public.profiles p where p.id = p_target_user;
  end if;
  insert into public.reports (reporter_id, target_user_id, message_id, asset_id, category, details, snapshot)
  values (auth.uid(), p_target_user, p_message, p_asset, p_category, left(p_details, 1000), snap)
  returning id into rid;
  return rid;
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: administration (founder / moderators). Every one checks the role
-- server-side via is_staff()/is_founder(), which use the user id, not a name.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_reports(only_open boolean default true)
returns setof public.reports language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return query select * from public.reports
    where (not only_open or status = 'open') order by created_at desc limit 200;
end $$;

create or replace function public.admin_resolve_report(report uuid, new_status text, note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  update public.reports set status = new_status, resolution_note = note, resolved_by = auth.uid(), resolved_at = now()
   where id = report;
  insert into public.moderation_actions (actor_id, action, details)
  values (auth.uid(), 'resolve_report', jsonb_build_object('report', report, 'status', new_status));
end $$;

create or replace function public.admin_suspend_user(target uuid, days integer, reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  if exists (select 1 from public.profiles where id = target and role = 'founder') then
    raise exception 'cannot_suspend_founder';
  end if;
  update public.profiles set suspended_until = now() + make_interval(days => days), presence = 'offline'
   where id = target;
  update public.account_private set suspension_reason = reason where user_id = target;
  insert into public.moderation_actions (actor_id, target_user_id, action, details)
  values (auth.uid(), target, 'suspend', jsonb_build_object('days', days, 'reason', reason));
end $$;

create or replace function public.admin_unsuspend_user(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  update public.profiles set suspended_until = null where id = target;
  insert into public.moderation_actions (actor_id, target_user_id, action) values (auth.uid(), target, 'unsuspend');
end $$;

-- Replaces an inappropriate username/display name with a neutral generated one
create or replace function public.admin_reset_identity(target uuid)
returns text language plpgsql security definer set search_path = public as $$
declare newname text;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  if exists (select 1 from public.profiles where id = target and role = 'founder') then raise exception 'forbidden'; end if;
  newname := 'user_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  update public.profiles set username = newname, display_name = newname, status_message = '' where id = target;
  insert into public.moderation_actions (actor_id, target_user_id, action, details)
  values (auth.uid(), target, 'reset_identity', jsonb_build_object('new_username', newname));
  return newname;
end $$;

create or replace function public.admin_remove_asset(asset uuid)
returns void language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  select user_id into owner from public.profile_assets where id = asset;
  delete from public.profile_assets where id = asset;   -- profile references are set null by FK
  insert into public.moderation_actions (actor_id, target_user_id, action, details)
  values (auth.uid(), owner, 'remove_asset', jsonb_build_object('asset', asset));
end $$;

create or replace function public.admin_find_user(q text)
returns table (id uuid, username text, display_name text, role text, suspended_until timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return query select p.id, p.username, p.display_name, p.role::text, p.suspended_until, p.created_at
    from public.profiles p
    where p.username ilike '%' || q || '%' or p.display_name ilike '%' || q || '%'
    order by p.created_at desc limit 50;
end $$;

create or replace function public.admin_set_moderator(target uuid, make_moderator boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_founder() then raise exception 'forbidden'; end if;
  update public.profiles set role = case when make_moderator then 'moderator'::public.user_role else 'user'::public.user_role end
   where id = target and role <> 'founder';
  insert into public.moderation_actions (actor_id, target_user_id, action, details)
  values (auth.uid(), target, 'set_moderator', jsonb_build_object('value', make_moderator));
end $$;

create or replace function public.admin_upsert_cosmetic(
  p_id text, p_kind text, p_name text, p_is_premium boolean, p_is_released boolean,
  p_founder_only boolean, p_payload jsonb, p_sort integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_founder() then raise exception 'forbidden'; end if;
  insert into public.cosmetic_items (id, kind, name, is_premium, is_released, founder_only, payload, sort_order)
  values (p_id, p_kind, p_name, p_is_premium, p_is_released, p_founder_only, p_payload, p_sort)
  on conflict (id) do update set kind = excluded.kind, name = excluded.name, is_premium = excluded.is_premium,
    is_released = excluded.is_released, founder_only = excluded.founder_only,
    payload = excluded.payload, sort_order = excluded.sort_order;
end $$;

create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'online', (select count(*) from public.profiles where last_seen_at > now() - interval '3 minutes' and presence <> 'invisible'),
    'plus', (select count(*) from public.entitlements where plus_expires_at > now() and not revoked),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'suspended', (select count(*) from public.profiles where suspended_until > now()),
    'messages_24h', (select count(*) from public.messages where created_at > now() - interval '24 hours')
  );
end $$;
