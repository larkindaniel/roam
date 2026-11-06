-- M3: place resolution, experience projections, bookmarks, lists, member search and reports.

-- Following score: equal mean of one current rating per followed, visible member (self and
-- blocked excluded; muting does not affect eligibility). Null when nobody qualifies.
create or replace function app_private.following_score(p_viewer uuid, p_experience uuid)
returns table (score numeric, raters integer) language sql stable security definer set search_path = '' as $$
  select round(avg(r.score), 1), count(*)::integer
  from public.follows f
  join public.ratings r on r.owner_id = f.followee_id and r.experience_id = p_experience
  join public.profiles p on p.id = f.followee_id and p.deactivated_at is null
  where f.follower_id = p_viewer and f.followee_id <> p_viewer and not app_private.is_blocked_pair(p_viewer, f.followee_id)
$$;

create or replace function app_private.experience_summary_json(p_experience uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', e.id, 'placeID', pl.id, 'name', pl.name, 'category', e.category,
    'locality', pl.locality, 'region', pl.region, 'countryCode', pl.country_code, 'countryName', pl.country_name,
    'latitude', pl.latitude, 'longitude', pl.longitude, 'providerPlaceID', pl.provider_place_id,
    'followingScore', fs.score, 'followingCount', coalesce(fs.raters, 0),
    'viewer', jsonb_build_object(
      'isBookmarked', exists (select 1 from public.bookmarks b where b.owner_id = p_viewer and b.experience_id = e.id),
      'myRatingCategory', mine.category, 'myScore', mine.score, 'myRank', mine.rank,
      'hasVisits', exists (select 1 from public.visits v where v.owner_id = p_viewer and v.experience_id = e.id)))
  from public.experiences e
  join public.places pl on pl.id = e.place_id
  left join lateral (select * from app_private.following_score(p_viewer, e.id)) fs on true
  left join lateral (select r.category, r.score, r.rank from public.ratings r where r.owner_id = p_viewer and r.experience_id = e.id) mine on true
  where e.id = p_experience
$$;

