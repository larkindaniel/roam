-- One week-long cache for every Google area photo: states ("CA|ON") and now cities ("city|waterloo|ontario|canada").
alter table public.region_photos rename to area_photos;
drop function public.region_photo(text);
drop function public.save_region_photo(text, text, text);

create or replace function public.area_photo(p_key text)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('photoURL', a.photo_url, 'photoCredit', a.photo_credit, 'fresh', a.checked_at > now() - interval '7 days')
  from public.area_photos a where a.key = p_key
$$;

create or replace function public.save_area_photo(p_key text, p_url text, p_credit text)
returns void language sql security definer set search_path='' as $$
  insert into public.area_photos(key, photo_url, photo_credit, checked_at) values (p_key, p_url, p_credit, now())
  on conflict (key) do update set photo_url=excluded.photo_url, photo_credit=excluded.photo_credit, checked_at=now()
$$;

revoke execute on function public.area_photo(text), public.save_area_photo(text,text,text) from public, anon, authenticated;
grant execute on function public.area_photo(text), public.save_area_photo(text,text,text) to service_role;
