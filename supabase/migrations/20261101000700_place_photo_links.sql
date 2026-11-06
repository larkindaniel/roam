-- A place can show a linked photo with its credit. The photo is loaded from its source, never stored here.
alter table public.places add column photo_url text check (photo_url is null or photo_url like 'https://%');
alter table public.places add column photo_credit text;

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
