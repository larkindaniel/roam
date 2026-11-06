-- Only cities are planned now. Places put on a trip the old way become saved places instead: each joins the trip
-- owner's wishlist, its city joins the trip (so it still shows there), and it leaves the trip. Places already visited
-- stay on their trips as part of the trip's history.

insert into public.bookmarks(owner_id, experience_id)
select t.owner_id, tp.experience_id
from public.trip_places tp join public.trips t on t.id = tp.trip_id
where not exists (select 1 from public.visits v where v.owner_id = t.owner_id and v.experience_id = tp.experience_id)
on conflict do nothing;

insert into public.trip_cities(trip_id, city_id, position)
select distinct tp.trip_id, pl.city_id, 0
from public.trip_places tp
join public.trips t on t.id = tp.trip_id
join public.experiences e on e.id = tp.experience_id
join public.places pl on pl.id = e.place_id
where pl.city_id is not null
  and not exists (select 1 from public.visits v where v.owner_id = t.owner_id and v.experience_id = tp.experience_id)
on conflict do nothing;

delete from public.trip_places tp
using public.trips t
where t.id = tp.trip_id
  and not exists (select 1 from public.visits v where v.owner_id = t.owner_id and v.experience_id = tp.experience_id);
