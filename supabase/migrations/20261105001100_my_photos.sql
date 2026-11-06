-- Your own photos for a place, a city, a state or a country, newest first, so pages can show yours ahead of Google's.
-- They roll up: a city has its city-log photos and those from your visits to places in it; a state or country has all
-- of those within it. Only your own attached photos, so this is only ever shown to you.

create or replace function public.my_photos(p_experience uuid default null, p_country text default null,
                                            p_region text default null, p_region_name text default null,
                                            p_city text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((
    select jsonb_agg(x.path order by x.attached_at desc nulls last, x.position)
    from (
      -- From your visits.
      select m.bucket||'/'||m.object_path path, m.attached_at, m.position
      from public.media m
      join public.visits v on v.id=m.visit_id
      join public.experiences e on e.id=v.experience_id
      join public.places pl on pl.id=e.place_id
      left join public.cities ci on ci.id=pl.city_id
      where m.owner_id=v_me and m.state='attached' and v.owner_id=v_me
        and (p_experience is null or e.id=p_experience)
        and (p_country is null or upper(pl.country_code)=upper(p_country))
        and (p_region is null or lower(coalesce(ci.region, pl.region, '')) in (lower(p_region), lower(coalesce(p_region_name, p_region))))
        and (p_city is null or lower(coalesce(ci.name, pl.locality, ''))=lower(p_city))
      union all
      -- From your city logs (not for a single place).
      select m.bucket||'/'||m.object_path, m.attached_at, m.position
      from public.media m
      join public.cities ci on ci.id=m.city_id
      where p_experience is null and m.owner_id=v_me and m.state='attached'
        and (p_country is null or ci.country_code=upper(p_country))
        and (p_region is null or lower(coalesce(ci.region, '')) in (lower(p_region), lower(coalesce(p_region_name, p_region))))
        and (p_city is null or lower(ci.name)=lower(p_city))
    ) x
  ), '[]'::jsonb);
end$$;

revoke execute on function public.my_photos(uuid,text,text,text,text) from public, anon;
grant execute on function public.my_photos(uuid,text,text,text,text) to authenticated;
