-- A trip can be to a whole country before any of its cities or places are picked ("Norway, in June").

create table public.trip_countries (
  trip_id uuid not null references public.trips (id) on delete cascade,
  country_code character(2) not null references public.countries (code),
  position integer not null default 0,
  primary key (trip_id, country_code)
);
alter table public.trip_countries enable row level security;

create or replace function public.set_trip_country(p_trip_id uuid, p_code text, p_name text, p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_code text;
begin
  if not exists (select 1 from public.trips where id=p_trip_id and owner_id=v_me) then
    perform app_private.validation_error('That trip isn''t yours.');
  end if;
  v_code:=app_private.upsert_country(p_code,p_name);
  if v_code is null then perform app_private.validation_error('Choose a country.'); end if;
  if p_present then
    insert into public.trip_countries(trip_id,country_code,position)
    values(p_trip_id,v_code,(select coalesce(max(position)+1,0) from public.trip_countries where trip_id=p_trip_id))
    on conflict do nothing;
  else
    delete from public.trip_countries where trip_id=p_trip_id and country_code=v_code;
  end if;
end$$;

-- The trip summary also lists the countries named for it.
create or replace function app_private.trip_json(p_trip uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',t.id,'owner',app_private.member_json(t.owner_id),'name',t.name,'description',t.description,
    'startDate',t.start_date,'endDate',t.end_date,'status',t.status,'isOwn',t.owner_id=p_viewer,
    'plannedCount',(select count(*) from public.trip_places p where p.trip_id=t.id),
    'visitedCount',(select count(distinct v.experience_id) from public.visits v where v.trip_id=t.id and app_private.audience_allows(v.owner_id,v.audience,p_viewer)),
    'stops',coalesce((select jsonb_agg(distinct p.stop) from public.trip_places p where p.trip_id=t.id and p.stop<>''),'[]'::jsonb),
    'cities',coalesce((select jsonb_agg(app_private.destination_json(c.city_id) order by c.ord) from app_private.trip_city_ids(t.id,p_viewer) c),'[]'::jsonb),
    'countries',coalesce((select jsonb_agg(tc.country_code::text order by tc.position) from public.trip_countries tc where tc.trip_id=t.id),'[]'::jsonb))
  from public.trips t where t.id=p_trip
$$;

revoke execute on function public.set_trip_country(uuid,text,text,boolean) from public, anon;
grant execute on function public.set_trip_country(uuid,text,text,boolean) to authenticated;
