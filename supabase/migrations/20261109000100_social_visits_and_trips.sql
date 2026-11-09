-- Shared trips and immediate friends-only visit tags. All access goes through RPCs.
create table public.trip_members (
  trip_id uuid not null references public.trips(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  invited_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (trip_id, member_id)
);
create index trip_members_by_member on public.trip_members(member_id, trip_id);
alter table public.trip_members enable row level security;
revoke all on public.trip_members from public, anon, authenticated;

create table public.visit_companions (
  visit_id uuid not null references public.visits(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  primary key (visit_id, member_id)
);
create index visit_companions_by_member on public.visit_companions(member_id);
alter table public.visit_companions enable row level security;
revoke all on public.visit_companions from public, anon, authenticated;

create or replace function app_private.lock_active_friend(p_actor uuid,p_friend uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.follows
  where follower_id=p_actor and followee_id=p_friend for key share;
  return found and app_private.is_active_friend(p_actor,p_friend);
end$$;

create or replace function app_private.can_edit_trip(p_trip uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.trips t where t.id=p_trip and (
      t.owner_id=p_viewer or (app_private.is_active_friend(p_viewer,t.owner_id) and exists (
        select 1 from public.trip_members m where m.trip_id=t.id and m.member_id=p_viewer and m.accepted_at is not null
      ))
    )
  )
$$;

-- Serialize writes to an itinerary and hold the membership until the write commits.
create or replace function app_private.lock_trip_edit(p_trip uuid,p_viewer uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare owner uuid;
begin
  select owner_id into owner from public.trips where id=p_trip for no key update;
  if owner is null then return false; end if;
  if owner=p_viewer then return true; end if;
  perform 1 from public.trip_members
  where trip_id=p_trip and member_id=p_viewer and accepted_at is not null for key share;
  return found and app_private.is_active_friend(p_viewer,owner);
end$$;

create or replace function app_private.can_read_trip(p_trip uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select app_private.can_edit_trip(p_trip,p_viewer) or exists (
    select 1 from public.trips t join public.direct_shares s on s.trip_id=t.id and s.sender_id=t.owner_id
    where t.id=p_trip and s.recipient_id=p_viewer and app_private.is_active_friend(p_viewer,t.owner_id)
  )
$$;

create or replace function app_private.can_read_list(p_list uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.lists l where l.id=p_list and (l.owner_id=p_viewer or (
      app_private.is_active_friend(p_viewer,l.owner_id) and exists (
        select 1 from public.direct_shares s where s.list_id=l.id and s.sender_id=l.owner_id and s.recipient_id=p_viewer
      )
    ))
  )
$$;

create or replace function public.set_trip_membership(p_trip_id uuid, p_member_id uuid, p_action text)
returns void language plpgsql security definer set search_path='' as $$
declare
  me uuid:=app_private.require_member();
  owner uuid;
begin
  select owner_id into owner from public.trips where id=p_trip_id;
  if owner is null or p_member_id is null or p_member_id=owner then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;

  case p_action
    when 'invite' then
      if me<>owner or not app_private.lock_active_friend(me,p_member_id) then
        raise exception 'roam:forbidden' using errcode='42501';
      end if;
      insert into public.trip_members(trip_id,member_id) values(p_trip_id,p_member_id) on conflict do nothing;
    when 'accept' then
      if me<>p_member_id or not app_private.lock_active_friend(me,owner) then
        raise exception 'roam:forbidden' using errcode='42501';
      end if;
      update public.trip_members set accepted_at=coalesce(accepted_at,now())
        where trip_id=p_trip_id and member_id=me;
      if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
    when 'decline', 'leave', 'remove' then
      if (p_action='remove' and me<>owner) or (p_action<>'remove' and me<>p_member_id) then
        raise exception 'roam:forbidden' using errcode='42501';
      end if;
      delete from public.trip_members
      where trip_id=p_trip_id and member_id=p_member_id
        and (p_action='remove' or (p_action='decline' and accepted_at is null) or (p_action='leave' and accepted_at is not null));
    else
      perform app_private.validation_error('Choose a trip action.');
  end case;
end$$;

create or replace function public.trip_invitations()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,'name',t.name,'owner',app_private.member_json(t.owner_id),
      'startDate',t.start_date,'endDate',t.end_date
    ) order by m.invited_at desc,t.id)
    from public.trip_members m join public.trips t on t.id=m.trip_id
    where m.member_id=me and m.accepted_at is null and app_private.is_active_friend(me,t.owner_id)), '[]'::jsonb);
end$$;

-- A removed member keeps their visits. The old itinerary no longer appears on those visits.
create or replace function app_private.detach_trip_member_visits()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update public.visits set trip_id=null where trip_id=old.trip_id and owner_id=old.member_id;
  return old;
end$$;

create trigger detach_trip_member_visits after delete on public.trip_members
for each row when (old.accepted_at is not null) execute function app_private.detach_trip_member_visits();

-- The two follow rows represent one friendship. Both deletions can safely invoke cleanup.
create or replace function app_private.revoke_friend_access()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  delete from public.direct_shares s
    where (s.sender_id,s.recipient_id) in ((old.follower_id,old.followee_id),(old.followee_id,old.follower_id));
  delete from public.trip_members m using public.trips t
    where m.trip_id=t.id and (t.owner_id,m.member_id) in ((old.follower_id,old.followee_id),(old.followee_id,old.follower_id));
  delete from public.visit_companions c using public.visits v
    where c.visit_id=v.id and (v.owner_id,c.member_id) in ((old.follower_id,old.followee_id),(old.followee_id,old.follower_id));
  return old;
end$$;

create trigger revoke_friend_access after delete on public.follows
for each row execute function app_private.revoke_friend_access();

create or replace function app_private.visit_companion_json(p_visit uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(app_private.member_json(c.member_id) order by p.display_name,c.member_id),'[]'::jsonb)
  from public.visit_companions c
  join public.visits v on v.id=c.visit_id
  join public.profiles p on p.id=c.member_id
  where v.id=p_visit and app_private.audience_allows(v.owner_id,v.audience,p_viewer)
    and app_private.is_active_friend(v.owner_id,c.member_id)
    and (p_viewer in (v.owner_id,c.member_id) or app_private.is_active_friend(p_viewer,c.member_id))
$$;

create or replace function app_private.save_visit_companions(p_visit uuid, p_members jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
  delete from public.visit_companions c where c.visit_id=p_visit
    and not exists (select 1 from jsonb_array_elements_text(p_members) x where x.value::uuid=c.member_id);
  insert into public.visit_companions(visit_id,member_id)
    select p_visit,value::uuid from jsonb_array_elements_text(p_members) on conflict do nothing;
end$$;

create or replace function public.remove_my_visit_tag(p_visit_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.require_member();
begin
  delete from public.visit_companions where visit_id=p_visit_id and member_id=me;
end$$;

create or replace function public.list_recipients(p_list_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid:=app_private.require_member();
begin
  if not exists (select 1 from public.lists where id=p_list_id and owner_id=me) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  return coalesce((select jsonb_agg(app_private.member_json(x.recipient_id) order by x.recipient_id)
    from (select distinct recipient_id from public.direct_shares
          where sender_id=me and list_id=p_list_id and app_private.is_active_friend(me,recipient_id)) x),'[]'::jsonb);
end$$;

create or replace function public.revoke_list_share(p_list_id uuid,p_recipient_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.require_member();
begin
  if not exists (select 1 from public.lists where id=p_list_id and owner_id=me) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  delete from public.direct_shares where list_id=p_list_id and sender_id=me and recipient_id=p_recipient_id;
end$$;

create or replace function public.friends_activity(p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare me uuid:=app_private.require_member(); cursor_data jsonb:=app_private.decode_cursor(p_cursor); rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.activity_json(x.id,me) order by x.published_at desc,x.id desc),'[]') into rows
  from (
    select a.id,a.published_at from public.activities a left join public.visits v on v.id=a.visit_id
    where app_private.is_active_friend(me,a.author_id)
      and app_private.activity_allowed(a.id,me)
      and (v.visit_date is not null or a.type='rerank')
      and not exists (select 1 from public.mutes where muter_id=me and muted_id=a.author_id)
      and (cursor_data is null or (a.published_at,a.id)<((cursor_data->>'publishedAt')::timestamptz,(cursor_data->>'id')::uuid))
    order by a.published_at desc,a.id desc limit 31
  ) x;
  return app_private.page_json(rows,'publishedAt');
end$$;

revoke execute on function app_private.lock_active_friend(uuid,uuid),app_private.can_edit_trip(uuid,uuid),app_private.lock_trip_edit(uuid,uuid),app_private.detach_trip_member_visits(),
  app_private.revoke_friend_access(),app_private.visit_companion_json(uuid,uuid),app_private.save_visit_companions(uuid,jsonb)
  from public,anon,authenticated;
revoke execute on function public.set_trip_membership(uuid,uuid,text),public.trip_invitations(),public.remove_my_visit_tag(uuid),
  public.list_recipients(uuid),public.revoke_list_share(uuid,uuid),public.friends_activity(text) from public,anon;
grant execute on function public.set_trip_membership(uuid,uuid,text),public.trip_invitations(),public.remove_my_visit_tag(uuid),
  public.list_recipients(uuid),public.revoke_list_share(uuid,uuid),public.friends_activity(text) to authenticated;

CREATE OR REPLACE FUNCTION app_private.normalized_visit_payload(p_visit jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  payload jsonb := case when p_visit is null or p_visit = 'null'::jsonb then '{}'::jsonb else p_visit end;
  date_text text;
  visit_date date;
  zone text;
  note text;
  media_ids jsonb;
  v_audience text := nullif(p_visit ->> 'audience', '');
  v_trip uuid;
  companions jsonb;
begin
  perform app_private.assert_json_keys(payload, array['date', 'timeZoneIdentifier', 'publicNote', 'mediaIDs', 'audience', 'tripID', 'companionIDs', 'replaceTrip']);
  if (payload ? 'date' and payload -> 'date' <> 'null'::jsonb and jsonb_typeof(payload -> 'date') <> 'string')
    or (payload ? 'timeZoneIdentifier' and payload -> 'timeZoneIdentifier' <> 'null'::jsonb and jsonb_typeof(payload -> 'timeZoneIdentifier') <> 'string')
    or (payload ? 'publicNote' and jsonb_typeof(payload -> 'publicNote') <> 'string')
    or (payload ? 'mediaIDs' and jsonb_typeof(payload -> 'mediaIDs') <> 'array') then
    perform app_private.validation_error('Check the visit details.');
  end if;
  if v_audience is not null and v_audience not in ('friends', 'only_me', 'public') then
    perform app_private.validation_error('Choose who can see this visit.');
  end if;
  begin
    v_trip := nullif(payload ->> 'tripID', '')::uuid;
  exception when invalid_text_representation then
    perform app_private.validation_error('Check the trip for this visit.');
  end;
  date_text := payload ->> 'date';
  if date_text is not null then
    if date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform app_private.validation_error('Use a calendar date for this visit.');
    end if;
    begin
      visit_date := date_text::date;
    exception when datetime_field_overflow or invalid_datetime_format then
      perform app_private.validation_error('Use a valid calendar date for this visit.');
    end;
  end if;
  zone := nullif(payload ->> 'timeZoneIdentifier', '');
  if zone is not null and not exists (select 1 from pg_timezone_names where name = zone) then
    perform app_private.validation_error('Use a valid time zone for this visit.');
  end if;
  note := coalesce(payload ->> 'publicNote', '');
  if char_length(note) > 5000 then
    perform app_private.validation_error('Use 5,000 characters or fewer for your public note.');
  end if;
  begin
    select coalesce(jsonb_agg((value #>> '{}')::uuid::text order by ordinal), '[]'::jsonb) into media_ids
    from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) with ordinality item(value, ordinal);
  exception when invalid_text_representation then
    perform app_private.validation_error('A photo reference is invalid.');
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) item where jsonb_typeof(item) <> 'string')
    or (select count(distinct value) from jsonb_array_elements(media_ids)) <> jsonb_array_length(media_ids) then
    perform app_private.validation_error('Choose different photos for this visit.');
  end if;
  if payload ? 'companionIDs' then
    if jsonb_typeof(payload->'companionIDs') <> 'array' then
      perform app_private.validation_error('Check who went with you.');
    end if;
    if exists (select 1 from jsonb_array_elements(payload->'companionIDs') x where jsonb_typeof(x.value) <> 'string') then
      perform app_private.validation_error('Check who went with you.');
    end if;
    begin
      select coalesce(jsonb_agg(distinct value::uuid order by value::uuid),'[]'::jsonb) into companions
      from jsonb_array_elements_text(payload->'companionIDs');
    exception when invalid_text_representation then
      perform app_private.validation_error('Check who went with you.');
    end;
  end if;
  if payload ? 'replaceTrip' and jsonb_typeof(payload->'replaceTrip') <> 'boolean' then
    perform app_private.validation_error('Check the trip for this visit.');
  end if;
  return jsonb_build_object('date', visit_date, 'timeZoneIdentifier', zone, 'publicNote', note, 'mediaIDs', media_ids, 'audience', v_audience, 'tripID', v_trip)
    || (case when payload ? 'companionIDs' then jsonb_build_object('companionIDs',companions) else '{}'::jsonb end)
    || (case when payload ? 'replaceTrip' then jsonb_build_object('replaceTrip',payload->'replaceTrip') else '{}'::jsonb end);
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.write_rating_visit(p_actor uuid, p_experience uuid, p_operation uuid, p_payload jsonb, p_anchor uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_visit uuid := p_anchor;
  asset record;
  companion uuid;
begin
  for companion in select value::uuid from jsonb_array_elements_text(p_payload->'companionIDs') loop
    if not app_private.lock_active_friend(p_actor,companion) then
      raise exception 'roam:validation:You can only add current friends to a visit.' using errcode='22023';
    end if;
  end loop;
  perform app_private.validate_rating_visit(p_actor, p_payload, p_anchor);
  if p_payload ->> 'tripID' is not null and not app_private.lock_trip_edit((p_payload ->> 'tripID')::uuid,p_actor) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  if v_visit is null then
    insert into public.visits(owner_id, experience_id, visit_date, date_precision, time_zone, public_note, source_operation_id, audience, trip_id)
    values (p_actor, p_experience, (p_payload ->> 'date')::date,
            case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
            p_payload ->> 'timeZoneIdentifier', p_payload ->> 'publicNote', p_operation,
            coalesce(p_payload ->> 'audience', 'friends'), (p_payload ->> 'tripID')::uuid)
    returning id into v_visit;
  else
    update public.visits set visit_date = (p_payload ->> 'date')::date,
      date_precision = case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
      time_zone = p_payload ->> 'timeZoneIdentifier', public_note = p_payload ->> 'publicNote',
      audience = coalesce(p_payload ->> 'audience', audience), trip_id = case when (p_payload->>'replaceTrip')::boolean then (p_payload->>'tripID')::uuid
                     else coalesce((p_payload ->> 'tripID')::uuid, trip_id) end
    where id = v_visit and owner_id = p_actor and experience_id = p_experience;
    if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
    delete from public.media m where m.visit_id = v_visit and m.owner_id = p_actor
      and not m.id::text in (select value from jsonb_array_elements_text(p_payload -> 'mediaIDs'));
  end if;
  for asset in select value, ordinal from jsonb_array_elements_text(p_payload -> 'mediaIDs') with ordinality item(value, ordinal) loop
    update public.media set state = 'attached', visit_id = v_visit,
      position = asset.ordinal - 1, attached_at = coalesce(attached_at, now()) where id = asset.value::uuid;
  end loop;
  if p_payload ? 'companionIDs' then
    perform app_private.save_visit_companions(v_visit,p_payload->'companionIDs');
  end if;
  return v_visit;
end;
$function$;

-- write_rating_visit locks companion and trip access before taking the visit row lock.
create or replace function public.update_visit(p_visit_id uuid,p_payload jsonb,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_payload jsonb:=app_private.normalized_visit_payload(p_payload); v_receipt jsonb; v_visit public.visits; v_result jsonb;
begin
  v_receipt:=app_private.rating_receipt(v_me,p_operation_id,'update_visit',jsonb_build_object('visitID',p_visit_id,'visit',v_payload));
  if v_receipt is not null then return v_receipt; end if;
  select * into v_visit from public.visits where id=p_visit_id;
  if v_visit.id is null then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if v_visit.owner_id<>v_me then raise exception 'roam:forbidden' using errcode='42501'; end if;
  perform id from public.experiences where id=v_visit.experience_id for update;
  perform app_private.write_rating_visit(v_me,v_visit.experience_id,p_operation_id,v_payload,p_visit_id);
  v_result:=app_private.visit_json(p_visit_id);
  perform app_private.store_rating_receipt(v_me,p_operation_id,'update_visit',jsonb_build_object('visitID',p_visit_id,'visit',v_payload),v_result);
  return v_result;
end$$;

create or replace function public.set_trip_city(p_trip_id uuid, p_city jsonb, p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_city uuid;
begin
  if not app_private.lock_trip_edit(p_trip_id,v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_city is null or jsonb_typeof(p_city)<>'object' then perform app_private.validation_error('Choose a city.'); end if;
  v_city:=app_private.upsert_city(p_city->>'countryCode',p_city->>'countryName',p_city->>'region',p_city->>'name',
                                  (p_city->>'latitude')::double precision,(p_city->>'longitude')::double precision);
  if p_present then
    insert into public.trip_cities(trip_id,city_id,position)
    values(p_trip_id,v_city,(select coalesce(max(position)+1,0) from public.trip_cities where trip_id=p_trip_id))
    on conflict do nothing;
  else
    delete from public.trip_cities where trip_id=p_trip_id and city_id=v_city;
  end if;
end$$;

create or replace function public.set_trip_country(p_trip_id uuid, p_code text, p_name text, p_present boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_code text;
begin
  if not app_private.lock_trip_edit(p_trip_id,v_me) then
    perform app_private.validation_error('You can''t edit this trip.');
  end if;
  v_code:=app_private.upsert_country(p_code,p_name);
  if v_code is null then perform app_private.validation_error('Choose a country.'); end if;
  if p_present then
    insert into public.trip_countries(trip_id,country_code,position)
    values(p_trip_id,v_code,(select coalesce(max(position)+1,0) from public.trip_countries where trip_id=p_trip_id))
    on conflict do nothing;
  else
    delete from public.trip_countries where trip_id=p_trip_id and country_code=v_code;
  end if;
end$$;

create or replace function public.set_visit_trip(p_visit_id uuid,p_trip_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_trip_id is not null and not app_private.lock_trip_edit(p_trip_id,v_me) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  update public.visits set trip_id=p_trip_id,updated_at=now() where id=p_visit_id and owner_id=v_me;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
end$$;

create or replace function public.my_trips()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.trip_json(t.id,v_me) order by t.created_at desc,t.id) from public.trips t where app_private.can_edit_trip(t.id,v_me)),'[]'::jsonb);
end$$;

create or replace function app_private.trip_json(p_trip uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',t.id,'owner',app_private.member_json(t.owner_id),'name',t.name,'description',t.description,
    'startDate',t.start_date,'endDate',t.end_date,'status',t.status,'isOwn',t.owner_id=p_viewer,'canEdit',app_private.can_edit_trip(t.id,p_viewer),
    'plannedCount',(select count(*) from public.trip_places p where p.trip_id=t.id),
    'visitedCount',(select count(distinct v.experience_id) from public.visits v where v.trip_id=t.id and app_private.audience_allows(v.owner_id,v.audience,p_viewer)),
    'stops',coalesce((select jsonb_agg(distinct p.stop) from public.trip_places p where p.trip_id=t.id and p.stop<>''),'[]'::jsonb),
    'cities',coalesce((select jsonb_agg(app_private.destination_json(c.city_id) order by c.ord) from app_private.trip_city_ids(t.id,p_viewer) c),'[]'::jsonb),
    'countries',coalesce((select jsonb_agg(tc.country_code::text order by tc.position) from public.trip_countries tc where tc.trip_id=t.id),'[]'::jsonb))
  from public.trips t where t.id=p_trip
$$;

create or replace function public.trip_detail(p_trip_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not app_private.can_read_trip(p_trip_id,v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.trip_json(p_trip_id,v_me)||jsonb_build_object(
    'members',coalesce((select jsonb_agg(jsonb_build_object('member',app_private.member_json(m.member_id),
      'accepted',m.accepted_at is not null) order by m.accepted_at nulls last,m.member_id)
      from public.trip_members m join public.trips t on t.id=m.trip_id
      where m.trip_id=p_trip_id and app_private.is_active_friend(t.owner_id,m.member_id)
        and not app_private.is_blocked_pair(v_me,m.member_id)
        and (t.owner_id=v_me or (app_private.can_edit_trip(t.id,v_me) and m.accepted_at is not null))),'[]'::jsonb),
    'places',coalesce((
    select jsonb_agg(jsonb_build_object('experience',app_private.experience_summary_json(x.experience_id,v_me),'stop',x.stop,'isPlanned',x.planned,'isVisited',x.visited)
                     order by x.stop,x.position,x.experience_id)
    from(select e.experience_id,coalesce(p.stop,'') stop,coalesce(p.position,2147483647) "position",p.trip_id is not null planned,
                exists(select 1 from public.visits v where v.trip_id=p_trip_id and v.experience_id=e.experience_id and app_private.audience_allows(v.owner_id,v.audience,v_me)) visited
         from(select p2.experience_id from public.trip_places p2 where p2.trip_id=p_trip_id
              union select v2.experience_id from public.visits v2 where v2.trip_id=p_trip_id and app_private.audience_allows(v2.owner_id,v2.audience,v_me)) e
         left join public.trip_places p on p.trip_id=p_trip_id and p.experience_id=e.experience_id)x),'[]'::jsonb));
end$$;

CREATE OR REPLACE FUNCTION app_private.visit_json(p_visit uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id', v.id, 'experienceID', v.experience_id, 'ownerID', v.owner_id,
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'publicNote', v.public_note, 'audience', v.audience, 'tripID', case when app_private.can_read_trip(v.trip_id,auth.uid()) then v.trip_id end,
    'companions', app_private.visit_companion_json(v.id,auth.uid()),
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = v.id and m.state = 'attached'), '[]'::jsonb),
    'createdAt', v.created_at, 'updatedAt', v.updated_at)
  from public.visits v where v.id = p_visit
$function$;

create or replace function app_private.activity_json(p_activity uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', a.id, 'type', a.type, 'author', app_private.member_json(a.author_id),
    'experience', app_private.experience_summary_json(a.experience_id, p_viewer), 'category', a.category,
    'scoreSnapshot', a.score_snapshot, 'rankSnapshot', a.rank_snapshot, 'sentimentSnapshot', a.sentiment_snapshot,
    'visitID', a.visit_id,
    'trip', (select jsonb_build_object('id',t.id,'name',t.name) from public.trips t
             where t.id=v.trip_id and app_private.can_read_trip(t.id,p_viewer)),
    'companions', app_private.visit_companion_json(v.id,p_viewer),
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'note', coalesce(v.public_note, ''),
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = a.visit_id and m.state = 'attached'), '[]'::jsonb),
    'publishedAt', a.published_at,
    'likeCount', (select count(*) from public.likes l join public.profiles p on p.id = l.actor_id
                  where l.activity_id = a.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, l.actor_id)),
    'commentCount', (select count(*) from public.comments c join public.profiles p on p.id = c.author_id
                     where c.activity_id = a.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, c.author_id)),
    'likedByViewer', exists (select 1 from public.likes l where l.activity_id = a.id and l.actor_id = p_viewer),
    'isOwn', a.author_id = p_viewer)
  from public.activities a left join public.visits v on v.id = a.visit_id
  where a.id = p_activity
$$;

create or replace function public.friend_memories(p_experience_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
      'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),'publicNote',v.public_note,
      'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,v_me),'createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',false,
      'score',(select r.score from public.ratings r where r.owner_id=v.owner_id and r.experience_id=v.experience_id and app_private.audience_allows(r.owner_id,r.audience,v_me)))
      order by v.created_at desc,v.id desc)
    from(select x.* from public.visits x
         where x.experience_id=p_experience_id and x.owner_id<>v_me and app_private.are_friends(v_me,x.owner_id)
           and app_private.audience_allows(x.owner_id,x.audience,v_me)
         order by x.created_at desc,x.id desc limit 30)v),'[]'::jsonb);
end$$;

CREATE OR REPLACE FUNCTION public.public_memories(p_experience_id uuid, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb; v_date timestamptz; v_id uuid; v_rows jsonb;
begin
  if not exists(select 1 from public.experiences where id=p_experience_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_cursor is not null then
    begin
      v_cursor:=convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
      v_date:=(v_cursor->>'createdAt')::timestamptz; v_id:=(v_cursor->>'id')::uuid;
      if v_date is null or v_id is null then raise exception 'invalid cursor'; end if;
    exception when others then perform app_private.validation_error('This memory page has an invalid cursor.'); end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
    'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),'publicNote',v.public_note,'audience',v.audience,
    'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,v_me),'createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',v.owner_id=v_me,
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1))
    order by v.created_at desc,v.id desc),'[]') into v_rows
  from(select x.* from public.visits x join public.profiles p on p.id=x.owner_id and p.deactivated_at is null
       where x.experience_id=p_experience_id and app_private.audience_allows(x.owner_id,x.audience,v_me)
         and(p_cursor is null or(x.created_at,x.id)<(v_date,v_id)) order by x.created_at desc,x.id desc limit 31)v;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinal),'[]') from jsonb_array_elements(v_rows) with ordinality t(value,ordinal) where ordinal<=30),
    'nextCursor',case when jsonb_array_length(v_rows)>30 then translate(encode(convert_to(jsonb_build_object('createdAt',v_rows->29->>'createdAt','id',v_rows->29->>'id')::text,'UTF8'),'base64'),E'\n','') end);
