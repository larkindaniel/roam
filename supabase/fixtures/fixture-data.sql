-- Test-only fictional fixture content for the disposable LOCAL database (run by scripts/fixtures/setup.py
-- as the local postgres role after accounts/profiles exist). Idempotent: fixture-owned rows are replaced.
-- All people, places and notes are invented; coordinates are real so geography can be exercised.
begin;

create temporary table fixture_places (
  key text, n int, name text, category public.experience_category, address text, locality text, region text,
  country_code text, country_name text, latitude double precision, longitude double precision, time_zone text,
  phone text, website text, is_locality boolean, provider_category text
) on commit drop;

insert into fixture_places values
  ('harbor', 1, 'Harbor Lantern Café', 'food_drink', '12 Rua do Cais, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7072, -9.1366, 'Europe/Lisbon', '+351 21 000 0101', 'https://example.com/harbor-lantern', false, 'MKPOICategoryCafe'),
  ('cedar', 2, 'Cedar Ridge Trail', 'outdoors', 'Cedar Ridge Trailhead, Banff, AB, Canada', 'Banff', 'Alberta', 'CA', 'Canada', 51.1801, -115.5653, 'America/Edmonton', null, null, false, 'MKPOICategoryHiking'),
  ('willow', 3, 'Willow Bay', 'day_trips', null, 'Willow Bay', 'Wellington', 'NZ', 'New Zealand', -41.2189, 174.9031, 'Pacific/Auckland', null, null, true, null),
  ('quay', 4, 'North Quay Gallery', 'culture', '4 Nordkajen, Copenhagen, Denmark', 'Copenhagen', 'Capital Region', 'DK', 'Denmark', 55.6879, 12.5986, 'Europe/Copenhagen', null, 'https://example.com/north-quay', false, 'MKPOICategoryMuseum'),
  ('moonline', 5, 'Moonline Jazz Room', 'nightlife', '3-8 Shibuya, Tokyo, Japan', 'Tokyo', 'Tokyo', 'JP', 'Japan', 35.6597, 139.7006, 'Asia/Tokyo', '+81 3 0000 0202', null, false, 'MKPOICategoryNightlife'),
  ('kite', 6, 'Blue Kite Workshop', 'activities', '18 Bree Street, Cape Town, South Africa', 'Cape Town', 'Western Cape', 'ZA', 'South Africa', -33.9206, 18.4187, 'Africa/Johannesburg', null, null, false, 'MKPOICategoryFairground'),
  ('aster', 7, 'Aster House', 'stays', '55 Gion-machi, Kyoto, Japan', 'Kyoto', 'Kyoto', 'JP', 'Japan', 35.0037, 135.7788, 'Asia/Tokyo', null, 'https://example.com/aster-house', false, 'MKPOICategoryHotel'),
  ('saltmarsh', 8, 'Saltmarsh Oyster Bar', 'food_drink', '88 Avenida Ribeira, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7101, -9.1432, 'Europe/Lisbon', null, null, false, 'MKPOICategoryRestaurant'),
  ('tidewater', 9, 'Tidewater Noodle House', 'food_drink', '2-1 Ebisu, Tokyo, Japan', 'Tokyo', 'Tokyo', 'JP', 'Japan', 35.6467, 139.7101, 'Asia/Tokyo', null, null, false, 'MKPOICategoryRestaurant'),
  ('gull', 10, 'Gull & Pine Tavern', 'food_drink', '40 Fore Street, Portland, ME, United States', 'Portland', 'Maine', 'US', 'United States', 43.6563, -70.2524, 'America/New_York', null, null, false, 'MKPOICategoryRestaurant'),
  ('rosebud', 11, 'Rosebud Supper Club', 'nightlife', '711 SW Alder St, Portland, OR, United States', 'Portland', 'Oregon', 'US', 'United States', 45.5202, -122.6806, 'America/Los_Angeles', null, null, false, 'MKPOICategoryNightlife'),
  ('lookout', 12, 'Lantern Hill Lookout', 'outdoors', 'Higashiyama Trail, Kyoto, Japan', 'Kyoto', 'Kyoto', 'JP', 'Japan', 35.0097, 135.7952, 'Asia/Tokyo', null, null, false, 'MKPOICategoryPark'),
  ('fjord', 13, 'Ice Fjord Overlook', 'outdoors', null, null, null, 'GL', 'Greenland', 69.1675, -50.9821, 'America/Nuuk', null, null, false, 'MKPOICategoryNationalPark'),
  ('coral', 14, 'Coral Rest Lodge', 'stays', 'Matei Road, Taveuni, Fiji', 'Matei', 'Northern', 'FJ', 'Fiji', -16.6900, -179.8820, 'Pacific/Fiji', null, null, false, 'MKPOICategoryHotel'),
  ('lumen', 15, 'Lumen Street Hawker Hall', 'food_drink', '9 Lumen Street, Singapore', 'Singapore', null, 'SG', 'Singapore', 1.2838, 103.8500, 'Asia/Singapore', null, null, false, 'MKPOICategoryFoodMarket'),
  ('fig', 16, 'Fig & Ember Bakery', 'food_drink', '21 Jægersborggade, Copenhagen, Denmark', 'Copenhagen', 'Capital Region', 'DK', 'Denmark', 55.6925, 12.5450, 'Europe/Copenhagen', null, null, false, 'MKPOICategoryBakery'),
  ('lagoon', 17, 'Glass Lagoon Baths', 'activities', 'Lagoon Road, Reykjavík, Iceland', 'Reykjavík', 'Capital Region', 'IS', 'Iceland', 64.1356, -21.8954, 'Atlantic/Reykjavik', null, null, false, 'MKPOICategorySpa'),
  ('juniper', 18, 'Juniper Peak Hut', 'stays', 'Juniper Track, Queenstown, New Zealand', 'Queenstown', 'Otago', 'NZ', 'New Zealand', -45.0312, 168.6626, 'Pacific/Auckland', null, null, false, 'MKPOICategoryCampground'),
  ('mill', 19, 'Old Mill Cinema', 'culture', '7 Mill Lane, Edinburgh, United Kingdom', 'Edinburgh', 'Scotland', 'GB', 'United Kingdom', 55.9486, -3.1999, 'Europe/London', null, null, false, 'MKPOICategoryMovieTheater'),
  ('drift', 20, 'Driftwood Kayak Co.', 'outdoors', 'Harbour Quay, Wellington, New Zealand', 'Wellington', 'Wellington', 'NZ', 'New Zealand', -41.2865, 174.7762, 'Pacific/Auckland', null, null, false, 'MKPOICategoryKayaking');

-- Places and experiences (provider = fixture, provider ID fixture-<key>).
insert into public.places (id, provider, provider_place_id, name, normalized_name, address, normalized_address, locality, region,
                           country_code, country_name, city_id, latitude, longitude, phone, website, provider_category, time_zone,
                           is_locality, provenance)
select ('00000020-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'fixture', 'fixture-' || key, name,
       app_private.normalize_text(name), address, nullif(app_private.normalize_text(address), ''), locality, region,
       app_private.upsert_country(country_code, country_name), country_name,
       app_private.upsert_city(country_code, country_name, region, locality, latitude, longitude),
       latitude, longitude, phone, website, provider_category, time_zone, is_locality,
       jsonb_build_object('source', 'roam-fixture', 'note', 'fictional test place')
from fixture_places
on conflict (id) do nothing;

insert into public.experiences (id, place_id, category, category_source)
select ('00000030-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, ('00000020-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       category, 'suggested'
from fixture_places
on conflict (id) do nothing;

-- Replace fixture-owned memory content.
delete from public.private_notes where owner_id in (select id from public.profiles where handle in ('mayaroams', 'theowanders', 'priyaplans', 'jonashikes', 'lenaeats', 'samexplores'));
delete from public.bookmarks where owner_id in (select id from public.profiles where handle in ('mayaroams', 'theowanders', 'priyaplans', 'jonashikes', 'lenaeats', 'samexplores'));
delete from public.visits where source_operation_id = '00000099-0000-4000-8000-000000000000';

-- Public memories that stay unranked (rated memories are created through the ranking RPC from M4).
insert into public.visits (owner_id, experience_id, visit_date, date_precision, time_zone, public_note, source_operation_id)
values
  ('00000010-0000-4000-8000-000000000001', '00000030-0000-4000-8000-000000000015', '2026-01-08', 'day', 'Asia/Singapore', 'Laksa stall #14.', '00000099-0000-4000-8000-000000000000'),
  ('00000010-0000-4000-8000-000000000003', '00000030-0000-4000-8000-000000000006', null, 'unknown', null, 'Built a kite, lost a kite.', '00000099-0000-4000-8000-000000000000');

-- Owner-only private memories.
insert into public.private_notes (owner_id, experience_id, body) values
  ('00000010-0000-4000-8000-000000000001', '00000030-0000-4000-8000-000000000001', 'Ask for the corner table by the window. Card only.'),
  ('00000010-0000-4000-8000-000000000002', '00000030-0000-4000-8000-000000000016', 'Arrive before 9 for the cardamom buns.');

-- Want to Go bookmarks.
insert into public.bookmarks (owner_id, experience_id, saved_at) values
  ('00000010-0000-4000-8000-000000000001', '00000030-0000-4000-8000-000000000017', now() - interval '3 days'),
  ('00000010-0000-4000-8000-000000000001', '00000030-0000-4000-8000-000000000018', now() - interval '10 days'),
  ('00000010-0000-4000-8000-000000000001', '00000030-0000-4000-8000-000000000016', now() - interval '25 days'),
  ('00000010-0000-4000-8000-000000000002', '00000030-0000-4000-8000-000000000017', now() - interval '2 days'),
  ('00000010-0000-4000-8000-000000000002', '00000030-0000-4000-8000-000000000018', now() - interval '6 days'),
  ('00000010-0000-4000-8000-000000000002', '00000030-0000-4000-8000-000000000019', now() - interval '8 days'),
  ('00000010-0000-4000-8000-000000000004', '00000030-0000-4000-8000-000000000018', now() - interval '4 days');

commit;
