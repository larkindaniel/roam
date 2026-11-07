-- Roam's own suggestions to you: places on a city page, cities on Discover and on a country or state page.
-- Everything that uses other people's data is worked out here, and only from what the viewer may see: friends'
-- entries go through audience_allows (Only me, blocks and deactivated accounts never count), and sent places and
-- shared lists only count from current, active, unblocked friends. The weights live in one place,
-- app_private.suggestion_weights(), and are recorded in DECISIONS.md.

-- Friends' average score and count ("2 friends rated this") only count ratings the viewer may see. Before this, a
-- friend's Only me rating was included.
create or replace function app_private.following_score(p_viewer uuid, p_experience uuid)
returns table (score numeric, raters integer) language sql stable security definer set search_path = '' as $$
  select round(avg(r.score), 1), count(*)::integer
  from public.follows f
  join public.ratings r on r.owner_id = f.followee_id and r.experience_id = p_experience
  where f.follower_id = p_viewer and f.followee_id <> p_viewer
    and app_private.audience_allows(r.owner_id, r.audience, p_viewer)
$$;

-- The weights ----------------------------------------------------------------------------------------------------
create or replace function app_private.suggestion_weights()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    -- A place a friend sent you: the first friend counts most, a second adds less, more add nothing.
    'sent_first', 40, 'sent_second', 20,
    -- A place on a list a friend shared with you, counted once.
    'shared_list', 25,
    -- Sent and shared places older than this count half.
    'stale_after_days', 90, 'stale_factor', 0.5,
    -- Each friend who rated it, by their feeling; a friend who's been without rating it.
    'friend_liked', 15, 'friend_fine', 5, 'friend_disliked', -10, 'friend_been', 5,
    -- Up to this much for a category you lean towards (your share of Liked places in it), once you've liked 3 places.
    'taste_max', 10, 'taste_min_liked', 3,
    -- Rated highly by people on Roam: at least this many ratings averaging at least this score (out of 10).
    'popular', 5, 'popular_min_raters', 3, 'popular_min_score', 7.0,
    -- A city adds up its best places, then gets more for being on an upcoming trip or your wishlist.
    'city_top_places', 5, 'city_on_trip', 30, 'city_in_trip_country', 15, 'city_saved', 10)
$$;

-- Not interested ----------------------------------------------------------------------------------------------
create table public.hidden_suggestions (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  experience_id uuid references public.experiences (id) on delete cascade,
  city_id uuid references public.cities (id) on delete cascade,
  hidden_at timestamptz not null default now(),
  check (num_nonnulls(experience_id, city_id) = 1)
);
create unique index hidden_suggestions_place on public.hidden_suggestions (owner_id, experience_id) where experience_id is not null;
create unique index hidden_suggestions_city on public.hidden_suggestions (owner_id, city_id) where city_id is not null;
alter table public.hidden_suggestions enable row level security;
revoke all on public.hidden_suggestions from anon, authenticated;

create or replace function public.hide_suggestion(p_experience_id uuid default null, p_city_id uuid default null, p_hidden boolean default true)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member();
begin
  if num_nonnulls(p_experience_id, p_city_id) <> 1 then perform app_private.validation_error('Choose a place or a city.'); end if;
  if p_hidden then
    if p_experience_id is not null then
      insert into public.hidden_suggestions (owner_id, experience_id) values (v_me, p_experience_id) on conflict do nothing;
    else
      insert into public.hidden_suggestions (owner_id, city_id) values (v_me, p_city_id) on conflict do nothing;
    end if;
  else
    delete from public.hidden_suggestions h where h.owner_id = v_me
      and (h.experience_id = p_experience_id or h.city_id = p_city_id);
  end if;
  return p_hidden;
end$$;