end$function$;

create or replace function app_private.trip_feed_entry(p_visit uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',v.id,'experience',app_private.experience_summary_json(v.experience_id,p_viewer),
    'publicNote',v.public_note,'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),
    'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,p_viewer),'author',app_private.member_json(v.owner_id),'createdAt',v.created_at,
    'score',(select r.score from public.ratings r where r.owner_id=v.owner_id and r.experience_id=v.experience_id),
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1))
  from public.visits v where v.id=p_visit
$$;

create or replace function public.trip_updates(p_owner uuid,p_trip_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if (p_trip_id is null and p_owner is null) or (p_trip_id is not null and not app_private.can_read_trip(p_trip_id,v_me)) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  return coalesce((select jsonb_agg(app_private.trip_feed_entry(v.id,v_me) order by v.created_at desc,v.id desc)
    from public.visits v where (p_owner is null or v.owner_id=p_owner) and v.trip_id is not distinct from p_trip_id
      and app_private.audience_allows(v.owner_id,v.audience,v_me)),'[]'::jsonb);
end$$;

CREATE OR REPLACE FUNCTION public.trip_feed()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(g.owner_id),'tripID',case when app_private.can_read_trip(g.trip_id,v_me) then g.trip_id end,
      'tripName',(select t.name from public.trips t where t.id=g.trip_id and app_private.can_read_trip(t.id,v_me)),'visitCount',g.visits,'latestAt',g.latest,'isOwn',g.owner_id=v_me,
      'locations',(select coalesce(jsonb_agg(distinct jsonb_build_object('city',pl.locality,'countryCode',pl.country_code,'country',pl.country_name)),'[]'::jsonb)
                   from public.visits x join public.experiences e on e.id=x.experience_id join public.places pl on pl.id=e.place_id
                   where x.owner_id=g.owner_id and x.trip_id is not distinct from g.trip_id and app_private.audience_allows(x.owner_id,x.audience,v_me)),
      'entries',(select jsonb_agg(app_private.trip_feed_entry(l.id,v_me) order by l.created_at desc)
                 from(select x.id,x.created_at from public.visits x
                      where x.owner_id=g.owner_id and x.trip_id is not distinct from g.trip_id and app_private.audience_allows(x.owner_id,x.audience,v_me)
                      order by x.created_at desc,x.id desc limit 5)l)) order by g.latest desc,g.owner_id,g.trip_id)
    from(select v.owner_id,v.trip_id,count(*)::int visits,max(v.created_at) latest from public.visits v
         where app_private.audience_allows(v.owner_id,v.audience,v_me)
           and(v.owner_id=v_me or(app_private.are_friends(v_me,v.owner_id)
               and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=v.owner_id)))
         group by v.owner_id,v.trip_id order by latest desc limit 50)g),'[]'::jsonb);
