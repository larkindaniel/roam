-- Something can be on your wishlist or where you've been, not both, and been wins. Being somewhere takes it off your
-- wishlist at its own level: a place you've visited or ranked, a city you've marked, live in or logged a place in, and
-- the state and country those are in. Saving something you've already been to doesn't stick.

create or replace function app_private.clear_been_wishlist(p_owner uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  delete from public.bookmarks b where b.owner_id=p_owner and (
    exists(select 1 from public.visits v where v.owner_id=p_owner and v.experience_id=b.experience_id)
    or exists(select 1 from public.ratings r where r.owner_id=p_owner and r.experience_id=b.experience_id));

  with been as (
    select vc.city_id from public.visited_cities vc where vc.owner_id=p_owner
    union select h.city_id from public.home_cities h where h.owner_id=p_owner
    union select pl.city_id from public.visits v join public.experiences e on e.id=v.experience_id
      join public.places pl on pl.id=e.place_id where v.owner_id=p_owner and pl.city_id is not null
  ), been_cities as (select c.* from public.cities c join been on been.city_id=c.id)
  , gone_cities as (delete from public.saved_cities s where s.owner_id=p_owner and s.city_id in (select city_id from been) returning 1)
  , gone_regions as (
    delete from public.saved_regions s where s.owner_id=p_owner and exists(
      select 1 from been_cities c where c.country_code=s.country_code
        and (lower(c.region)=lower(s.region_code) or lower(c.region)=lower(s.name))) returning 1)
  delete from public.saved_countries s where s.owner_id=p_owner and (
    s.country_code in (select country_code from been_cities)
    or exists(select 1 from public.visits v join public.experiences e on e.id=v.experience_id
              join public.places pl on pl.id=e.place_id where v.owner_id=p_owner and pl.country_code=s.country_code));
end$$;

create or replace function app_private.clear_been_wishlist_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform app_private.clear_been_wishlist(new.owner_id);
  return null;
end$$;

do $$
declare t text;
begin
  foreach t in array array['visits','ratings','visited_cities','home_cities','bookmarks','saved_cities','saved_regions','saved_countries'] loop
    execute format('drop trigger if exists clear_been_wishlist on public.%I', t);
    execute format('create trigger clear_been_wishlist after insert on public.%I for each row execute function app_private.clear_been_wishlist_trigger()', t);
  end loop;
end$$;

-- Tidy what's already there.
select app_private.clear_been_wishlist(id) from public.profiles;
