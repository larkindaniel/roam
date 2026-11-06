-- A city can be logged like a place: how it was (liked / fine / disliked), when, and a note, kept on its been mark.

alter table public.visited_cities
  add column sentiment text check (sentiment is null or sentiment in ('liked', 'fine', 'disliked')),
  add column note text not null default '' check (char_length(note) <= 5000);

create or replace function public.log_city(p_city jsonb, p_start date, p_end date, p_sentiment text, p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  if p_start is not null and p_end is not null and p_end < p_start then perform app_private.validation_error('The end can''t be before the start.'); end if;
  if p_sentiment is not null and p_sentiment not in ('liked','fine','disliked') then perform app_private.validation_error('Choose how it was.'); end if;
  if char_length(coalesce(p_note,'')) > 5000 then perform app_private.validation_error('Notes can have up to 5,000 characters.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  insert into public.visited_cities(owner_id,city_id,start_date,end_date,sentiment,note)
  values(v_me,v_city,p_start,p_end,p_sentiment,coalesce(p_note,''))
  on conflict (owner_id,city_id) do update
    set start_date=excluded.start_date, end_date=excluded.end_date, sentiment=excluded.sentiment, note=excluded.note;
end$$;

revoke execute on function public.log_city(jsonb,date,date,text,text) from public, anon;
grant execute on function public.log_city(jsonb,date,date,text,text) to authenticated;
