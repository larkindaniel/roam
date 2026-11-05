-- A city log can have photos, like a visit: staged uploads are attached to the city when it's logged.

alter table public.media add column city_id uuid references public.cities (id) on delete set null;
alter table public.media drop constraint media_check;
alter table public.media add constraint media_check
  check (state <> 'attached' or purpose = 'avatar' or visit_id is not null or city_id is not null);

drop function public.log_city(jsonb, date, date, text, text);
create or replace function public.log_city(p_city jsonb, p_start date, p_end date, p_sentiment text, p_note text,
                                           p_media_ids uuid[] default '{}')
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid; v_ids uuid[]:=coalesce(p_media_ids,'{}'); v_count integer;
begin
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  if p_start is not null and p_end is not null and p_end < p_start then perform app_private.validation_error('The end can''t be before the start.'); end if;
  if p_sentiment is not null and p_sentiment not in ('liked','fine','disliked') then perform app_private.validation_error('Choose how it was.'); end if;
  if char_length(coalesce(p_note,'')) > 5000 then perform app_private.validation_error('Notes can have up to 5,000 characters.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  -- The photos must be this member's own uploads, checked and not expired, as for a visit.
  if cardinality(v_ids) > 0 then
    perform id from public.media where id=any(v_ids) order by id for update;
    select count(*)::integer into v_count from public.media m join storage.objects o on o.bucket_id=m.bucket and o.name=m.object_path
    where m.id=any(v_ids) and m.owner_id=v_me and m.purpose='visit' and m.bucket='visit-media' and m.state='staged'
      and m.visit_id is null and m.expires_at>now() and m.inspected_at is not null and m.content_sha256 is not null
      and split_part(m.object_path,'/',1)=v_me::text and o.id=m.storage_object_id and (o.metadata->>'size')::bigint=m.byte_size;
    if v_count<>cardinality(v_ids) then perform app_private.validation_error('A photo is not inspected, uploaded, owned by you, or available.'); end if;
  end if;
  insert into public.visited_cities(owner_id,city_id,start_date,end_date,sentiment,note)
  values(v_me,v_city,p_start,p_end,p_sentiment,coalesce(p_note,''))
  on conflict (owner_id,city_id) do update
    set start_date=excluded.start_date, end_date=excluded.end_date, sentiment=excluded.sentiment, note=excluded.note;
  update public.media set state='attached', attached_at=now(), city_id=v_city,
         position=(select array_position(v_ids, media.id) - 1)
  where id=any(v_ids);
end$$;

revoke execute on function public.log_city(jsonb,date,date,text,text,uuid[]) from public, anon;
grant execute on function public.log_city(jsonb,date,date,text,text,uuid[]) to authenticated;
