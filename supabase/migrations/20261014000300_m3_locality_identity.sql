-- Localities use provider/canonical city identity. Without either, keep them separate from
-- POI address fallbacks and flag the unresolved geography for later reconciliation.
create or replace function public.resolve_place(p_candidate jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  v_provider text := p_candidate ->> 'provider';
  v_provider_id text := nullif(btrim(p_candidate ->> 'providerPlaceID'), '');
  v_name text := btrim(p_candidate ->> 'name');
  v_address text := nullif(btrim(p_candidate ->> 'address'), '');
  v_lat double precision := (p_candidate ->> 'latitude')::double precision;
  v_lon double precision := (p_candidate ->> 'longitude')::double precision;
  v_is_locality boolean := coalesce((p_candidate ->> 'isLocality')::boolean, false);
  v_country text;
  v_city uuid;
  v_place uuid;
  v_experience uuid;
  v_category public.experience_category := nullif(p_candidate ->> 'suggestedCategory', '')::public.experience_category;
begin
  if v_provider is distinct from 'mapkit' then
    perform app_private.validation_error('Places must come from Apple Maps.');
  end if;
  if v_name is null or v_name = '' or v_lat is null or v_lon is null or v_lat not between -90 and 90 or v_lon not between -180 and 180 then
    perform app_private.validation_error('This place is missing a name or location.');
  end if;
  v_country := app_private.upsert_country(p_candidate ->> 'countryCode', p_candidate ->> 'countryName');
  v_city := app_private.upsert_city(v_country, p_candidate ->> 'countryName', p_candidate ->> 'region',
                                    coalesce(p_candidate ->> 'locality', case when v_is_locality then v_name end),
                                    case when v_is_locality then v_lat end, case when v_is_locality then v_lon end);
  if v_provider_id is not null then
    select id into v_place from public.places where provider = 'mapkit' and provider_place_id = v_provider_id;
  elsif v_is_locality and v_city is not null then
    select id into v_place from public.places where provider = 'mapkit' and provider_place_id is null and is_locality and city_id = v_city;
  elsif not v_is_locality and v_address is not null then
    select id into v_place from public.places
    where provider = 'mapkit' and provider_place_id is null and not is_locality
      and normalized_name = app_private.normalize_text(v_name) and normalized_address = app_private.normalize_text(v_address)
      and lat6 = round(v_lat::numeric, 6) and lon6 = round(v_lon::numeric, 6);
  end if;
  if v_place is null then
    begin
      insert into public.places (provider, provider_place_id, name, normalized_name, address, normalized_address, locality, region,
                                 country_code, country_name, city_id, latitude, longitude, phone, website, provider_category,
                                 time_zone, is_locality, needs_reconciliation, provenance)
      values ('mapkit', v_provider_id, v_name, app_private.normalize_text(v_name), v_address,
              nullif(app_private.normalize_text(v_address), ''), nullif(btrim(p_candidate ->> 'locality'), ''),
              nullif(btrim(p_candidate ->> 'region'), ''), v_country, nullif(btrim(p_candidate ->> 'countryName'), ''), v_city,
              v_lat, v_lon, nullif(p_candidate ->> 'phone', ''), nullif(p_candidate ->> 'website', ''),
              nullif(p_candidate ->> 'providerCategory', ''), nullif(p_candidate ->> 'timeZoneIdentifier', ''), v_is_locality,
              v_provider_id is null and (not v_is_locality or v_city is null),
              jsonb_build_object('source', 'mapkit', 'resolvedAt', now(), 'resolvedBy', me))
      returning id into v_place;
    exception when unique_violation then
      -- A concurrent resolution created the same identity first.
      select id into v_place from public.places
      where provider = 'mapkit'
        and ((v_provider_id is not null and provider_place_id = v_provider_id)
          or (v_provider_id is null and v_is_locality and is_locality and city_id = v_city)
          or (v_provider_id is null and not v_is_locality and normalized_name = app_private.normalize_text(v_name)
              and normalized_address = app_private.normalize_text(v_address) and lat6 = round(v_lat::numeric, 6) and lon6 = round(v_lon::numeric, 6)));
    end;
  end if;
  insert into public.experiences (place_id, category, category_source) values (v_place, v_category, 'suggested')
  on conflict (place_id) do nothing;
  select id into v_experience from public.experiences where place_id = v_place;
  return app_private.experience_summary_json(v_experience, me);
end;
$$;