-- Places friends sent you and lists they shared with you ---------------------------------------------------------
-- The one read-only function this feature uses for #3's sharing data. It reads the agreed shape (who sent it, who
-- received it, the place or list, when) and never writes. If #3 moves sharing into new tables, only this body changes.
create or replace function app_private.is_active_friend(p_viewer uuid, p_other uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_viewer <> p_other
    and app_private.are_friends(p_viewer, p_other)
    and not app_private.is_blocked_pair(p_viewer, p_other)
    and exists (select 1 from public.profiles p where p.id = p_other and p.deactivated_at is null)
$$;

create or replace function app_private.incoming_picks(p_viewer uuid)
returns table (experience_id uuid, sender_id uuid, via text, list_id uuid, list_title text, shared_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select s.experience_id, s.sender_id, 'sent', null::uuid, null::text, s.created_at
  from public.direct_shares s
  where s.recipient_id = p_viewer and s.experience_id is not null and app_private.is_active_friend(p_viewer, s.sender_id)
  union all
  select i.experience_id, l.owner_id, 'list', l.id, l.title, s.created_at
  from public.direct_shares s
  join public.lists l on l.id = s.list_id
  join public.list_items i on i.list_id = l.id
  where s.recipient_id = p_viewer and app_private.is_active_friend(p_viewer, l.owner_id)
$$;

-- Places ------------------------------------------------------------------------------------------------------
-- Every place in an area worth suggesting to the viewer, with its points and the facts behind its reason line.
-- Leaves out places you've been to, rated, saved or hidden, places Apple lists as unavailable, and towns.
create or replace function app_private.place_suggestions(p_viewer uuid, p_min_lat double precision, p_max_lat double precision,
                                                         p_min_lon double precision, p_max_lon double precision, p_country text)
returns table (experience_id uuid, city_id uuid, points numeric, google_rating numeric, name text, evidence jsonb)
language sql stable security definer set search_path = '' as $$
  with w as (select app_private.suggestion_weights() as w),
  area as (
    select e.id as experience_id, e.category, pl.city_id, pl.google_rating, pl.name
    from public.experiences e join public.places pl on pl.id = e.place_id
    where pl.status = 'active' and not pl.is_locality
      and (p_min_lat is null or pl.latitude between p_min_lat and p_max_lat)
      and (p_min_lon is null or pl.longitude between p_min_lon and p_max_lon)
      and (p_country is null or pl.country_code = upper(p_country))
      and not exists (select 1 from public.visits v where v.owner_id = p_viewer and v.experience_id = e.id)
      and not exists (select 1 from public.ratings r where r.owner_id = p_viewer and r.experience_id = e.id)
      and not exists (select 1 from public.bookmarks b where b.owner_id = p_viewer and b.experience_id = e.id)
      and not exists (select 1 from public.hidden_suggestions h where h.owner_id = p_viewer and h.experience_id = e.id)),
  picks as (select p.* from app_private.incoming_picks(p_viewer) p join area a on a.experience_id = p.experience_id),
  sent as (
    select p.experience_id, count(distinct p.sender_id)::int as senders, max(p.shared_at) as latest,
           jsonb_agg(pr.display_name order by p.shared_at desc, pr.display_name) as names
    from (select distinct on (experience_id, sender_id) experience_id, sender_id, shared_at from picks where via = 'sent'
          order by experience_id, sender_id, shared_at desc) p
    join public.profiles pr on pr.id = p.sender_id
    group by p.experience_id),
  listed as (
    select distinct on (p.experience_id) p.experience_id, p.shared_at as latest,
           jsonb_build_object('owner', pr.display_name, 'title', p.list_title) as list
    from picks p join public.profiles pr on pr.id = p.sender_id
    where p.via = 'list'
    order by p.experience_id, p.shared_at desc, p.list_id),
  -- Friends' ratings and visits the viewer may see.
  friend_ratings as (
    select r.experience_id, r.owner_id, r.sentiment
    from public.ratings r join area a on a.experience_id = r.experience_id
    where app_private.is_active_friend(p_viewer, r.owner_id) and app_private.audience_allows(r.owner_id, r.audience, p_viewer)),
  friend_visitors as (
    select distinct v.experience_id, v.owner_id
    from public.visits v join area a on a.experience_id = v.experience_id
    where app_private.is_active_friend(p_viewer, v.owner_id) and app_private.audience_allows(v.owner_id, v.audience, p_viewer)
    union
    select experience_id, owner_id from friend_ratings),
  friends as (
    select fv.experience_id,
           jsonb_agg(pr.display_name order by pr.display_name) as been,
           coalesce(jsonb_agg(pr.display_name order by pr.display_name) filter (where fr.sentiment = 'liked'), '[]'::jsonb) as loved,
           count(*) filter (where fr.sentiment = 'liked')::int as liked,
           count(*) filter (where fr.sentiment = 'fine')::int as fine,
           count(*) filter (where fr.sentiment = 'disliked')::int as disliked,
           count(*) filter (where fr.sentiment is null)::int as been_only
    from friend_visitors fv
    join public.profiles pr on pr.id = fv.owner_id
    left join friend_ratings fr on fr.experience_id = fv.experience_id and fr.owner_id = fv.owner_id
    group by fv.experience_id),
  -- Everyone else's ratings the viewer may see (friends included), for "Popular on Roam".
  community as (
    select r.experience_id, count(*)::int as raters, round(avg(r.score), 1) as score
    from public.ratings r join area a on a.experience_id = r.experience_id
    where r.owner_id <> p_viewer and app_private.audience_allows(r.owner_id, r.audience, p_viewer)
    group by r.experience_id),
  -- Your own lean: your share of Liked places in each category.
  taste as (
    select r.category, count(*)::numeric / nullif(sum(count(*)) over (), 0) as lean, count(*)::int as liked,
           sum(count(*)) over ()::int as total_liked
    from public.ratings r where r.owner_id = p_viewer and r.sentiment = 'liked'
    group by r.category),
  scored as (
    select a.experience_id, a.city_id, a.google_rating, a.name, a.category,
           s.senders, s.names as sent_names, s.latest as sent_at, l.list, l.latest as listed_at,
           f.been, f.loved, f.liked, f.fine, f.disliked, f.been_only, c.raters, c.score as community_score,
           t.liked as liked_in_category, t.lean, t.total_liked,
           coalesce(f.liked * (w.w->>'friend_liked')::numeric + f.fine * (w.w->>'friend_fine')::numeric
                    + f.disliked * (w.w->>'friend_disliked')::numeric + f.been_only * (w.w->>'friend_been')::numeric, 0) as friend_points,
           coalesce(case when s.senders >= 1 then (w.w->>'sent_first')::numeric else 0 end
                    + case when s.senders >= 2 then (w.w->>'sent_second')::numeric else 0 end, 0)
             * case when s.latest < now() - make_interval(days => (w.w->>'stale_after_days')::int) then (w.w->>'stale_factor')::numeric else 1 end
           + case when l.list is null then 0 else (w.w->>'shared_list')::numeric
               * case when l.latest < now() - make_interval(days => (w.w->>'stale_after_days')::int) then (w.w->>'stale_factor')::numeric else 1 end end
           + coalesce(f.liked * (w.w->>'friend_liked')::numeric + f.fine * (w.w->>'friend_fine')::numeric
                      + f.disliked * (w.w->>'friend_disliked')::numeric + f.been_only * (w.w->>'friend_been')::numeric, 0)
           + case when coalesce(t.total_liked, 0) >= (w.w->>'taste_min_liked')::int then coalesce(t.lean, 0) * (w.w->>'taste_max')::numeric else 0 end
           + case when c.raters >= (w.w->>'popular_min_raters')::int and c.score >= (w.w->>'popular_min_score')::numeric
               then (w.w->>'popular')::numeric else 0 end as points
    from area a cross join w
    left join sent s on s.experience_id = a.experience_id
    left join listed l on l.experience_id = a.experience_id
    left join friends f on f.experience_id = a.experience_id
    left join community c on c.experience_id = a.experience_id
    left join taste t on t.category = a.category
    -- Only places someone you can see has rated, been to or passed on to you.
    where s.experience_id is not null or l.experience_id is not null or f.experience_id is not null or c.experience_id is not null)
  select experience_id, city_id, round(points, 1), google_rating, name,
         jsonb_strip_nulls(jsonb_build_object(
           'sentBy', sent_names, 'list', list,
           'friendsLoved', loved, 'friendsBeen', been,
           'friendsFine', fine, 'friendsDisliked', disliked,
           'communityCount', raters, 'communityScore', community_score,
           'likedInCategory', case when coalesce(total_liked, 0) >= (select (w->>'taste_min_liked')::int from w) then liked_in_category end,
           'isPopular', coalesce(raters >= (select (w->>'popular_min_raters')::int from w)
                                 and community_score >= (select (w->>'popular_min_score')::numeric from w), false)))
  from scored
  -- Places your friends didn't like on balance aren't suggested, whatever your taste or Roam says, unless a friend
  -- passed them on to you.
  where points >= 0 and (friend_points >= 0 or senders is not null or list is not null)
$$;

-- What a city page suggests: the area's places, best first.
create or replace function public.suggested_places(p_min_lat double precision default null, p_max_lat double precision default null,
                                                   p_min_lon double precision default null, p_max_lon double precision default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'experience', app_private.experience_summary_json(s.experience_id, v_me),
      'points', s.points, 'evidence', s.evidence,
      'communityScore', s.evidence->'communityScore', 'communityCount', coalesce((s.evidence->>'communityCount')::int, 0),
      'friendNames', coalesce(s.evidence->'friendsBeen', '[]'::jsonb),
      'coverPath', (select m.bucket || '/' || m.object_path from public.media m join public.visits v on v.id = m.visit_id
                    where v.experience_id = s.experience_id and m.state = 'attached' and app_private.audience_allows(v.owner_id, v.audience, v_me)
                    order by v.created_at desc, m.position limit 1))
      order by s.points desc, s.google_rating desc nulls last, s.name, s.experience_id)
    from (select * from app_private.place_suggestions(v_me, p_min_lat, p_max_lat, p_min_lon, p_max_lon, null)
          order by points desc, google_rating desc nulls last, name, experience_id limit 40) s), '[]'::jsonb);
