-- Who can see an entry, plus trips, lists, direct shares and taste preferences.
-- Audience is enforced here, in row policies, storage access and every RPC that reads visits.

-- Existing entries were published to all members, so they stay public. New ones default to friends.
alter table public.visits add column audience text not null default 'public' check (audience in ('friends', 'only_me', 'public'));
alter table public.visits alter column audience set default 'friends';
alter table public.ratings add column audience text not null default 'public' check (audience in ('friends', 'only_me', 'public'));
alter table public.ratings alter column audience set default 'friends';

create or replace function app_private.are_friends(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.follows f where f.follower_id=p_a and f.followee_id=p_b)
$$;

create or replace function app_private.audience_allows(p_owner uuid, p_audience text, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select p_viewer=p_owner or (
    p_audience<>'only_me'
    and exists(select 1 from public.profiles p where p.id=p_owner and p.deactivated_at is null)
    and not app_private.is_blocked_pair(p_viewer,p_owner)
    and (p_audience='public' or app_private.are_friends(p_viewer,p_owner)))
$$;

-- A post follows its visit; a post with no visit follows its rating.
create or replace function app_private.activity_allowed(p_activity uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select app_private.audience_allows(a.author_id, coalesce(v.audience, r.audience, 'friends'), p_viewer)
  from public.activities a
  left join public.visits v on v.id=a.visit_id
  left join public.ratings r on r.id=a.rating_id
  where a.id=p_activity
$$;

-- A rating shares the audience of the member's latest visit to that place.
create or replace function app_private.rating_audience_from_visit()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.ratings set audience=new.audience where owner_id=new.owner_id and experience_id=new.experience_id and audience<>new.audience;
  return new;
end$$;
create trigger visit_sets_rating_audience after insert or update of audience on public.visits
  for each row execute function app_private.rating_audience_from_visit();

create or replace function app_private.rating_audience_on_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  select v.audience into new.audience from public.visits v where v.owner_id=new.owner_id and v.experience_id=new.experience_id
  order by v.created_at desc limit 1;
  new.audience:=coalesce(new.audience,'friends');
  return new;
end$$;
create trigger rating_takes_visit_audience before insert on public.ratings
  for each row execute function app_private.rating_audience_on_insert();

drop policy read_visible_visits on public.visits;
create policy read_visible_visits on public.visits for select to authenticated
  using (app_private.audience_allows(owner_id, audience, app_private.current_member()));
drop policy read_visible_ratings on public.ratings;
create policy read_visible_ratings on public.ratings for select to authenticated
  using (app_private.audience_allows(owner_id, audience, app_private.current_member()));
drop policy read_visible_activities on public.activities;
create policy read_visible_activities on public.activities for select to authenticated
  using (app_private.activity_allowed(id, app_private.current_member()));
drop policy read_media on public.media;
create policy read_media on public.media for select to authenticated
  using (owner_id = app_private.current_member() or (state = 'attached' and app_private.can_read_object(bucket, object_path)));

-- A stored photo is readable only by people who can see its visit.
create or replace function app_private.can_read_object(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
      select 1 from public.media m
      left join public.visits v on v.id = m.visit_id
      where m.bucket = p_bucket and m.object_path = p_name and m.state = 'attached'
        and app_private.can_see_member(m.owner_id)
        and (v.id is null or app_private.audience_allows(v.owner_id, v.audience, app_private.current_member())))
    or (p_bucket = 'avatars' and exists (
      select 1 from public.profiles p where p.avatar_path = p_name and app_private.can_see_member(p.id)))
$$;

-- Trips, lists, shares and taste ------------------------------------------------------------------
create table public.trips (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  description text not null default '' check (char_length(description) <= 500),
  start_date date,
  end_date date,
  status text not null default 'planning' check (status in ('planning', 'upcoming', 'ongoing', 'past')),
  created_at timestamptz not null default now(),
  check (start_date is null or end_date is null or start_date <= end_date)
);
create index trips_owner on public.trips (owner_id, created_at desc);

create table public.trip_places (
  trip_id uuid not null references public.trips (id) on delete cascade,
  experience_id uuid not null references public.experiences (id),
  stop text not null default '' check (char_length(stop) <= 80),
  position integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (trip_id, experience_id)
);

alter table public.visits add column trip_id uuid references public.trips (id) on delete set null;
create index visits_trip on public.visits (trip_id);

create table public.lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  description text not null default '' check (char_length(description) <= 500),
  created_at timestamptz not null default now()
);
create index lists_owner on public.lists (owner_id, created_at desc);

create table public.list_items (
  list_id uuid not null references public.lists (id) on delete cascade,
  experience_id uuid not null references public.experiences (id),
  note text not null default '' check (char_length(note) <= 500),
  position integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (list_id, experience_id)
);

create table public.direct_shares (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid references public.experiences (id),
  list_id uuid references public.lists (id) on delete cascade,
  trip_id uuid references public.trips (id) on delete cascade,
  message text not null default '' check (char_length(message) <= 500),
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  unique (sender_id, operation_id),
  check (sender_id <> recipient_id),
  check (num_nonnulls(experience_id, list_id, trip_id) = 1)
);
create index direct_shares_recipient on public.direct_shares (recipient_id, created_at desc);
create index direct_shares_list on public.direct_shares (list_id);
create index direct_shares_trip on public.direct_shares (trip_id);

create table public.taste_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- All of these are read and written through the RPCs below.
alter table public.trips enable row level security;
alter table public.trip_places enable row level security;
alter table public.lists enable row level security;
alter table public.list_items enable row level security;
alter table public.direct_shares enable row level security;
alter table public.taste_profiles enable row level security;
revoke all on public.trips, public.trip_places, public.lists, public.list_items, public.direct_shares, public.taste_profiles from anon, authenticated;

create or replace function app_private.can_read_trip(p_trip uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.trips t where t.id=p_trip and (t.owner_id=p_viewer or exists(
    select 1 from public.direct_shares s where s.trip_id=t.id and s.recipient_id=p_viewer and app_private.are_friends(p_viewer,t.owner_id))))
$$;

create or replace function app_private.can_read_list(p_list uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.lists l where l.id=p_list and (l.owner_id=p_viewer or exists(
    select 1 from public.direct_shares s where s.list_id=l.id and s.recipient_id=p_viewer and app_private.are_friends(p_viewer,l.owner_id))))
$$;

CREATE OR REPLACE FUNCTION app_private.normalized_visit_payload(p_visit jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  payload jsonb := case when p_visit is null or p_visit = 'null'::jsonb then '{}'::jsonb else p_visit end;
  date_text text;
  visit_date date;
  zone text;
  note text;
  media_ids jsonb;
  v_audience text := nullif(p_visit ->> 'audience', '');
  v_trip uuid;
begin
  perform app_private.assert_json_keys(payload, array['date', 'timeZoneIdentifier', 'publicNote', 'mediaIDs', 'audience', 'tripID']);
  if (payload ? 'date' and payload -> 'date' <> 'null'::jsonb and jsonb_typeof(payload -> 'date') <> 'string')
    or (payload ? 'timeZoneIdentifier' and payload -> 'timeZoneIdentifier' <> 'null'::jsonb and jsonb_typeof(payload -> 'timeZoneIdentifier') <> 'string')
    or (payload ? 'publicNote' and jsonb_typeof(payload -> 'publicNote') <> 'string')
    or (payload ? 'mediaIDs' and jsonb_typeof(payload -> 'mediaIDs') <> 'array') then
    perform app_private.validation_error('Check the visit details.');
  end if;
  if v_audience is not null and v_audience not in ('friends', 'only_me', 'public') then
    perform app_private.validation_error('Choose who can see this visit.');
  end if;
  begin
    v_trip := nullif(payload ->> 'tripID', '')::uuid;
  exception when invalid_text_representation then
    perform app_private.validation_error('Check the trip for this visit.');
  end;
  date_text := payload ->> 'date';
  if date_text is not null then
    if date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform app_private.validation_error('Use a calendar date for this visit.');
    end if;
    begin
      visit_date := date_text::date;
    exception when datetime_field_overflow or invalid_datetime_format then
      perform app_private.validation_error('Use a valid calendar date for this visit.');
    end;
  end if;
  zone := nullif(payload ->> 'timeZoneIdentifier', '');
  if zone is not null and not exists (select 1 from pg_timezone_names where name = zone) then
    perform app_private.validation_error('Use a valid time zone for this visit.');
  end if;
  note := coalesce(payload ->> 'publicNote', '');
  if char_length(note) > 5000 then
    perform app_private.validation_error('Use 5,000 characters or fewer for your public note.');
  end if;
  begin
    select coalesce(jsonb_agg((value #>> '{}')::uuid::text order by ordinal), '[]'::jsonb) into media_ids
    from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) with ordinality item(value, ordinal);
  exception when invalid_text_representation then
    perform app_private.validation_error('A photo reference is invalid.');
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) item where jsonb_typeof(item) <> 'string')
    or jsonb_array_length(media_ids) > 6
    or (select count(distinct value) from jsonb_array_elements(media_ids)) <> jsonb_array_length(media_ids) then
    perform app_private.validation_error('Choose up to six different photos for this visit.');
  end if;
  return jsonb_build_object('date', visit_date, 'timeZoneIdentifier', zone, 'publicNote', note, 'mediaIDs', media_ids, 'audience', v_audience, 'tripID', v_trip);
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.write_rating_visit(p_actor uuid, p_experience uuid, p_operation uuid, p_payload jsonb, p_anchor uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_visit uuid := p_anchor;
  asset record;
begin
  perform app_private.validate_rating_visit(p_actor, p_payload, p_anchor);
  if p_payload ->> 'tripID' is not null and not exists (select 1 from public.trips t where t.id = (p_payload ->> 'tripID')::uuid and t.owner_id = p_actor) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  if v_visit is null then
    insert into public.visits(owner_id, experience_id, visit_date, date_precision, time_zone, public_note, source_operation_id, audience, trip_id)
    values (p_actor, p_experience, (p_payload ->> 'date')::date,
            case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
            p_payload ->> 'timeZoneIdentifier', p_payload ->> 'publicNote', p_operation,
            coalesce(p_payload ->> 'audience', 'friends'), (p_payload ->> 'tripID')::uuid)
    returning id into v_visit;
  else
    update public.visits set visit_date = (p_payload ->> 'date')::date,
      date_precision = case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
      time_zone = p_payload ->> 'timeZoneIdentifier', public_note = p_payload ->> 'publicNote',
      audience = coalesce(p_payload ->> 'audience', audience), trip_id = coalesce((p_payload ->> 'tripID')::uuid, trip_id)
    where id = v_visit and owner_id = p_actor and experience_id = p_experience;
    if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
    delete from public.media m where m.visit_id = v_visit and m.owner_id = p_actor
      and not m.id::text in (select value from jsonb_array_elements_text(p_payload -> 'mediaIDs'));
  end if;
  for asset in select value, ordinal from jsonb_array_elements_text(p_payload -> 'mediaIDs') with ordinality item(value, ordinal) loop
    update public.media set state = 'attached', visit_id = v_visit,
      position = asset.ordinal - 1, attached_at = coalesce(attached_at, now()) where id = asset.value::uuid;
  end loop;
  return v_visit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.add_visit(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  operation uuid;
  experience uuid;
  visit_payload jsonb;
  payload jsonb;
  receipt jsonb;
  current_rating public.ratings;
  visit uuid;
  activity uuid;
  result jsonb;
  unranked_category public.experience_category;
begin
  perform app_private.assert_json_keys(p_request, array['operationID', 'experienceID', 'visit', 'category']);
  if jsonb_typeof(p_request -> 'operationID') is distinct from 'string' or jsonb_typeof(p_request -> 'experienceID') is distinct from 'string'
    or jsonb_typeof(p_request -> 'visit') is distinct from 'object' then perform app_private.validation_error('This visit save is incomplete.'); end if;
  begin
    operation := (p_request ->> 'operationID')::uuid;
    experience := (p_request ->> 'experienceID')::uuid;
  exception when invalid_text_representation then perform app_private.validation_error('Check the visit identifiers.'); end;
  visit_payload := app_private.normalized_visit_payload(p_request -> 'visit');
  payload := jsonb_build_object('experienceID', experience, 'visit', visit_payload, 'category', p_request ->> 'category');
  receipt := app_private.rating_receipt(me, operation, 'add_visit', payload);
  if receipt is not null then return receipt; end if;
  perform id from public.experiences where id = experience for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  if not found then
    -- Logging never requires ranking: the visit stands alone until the member chooses to rank it.
    begin
      unranked_category := coalesce((p_request ->> 'category')::public.experience_category, (select category from public.experiences where id = experience));
    exception when invalid_text_representation then perform app_private.validation_error('Choose a category for this place.'); end;
    if unranked_category is null then perform app_private.validation_error('Choose a category for this place.'); end if;
    update public.experiences set category = unranked_category where id = experience and category is null;
    visit := app_private.write_rating_visit(me, experience, operation, visit_payload);
    insert into public.activities(author_id, type, experience_id, visit_id, category, source_operation_id)
    values (me, 'revisit', experience, visit, unranked_category, operation) returning id into activity;
    result := jsonb_build_object('visitID', visit, 'activityID', activity);
    perform app_private.store_rating_receipt(me, operation, 'add_visit', payload, result);
    return result;
  end if;
  perform app_private.lock_category_revision(me, current_rating.category);
  -- A different experience's commit can reflow this category while the lock is pending.
  -- The revisit snapshot must use the score/rank acknowledged after that transaction.
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  visit := app_private.write_rating_visit(me, experience, operation, visit_payload);
  insert into public.activities(author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, source_operation_id)
  values (me, 'revisit', experience, visit, current_rating.id, current_rating.category, current_rating.score, current_rating.rank, current_rating.sentiment, operation)
  returning id into activity;
  result := jsonb_build_object('visitID', visit, 'activityID', activity);
  perform app_private.store_rating_receipt(me, operation, 'add_visit', payload, result);
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.visit_json(p_visit uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id', v.id, 'experienceID', v.experience_id, 'ownerID', v.owner_id,
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'publicNote', v.public_note, 'audience', v.audience, 'tripID', v.trip_id,
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = v.id and m.state = 'attached'), '[]'::jsonb),
    'createdAt', v.created_at, 'updatedAt', v.updated_at)
  from public.visits v where v.id = p_visit
$function$;

CREATE OR REPLACE FUNCTION public.public_memories(p_experience_id uuid, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb; v_date timestamptz; v_id uuid; v_rows jsonb;
begin
  if not exists(select 1 from public.experiences where id=p_experience_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_cursor is not null then
    begin
      v_cursor:=convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
      v_date:=(v_cursor->>'createdAt')::timestamptz; v_id:=(v_cursor->>'id')::uuid;
      if v_date is null or v_id is null then raise exception 'invalid cursor'; end if;
    exception when others then perform app_private.validation_error('This memory page has an invalid cursor.'); end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
    'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),'publicNote',v.public_note,'audience',v.audience,
    'media',app_private.visit_json(v.id)->'media','createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',v.owner_id=v_me,
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1))
    order by v.created_at desc,v.id desc),'[]') into v_rows
  from(select x.* from public.visits x join public.profiles p on p.id=x.owner_id and p.deactivated_at is null
       where x.experience_id=p_experience_id and app_private.audience_allows(x.owner_id,x.audience,v_me)
         and(p_cursor is null or(x.created_at,x.id)<(v_date,v_id)) order by x.created_at desc,x.id desc limit 31)v;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinal),'[]') from jsonb_array_elements(v_rows) with ordinality t(value,ordinal) where ordinal<=30),
    'nextCursor',case when jsonb_array_length(v_rows)>30 then translate(encode(convert_to(jsonb_build_object('createdAt',v_rows->29->>'createdAt','id',v_rows->29->>'id')::text,'UTF8'),'base64'),E'\n','') end);
