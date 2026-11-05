-- No set number of photos on a visit: the six-photo cap goes, from the visit check and the photos' positions.

alter table public.media drop constraint media_position_check;
alter table public.media add constraint media_position_check check (position >= 0);

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
begin
  perform app_private.assert_json_keys(payload, array['date', 'timeZoneIdentifier', 'publicNote', 'mediaIDs', 'audience', 'tripID']);
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
  return jsonb_build_object('date', visit_date, 'timeZoneIdentifier', zone, 'publicNote', note, 'mediaIDs', media_ids, 'audience', v_audience, 'tripID', v_trip);
end;
$function$;
