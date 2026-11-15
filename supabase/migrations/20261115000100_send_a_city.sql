-- Send a city to friends, as well as a place, list or trip. A city isn't a stored place: it's a name with where it is
-- (region, country, centre and search radius), kept on the share as the app's Destination.

alter table public.direct_shares add column city jsonb;

alter table public.direct_shares drop constraint direct_shares_check1;
alter table public.direct_shares add constraint direct_shares_one_target
  check (num_nonnulls(experience_id, list_id, trip_id, city) = 1);

alter table public.direct_shares add constraint direct_shares_city_shape check (
  city is null or (
    jsonb_typeof(city) = 'object'
    and jsonb_typeof(city->'name') = 'string' and char_length(city->>'name') between 1 and 200
    and jsonb_typeof(city->'latitude') = 'number' and (city->>'latitude')::double precision between -90 and 90
    and jsonb_typeof(city->'longitude') = 'number' and (city->>'longitude')::double precision between -180 and 180
    and jsonb_typeof(city->'radiusMeters') = 'number' and (city->>'radiusMeters')::double precision between 0 and 500000
    and char_length(coalesce(city->>'region', '')) <= 200
    and char_length(coalesce(city->>'countryCode', '')) <= 3
    and char_length(coalesce(city->>'countryName', '')) <= 200
  )
);

drop function public.send_share(uuid, uuid, uuid, uuid, text, uuid);

create function public.send_share(p_recipient uuid, p_experience_id uuid, p_list_id uuid, p_trip_id uuid, p_message text,
                                  p_operation_id uuid, p_city jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member(); v_id uuid; v_city jsonb;
begin
  if p_operation_id is null then perform app_private.validation_error('This share needs an operation identifier.'); end if;
  if num_nonnulls(p_experience_id, p_list_id, p_trip_id, p_city) <> 1 then
    perform app_private.validation_error('Choose one place, city, list or trip to share.');
  end if;
  if char_length(coalesce(p_message, '')) > 500 then perform app_private.validation_error('Use 500 characters or fewer for your message.'); end if;
  if not app_private.lock_active_friend(v_me, p_recipient) then raise exception 'roam:forbidden' using errcode = '42501'; end if;
  if p_list_id is not null and not exists (select 1 from public.lists where id = p_list_id and owner_id = v_me) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  if p_trip_id is not null and not exists (select 1 from public.trips where id = p_trip_id and owner_id = v_me) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  -- Keep only the city's own fields; the table's check refuses anything malformed.
  if p_city is not null then
    if jsonb_typeof(p_city) <> 'object' then perform app_private.validation_error('That city is missing its details.'); end if;
    v_city := jsonb_strip_nulls(jsonb_build_object(
      'name', p_city->'name', 'region', p_city->'region', 'countryCode', p_city->'countryCode', 'countryName', p_city->'countryName',
      'latitude', p_city->'latitude', 'longitude', p_city->'longitude', 'radiusMeters', p_city->'radiusMeters'));
  end if;
  begin
    insert into public.direct_shares (sender_id, recipient_id, experience_id, list_id, trip_id, city, message, operation_id)
    values (v_me, p_recipient, p_experience_id, p_list_id, p_trip_id, v_city, coalesce(p_message, ''), p_operation_id)
    on conflict (sender_id, operation_id) do nothing returning id into v_id;
  exception when check_violation then
    perform app_private.validation_error('That city is missing its details.');
  end;
  if v_id is null then select id into v_id from public.direct_shares where sender_id = v_me and operation_id = p_operation_id; end if;
  return v_id;
end $$;

revoke execute on function public.send_share(uuid, uuid, uuid, uuid, text, uuid, jsonb) from public, anon;
grant execute on function public.send_share(uuid, uuid, uuid, uuid, text, uuid, jsonb) to authenticated;

create or replace function public.shared_with_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'sender', app_private.member_json(s.sender_id), 'message', s.message,
      'createdAt', s.created_at,
      'experience', case when s.experience_id is not null then app_private.experience_summary_json(s.experience_id, v_me) end,
      'list', case when s.list_id is not null then app_private.list_json(s.list_id, v_me) end,
      'trip', case when s.trip_id is not null then app_private.trip_json(s.trip_id, v_me) end,
      'city', s.city) order by s.created_at desc, s.id)
    from public.direct_shares s join public.profiles p on p.id = s.sender_id and p.deactivated_at is null
    where s.recipient_id = v_me and app_private.are_friends(v_me, s.sender_id) and not app_private.is_blocked_pair(v_me, s.sender_id)), '[]'::jsonb);
end $$;
