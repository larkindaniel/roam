-- Google's photo and star rating for a place, looked up by the `google-place` function with the server's key.
-- Google's rating is kept beside Roam's scores and never mixed into them. Lookups are refreshed after a week
-- so Google's data isn't held indefinitely; a place Google doesn't know is remembered so it isn't searched daily.

alter table public.places add column google_place_id text;
alter table public.places add column google_rating numeric(2,1) check (google_rating is null or google_rating between 1 and 5);
alter table public.places add column google_rating_count integer check (google_rating_count is null or google_rating_count >= 0);
alter table public.places add column google_checked_at timestamptz;

-- What the function needs to look places up. Service role only.
create or replace function public.google_lookup_targets(p_experience_ids uuid[])
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('experienceID', e.id, 'name', pl.name, 'locality', pl.locality,
    'latitude', pl.latitude, 'longitude', pl.longitude,
    'fresh', pl.google_checked_at is not null and pl.google_checked_at > now() - interval '7 days')), '[]'::jsonb)
  from public.experiences e join public.places pl on pl.id = e.place_id
  where e.id = any(p_experience_ids) and not pl.is_locality
$$;

-- Saves one lookup. A place with no Google match keeps any photo it already had.
create or replace function public.save_google_lookup(p_experience_id uuid, p_google_place_id text, p_rating numeric,
                                                     p_rating_count integer, p_photo_url text, p_photo_credit text)
returns void language plpgsql security definer set search_path='' as $$
begin
  update public.places pl set
    google_place_id = p_google_place_id,
    google_rating = p_rating,
    google_rating_count = p_rating_count,
    photo_url = case when p_photo_url like 'https://%' then p_photo_url else pl.photo_url end,
    photo_credit = case when p_photo_url like 'https://%' then p_photo_credit else pl.photo_credit end,
    google_checked_at = now()
  from public.experiences e
  where e.id = p_experience_id and pl.id = e.place_id;
end$$;

revoke execute on function public.google_lookup_targets(uuid[]), public.save_google_lookup(uuid,text,numeric,integer,text,text) from public, anon, authenticated;
grant execute on function public.google_lookup_targets(uuid[]), public.save_google_lookup(uuid,text,numeric,integer,text,text) to service_role;

CREATE OR REPLACE FUNCTION app_private.experience_summary_json(p_experience uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id', e.id, 'placeID', pl.id, 'name', pl.name, 'category', e.category,
    'locality', pl.locality, 'region', pl.region, 'countryCode', pl.country_code, 'countryName', pl.country_name,
    'latitude', pl.latitude, 'longitude', pl.longitude, 'providerPlaceID', pl.provider_place_id,
    'photoURL', pl.photo_url, 'photoCredit', pl.photo_credit,
    'googleRating', pl.google_rating, 'googleRatingCount', pl.google_rating_count,
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
$function$;