-- Place resolution (SPEC R06, D24, M1 locality rule). Clients may only submit MapKit results;
-- fixture places exist only in the disposable local fixture database.
create or replace function public.resolve_place(p_candidate jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  v_provider text := p_candidate ->> 'provider';
  v_provider_id text := nullif(btrim(p_candidate ->> 'providerPlaceID'), '');
  v_name text := btrim(p_candidate ->> 'name');
  v_address text := nullif(btrim(p_candidate ->> 'address'), '');
  v_lat double precision := (p_candidate ->> 'latitude')::double precision;
  v_lon double precision := (p_candidate ->> 'longitude')::double precision;
  v_is_locality boolean := coalesce((p_candidate ->> 'isLocality')::boolean, false);
  v_country text;
  v_city uuid;
  v_place uuid;
  v_experience uuid;
  v_category public.experience_category := nullif(p_candidate ->> 'suggestedCategory', '')::public.experience_category;
begin
  if v_provider is distinct from 'mapkit' then
    perform app_private.validation_error('Places must come from Apple Maps.');
  end if;
  if v_name is null or v_name = '' or v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then
    perform app_private.validation_error('This place is missing a name or location.');
  end if;
  v_country := app_private.upsert_country(p_candidate ->> 'countryCode', p_candidate ->> 'countryName');
  v_city := app_private.upsert_city(v_country, p_candidate ->> 'countryName', p_candidate ->> 'region',
                                    coalesce(p_candidate ->> 'locality', case when v_is_locality then v_name end),
                                    case when v_is_locality then v_lat end, case when v_is_locality then v_lon end);
  if v_provider_id is not null then
    select id into v_place from public.places where provider = 'mapkit' and provider_place_id = v_provider_id;
  elsif v_is_locality and v_city is not null then
    select id into v_place from public.places where provider = 'mapkit' and provider_place_id is null and is_locality and city_id = v_city;
  elsif v_address is not null then
    select id into v_place from public.places
    where provider = 'mapkit' and provider_place_id is null and not is_locality
      and normalized_name = app_private.normalize_text(v_name) and normalized_address = app_private.normalize_text(v_address)
      and lat6 = round(v_lat::numeric, 6) and lon6 = round(v_lon::numeric, 6);
  end if;
  if v_place is null then
    begin
      insert into public.places (provider, provider_place_id, name, normalized_name, address, normalized_address, locality, region,
                                 country_code, country_name, city_id, latitude, longitude, phone, website, provider_category,
                                 time_zone, is_locality, needs_reconciliation, provenance)
      values ('mapkit', v_provider_id, v_name, app_private.normalize_text(v_name), v_address,
              nullif(app_private.normalize_text(v_address), ''), nullif(btrim(p_candidate ->> 'locality'), ''),
              nullif(btrim(p_candidate ->> 'region'), ''), v_country, nullif(btrim(p_candidate ->> 'countryName'), ''), v_city,
              v_lat, v_lon, nullif(p_candidate ->> 'phone', ''), nullif(p_candidate ->> 'website', ''),
              nullif(p_candidate ->> 'providerCategory', ''), nullif(p_candidate ->> 'timeZoneIdentifier', ''), v_is_locality,
              v_provider_id is null and not v_is_locality,
              jsonb_build_object('source', 'mapkit', 'resolvedAt', now(), 'resolvedBy', me))
      returning id into v_place;
    exception when unique_violation then
      -- A concurrent resolution created the same identity first.
      select id into v_place from public.places
      where provider = 'mapkit'
        and ((v_provider_id is not null and provider_place_id = v_provider_id)
          or (v_provider_id is null and v_is_locality and is_locality and city_id = v_city)
          or (v_provider_id is null and not v_is_locality and normalized_name = app_private.normalize_text(v_name)
              and normalized_address = app_private.normalize_text(v_address) and lat6 = round(v_lat::numeric, 6) and lon6 = round(v_lon::numeric, 6)));
    end;
  end if;
  insert into public.experiences (place_id, category, category_source) values (v_place, v_category, 'suggested')
  on conflict (place_id) do nothing;
  select id into v_experience from public.experiences where place_id = v_place;
  return app_private.experience_summary_json(v_experience, me);
end;
$$;

-- Existing experiences for provider search results, keyed by the client's candidate id.
create or replace function public.match_experiences(p_candidates jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  result jsonb := '{}'::jsonb;
  c jsonb;
  v_experience uuid;
begin
  for c in select * from jsonb_array_elements(coalesce(p_candidates, '[]'::jsonb)) loop
    v_experience := null;
    select e.id into v_experience
    from public.places pl join public.experiences e on e.place_id = pl.id
    where pl.provider = (c ->> 'provider')::public.place_provider
      and ((nullif(c ->> 'providerPlaceID', '') is not null and pl.provider_place_id = c ->> 'providerPlaceID')
        or (nullif(c ->> 'providerPlaceID', '') is null and coalesce((c ->> 'isLocality')::boolean, false) and pl.is_locality
            and pl.provider_place_id is null
            and pl.city_id = (select id from public.cities where city_key = app_private.city_key(c ->> 'countryCode', c ->> 'region', coalesce(c ->> 'locality', c ->> 'name'))))
        or (nullif(c ->> 'providerPlaceID', '') is null and not coalesce((c ->> 'isLocality')::boolean, false) and pl.provider_place_id is null
            and nullif(c ->> 'address', '') is not null
            and pl.normalized_name = app_private.normalize_text(c ->> 'name') and pl.normalized_address = app_private.normalize_text(c ->> 'address')
            and pl.lat6 = round((c ->> 'latitude')::numeric, 6) and pl.lon6 = round((c ->> 'longitude')::numeric, 6)))
    limit 1;
    if v_experience is not null then
      result := result || jsonb_build_object(c ->> 'id', app_private.experience_summary_json(v_experience, me));
    end if;
  end loop;
  return result;
end;
$$;

create or replace function app_private.visit_json(p_visit uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', v.id, 'experienceID', v.experience_id, 'ownerID', v.owner_id,
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'publicNote', v.public_note,
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = v.id and m.state = 'attached'), '[]'::jsonb),
    'createdAt', v.created_at, 'updatedAt', v.updated_at)
  from public.visits v where v.id = p_visit
$$;

create or replace function app_private.activity_json(p_activity uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', a.id, 'type', a.type, 'author', app_private.member_json(a.author_id),
    'experience', app_private.experience_summary_json(a.experience_id, p_viewer), 'category', a.category,
    'scoreSnapshot', a.score_snapshot, 'rankSnapshot', a.rank_snapshot, 'sentimentSnapshot', a.sentiment_snapshot,
    'visitID', a.visit_id,
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'note', coalesce(v.public_note, ''),
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = a.visit_id and m.state = 'attached'), '[]'::jsonb),
    'publishedAt', a.published_at,
    'likeCount', (select count(*) from public.likes l join public.profiles p on p.id = l.actor_id
                  where l.activity_id = a.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, l.actor_id)),
    'commentCount', (select count(*) from public.comments c join public.profiles p on p.id = c.author_id
                     where c.activity_id = a.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, c.author_id)),
    'likedByViewer', exists (select 1 from public.likes l where l.activity_id = a.id and l.actor_id = p_viewer),
    'isOwn', a.author_id = p_viewer)
  from public.activities a left join public.visits v on v.id = a.visit_id
  where a.id = p_activity
