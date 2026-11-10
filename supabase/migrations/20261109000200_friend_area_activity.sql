-- Friend evidence comes from visible place visits in the requested geography.
create function public.friend_area_activity(p_country_code text, p_regions text[], p_city text, p_friend_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid := app_private.require_member();
begin
  return coalesce((
    with visits_here as materialized (
      select v.owner_id, v.experience_id, v.visit_date, v.created_at,
        coalesce(c.name, nullif(btrim(p.locality), '')) city,
        coalesce(c.region, p.region) region, p.country_code, k.name country_name,
        coalesce(c.latitude, p.latitude) latitude, coalesce(c.longitude, p.longitude) longitude
      from public.follows f
      join public.visits v on v.owner_id=f.followee_id
      join public.experiences e on e.id=v.experience_id
      join public.places p on p.id=e.place_id
      join public.countries k on k.code=p.country_code
      left join public.cities c on c.id=p.city_id
      where f.follower_id=me
        and p.country_code=upper(btrim(p_country_code))
        and (p_friend_id is null or v.owner_id=p_friend_id)
        and app_private.is_active_friend(me,v.owner_id)
        and app_private.audience_allows(v.owner_id,v.audience,me)
        and coalesce(c.name, nullif(btrim(p.locality), '')) is not null
        and (coalesce(cardinality(p_regions),0)=0 or app_private.normalize_text(coalesce(c.region,p.region))=any(p_regions)
          or app_private.normalize_text(p.region)=any(p_regions))
        and (p_city is null or app_private.normalize_text(coalesce(c.name,p.locality))=app_private.normalize_text(p_city))
    ), people as (
      select owner_id, count(distinct experience_id) place_count, max(visit_date) last_visit, max(created_at) last_log
      from visits_here group by owner_id
    )
    select jsonb_agg(jsonb_build_object(
      'member', app_private.member_json(person.owner_id),
      'placeCount', person.place_count,
      'cities', coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', c.city, 'region', c.region, 'countryCode', c.country_code, 'countryName', c.country_name,
          'latitude', c.latitude, 'longitude', c.longitude, 'radiusMeters', 15000
        ) order by c.visit_date desc nulls last,c.created_at desc,c.city)
        from (
          select distinct on (app_private.city_key(v.country_code,v.region,v.city)) v.*
          from visits_here v where v.owner_id=person.owner_id
          order by app_private.city_key(v.country_code,v.region,v.city),v.visit_date desc nulls last,v.created_at desc,v.experience_id
        ) c
      ),'[]'::jsonb),
      'places', case when p_friend_id is not null and p_city is not null then coalesce((
        select jsonb_agg(app_private.experience_summary_json(p.experience_id,me) order by p.last_visit desc nulls last,p.last_log desc,p.experience_id)
        from (
          select experience_id,max(visit_date) last_visit,max(created_at) last_log
          from visits_here where owner_id=person.owner_id group by experience_id
        ) p
      ),'[]'::jsonb) else '[]'::jsonb end
    ) order by person.last_visit desc nulls last,person.last_log desc,person.owner_id)
    from people person
  ),'[]'::jsonb);
end$$;

-- Keep the existing public memory API and share its pagination with friend-specific visits.
create function app_private.place_memories(p_experience_id uuid, p_cursor text, p_friend_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid := app_private.require_member();
  cursor_data jsonb; cursor_date timestamptz; cursor_id uuid; rows jsonb;
begin
  if not exists(select 1 from public.experiences where id=p_experience_id) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  if p_friend_id is not null and not app_private.is_active_friend(me,p_friend_id) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  if p_cursor is not null then
    begin
      cursor_data := convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
      cursor_date := (cursor_data->>'createdAt')::timestamptz;
      cursor_id := (cursor_data->>'id')::uuid;
      if cursor_date is null or cursor_id is null then raise exception 'invalid cursor'; end if;
    exception when others then perform app_private.validation_error('This memory page has an invalid cursor.');
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
    'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),
    'publicNote',v.public_note,'audience',v.audience,
    'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,me),
    'createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',v.owner_id=me,
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1)
  ) order by v.created_at desc,v.id desc),'[]') into rows
  from (
    select x.* from public.visits x join public.profiles p on p.id=x.owner_id and p.deactivated_at is null
    where x.experience_id=p_experience_id and (p_friend_id is null or x.owner_id=p_friend_id)
      and app_private.audience_allows(x.owner_id,x.audience,me)
      and (p_cursor is null or (x.created_at,x.id)<(cursor_date,cursor_id))
    order by x.created_at desc,x.id desc limit 31
  ) v;
  return app_private.page_json(rows,'createdAt');
end$$;

create or replace function public.public_memories(p_experience_id uuid, p_cursor text default null)
returns jsonb language sql stable security definer set search_path='' as $$
  select app_private.place_memories(p_experience_id,p_cursor,null)
$$;

create function public.friend_place_memories(p_experience_id uuid, p_friend_id uuid, p_cursor text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if p_friend_id is null then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.place_memories(p_experience_id,p_cursor,p_friend_id);
end$$;

revoke execute on function app_private.place_memories(uuid,text,uuid) from public,anon,authenticated;
revoke execute on function public.friend_area_activity(text,text[],text,uuid),
  public.friend_place_memories(uuid,uuid,text) from public,anon;
grant execute on function public.friend_area_activity(text,text[],text,uuid),
  public.friend_place_memories(uuid,uuid,text) to authenticated;