end$function$;

create or replace function public.send_share(p_recipient uuid,p_experience_id uuid,p_list_id uuid,p_trip_id uuid,p_message text,p_operation_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_id uuid;
begin
  if p_operation_id is null then perform app_private.validation_error('This share needs an operation identifier.'); end if;
  if num_nonnulls(p_experience_id,p_list_id,p_trip_id)<>1 then perform app_private.validation_error('Choose one place, list or trip to share.'); end if;
  if char_length(coalesce(p_message,''))>500 then perform app_private.validation_error('Use 500 characters or fewer for your message.'); end if;
  if not app_private.lock_active_friend(v_me,p_recipient) then raise exception 'roam:forbidden' using errcode='42501'; end if;
  if p_list_id is not null and not exists(select 1 from public.lists where id=p_list_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_trip_id is not null and not exists(select 1 from public.trips where id=p_trip_id and owner_id=v_me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  insert into public.direct_shares(sender_id,recipient_id,experience_id,list_id,trip_id,message,operation_id)
  values(v_me,p_recipient,p_experience_id,p_list_id,p_trip_id,coalesce(p_message,''),p_operation_id)
  on conflict(sender_id,operation_id) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.direct_shares where sender_id=v_me and operation_id=p_operation_id; end if;
  return v_id;
end$$;

-- Date edits are separate from ownership-only name and description edits.
create or replace function public.set_trip_dates(p_trip_id uuid,p_start date,p_end date,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare me uuid:=app_private.require_member();
begin
  if not app_private.lock_trip_edit(p_trip_id,me) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_start is not null and p_end is not null and p_start>p_end then
    perform app_private.validation_error('The trip can''t end before it starts.');
  end if;
  if p_status is null or p_status not in ('planning','upcoming','ongoing','past') then
    perform app_private.validation_error('Choose a trip status.');
  end if;
  update public.trips set start_date=p_start,end_date=p_end,status=p_status where id=p_trip_id;
  return app_private.trip_json(p_trip_id,me);
end$$;
revoke execute on function public.set_trip_dates(uuid,date,date,text) from public,anon;
grant execute on function public.set_trip_dates(uuid,date,date,text) to authenticated;

-- A profile passport counts only visits the viewer can read.
create or replace function public.passport(p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_owner<>v_me and not app_private.is_active_friend(v_me,p_owner) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('code',k.code,'name',k.name,'cities',k.cities,'otherPlaceCount',k.other_places,'otherVisibleCount',k.other_visible)
                     order by k.name)
    from (
      select co.code, co.name,
        coalesce((select jsonb_agg(jsonb_build_object('city',app_private.destination_json(c.city_id),
                    'placeCount',c.places,'visibleCount',c.visible,'firstVisit',c.first_visit,'lastVisit',c.last_visit,
                    'isMarked',c.marked,'isHome',exists(select 1 from public.home_cities h where h.owner_id=p_owner and h.city_id=c.city_id),
                    'markedStart',(select vc.start_date from public.visited_cities vc where vc.owner_id=p_owner and vc.city_id=c.city_id),
                    'markedEnd',(select vc.end_date from public.visited_cities vc where vc.owner_id=p_owner and vc.city_id=c.city_id))
                  order by c.places desc, ci.name)
                  from (
                    select x.city_id, count(distinct x.experience_id) filter (where x.experience_id is not null) places,
                           count(distinct x.experience_id) filter (where x.visible) visible,
                           min(x.visit_date) first_visit, max(x.visit_date) last_visit, bool_or(x.marked) marked
                    from (
                      select pl.city_id, v.experience_id, v.visit_date, app_private.audience_allows(v.owner_id,v.audience,v_me) visible, false marked
                      from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
                      where v.owner_id=p_owner and app_private.audience_allows(v.owner_id,v.audience,v_me) and pl.city_id is not null and pl.country_code=co.code
                      union all
                      select vc.city_id, null, null, false, true from public.visited_cities vc join public.cities ci2 on ci2.id=vc.city_id
                      where vc.owner_id=p_owner and ci2.country_code=co.code
                      union all
                      select h.city_id, null, null, false, false from public.home_cities h join public.cities ci3 on ci3.id=h.city_id
                      where h.owner_id=p_owner and ci3.country_code=co.code
                    ) x group by x.city_id
                  ) c join public.cities ci on ci.id=c.city_id),'[]'::jsonb) cities,
        (select count(distinct v.experience_id) from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
          where v.owner_id=p_owner and app_private.audience_allows(v.owner_id,v.audience,v_me) and pl.city_id is null and pl.country_code=co.code) other_places,
        (select count(distinct v.experience_id) from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
          where v.owner_id=p_owner and app_private.audience_allows(v.owner_id,v.audience,v_me) and pl.city_id is null and pl.country_code=co.code) other_visible
      from public.countries co
      where co.code in (
        select pl.country_code from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
        where v.owner_id=p_owner and app_private.audience_allows(v.owner_id,v.audience,v_me) and pl.country_code is not null
        union select ci.country_code from public.visited_cities vc join public.cities ci on ci.id=vc.city_id where vc.owner_id=p_owner
        union select ci.country_code from public.home_cities h join public.cities ci on ci.id=h.city_id where h.owner_id=p_owner)
    ) k),'[]'::jsonb);
end$$;
