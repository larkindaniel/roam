-- M2: profile, setup, media registration and follow RPCs. Every function derives the actor from
-- the JWT, fixes search_path, validates input and is executable only by signed-in clients.

-- JSON projections ---------------------------------------------------------------------------
create or replace function app_private.member_json(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'handle', p.handle, 'displayName', p.display_name,
                            'avatarPath', case when p.avatar_path is null then null else 'avatars/' || p.avatar_path end)
  from public.profiles p where p.id = p_id
$$;

create or replace function app_private.destination_json(p_city_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('name', c.name, 'region', c.region, 'countryCode', c.country_code, 'countryName', k.name,
                            'latitude', coalesce(c.latitude, 0), 'longitude', coalesce(c.longitude, 0), 'radiusMeters', 15000)
  from public.cities c join public.countries k on k.code = c.country_code
  where c.id = p_city_id
$$;

create or replace function app_private.own_profile_json(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'handle', p.handle, 'displayName', p.display_name, 'bio', p.bio,
    'avatarPath', case when p.avatar_path is null then null else 'avatars/' || p.avatar_path end,
    'homeCity', app_private.destination_json(p.home_city_id), 'setupCheckpoint', p.setup_checkpoint,
    'hasSeenBeenIntro', p.has_seen_been_intro, 'createdAt', p.created_at)
  from public.profiles p where p.id = p_id
$$;

-- Geography upserts ----------------------------------------------------------------------------
create or replace function app_private.upsert_country(p_code text, p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_code text := upper(p_code);
begin
  if v_code is null or v_code !~ '^[A-Z]{2}$' then
    return null;
  end if;
  insert into public.countries (code, name) values (v_code, coalesce(nullif(btrim(p_name), ''), v_code))
  on conflict on constraint countries_pkey do nothing;
  return v_code;
end;
$$;

create or replace function app_private.upsert_city(p_country_code text, p_country_name text, p_region text, p_locality text,
                                                   p_latitude double precision, p_longitude double precision)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_code text := app_private.upsert_country(p_country_code, p_country_name);
  v_key text := app_private.city_key(v_code, p_region, p_locality);
  v_city uuid;
begin
  if v_key is null then
    return null;
  end if;
  insert into public.cities (city_key, name, region, country_code, latitude, longitude)
  values (v_key, btrim(p_locality), nullif(btrim(p_region), ''), v_code, p_latitude, p_longitude)
  on conflict on constraint cities_city_key_key do update
    set latitude = coalesce(public.cities.latitude, excluded.latitude),
        longitude = coalesce(public.cities.longitude, excluded.longitude)
  returning id into v_city;
  return v_city;
end;
$$;

create or replace function app_private.validation_error(message text)
returns void language plpgsql set search_path = '' as $$
begin
  raise exception 'roam:validation:%', message using errcode = '22023';
end;
$$;

create or replace function app_private.validate_profile_fields(p_display_name text, p_handle text, p_bio text)
returns void language plpgsql set search_path = '' as $$
begin
  if p_display_name is null or char_length(btrim(p_display_name)) = 0 then
    perform app_private.validation_error('Enter a display name.');
  end if;
  if char_length(btrim(p_display_name)) > 50 then
    perform app_private.validation_error('Use 50 characters or fewer for your name.');
  end if;
  if p_handle is null or p_handle !~ '^[a-z0-9_]{3,20}$' then
    perform app_private.validation_error('Handles are 3–20 lowercase letters, numbers or underscores.');
  end if;
  if char_length(coalesce(p_bio, '')) > 160 then
    perform app_private.validation_error('Use 160 characters or fewer for your bio.');
  end if;
end;
$$;

-- Notifications helper (honours recipient preferences, blocks, self and event-key dedup) --------
create or replace function app_private.notify(p_recipient uuid, p_actor uuid, p_type public.notification_type,
                                              p_activity uuid, p_comment uuid, p_event_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  prefs public.user_settings;
begin
  if p_recipient = p_actor or app_private.is_blocked_pair(p_recipient, p_actor) then
    return;
  end if;
  select * into prefs from public.user_settings where user_id = p_recipient;
  if found and ((p_type = 'follow' and not prefs.notify_follows) or (p_type = 'like' and not prefs.notify_likes)
                or (p_type = 'comment' and not prefs.notify_comments)) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, activity_id, comment_id, event_key)
  values (p_recipient, p_actor, p_type, p_activity, p_comment, p_event_key)
  on conflict (event_key) do nothing;
end;
$$;

-- Profile RPCs ---------------------------------------------------------------------------------
create or replace function public.my_profile()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'roam:not_signed_in' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and deactivated_at is not null) then
    raise exception 'roam:account_disabled' using errcode = '42501';
  end if;
  return app_private.own_profile_json(auth.uid());
end;
$$;

-- Availability check only; it never reserves a handle.
create or replace function public.check_handle(p_handle text)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'roam:not_signed_in' using errcode = '42501';
  end if;
  if p_handle is null or p_handle !~ '^[a-z0-9_]{3,20}$' then
    return 'invalid';
  end if;
  if exists (select 1 from public.profiles where handle = p_handle and id <> auth.uid()) then
    return 'taken';
  end if;
  return 'available';
end;
$$;

create or replace function public.create_profile(p_display_name text, p_handle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'roam:not_signed_in' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = uid) then
    -- Retried creation returns the existing profile unchanged.
    return app_private.own_profile_json(uid);
  end if;
  perform app_private.validate_profile_fields(p_display_name, p_handle, '');
  begin
    insert into public.profiles (id, handle, display_name) values (uid, p_handle, btrim(p_display_name));
  exception when unique_violation then
    raise exception 'roam:handle_taken' using errcode = '23505';
  end;
  insert into public.user_settings (user_id) values (uid) on conflict do nothing;
  return app_private.own_profile_json(uid);
end;
$$;

create or replace function public.update_profile(p_display_name text, p_handle text, p_bio text, p_home_city jsonb, p_avatar_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  v_city uuid;
  old_avatar text;
  -- Clients send bucket-qualified storage paths; the table stores the object path.
  v_avatar text := nullif(regexp_replace(coalesce(p_avatar_path, ''), '^avatars/', ''), '');
begin
  perform app_private.validate_profile_fields(p_display_name, p_handle, coalesce(p_bio, ''));
  if p_home_city is not null and jsonb_typeof(p_home_city) = 'object' then
    v_city := app_private.upsert_city(p_home_city ->> 'countryCode', p_home_city ->> 'countryName', p_home_city ->> 'region',
                                    p_home_city ->> 'name', (p_home_city ->> 'latitude')::double precision,
                                    (p_home_city ->> 'longitude')::double precision);
    if v_city is null then
      perform app_private.validation_error('Choose a home city from the search results.');
    end if;
  end if;
  select avatar_path into old_avatar from public.profiles where id = me;
  if v_avatar is not null and v_avatar is distinct from old_avatar then
    update public.media set state = 'attached', attached_at = now()
    where object_path = v_avatar and owner_id = me and purpose = 'avatar' and bucket = 'avatars';
    if not found then
      raise exception 'roam:forbidden:avatar_not_owned' using errcode = '42501';
    end if;
  end if;
  begin
    update public.profiles
    set display_name = btrim(p_display_name), handle = p_handle, bio = coalesce(p_bio, ''),
        home_city_id = v_city, avatar_path = v_avatar
    where id = me;
  exception when unique_violation then
    raise exception 'roam:handle_taken' using errcode = '23505';
  end;
  if old_avatar is not null and old_avatar is distinct from v_avatar then
    delete from public.media where object_path = old_avatar and owner_id = me and purpose = 'avatar';
  end if;
  return app_private.own_profile_json(me);
end;
$$;

-- Checkpoints only move forward, so an interrupted setup resumes where it stopped.
create or replace function public.set_setup_checkpoint(p_checkpoint public.setup_checkpoint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  update public.profiles set setup_checkpoint = p_checkpoint where id = me and setup_checkpoint < p_checkpoint;
  return app_private.own_profile_json(me);
end;
$$;

create or replace function public.mark_been_intro_seen()
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  update public.profiles set has_seen_been_intro = true where id = me;
end;
$$;

-- Public profile header: approved fields and server-derived all-time totals only.
create or replace function public.public_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  result jsonb;
begin
  if not app_private.can_see_member(p_user_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'member', app_private.member_json(p.id),
    'bio', p.bio,
    'homeCityName', (select c.name || coalesce(', ' || c.region, '') || ', ' || k.name from public.cities c
                     join public.countries k on k.code = c.country_code where c.id = p.home_city_id),
    'joinedAt', p.created_at,
    'followerCount', (select count(*) from public.follows f join public.profiles x on x.id = f.follower_id
                      where f.followee_id = p.id and x.deactivated_at is null and not app_private.is_blocked_pair(me, f.follower_id)),
    'followingCount', (select count(*) from public.follows f join public.profiles x on x.id = f.followee_id
                       where f.follower_id = p.id and x.deactivated_at is null and not app_private.is_blocked_pair(me, f.followee_id)),
    'rankedCount', (select count(*) from public.ratings r where r.owner_id = p.id),
    'wantCount', (select count(*) from public.bookmarks b where b.owner_id = p.id),
    'countryCount', (select count(distinct pl.country_code) from public.visits v join public.experiences e on e.id = v.experience_id
                     join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.country_code is not null),
    'cityCount', (select count(distinct pl.city_id) from public.visits v join public.experiences e on e.id = v.experience_id
                  join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.city_id is not null),
    'relationship', jsonb_build_object(
      'isSelf', p.id = me,
      'isFollowing', exists (select 1 from public.follows where follower_id = me and followee_id = p.id),
      'followsViewer', exists (select 1 from public.follows where follower_id = p.id and followee_id = me),
      'isMuted', exists (select 1 from public.mutes where muter_id = me and muted_id = p.id),
      'isBlocked', exists (select 1 from public.blocks where blocker_id = me and blocked_id = p.id)))
  into result
  from public.profiles p where p.id = p_user_id;
  return result;
end;
$$;

-- Deterministic suggestions: most-rated visible members not yet followed. Never auto-follows.
create or replace function public.suggested_members(p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('member', app_private.member_json(s.id), 'isFollowing', false,
                                        'followsViewer', s.follows_me, 'isSelf', false) order by s.rated desc, s.handle)
    from (
      select p.id, p.handle,
             (select count(*) from public.ratings r where r.owner_id = p.id) as rated,
             exists (select 1 from public.follows f where f.follower_id = p.id and f.followee_id = me) as follows_me
      from public.profiles p
      where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
        and not exists (select 1 from public.follows f where f.follower_id = me and f.followee_id = p.id)
      order by rated desc, p.handle
      limit least(greatest(coalesce(p_limit, 10), 1), 30)
    ) s), '[]'::jsonb);
end;
$$;

-- Media registration: only a fully uploaded object in the caller's own folder can be registered.
create or replace function public.register_media(p_bucket text, p_path text, p_purpose public.media_purpose,
                                                 p_width integer, p_height integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  v_size bigint;
  v_type text;
  v_media public.media;
begin
  if (p_purpose = 'avatar' and p_bucket <> 'avatars') or (p_purpose = 'visit' and p_bucket <> 'visit-media') then
    perform app_private.validation_error('Wrong storage bucket for this photo.');
  end if;
  if split_part(p_path, '/', 1) <> me::text then
    raise exception 'roam:forbidden:not_owner' using errcode = '42501';
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype' into v_size, v_type
  from storage.objects o where o.bucket_id = p_bucket and o.name = p_path;
  if not found then
    perform app_private.validation_error('This photo has not finished uploading.');
  end if;
  if v_type is distinct from 'image/jpeg' or v_size > 3145728 or p_width > 2048 or p_height > 2048 then
    perform app_private.validation_error('Photos must be JPEG, at most 2048 pixels and 3 MB.');
  end if;
  insert into public.media (owner_id, purpose, bucket, object_path, byte_size, width, height)
  values (me, p_purpose, p_bucket, p_path, v_size, p_width, p_height)
  on conflict on constraint media_object_path_key do nothing
  returning * into v_media;
  if v_media.id is null then
    select * into v_media from public.media where object_path = p_path and owner_id = me;
    if not found then
      raise exception 'roam:forbidden:not_owner' using errcode = '42501';
    end if;
  end if;
  return jsonb_build_object('id', v_media.id, 'path', v_media.bucket || '/' || v_media.object_path,
                            'width', v_media.width, 'height', v_media.height);
end;
$$;

create or replace function public.discard_staged_media(p_media_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  delete from public.media where id = p_media_id and owner_id = me and state = 'staged';
end;
$$;

-- Desired-state follow: repeated calls are safe. Rejects self-follow and blocked pairs.
create or replace function public.set_follow(p_user_id uuid, p_following boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  if p_user_id = me then
    perform app_private.validation_error('You can''t follow yourself.');
  end if;
  if not app_private.can_see_member(p_user_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  if p_following then
    insert into public.follows (follower_id, followee_id) values (me, p_user_id) on conflict do nothing;
    if found then
      perform app_private.notify(p_user_id, me, 'follow', null, null, 'follow:' || me || ':' || p_user_id);
    end if;
  else
    delete from public.follows where follower_id = me and followee_id = p_user_id;
  end if;
  return exists (select 1 from public.follows where follower_id = me and followee_id = p_user_id);
end;
$$;

revoke all on function public.my_profile(), public.check_handle(text), public.create_profile(text, text),
  public.update_profile(text, text, text, jsonb, text), public.set_setup_checkpoint(public.setup_checkpoint),
  public.mark_been_intro_seen(), public.public_profile(uuid), public.suggested_members(integer),
  public.register_media(text, text, public.media_purpose, integer, integer), public.discard_staged_media(uuid),
  public.set_follow(uuid, boolean) from public, anon;
grant execute on function public.my_profile(), public.check_handle(text), public.create_profile(text, text),
  public.update_profile(text, text, text, jsonb, text), public.set_setup_checkpoint(public.setup_checkpoint),
  public.mark_been_intro_seen(), public.public_profile(uuid), public.suggested_members(integer),
  public.register_media(text, text, public.media_purpose, integer, integer), public.discard_staged_media(uuid),
  public.set_follow(uuid, boolean) to authenticated;
