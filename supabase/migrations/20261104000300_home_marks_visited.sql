-- Setting a home city also marks it as somewhere you've been, so it stays been if it stops being home.

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
    -- A home is somewhere you've been: it stays in your passport after it stops being home.
    insert into public.visited_cities(owner_id,city_id) values(v_me,v_city) on conflict do nothing;
  else
    delete from public.home_cities where owner_id=v_me and city_id=v_city;
    update public.profiles set home_city_id=(select h.city_id from public.home_cities h where h.owner_id=v_me order by h.position limit 1)
    where id=v_me and home_city_id=v_city;
  end if;
  return public.my_home_cities();
end$$;

-- Cities already set as home count as been too.
insert into public.visited_cities(owner_id,city_id)
select h.owner_id,h.city_id from public.home_cities h on conflict do nothing;
