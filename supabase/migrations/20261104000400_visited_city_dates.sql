-- When you were in a city you marked as been (optional), so it can sit on your timeline and friends' feeds in order.

alter table public.visited_cities add column start_date date;
alter table public.visited_cities add column end_date date check (end_date is null or start_date is null or end_date >= start_date);

create or replace function public.mark_city_visited(p_city jsonb, p_start date, p_end date)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  if p_start is not null and p_end is not null and p_end < p_start then perform app_private.validation_error('The end can''t be before the start.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  insert into public.visited_cities(owner_id,city_id,start_date,end_date) values(v_me,v_city,p_start,p_end)
  on conflict (owner_id,city_id) do update set start_date=excluded.start_date, end_date=excluded.end_date;
end$$;

revoke execute on function public.mark_city_visited(jsonb,date,date) from public, anon;
grant execute on function public.mark_city_visited(jsonb,date,date) to authenticated;
