-- Home cities: places in them are your local spots, kept out of the travel timeline.
-- Trip cities: a trip covers one or more cities, named up front or taken from its places.

create table public.home_cities (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  city_id uuid not null references public.cities (id),
  position integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (owner_id, city_id)
);

create table public.trip_cities (
  trip_id uuid not null references public.trips (id) on delete cascade,
  city_id uuid not null references public.cities (id),
  position integer not null default 0,
  primary key (trip_id, city_id)
);

alter table public.home_cities enable row level security;
alter table public.trip_cities enable row level security;

insert into public.home_cities (owner_id, city_id)
select id, home_city_id from public.profiles where home_city_id is not null
on conflict do nothing;

create or replace function public.my_home_cities()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.destination_json(h.city_id) order by h.position,h.added_at)
                   from public.home_cities h where h.owner_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.set_home_city(p_city jsonb, p_present boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  if p_present then
    insert into public.home_cities(owner_id,city_id,position)
    values(v_me,v_city,(select coalesce(max(position)+1,0) from public.home_cities where owner_id=v_me))
    on conflict do nothing;
    update public.profiles set home_city_id=coalesce(home_city_id,v_city) where id=v_me;
  else
    delete from public.home_cities where owner_id=v_me and city_id=v_city;
    update public.profiles set home_city_id=(select h.city_id from public.home_cities h where h.owner_id=v_me order by h.position limit 1)
    where id=v_me and home_city_id=v_city;
  end if;
  return public.my_home_cities();
end$$;

create or replace function public.set_trip_city(p_trip_id uuid, p_city jsonb, p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if not exists(select 1 from public.trips where id=p_trip_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  if p_present then
    insert into public.trip_cities(trip_id,city_id,position)
    values(p_trip_id,v_city,(select coalesce(max(position)+1,0) from public.trip_cities where trip_id=p_trip_id))
    on conflict do nothing;
  else
    delete from public.trip_cities where trip_id=p_trip_id and city_id=v_city;
  end if;
end$$;

-- A trip's cities: the ones named for it, then the cities of its planned and visited places.
create or replace function app_private.trip_city_ids(p_trip uuid, p_viewer uuid)
returns table(city_id uuid, ord bigint) language sql stable security definer set search_path='' as $$
  select c.city_id, min(c.ord) from (
    select tc.city_id, tc.position::bigint ord from public.trip_cities tc where tc.trip_id=p_trip
    union all
    select pl.city_id, 100000+tp.position from public.trip_places tp
      join public.experiences e on e.id=tp.experience_id join public.places pl on pl.id=e.place_id
      where tp.trip_id=p_trip and pl.city_id is not null
    union all
    select pl.city_id, 200000 from public.visits v
      join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
      where v.trip_id=p_trip and pl.city_id is not null and app_private.audience_allows(v.owner_id,v.audience,p_viewer)
  ) c group by c.city_id
$$;

create or replace function app_private.trip_json(p_trip uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',t.id,'owner',app_private.member_json(t.owner_id),'name',t.name,'description',t.description,
    'startDate',t.start_date,'endDate',t.end_date,'status',t.status,'isOwn',t.owner_id=p_viewer,
    'plannedCount',(select count(*) from public.trip_places p where p.trip_id=t.id),
    'visitedCount',(select count(distinct v.experience_id) from public.visits v where v.trip_id=t.id and app_private.audience_allows(v.owner_id,v.audience,p_viewer)),
    'stops',coalesce((select jsonb_agg(distinct p.stop) from public.trip_places p where p.trip_id=t.id and p.stop<>''),'[]'::jsonb),
    'cities',coalesce((select jsonb_agg(app_private.destination_json(c.city_id) order by c.ord) from app_private.trip_city_ids(t.id,p_viewer) c),'[]'::jsonb))
  from public.trips t where t.id=p_trip
$$;

revoke execute on function public.my_home_cities(),public.set_home_city(jsonb,boolean),public.set_trip_city(uuid,jsonb,boolean) from public,anon;
grant execute on function public.my_home_cities(),public.set_home_city(jsonb,boolean),public.set_trip_city(uuid,jsonb,boolean) to authenticated;
revoke execute on function app_private.trip_city_ids(uuid,uuid) from public,anon,authenticated;