end$function$;

CREATE OR REPLACE FUNCTION app_private.activity_visible(p_activity uuid, p_viewer uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.activities a join public.profiles p on p.id=a.author_id and p.deactivated_at is null
                where a.id=p_activity and (a.author_id=p_viewer or not app_private.is_blocked_pair(p_viewer,a.author_id))
                  and app_private.activity_allowed(a.id,p_viewer))
$function$;

CREATE OR REPLACE FUNCTION public.feed(p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.activity_json(x.id,v_me) order by x.published_at desc,x.id desc),'[]') into v_rows
  from(select a.id,a.published_at from public.activities a join public.profiles p on p.id=a.author_id and p.deactivated_at is null
       where(a.author_id=v_me or(exists(select 1 from public.follows f where f.follower_id=v_me and f.followee_id=a.author_id)
                                 and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=a.author_id)
                                 and not app_private.is_blocked_pair(v_me,a.author_id)
                                 and app_private.activity_allowed(a.id,v_me)))
         and(v_cursor is null or(a.published_at,a.id)<((v_cursor->>'publishedAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by a.published_at desc,a.id desc limit 31)x;
  return app_private.page_json(v_rows,'publishedAt');
end$function$;

CREATE OR REPLACE FUNCTION public.profile_activity(p_user_id uuid, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(app_private.activity_json(x.id,v_me) order by x.published_at desc,x.id desc),'[]') into v_rows
  from(select a.id,a.published_at from public.activities a where a.author_id=p_user_id and app_private.activity_allowed(a.id,v_me)
         and(v_cursor is null or(a.published_at,a.id)<((v_cursor->>'publishedAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by a.published_at desc,a.id desc limit 31)x;
  return app_private.page_json(v_rows,'publishedAt');
end$function$;

CREATE OR REPLACE FUNCTION public.been_list(p_owner uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
begin
  if not app_private.can_see_member(p_owner) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  return coalesce((
    select jsonb_agg(app_private.list_entry_json(x.experience_id, p_owner, me, null))
    from (select r.experience_id from public.ratings r where r.owner_id = p_owner and app_private.audience_allows(r.owner_id, r.audience, me)
          union select v.experience_id from public.visits v where v.owner_id = p_owner and app_private.audience_allows(v.owner_id, v.audience, me)) x), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.list_entry_json(p_experience uuid, p_owner uuid, p_viewer uuid, p_saved_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'experience', app_private.experience_summary_json(e.id, p_viewer),
    'ownerCategory', coalesce(r.category, e.category), 'ownerSentiment', r.sentiment, 'ownerScore', r.score, 'ownerRank', r.rank,
    'ownerFirstRatedAt', r.first_rated_at,
    'isRanked', r.id is not null,
    'latestVisitDate', (select max(v.visit_date) from public.visits v where v.owner_id = p_owner and v.experience_id = e.id and app_private.audience_allows(v.owner_id, v.audience, p_viewer)),
    'latestVisitAt', (select max(v.created_at) from public.visits v where v.owner_id = p_owner and v.experience_id = e.id and app_private.audience_allows(v.owner_id, v.audience, p_viewer)),
    'savedAt', p_saved_at,
    'viewerSavedAt', (select b.saved_at from public.bookmarks b where b.owner_id = p_viewer and b.experience_id = e.id),
    'cityKey', c.city_key, 'cityName', c.name)
  from public.experiences e
  join public.places pl on pl.id = e.place_id
  left join public.cities c on c.id = pl.city_id
  left join public.ratings r on r.owner_id = p_owner and r.experience_id = e.id and app_private.audience_allows(r.owner_id, r.audience, p_viewer)
  where e.id = p_experience
$function$;

CREATE OR REPLACE FUNCTION app_private.following_score(p_viewer uuid, p_experience uuid)
 RETURNS TABLE(score numeric, raters integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select round(avg(r.score), 1), count(*)::integer
  from public.follows f
  join public.ratings r on r.owner_id = f.followee_id and r.experience_id = p_experience and r.audience <> 'only_me'
  join public.profiles p on p.id = f.followee_id and p.deactivated_at is null
  where f.follower_id = p_viewer and f.followee_id <> p_viewer and not app_private.is_blocked_pair(p_viewer, f.followee_id)
$function$;

CREATE OR REPLACE FUNCTION public.travel_profile(p_user_id uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member(); v_result jsonb;
begin
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_year is null or p_year not between 1900 and 2999 then perform app_private.validation_error('Choose a calendar year.'); end if;
  with visited as(
    select v.experience_id,min(v.visit_date) as first_known,bool_and(v.visit_date is null) as only_unknown,count(*) as visits
    from public.visits v where v.owner_id=p_user_id and app_private.audience_allows(v.owner_id,v.audience,app_private.current_member()) group by v.experience_id),
  place as(
    select x.experience_id,x.first_known,x.only_unknown,x.visits,pl.name,pl.latitude,pl.longitude,pl.country_code,
           coalesce(k.name,pl.country_name,pl.country_code) as country_name,c.city_key,c.name as city_name,c.region as city_region,
           coalesce(r.category,e.category) as category
    from visited x join public.experiences e on e.id=x.experience_id join public.places pl on pl.id=e.place_id
    left join public.cities c on c.id=pl.city_id left join public.countries k on k.code=pl.country_code
    left join public.ratings r on r.owner_id=p_user_id and r.experience_id=x.experience_id)
  select jsonb_build_object(
    'pins',coalesce((select jsonb_agg(jsonb_build_object('experienceID',experience_id,'name',name,'category',category,'latitude',latitude,
                     'longitude',longitude,'countryCode',country_code,'countryName',country_name,'cityKey',city_key,'cityName',city_name,
                     'firstVisitDate',first_known,'visitCount',visits) order by name,experience_id) from place),'[]'::jsonb),
    'countryCount',(select count(distinct country_code) from place where country_code is not null),
    'cityCount',(select count(distinct city_key) from place where city_key is not null),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('category',category,'count',n) order by n desc,category nulls last)
                            from(select category,count(*) n from place group by category)g),'[]'::jsonb),
    'cities',coalesce((select jsonb_agg(jsonb_build_object('cityKey',city_key,'name',city_name,'region',city_region,'countryCode',country_code,
                        'countryName',country_name,'count',n) order by n desc,city_name,city_key)
                        from(select city_key,city_name,city_region,country_code,country_name,count(*) n from place
                             where city_key is not null group by city_key,city_name,city_region,country_code,country_name)g),'[]'::jsonb),
    'countries',coalesce((select jsonb_agg(jsonb_build_object('countryCode',country_code,'name',country_name,'count',n) order by n desc,country_name,country_code)
                           from(select country_code,country_name,count(*) n from place where country_code is not null group by country_code,country_name)g),'[]'::jsonb),
    'placesWithoutCity',(select count(*) from place where city_key is null),
    'newThisYear',jsonb_build_object('year',p_year,
      'count',(select count(*) from place where extract(year from first_known)=p_year),
      'unknownDateCount',(select count(*) from place where only_unknown),
      'experienceIDs',coalesce((select jsonb_agg(experience_id order by first_known desc,name,experience_id) from place
                                where extract(year from first_known)=p_year),'[]'::jsonb)))
  into v_result;
  return v_result;
end$function$;

CREATE OR REPLACE FUNCTION public.public_profile(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'rankedCount', (select count(*) from public.ratings r where r.owner_id = p.id and app_private.audience_allows(r.owner_id, r.audience, me)),
    'wantCount', (select count(*) from public.bookmarks b where b.owner_id = p.id),
    'countryCount', (select count(distinct pl.country_code) from public.visits v join public.experiences e on e.id = v.experience_id
                     join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.country_code is not null and app_private.audience_allows(v.owner_id, v.audience, me)),
    'cityCount', (select count(distinct pl.city_id) from public.visits v join public.experiences e on e.id = v.experience_id
                  join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.city_id is not null and app_private.audience_allows(v.owner_id, v.audience, me)),
    'relationship', jsonb_build_object(
      'isSelf', p.id = me,
      'friendState', app_private.friend_state(me, p.id),
      'isMuted', exists (select 1 from public.mutes where muter_id = me and muted_id = p.id),
      'isBlocked', exists (select 1 from public.blocks where blocker_id = me and blocked_id = p.id)))
  into result
  from public.profiles p where p.id = p_user_id;
  return result;
end;
$function$;


create or replace function app_private.trip_json(p_trip uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',t.id,'owner',app_private.member_json(t.owner_id),'name',t.name,'description',t.description,
    'startDate',t.start_date,'endDate',t.end_date,'status',t.status,'isOwn',t.owner_id=p_viewer,
    'plannedCount',(select count(*) from public.trip_places p where p.trip_id=t.id),
    'visitedCount',(select count(distinct v.experience_id) from public.visits v where v.trip_id=t.id and app_private.audience_allows(v.owner_id,v.audience,p_viewer)),
    'stops',coalesce((select jsonb_agg(distinct p.stop) from public.trip_places p where p.trip_id=t.id and p.stop<>''),'[]'::jsonb))
  from public.trips t where t.id=p_trip
$$;

create or replace function public.my_trips()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.trip_json(t.id,v_me) order by t.created_at desc,t.id) from public.trips t where t.owner_id=v_me),'[]'::jsonb);
end$$;

-- Planned places stay separate from visits. Sharing a trip does not widen any entry's audience.
create or replace function public.trip_detail(p_trip_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not app_private.can_read_trip(p_trip_id,v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.trip_json(p_trip_id,v_me)||jsonb_build_object('places',coalesce((
    select jsonb_agg(jsonb_build_object('experience',app_private.experience_summary_json(x.experience_id,v_me),'stop',x.stop,'isPlanned',x.planned,'isVisited',x.visited)
                     order by x.stop,x.position,x.experience_id)
    from(select e.experience_id,coalesce(p.stop,'') stop,coalesce(p.position,2147483647) "position",p.trip_id is not null planned,
                exists(select 1 from public.visits v where v.trip_id=p_trip_id and v.experience_id=e.experience_id and app_private.audience_allows(v.owner_id,v.audience,v_me)) visited
         from(select p2.experience_id from public.trip_places p2 where p2.trip_id=p_trip_id
              union select v2.experience_id from public.visits v2 where v2.trip_id=p_trip_id and app_private.audience_allows(v2.owner_id,v2.audience,v_me)) e
         left join public.trip_places p on p.trip_id=p_trip_id and p.experience_id=e.experience_id)x),'[]'::jsonb));
end$$;

create or replace function public.save_trip(p_trip_id uuid,p_name text,p_description text,p_start date,p_end date,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_id uuid;
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 then perform app_private.validation_error('Give this trip a name of 80 characters or fewer.'); end if;
  if char_length(coalesce(p_description,''))>500 then perform app_private.validation_error('Use 500 characters or fewer for the description.'); end if;
  if p_start is not null and p_end is not null and p_start>p_end then perform app_private.validation_error('The trip can''t end before it starts.'); end if;
  if p_status is null or p_status not in ('planning','upcoming','ongoing','past') then perform app_private.validation_error('Choose a trip status.'); end if;
  if p_trip_id is null then
    insert into public.trips(owner_id,name,description,start_date,end_date,status) values(v_me,btrim(p_name),coalesce(p_description,''),p_start,p_end,p_status) returning id into v_id;
  else
    update public.trips set name=btrim(p_name),description=coalesce(p_description,''),start_date=p_start,end_date=p_end,status=p_status where id=p_trip_id and owner_id=v_me returning id into v_id;
    if v_id is null then raise exception 'roam:not_found' using errcode='P0002'; end if;
  end if;
  return app_private.trip_json(v_id,v_me);
end$$;

-- Deleting a trip keeps its visits (trip_id clears) and every saved place.
create or replace function public.delete_trip(p_trip_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  delete from public.trips where id=p_trip_id and owner_id=v_me;
end$$;

create or replace function public.set_trip_place(p_trip_id uuid,p_experience_id uuid,p_stop text,p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not exists(select 1 from public.trips where id=p_trip_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if char_length(coalesce(p_stop,''))>80 then perform app_private.validation_error('Use 80 characters or fewer for the stop.'); end if;
  if p_present then
    insert into public.trip_places(trip_id,experience_id,stop,position)
    values(p_trip_id,p_experience_id,coalesce(p_stop,''),(select coalesce(max(position)+1,0) from public.trip_places where trip_id=p_trip_id))
    on conflict(trip_id,experience_id) do update set stop=excluded.stop;
  else
    delete from public.trip_places where trip_id=p_trip_id and experience_id=p_experience_id;
  end if;
end$$;

create or replace function app_private.list_json(p_list uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',l.id,'owner',app_private.member_json(l.owner_id),'title',l.title,'description',l.description,'isOwn',l.owner_id=p_viewer,
    'itemCount',(select count(*) from public.list_items i where i.list_id=l.id))
  from public.lists l where l.id=p_list
$$;

create or replace function public.my_lists()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.list_json(l.id,v_me) order by l.created_at desc,l.id) from public.lists l where l.owner_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.list_detail(p_list_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not app_private.can_read_list(p_list_id,v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.list_json(p_list_id,v_me)||jsonb_build_object('items',coalesce((
    select jsonb_agg(jsonb_build_object('experience',app_private.experience_summary_json(i.experience_id,v_me),'note',i.note) order by i.position,i.experience_id)
    from public.list_items i where i.list_id=p_list_id),'[]'::jsonb));
end$$;

create or replace function public.save_list(p_list_id uuid,p_title text,p_description text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_id uuid;
begin
  if p_title is null or char_length(btrim(p_title)) not between 1 and 80 then perform app_private.validation_error('Give this list a title of 80 characters or fewer.'); end if;
  if char_length(coalesce(p_description,''))>500 then perform app_private.validation_error('Use 500 characters or fewer for the description.'); end if;
  if p_list_id is null then
    insert into public.lists(owner_id,title,description) values(v_me,btrim(p_title),coalesce(p_description,'')) returning id into v_id;
  else
    update public.lists set title=btrim(p_title),description=coalesce(p_description,'') where id=p_list_id and owner_id=v_me returning id into v_id;
    if v_id is null then raise exception 'roam:not_found' using errcode='P0002'; end if;
  end if;
  return app_private.list_json(v_id,v_me);
end$$;

create or replace function public.delete_list(p_list_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  delete from public.lists where id=p_list_id and owner_id=v_me;
end$$;

create or replace function public.set_list_item(p_list_id uuid,p_experience_id uuid,p_note text,p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not exists(select 1 from public.lists where id=p_list_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if char_length(coalesce(p_note,''))>500 then perform app_private.validation_error('Use 500 characters or fewer for the note.'); end if;
  if p_present then
    insert into public.list_items(list_id,experience_id,note,position)
    values(p_list_id,p_experience_id,coalesce(p_note,''),(select coalesce(max(position)+1,0) from public.list_items where list_id=p_list_id))
    on conflict(list_id,experience_id) do update set note=excluded.note;
  else
    delete from public.list_items where list_id=p_list_id and experience_id=p_experience_id;
  end if;
end$$;

-- Friends only, and only your own lists and trips. Retrying with the same operation changes nothing.
create or replace function public.send_share(p_recipient uuid,p_experience_id uuid,p_list_id uuid,p_trip_id uuid,p_message text,p_operation_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_id uuid;
begin
  if p_operation_id is null then perform app_private.validation_error('This share needs an operation identifier.'); end if;
  if num_nonnulls(p_experience_id,p_list_id,p_trip_id)<>1 then perform app_private.validation_error('Choose one place, list or trip to share.'); end if;
  if char_length(coalesce(p_message,''))>500 then perform app_private.validation_error('Use 500 characters or fewer for your message.'); end if;
  if not app_private.are_friends(v_me,p_recipient) or app_private.is_blocked_pair(v_me,p_recipient) then raise exception 'roam:forbidden' using errcode='42501'; end if;
  if p_list_id is not null and not exists(select 1 from public.lists where id=p_list_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_trip_id is not null and not exists(select 1 from public.trips where id=p_trip_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  insert into public.direct_shares(sender_id,recipient_id,experience_id,list_id,trip_id,message,operation_id)
  values(v_me,p_recipient,p_experience_id,p_list_id,p_trip_id,coalesce(p_message,''),p_operation_id)
  on conflict(sender_id,operation_id) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.direct_shares where sender_id=v_me and operation_id=p_operation_id; end if;
  return v_id;
end$$;

create or replace function public.shared_with_me()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'sender',app_private.member_json(s.sender_id),'message',s.message,'createdAt',s.created_at,
      'experience',case when s.experience_id is not null then app_private.experience_summary_json(s.experience_id,v_me) end,
      'list',case when s.list_id is not null then app_private.list_json(s.list_id,v_me) end,
      'trip',case when s.trip_id is not null then app_private.trip_json(s.trip_id,v_me) end) order by s.created_at desc,s.id)
    from public.direct_shares s join public.profiles p on p.id=s.sender_id and p.deactivated_at is null
    where s.recipient_id=v_me and app_private.are_friends(v_me,s.sender_id) and not app_private.is_blocked_pair(v_me,s.sender_id)),'[]'::jsonb);
end$$;

create or replace function public.my_taste()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select answers from public.taste_profiles where user_id=v_me),'{}'::jsonb);
end$$;

create or replace function public.save_taste(p_answers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if jsonb_typeof(p_answers) is distinct from 'object' then perform app_private.validation_error('Check your taste answers.'); end if;
  perform app_private.assert_json_keys(p_answers,array['atmosphere','budget','crowds','novelty','pace']);
  if exists(select 1 from jsonb_each(p_answers) e where jsonb_typeof(e.value)<>'string' or char_length(e.value #>> '{}')>40) then
    perform app_private.validation_error('Check your taste answers.');
  end if;
  insert into public.taste_profiles(user_id,answers) values(v_me,p_answers)
  on conflict(user_id) do update set answers=excluded.answers,updated_at=now();
  return p_answers;
end$$;

revoke execute on function app_private.are_friends(uuid,uuid),app_private.activity_allowed(uuid,uuid),
  app_private.can_read_trip(uuid,uuid),app_private.can_read_list(uuid,uuid),app_private.trip_json(uuid,uuid),app_private.list_json(uuid,uuid),
  app_private.rating_audience_from_visit(),app_private.rating_audience_on_insert() from public,anon,authenticated;
grant execute on function app_private.audience_allows(uuid,text,uuid),app_private.activity_allowed(uuid,uuid) to authenticated;
revoke execute on function public.my_trips(),public.trip_detail(uuid),public.save_trip(uuid,text,text,date,date,text),public.delete_trip(uuid),
  public.set_trip_place(uuid,uuid,text,boolean),public.my_lists(),public.list_detail(uuid),public.save_list(uuid,text,text),public.delete_list(uuid),
  public.set_list_item(uuid,uuid,text,boolean),public.send_share(uuid,uuid,uuid,uuid,text,uuid),public.shared_with_me(),public.my_taste(),public.save_taste(jsonb) from public,anon;
grant execute on function public.my_trips(),public.trip_detail(uuid),public.save_trip(uuid,text,text,date,date,text),public.delete_trip(uuid),
  public.set_trip_place(uuid,uuid,text,boolean),public.my_lists(),public.list_detail(uuid),public.save_list(uuid,text,text),public.delete_list(uuid),
  public.set_list_item(uuid,uuid,text,boolean),public.send_share(uuid,uuid,uuid,uuid,text,uuid),public.shared_with_me(),public.my_taste(),public.save_taste(jsonb) to authenticated;

-- A single visit read follows the same audience as every list of visits.
create or replace function public.visit(p_visit_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_owner uuid; v_audience text;
begin
  select owner_id,audience into v_owner,v_audience from public.visits where id=p_visit_id;
  if v_owner is null or not app_private.audience_allows(v_owner,v_audience,v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.visit_json(p_visit_id);
end$$;
