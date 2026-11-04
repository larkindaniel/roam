-- Cities on your wishlist: somewhere you want to go, saved as a whole rather than place by place. Private to you.

create table public.saved_cities (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  city_id uuid not null references public.cities (id),
  added_at timestamptz not null default now(),
  primary key (owner_id, city_id)
);
alter table public.saved_cities enable row level security;

create or replace function public.my_saved_cities()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.destination_json(s.city_id) order by s.added_at desc)
                   from public.saved_cities s where s.owner_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.set_city_saved(p_city jsonb, p_present boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  if p_present then
    insert into public.saved_cities(owner_id,city_id) values(v_me,v_city) on conflict do nothing;
  else
    delete from public.saved_cities where owner_id=v_me and city_id=v_city;
  end if;
  return public.my_saved_cities();
end$$;

revoke execute on function public.my_saved_cities(), public.set_city_saved(jsonb,boolean) from public, anon;
grant execute on function public.my_saved_cities(), public.set_city_saved(jsonb,boolean) to authenticated;