$$;

create or replace function public.experience_detail(p_experience_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  result jsonb;
begin
  if not exists (select 1 from public.experiences where id = p_experience_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'summary', app_private.experience_summary_json(e.id, me),
    'address', pl.address, 'phone', pl.phone, 'website', pl.website, 'timeZoneIdentifier', pl.time_zone,
    'provider', pl.provider, 'providerStatus', pl.status, 'isLocality', pl.is_locality,
    'categoryLocked', e.category_locked_at is not null,
    'myRating', (select jsonb_build_object('ratingID', r.id, 'category', r.category, 'sentiment', r.sentiment, 'score', r.score,
                                           'rank', r.rank,
                                           'groupSize', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category
                                                         and g.sentiment = r.sentiment and g.group_position = r.group_position),
                                           'categoryCount', (select count(*) from public.ratings c where c.owner_id = me and c.category = r.category),
                                           'firstRatedAt', r.first_rated_at)
                 from public.ratings r where r.owner_id = me and r.experience_id = e.id),
    'myVisits', coalesce((select jsonb_agg(app_private.visit_json(v.id)
                                           order by v.visit_date desc nulls last, v.created_at desc, v.id)
                          from public.visits v where v.owner_id = me and v.experience_id = e.id), '[]'::jsonb),
    'hasPrivateNote', exists (select 1 from public.private_notes n where n.owner_id = me and n.experience_id = e.id),
    'publicActivity', coalesce((select jsonb_agg(app_private.activity_json(x.id, me) order by x.published_at desc, x.id desc)
                                from (select a.id, a.published_at from public.activities a
                                      join public.profiles p on p.id = a.author_id and p.deactivated_at is null
                                      where a.experience_id = e.id and not app_private.is_blocked_pair(me, a.author_id)
                                      order by a.published_at desc, a.id desc limit 30) x), '[]'::jsonb))
  into result
  from public.experiences e join public.places pl on pl.id = e.place_id
  where e.id = p_experience_id;
  return result;
end;
$$;

