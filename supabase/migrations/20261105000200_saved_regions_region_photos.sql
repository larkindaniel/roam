-- States and provinces (Ontario, Kerala) can be wishlisted like countries, and have a Google photo kept a week.

create table public.saved_regions (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  country_code character(2) not null references public.countries (code),
  region_code text not null,
  name text not null,
  added_at timestamptz not null default now(),
  primary key (owner_id, country_code, region_code)
);
alter table public.saved_regions enable row level security;

-- Each saved region as "CA|ON".
create or replace function public.my_saved_regions()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(s.country_code::text||'|'||s.region_code order by s.added_at desc)
                   from public.saved_regions s where s.owner_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.set_region_saved(p_country text, p_region text, p_name text, p_present boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_code text; v_region text:=nullif(btrim(p_region),'');
begin
  v_code:=app_private.upsert_country(p_country,null);
  if v_code is null or v_region is null then perform app_private.validation_error('Choose a region.'); end if;
  if p_present then
    insert into public.saved_regions(owner_id,country_code,region_code,name)
    values(v_me,v_code,v_region,coalesce(nullif(btrim(p_name),''),v_region)) on conflict do nothing;
  else
    delete from public.saved_regions where owner_id=v_me and country_code=v_code and region_code=v_region;
  end if;
  return public.my_saved_regions();
end$$;

create table public.region_photos (
  key text primary key,
  photo_url text,
  photo_credit text,
  checked_at timestamptz not null default now()
);
alter table public.region_photos enable row level security;

create or replace function public.region_photo(p_key text)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('photoURL', r.photo_url, 'photoCredit', r.photo_credit, 'fresh', r.checked_at > now() - interval '7 days')
  from public.region_photos r where r.key = p_key
$$;

create or replace function public.save_region_photo(p_key text, p_url text, p_credit text)
returns void language sql security definer set search_path='' as $$
  insert into public.region_photos(key, photo_url, photo_credit, checked_at) values (p_key, p_url, p_credit, now())
  on conflict (key) do update set photo_url=excluded.photo_url, photo_credit=excluded.photo_credit, checked_at=now()
$$;

revoke execute on function public.my_saved_regions(), public.set_region_saved(text,text,text,boolean) from public, anon;
grant execute on function public.my_saved_regions(), public.set_region_saved(text,text,text,boolean) to authenticated;
revoke execute on function public.region_photo(text), public.save_region_photo(text,text,text) from public, anon, authenticated;
grant execute on function public.region_photo(text), public.save_region_photo(text,text,text) to service_role;
