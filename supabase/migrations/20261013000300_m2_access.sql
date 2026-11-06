-- M2: access rules. Signed-in, unblocked members can read public data; owners alone read their
-- private data; anonymous callers read nothing. All writes go through validated RPCs: no table
-- grants INSERT/UPDATE/DELETE to client roles.

grant usage on schema app_private to authenticated, service_role;

-- Visibility helpers --------------------------------------------------------------------------
create or replace function app_private.current_member()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p where p.id = auth.uid() and p.deactivated_at is null
$$;

create or replace function app_private.is_blocked_pair(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  )
$$;

-- True when the signed-in, active member may see `target` (self, or active and not blocked either way).
create or replace function app_private.can_see_member(target uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.profiles t
    cross join lateral (select app_private.current_member() as me) v
    where t.id = target
      and t.deactivated_at is null
      and v.me is not null
      and (t.id = v.me or not app_private.is_blocked_pair(v.me, t.id))
  )
$$;

-- Raises unless the caller is an active member; returns their id. Used by every write RPC.
create or replace function app_private.require_member()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.current_member();
begin
  if auth.uid() is null then
    raise exception 'roam:not_signed_in' using errcode = '42501';
  end if;
  if me is null then
    if exists (select 1 from public.profiles where id = auth.uid() and deactivated_at is not null) then
      raise exception 'roam:account_disabled' using errcode = '42501';
    end if;
    raise exception 'roam:forbidden:profile_required' using errcode = '42501';
  end if;
  return me;
end;
$$;

-- Text normalization shared by place dedup and geography keys (lower, accent-folded, punctuation
-- collapsed to single spaces). Mirrors GeographyKey.normalize in the app.
create or replace function app_private.normalize_text(value text)
returns text language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, ''))),
                              '[[:punct:][:space:]]+', ' ', 'g'))
$$;

create or replace function app_private.city_key(country_code text, region text, locality text)
returns text language sql immutable set search_path = '' as $$
  select case
    when country_code is null or char_length(country_code) <> 2 or app_private.normalize_text(locality) = '' then null
    else lower(country_code) || '|' || app_private.normalize_text(region) || '|' || app_private.normalize_text(locality)
  end
$$;

grant execute on function app_private.current_member(), app_private.is_blocked_pair(uuid, uuid),
  app_private.can_see_member(uuid), app_private.require_member(), app_private.normalize_text(text),
  app_private.city_key(text, text, text) to authenticated, service_role;

-- Row Level Security ------------------------------------------------------------------------
alter table public.categories enable row level security;
alter table public.countries enable row level security;
alter table public.cities enable row level security;
alter table public.places enable row level security;
alter table public.experiences enable row level security;
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.visits enable row level security;
alter table public.private_notes enable row level security;
alter table public.media enable row level security;
alter table public.ratings enable row level security;
alter table public.category_revisions enable row level security;
alter table public.bookmarks enable row level security;
alter table public.activities enable row level security;
alter table public.follows enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.notifications enable row level security;
alter table public.blocks enable row level security;
alter table public.mutes enable row level security;
alter table public.reports enable row level security;

create policy members_read_categories on public.categories for select to authenticated using (app_private.current_member() is not null);
create policy members_read_countries on public.countries for select to authenticated using (app_private.current_member() is not null);
create policy members_read_cities on public.cities for select to authenticated using (app_private.current_member() is not null);
create policy members_read_places on public.places for select to authenticated using (app_private.current_member() is not null);
create policy members_read_experiences on public.experiences for select to authenticated using (app_private.current_member() is not null);

create policy read_visible_profiles on public.profiles for select to authenticated using (app_private.can_see_member(id));
create policy read_own_settings on public.user_settings for select to authenticated using (user_id = app_private.current_member());
create policy read_visible_visits on public.visits for select to authenticated using (app_private.can_see_member(owner_id));
create policy read_own_private_notes on public.private_notes for select to authenticated using (owner_id = app_private.current_member());
create policy read_media on public.media for select to authenticated
  using (owner_id = app_private.current_member() or (state = 'attached' and app_private.can_see_member(owner_id)));
create policy read_visible_ratings on public.ratings for select to authenticated using (app_private.can_see_member(owner_id));
create policy read_own_revisions on public.category_revisions for select to authenticated using (owner_id = app_private.current_member());
create policy read_visible_bookmarks on public.bookmarks for select to authenticated using (app_private.can_see_member(owner_id));
create policy read_visible_activities on public.activities for select to authenticated using (app_private.can_see_member(author_id));
create policy read_visible_follows on public.follows for select to authenticated
  using (app_private.can_see_member(follower_id) and app_private.can_see_member(followee_id));