create or replace function public.experiences_in_bounds(p_min_lat double precision, p_max_lat double precision,
                                                        p_min_lon double precision, p_max_lon double precision,
                                                        p_category public.experience_category default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  return coalesce((
    select jsonb_agg(app_private.experience_summary_json(x.id, me) order by x.name)
    from (
      select e.id, pl.name from public.experiences e join public.places pl on pl.id = e.place_id
      where pl.latitude between p_min_lat and p_max_lat
        and (case when p_min_lon <= p_max_lon then pl.longitude between p_min_lon and p_max_lon
                  else pl.longitude >= p_min_lon or pl.longitude <= p_max_lon end)
        and (p_category is null or e.category = p_category)
      order by pl.name limit 200) x), '[]'::jsonb);
end;
$$;

-- Bookmarks (Want to Go): desired state, safe to retry, never touches visits/ratings/activity.
create or replace function public.set_bookmark(p_experience_id uuid, p_saved boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  if not exists (select 1 from public.experiences where id = p_experience_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  if p_saved then
    if exists (select 1 from public.ratings where owner_id = me and experience_id = p_experience_id) then
      raise exception 'roam:already_rated' using errcode = '22023';
    end if;
    insert into public.bookmarks (owner_id, experience_id) values (me, p_experience_id) on conflict do nothing;
  else
    delete from public.bookmarks where owner_id = me and experience_id = p_experience_id;
  end if;
  return exists (select 1 from public.bookmarks where owner_id = me and experience_id = p_experience_id);
end;
$$;

create or replace function public.my_library()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  return jsonb_build_object(
    'bookmarked', coalesce((select jsonb_agg(experience_id) from public.bookmarks where owner_id = me), '[]'::jsonb),
    'rated', coalesce((select jsonb_object_agg(experience_id, category) from public.ratings where owner_id = me), '{}'::jsonb),
    'visited', coalesce((select jsonb_agg(distinct experience_id) from public.visits where owner_id = me), '[]'::jsonb));
end;
$$;

create or replace function app_private.list_entry_json(p_experience uuid, p_owner uuid, p_viewer uuid, p_saved_at timestamptz)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'experience', app_private.experience_summary_json(e.id, p_viewer),
    'ownerCategory', coalesce(r.category, e.category), 'ownerSentiment', r.sentiment, 'ownerScore', r.score, 'ownerRank', r.rank,
    'ownerFirstRatedAt', r.first_rated_at,
    'isRanked', r.id is not null,
    'latestVisitDate', (select max(v.visit_date) from public.visits v where v.owner_id = p_owner and v.experience_id = e.id),
    'latestVisitAt', (select max(v.created_at) from public.visits v where v.owner_id = p_owner and v.experience_id = e.id),
    'savedAt', p_saved_at,
    'viewerSavedAt', (select b.saved_at from public.bookmarks b where b.owner_id = p_viewer and b.experience_id = e.id),
    'cityKey', c.city_key, 'cityName', c.name)
  from public.experiences e
  join public.places pl on pl.id = e.place_id
  left join public.cities c on c.id = pl.city_id
  left join public.ratings r on r.owner_id = p_owner and r.experience_id = e.id
  where e.id = p_experience
$$;

-- Personal lists are bounded per member and returned whole; the client filters and sorts with the
-- shared list engine. (Social feeds, comments, followers, member search and notifications paginate.)
create or replace function public.been_list(p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  if not app_private.can_see_member(p_owner) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  return coalesce((
    select jsonb_agg(app_private.list_entry_json(x.experience_id, p_owner, me, null))
    from (select experience_id from public.ratings where owner_id = p_owner
          union select experience_id from public.visits where owner_id = p_owner) x), '[]'::jsonb);
end;
$$;

create or replace function public.want_list(p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  if not app_private.can_see_member(p_owner) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  return coalesce((
    select jsonb_agg(app_private.list_entry_json(b.experience_id, p_owner, me, b.saved_at) order by b.saved_at desc, b.experience_id)
    from public.bookmarks b where b.owner_id = p_owner), '[]'::jsonb);
end;
$$;

-- Member search: case-insensitive handle/display-name match, stable handle-ordered keyset pages of 30.
create or replace function public.search_members(p_query text, p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  q text := lower(btrim(coalesce(p_query, '')));
  rows jsonb;
begin
  if q = '' then
    return jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null);
  end if;
  with page as (
    select p.id, p.handle from public.profiles p
    where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
      and (p.handle like '%' || replace(replace(q, '%', ''), '_', '\_') || '%' or lower(p.display_name) like '%' || replace(q, '%', '') || '%')
      and (p_cursor is null or p.handle > p_cursor)
    order by p.handle limit 31)
  select jsonb_agg(jsonb_build_object(
           'member', app_private.member_json(page.id),
           'isFollowing', exists (select 1 from public.follows f where f.follower_id = me and f.followee_id = page.id),
           'followsViewer', exists (select 1 from public.follows f where f.follower_id = page.id and f.followee_id = me),
           'isSelf', false) order by page.handle)
  into rows from page;
  rows := coalesce(rows, '[]'::jsonb);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value), '[]'::jsonb) from (select value from jsonb_array_elements(rows) limit 30) s),
    'nextCursor', case when jsonb_array_length(rows) > 30 then rows -> 29 -> 'member' ->> 'handle' end);
end;
$$;

-- Reports: stored for operators; the client's operation id makes retries idempotent.
create or replace function public.submit_report(p_operation_id uuid, p_target_type public.report_target, p_target_id uuid,
                                                p_reason public.report_reason, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  r public.reports;
begin
  if char_length(coalesce(p_body, '')) > 1000 then
    perform app_private.validation_error('Use 1,000 characters or fewer.');
  end if;
  insert into public.reports (id, reporter_id, target_type, target_id, reason, body)
  values (p_operation_id, me, p_target_type, p_target_id, p_reason, nullif(btrim(coalesce(p_body, '')), ''))
  on conflict (id) do nothing;
  select * into r from public.reports where id = p_operation_id and reporter_id = me;
  if not found then
    raise exception 'roam:operation_conflict' using errcode = '23505';
  end if;
  return jsonb_build_object('id', r.id, 'targetKind', r.target_type, 'reason', r.reason, 'status', r.status, 'createdAt', r.created_at);
end;
$$;

create or replace function public.my_reports()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'targetKind', target_type, 'reason', reason, 'status', status,
                                                       'createdAt', created_at) order by created_at desc)
                   from public.reports where reporter_id = me), '[]'::jsonb);
end;
$$;

grant execute on function public.resolve_place(jsonb), public.match_experiences(jsonb), public.experience_detail(uuid),
  public.experiences_in_bounds(double precision, double precision, double precision, double precision, public.experience_category),
  public.set_bookmark(uuid, boolean), public.my_library(), public.been_list(uuid), public.want_list(uuid),
  public.search_members(text, text), public.submit_report(uuid, public.report_target, uuid, public.report_reason, text),
  public.my_reports() to authenticated;
