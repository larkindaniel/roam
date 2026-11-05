-- A saved state keeps where it is, so it can open its page from a list.
alter table public.saved_regions
  add column latitude double precision,
  add column longitude double precision,
  add column radius_meters double precision;

drop function public.set_region_saved(text, text, text, boolean);
create or replace function public.set_region_saved(p_country text, p_region text, p_name text, p_present boolean,
                                                   p_latitude double precision default null, p_longitude double precision default null,
                                                   p_radius double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_code text; v_region text:=nullif(btrim(p_region),'');
begin
  v_code:=app_private.upsert_country(p_country,null);
  if v_code is null or v_region is null then perform app_private.validation_error('Choose a region.'); end if;
  if p_present then
    insert into public.saved_regions(owner_id,country_code,region_code,name,latitude,longitude,radius_meters)
    values(v_me,v_code,v_region,coalesce(nullif(btrim(p_name),''),v_region),p_latitude,p_longitude,p_radius)
    on conflict (owner_id,country_code,region_code) do update
      set latitude=coalesce(excluded.latitude,saved_regions.latitude), longitude=coalesce(excluded.longitude,saved_regions.longitude),
          radius_meters=coalesce(excluded.radius_meters,saved_regions.radius_meters);
  else
    delete from public.saved_regions where owner_id=v_me and country_code=v_code and region_code=v_region;
  end if;
  return public.my_saved_regions();
end$$;

create or replace function public.my_saved_region_list()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('countryCode', s.country_code::text, 'region', s.region_code, 'name', s.name,
                                                       'latitude', s.latitude, 'longitude', s.longitude, 'radiusMeters', s.radius_meters)
                                    order by s.added_at desc)
                   from public.saved_regions s where s.owner_id=v_me),'[]'::jsonb);
end$$;

revoke execute on function public.set_region_saved(text,text,text,boolean,double precision,double precision,double precision) from public, anon;
grant execute on function public.set_region_saved(text,text,text,boolean,double precision,double precision,double precision) to authenticated;