create policy read_visible_likes on public.likes for select to authenticated
  using (app_private.can_see_member(actor_id) and exists (select 1 from public.activities a where a.id = activity_id));
create policy read_visible_comments on public.comments for select to authenticated
  using (app_private.can_see_member(author_id) and exists (select 1 from public.activities a where a.id = activity_id));
create policy read_own_notifications on public.notifications for select to authenticated using (recipient_id = app_private.current_member());
create policy read_own_blocks on public.blocks for select to authenticated using (blocker_id = app_private.current_member());
create policy read_own_mutes on public.mutes for select to authenticated using (muter_id = app_private.current_member());
create policy read_own_reports on public.reports for select to authenticated using (reporter_id = app_private.current_member());

-- Read grants. Profiles expose only approved public columns; owner-only profile fields are read via
-- RPC. Nothing is granted to `anon`.
grant select on public.categories, public.countries, public.cities, public.places, public.experiences,
  public.user_settings, public.visits, public.private_notes, public.media, public.ratings,
  public.category_revisions, public.bookmarks, public.activities, public.follows, public.likes,
  public.comments, public.notifications, public.blocks, public.mutes, public.reports to authenticated;
grant select (id, handle, display_name, bio, avatar_path, home_city_id, created_at) on public.profiles to authenticated;
grant all on all tables in schema public to service_role;
grant all on all tables in schema app_private to service_role;
grant usage on all sequences in schema app_private to service_role;

-- Lifecycle triggers -------------------------------------------------------------------------
create or replace function app_private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles for each row execute function app_private.touch_updated_at();
create trigger places_touch before update on public.places for each row execute function app_private.touch_updated_at();
create trigger visits_touch before update on public.visits for each row execute function app_private.touch_updated_at();
create trigger settings_touch before update on public.user_settings for each row execute function app_private.touch_updated_at();

create or replace function app_private.enqueue_storage_cleanup(p_bucket text, p_path text, p_reason text)
returns void language sql security definer set search_path = '' as $$
  insert into app_private.storage_cleanup (bucket, object_path, reason)
  values (p_bucket, p_path, p_reason)
  on conflict (bucket, object_path) do update set done_at = null, reason = excluded.reason
$$;

-- Removing a media row (visit deletion, staged expiry, account deletion) queues its stored object
-- for durable, retried removal by the cleanup worker.
create or replace function app_private.media_removed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.enqueue_storage_cleanup(old.bucket, old.object_path, 'media_removed');
  return old;
end;
$$;
create trigger media_removed after delete on public.media for each row execute function app_private.media_removed();

-- Deleted sources remove their notifications.
create or replace function app_private.follow_removed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.notifications where event_key = 'follow:' || old.follower_id || ':' || old.followee_id;
  return old;
end;
$$;
create trigger follow_removed after delete on public.follows for each row execute function app_private.follow_removed();

create or replace function app_private.like_removed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.notifications where event_key = 'like:' || old.actor_id || ':' || old.activity_id;
  return old;
end;
$$;
create trigger like_removed after delete on public.likes for each row execute function app_private.like_removed();

-- Storage ------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('visit-media', 'visit-media', false, 3145728, array['image/jpeg']),
       ('avatars', 'avatars', false, 3145728, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Read access to a stored object follows its parent: attached visit media of a visible owner, or
-- the current avatar of a visible member. Blocks and account deactivation stop new signed URLs.
create or replace function app_private.can_read_object(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
      select 1 from public.media m
      where m.bucket = p_bucket and m.object_path = p_name and m.state = 'attached'
        and app_private.can_see_member(m.owner_id))
    or (p_bucket = 'avatars' and exists (
      select 1 from public.profiles p where p.avatar_path = p_name and app_private.can_see_member(p.id)))
$$;

create or replace function app_private.object_is_attached(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.media m where m.bucket = p_bucket and m.object_path = p_name and m.state = 'attached')
$$;

grant execute on function app_private.can_read_object(text, text), app_private.object_is_attached(text, text) to authenticated;

create policy roam_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id in ('visit-media', 'avatars')
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and app_private.current_member() is not null
);

create policy roam_objects_read on storage.objects for select to authenticated using (
  bucket_id in ('visit-media', 'avatars')
  and ((storage.foldername(name))[1] = (select auth.uid()::text) or app_private.can_read_object(bucket_id, name))
);

create policy roam_objects_delete on storage.objects for delete to authenticated using (
  bucket_id in ('visit-media', 'avatars')
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and not app_private.object_is_attached(bucket_id, name)
);
