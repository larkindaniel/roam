-- A country's photo comes from Google (its own Places entry), looked up by the google-place function and kept for a
-- week, so each country costs one search and one photo request about once a week however often it's viewed.

alter table public.countries
  add column photo_url text,
  add column photo_credit text,
  add column photo_checked_at timestamptz;

create or replace function public.country_photo(p_code text)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('photoURL', c.photo_url, 'photoCredit', c.photo_credit,
                            'fresh', c.photo_checked_at is not null and c.photo_checked_at > now() - interval '7 days')
  from public.countries c where c.code = upper(p_code)
$$;

create or replace function public.save_country_photo(p_code text, p_name text, p_url text, p_credit text)
returns void language plpgsql security definer set search_path='' as $$
declare v_code text;
begin
  v_code:=app_private.upsert_country(p_code,p_name);
  update public.countries set photo_url=p_url, photo_credit=p_credit, photo_checked_at=now() where code=v_code;
end$$;

revoke execute on function public.country_photo(text), public.save_country_photo(text,text,text,text) from public, anon, authenticated;
grant execute on function public.country_photo(text), public.save_country_photo(text,text,text,text) to service_role;