end$$;

-- Cities ------------------------------------------------------------------------------------------------------
-- What Discover (everywhere) and a country or state page (one country; the app keeps a state's own cities) suggest.
-- Leaves out your homes, cities you've been to and cities you've hidden. A city adds up its best few places' points,
-- and gets more for being on an upcoming trip or on your wishlist.
create or replace function public.suggested_cities(p_country text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member(); v_w jsonb := app_private.suggestion_weights();
begin
  return coalesce((
    with places as (
      select s.*, row_number() over (partition by s.city_id order by s.points desc, s.google_rating desc nulls last, s.name, s.experience_id) as n
      from app_private.place_suggestions(v_me, null, null, null, null, p_country) s where s.city_id is not null),
    upcoming as (
      select t.id, t.name, t.start_date from public.trips t
      where t.owner_id = v_me and t.status <> 'past' and (t.end_date is null or t.end_date >= current_date)),
    trip_city as (
      select distinct on (tc.city_id) tc.city_id, u.name from upcoming u join public.trip_cities tc on tc.trip_id = u.id
      order by tc.city_id, u.start_date nulls last, u.name),
    trip_country as (
      select distinct on (tc.country_code) tc.country_code, u.name from upcoming u join public.trip_countries tc on tc.trip_id = u.id
      order by tc.country_code, u.start_date nulls last, u.name),
    been as (
      select vc.city_id from public.visited_cities vc where vc.owner_id = v_me
      union select h.city_id from public.home_cities h where h.owner_id = v_me
      union select pl.city_id from public.visits v join public.experiences e on e.id = v.experience_id
              join public.places pl on pl.id = e.place_id where v.owner_id = v_me and pl.city_id is not null),
    candidates as (
      select city_id from places
      union select tc.city_id from trip_city tc join public.cities c on c.id = tc.city_id
             where p_country is null or c.country_code = upper(p_country)),
    cities as (
      select c.id, c.name, c.region, c.country_code, co.name as country_name,
             coalesce(c.latitude, (select avg(pl.latitude) from public.places pl where pl.city_id = c.id)) as latitude,
             coalesce(c.longitude, (select avg(pl.longitude) from public.places pl where pl.city_id = c.id)) as longitude,
             coalesce((select sum(p.points) from places p where p.city_id = c.id and p.n <= (v_w->>'city_top_places')::int), 0)
               + case when tc.city_id is not null then (v_w->>'city_on_trip')::numeric
                      when tco.country_code is not null then (v_w->>'city_in_trip_country')::numeric else 0 end
               + case when exists (select 1 from public.saved_cities sc where sc.owner_id = v_me and sc.city_id = c.id)
                      then (v_w->>'city_saved')::numeric else 0 end as points,
             (select max(p.google_rating) from places p where p.city_id = c.id) as best_google,
             coalesce(tc.name, tco.name) as trip_name,
             (select p.experience_id from places p where p.city_id = c.id and p.n = 1) as top_place
      from candidates k
      join public.cities c on c.id = k.city_id
      left join public.countries co on co.code = c.country_code
      left join trip_city tc on tc.city_id = c.id
      left join trip_country tco on tco.country_code = c.country_code
      where c.id not in (select city_id from been where city_id is not null)
        and not exists (select 1 from public.hidden_suggestions h where h.owner_id = v_me and h.city_id = c.id)),
    ranked as (select * from cities order by points desc, best_google desc nulls last, name, id limit 30)
    select jsonb_agg(jsonb_build_object(
        'cityID', r.id,
        'destination', jsonb_build_object('name', r.name, 'region', r.region, 'countryCode', r.country_code, 'countryName', r.country_name,
                                          'latitude', coalesce(r.latitude, 0), 'longitude', coalesce(r.longitude, 0), 'radiusMeters', 15000),
        'points', round(r.points, 1),
        'evidence', jsonb_strip_nulls(jsonb_build_object(
          'tripName', r.trip_name,
          'sentBy', (select jsonb_agg(distinct n.value) from places p, jsonb_array_elements(p.evidence->'sentBy') n where p.city_id = r.id),
          'list', (select p.evidence->'list' from places p where p.city_id = r.id and p.evidence ? 'list' order by p.n limit 1),
          'friendsLoved', (select jsonb_agg(distinct n.value) from places p, jsonb_array_elements(p.evidence->'friendsLoved') n where p.city_id = r.id),
          'friendsBeen', (select jsonb_agg(distinct n.value) from places p, jsonb_array_elements(p.evidence->'friendsBeen') n where p.city_id = r.id),
          'communityCount', (select nullif(sum(coalesce((p.evidence->>'communityCount')::int, 0)), 0) from places p where p.city_id = r.id),
          'isPopular', exists (select 1 from places p where p.city_id = r.id and (p.evidence->>'isPopular')::boolean))),
        'placeCount', (select count(*) from places p where p.city_id = r.id),
        'coverURL', (select pl.photo_url from public.experiences e join public.places pl on pl.id = e.place_id where e.id = r.top_place),
        'coverPath', (select m.bucket || '/' || m.object_path from public.media m join public.visits v on v.id = m.visit_id
                      where v.experience_id = r.top_place and m.state = 'attached' and app_private.audience_allows(v.owner_id, v.audience, v_me)
                      order by v.created_at desc, m.position limit 1))
      order by r.points desc, r.best_google desc nulls last, r.name, r.id)
    from ranked r), '[]'::jsonb);
end$$;

-- Onboarding --------------------------------------------------------------------------------------------------
-- Places around your home city you might have been to: the ones your friends have been to first, then the ones most
-- people on Roam have rated, then Google's best known. Never places you've already logged.
create or replace function public.onboarding_places(p_min_lat double precision, p_max_lat double precision,
                                                    p_min_lon double precision, p_max_lon double precision)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.experience_summary_json(x.id, v_me) order by x.friends desc, x.raters desc, x.google_count desc nulls last, x.name, x.id)
    from (
      select e.id, pl.name, pl.google_rating_count as google_count,
             (select count(distinct v.owner_id) from public.visits v where v.experience_id = e.id
                and app_private.is_active_friend(v_me, v.owner_id) and app_private.audience_allows(v.owner_id, v.audience, v_me)) as friends,
             (select count(*) from public.ratings r where r.experience_id = e.id and r.owner_id <> v_me
                and app_private.audience_allows(r.owner_id, r.audience, v_me)) as raters
      from public.experiences e join public.places pl on pl.id = e.place_id
      where pl.status = 'active' and not pl.is_locality
        and pl.latitude between p_min_lat and p_max_lat and pl.longitude between p_min_lon and p_max_lon
        and not exists (select 1 from public.visits v where v.owner_id = v_me and v.experience_id = e.id)
        and not exists (select 1 from public.ratings r where r.owner_id = v_me and r.experience_id = e.id)
      order by friends desc, raters desc, google_count desc nulls last, pl.name, e.id
      limit 12) x), '[]'::jsonb);
end$$;

revoke execute on function app_private.suggestion_weights(), app_private.is_active_friend(uuid, uuid), app_private.incoming_picks(uuid),
  app_private.place_suggestions(uuid, double precision, double precision, double precision, double precision, text) from public, anon, authenticated;
revoke execute on function public.hide_suggestion(uuid, uuid, boolean),
  public.suggested_places(double precision, double precision, double precision, double precision),
  public.suggested_cities(text),
  public.onboarding_places(double precision, double precision, double precision, double precision) from public, anon;
grant execute on function public.hide_suggestion(uuid, uuid, boolean),
  public.suggested_places(double precision, double precision, double precision, double precision),
  public.suggested_cities(text),
  public.onboarding_places(double precision, double precision, double precision, double precision) to authenticated;

-- Discover's old list of every rated place is replaced by suggested_places and suggested_cities.
drop function public.discover_places(double precision, double precision, double precision, double precision);
