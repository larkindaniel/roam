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
  ('tiles', 23, 'Azulejo House Museum', 'culture', '34 Rua das Janelas, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7246, -9.1136, 'Europe/Lisbon', null, null, false, 'MKPOICategoryMuseum'),
  ('miradouro', 24, 'Miradouro das Gaivotas', 'outdoors', 'Largo das Gaivotas, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7155, -9.1296, 'Europe/Lisbon', null, null, false, 'MKPOICategoryPark'),
  ('alfama', 21, 'Alfama Lantern Fado', 'nightlife', '9 Beco do Carneiro, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7118, -9.1299, 'Europe/Lisbon', null, null, false, 'MKPOICategoryNightlife'),
  ('bica', 22, 'Bica Corner Coffee', 'food_drink', '2 Calçada da Bica, Lisbon, Portugal', 'Lisbon', 'Lisboa', 'PT', 'Portugal', 38.7104, -9.1461, 'Europe/Lisbon', null, null, false, 'MKPOICategoryCafe'),
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

-- Sample activity from other members, so Discover and the Friends tab have something to show. Each entry
-- is public, with a visit, a rating and a post. Maya starts with no ratings, so her own rankings stay hers.
delete from public.ratings where owner_id in (select id from public.profiles where handle in ('theowanders', 'priyaplans', 'jonashikes', 'lenaeats', 'samexplores'));
create temporary table fixture_entries (who text, owner_id uuid, key text, sentiment public.sentiment, group_position int, note text) on commit drop;
insert into fixture_entries values
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'harbor', 'liked'::public.sentiment, 0, 'Best pastel de nata I had all trip. Sit outside at dusk.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'saltmarsh', 'liked'::public.sentiment, 1, 'Order the oysters and whatever they tell you to drink.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'miradouro', 'liked'::public.sentiment, 0, 'Go at sunset, bring a beer from the kiosk.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'tidewater', 'liked'::public.sentiment, 2, 'Tiny counter, huge broth. Worth the queue.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'aster', 'liked'::public.sentiment, 3, 'Quiet garden room, the breakfast alone is worth it.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'lookout', 'fine'::public.sentiment, 0, 'Lovely view but very busy on weekends.'),
  ('theo', '00000010-0000-4000-8000-000000000002'::uuid, 'fig', 'liked'::public.sentiment, 4, 'Cardamom buns, every morning.'),
  ('sam', '00000010-0000-4000-8000-000000000006'::uuid, 'harbor', 'liked'::public.sentiment, 0, 'Friendly staff and the coffee is great.'),
  ('sam', '00000010-0000-4000-8000-000000000006'::uuid, 'tiles', 'liked'::public.sentiment, 1, 'Spent three hours here and could have stayed longer.'),
  ('sam', '00000010-0000-4000-8000-000000000006'::uuid, 'bica', 'fine'::public.sentiment, 0, 'Good espresso, not much seating.'),
  ('sam', '00000010-0000-4000-8000-000000000006'::uuid, 'lagoon', 'liked'::public.sentiment, 0, 'Go early before the tour buses arrive.'),
  ('sam', '00000010-0000-4000-8000-000000000006'::uuid, 'gull', 'liked'::public.sentiment, 2, 'Lobster roll lived up to the hype.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'saltmarsh', 'liked'::public.sentiment, 0, 'Booked two weeks out and glad I did.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'quay', 'liked'::public.sentiment, 1, 'Small, thoughtful collection. Free on Thursdays.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'aster', 'liked'::public.sentiment, 0, 'Worth every yen.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'moonline', 'liked'::public.sentiment, 2, 'Late set is the one to catch.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'miradouro', 'liked'::public.sentiment, 3, 'Prettiest view in Lisbon.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'alfama', 'liked'::public.sentiment, 4, 'Fado at a table for six, unforgettable.'),
  ('priya', '00000010-0000-4000-8000-000000000003'::uuid, 'tiles', 'fine'::public.sentiment, 0, 'Interesting, though the cafe was the highlight.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'cedar', 'liked'::public.sentiment, 0, 'Long climb, big payoff at the ridge.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'lookout', 'liked'::public.sentiment, 1, 'Go at sunrise and you''ll have it to yourself.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'juniper', 'liked'::public.sentiment, 2, 'Book the bunk by the stove.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'fjord', 'liked'::public.sentiment, 3, 'Nothing prepares you for the scale.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'kite', 'fine'::public.sentiment, 0, 'Fun afternoon, a bit pricey.'),
  ('jonas', '00000010-0000-4000-8000-000000000004'::uuid, 'willow', 'liked'::public.sentiment, 4, 'Perfect short walk from the ferry.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'harbor', 'liked'::public.sentiment, 1, 'Their grilled sardines are the move.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'saltmarsh', 'liked'::public.sentiment, 0, 'Ask for the counter seats.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'tidewater', 'liked'::public.sentiment, 0, 'The spicy broth changed my week.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'fig', 'liked'::public.sentiment, 2, 'Rye loaf to go, always.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'rosebud', 'liked'::public.sentiment, 3, 'Dress up a little, it''s worth it.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'lumen', 'liked'::public.sentiment, 4, 'Stall 14, then stall 22.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'alfama', 'liked'::public.sentiment, 5, 'Tiny, loud, perfect.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'bica', 'liked'::public.sentiment, 6, 'My favourite coffee in the city.'),
  ('lena', '00000010-0000-4000-8000-000000000005'::uuid, 'coral', 'liked'::public.sentiment, 7, 'Fell asleep to the waves.');
insert into public.visits (id, owner_id, experience_id, visit_date, date_precision, public_note, audience, source_operation_id, created_at)
select ('00000040-0000-4000-' || substr(md5(e.who || e.key), 1, 4) || '-' || substr(md5(e.who || e.key), 5, 12))::uuid, e.owner_id,
       ('00000030-0000-4000-8000-' || lpad(p.n::text, 12, '0'))::uuid, current_date - (row_number() over () * 3)::int, 'day', e.note, 'public',
       '00000099-0000-4000-8000-000000000000', now() - (row_number() over () * interval '2 days')
from fixture_entries e join fixture_places p on p.key = e.key;
insert into public.ratings (owner_id, experience_id, category, sentiment, group_position, score, rank)
select e.owner_id, ('00000030-0000-4000-8000-' || lpad(p.n::text, 12, '0'))::uuid, p.category, e.sentiment, e.group_position, 5.0, 1
from fixture_entries e join fixture_places p on p.key = e.key;
update public.ratings r set audience = 'public' where r.owner_id in (select owner_id from fixture_entries);
do $seed$
declare c record;
begin
  for c in select distinct r.owner_id, r.category from public.ratings r where r.owner_id in (select owner_id from fixture_entries) loop
    perform app_private.reflow_rating_category(c.owner_id, c.category);
  end loop;
end $seed$;
insert into public.activities (author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, published_at, source_operation_id)
select v.owner_id, 'revisit', v.experience_id, v.id, r.id, r.category, r.score, r.rank, r.sentiment, v.created_at, v.id
from public.visits v join public.ratings r on r.owner_id = v.owner_id and r.experience_id = v.experience_id
where v.source_operation_id = '00000099-0000-4000-8000-000000000000';

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
