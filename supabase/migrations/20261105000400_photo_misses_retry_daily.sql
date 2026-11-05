-- A country or area Google had no photo for is asked again the next day, not a week later: the first ask may have
-- used a name Google doesn't know it by ("China mainland").
create or replace function public.country_photo(p_code text)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('photoURL', c.photo_url, 'photoCredit', c.photo_credit,
                            'fresh', c.photo_checked_at is not null
                                     and c.photo_checked_at > now() - case when c.photo_url is null then interval '1 day' else interval '7 days' end)
  from public.countries c where c.code = upper(p_code)
$$;

create or replace function public.area_photo(p_key text)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('photoURL', a.photo_url, 'photoCredit', a.photo_credit,
                            'fresh', a.checked_at > now() - case when a.photo_url is null then interval '1 day' else interval '7 days' end)
  from public.area_photos a where a.key = p_key
$$;

-- Countries looked up before their names were tidied get a fresh look.
update public.countries set photo_checked_at = null where photo_url is null;
