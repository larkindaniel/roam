-- Cities you've been to without logging a place, and the passport: every country and city a member has
-- been to. Friends see the whole passport, so a city counts even when its visits are private, but they open
-- only the places shared with them. Marking a city makes no activity, so it never reaches the feed.

create table public.visited_cities (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  city_id uuid not null references public.cities (id),
  added_at timestamptz not null default now(),
  primary key (owner_id, city_id)
);
alter table public.visited_cities enable row level security;

create or replace function public.set_city_visited(p_city jsonb, p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  if p_present then
    insert into public.visited_cities(owner_id,city_id) values(v_me,v_city) on conflict do nothing;
  else
    delete from public.visited_cities where owner_id=v_me and city_id=v_city;
  end if;
end$$;

create or replace function public.passport(p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_owner<>v_me and not app_private.are_friends(v_me,p_owner) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('code',k.code,'name',k.name,'cities',k.cities,'otherPlaceCount',k.other_places,'otherVisibleCount',k.other_visible)
                     order by k.name)
    from (
      select co.code, co.name,
        coalesce((select jsonb_agg(jsonb_build_object('city',app_private.destination_json(c.city_id),
                    'placeCount',c.places,'visibleCount',c.visible,'firstVisit',c.first_visit,'lastVisit',c.last_visit,
                    'isMarked',c.marked,'isHome',exists(select 1 from public.home_cities h where h.owner_id=p_owner and h.city_id=c.city_id))
                  order by c.places desc, ci.name)
                  from (
                    select x.city_id, count(distinct x.experience_id) filter (where x.experience_id is not null) places,
                           count(distinct x.experience_id) filter (where x.visible) visible,
                           min(x.visit_date) first_visit, max(x.visit_date) last_visit, bool_or(x.marked) marked
                    from (
                      select pl.city_id, v.experience_id, v.visit_date, app_private.audience_allows(v.owner_id,v.audience,v_me) visible, false marked
                      from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
                      where v.owner_id=p_owner and pl.city_id is not null and pl.country_code=co.code
                      union all
                      select vc.city_id, null, null, false, true from public.visited_cities vc join public.cities ci2 on ci2.id=vc.city_id
                      where vc.owner_id=p_owner and ci2.country_code=co.code
                      union all
                      select h.city_id, null, null, false, false from public.home_cities h join public.cities ci3 on ci3.id=h.city_id
                      where h.owner_id=p_owner and ci3.country_code=co.code
                    ) x group by x.city_id
                  ) c join public.cities ci on ci.id=c.city_id),'[]'::jsonb) cities,
        (select count(distinct v.experience_id) from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
          where v.owner_id=p_owner and pl.city_id is null and pl.country_code=co.code) other_places,
        (select count(distinct v.experience_id) from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
          where v.owner_id=p_owner and pl.city_id is null and pl.country_code=co.code and app_private.audience_allows(v.owner_id,v.audience,v_me)) other_visible
      from public.countries co
      where co.code in (
        select pl.country_code from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
        where v.owner_id=p_owner and pl.country_code is not null
        union select ci.country_code from public.visited_cities vc join public.cities ci on ci.id=vc.city_id where vc.owner_id=p_owner
        union select ci.country_code from public.home_cities h join public.cities ci on ci.id=h.city_id where h.owner_id=p_owner)
    ) k),'[]'::jsonb);
end$$;

revoke execute on function public.set_city_visited(jsonb,boolean),public.passport(uuid) from public,anon;
grant execute on function public.set_city_visited(jsonb,boolean),public.passport(uuid) to authenticated;
