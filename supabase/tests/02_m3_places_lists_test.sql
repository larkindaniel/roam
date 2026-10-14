-- M3: place identity, bookmarks, Following score, list visibility, member search and reports.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
from (values ('a1000000-0000-4000-8000-000000000001'::uuid, 'm3owner@test.local'), ('b1000000-0000-4000-8000-000000000002'::uuid, 'm3friend@test.local'),
             ('c1000000-0000-4000-8000-000000000003'::uuid, 'm3other@test.local'), ('d1000000-0000-4000-8000-000000000004'::uuid, 'm3blocked@test.local'),
             ('e1000000-0000-4000-8000-000000000005'::uuid, 'm3muted@test.local')) u(id, email);
insert into public.profiles (id, handle, display_name) values
  ('a1000000-0000-4000-8000-000000000001', 'm3_owner', 'Owner'), ('b1000000-0000-4000-8000-000000000002', 'm3_friend', 'Friend'),
  ('c1000000-0000-4000-8000-000000000003', 'm3_other', 'Other'), ('d1000000-0000-4000-8000-000000000004', 'm3_blocked', 'Blocked'),
  ('e1000000-0000-4000-8000-000000000005', 'm3_muted', 'Muted');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';

-- Provider identity -------------------------------------------------------------------------------
select throws_ok($$select public.resolve_place('{"provider":"fixture","name":"Fake","latitude":1,"longitude":1}')$$, '22023', null,
                 'clients cannot create non-MapKit places');
create temporary table ids (label text primary key, experience uuid) on commit drop;
insert into ids select 'poi', (public.resolve_place('{"provider":"mapkit","providerPlaceID":"I-POI-1","name":"Cove Café","address":"1 Shore Rd, Lisbon","locality":"Lisbon","region":"Lisboa","countryCode":"PT","countryName":"Portugal","latitude":38.7,"longitude":-9.1,"isLocality":false,"suggestedCategory":"food_drink"}') ->> 'id')::uuid;
select is((public.resolve_place('{"provider":"mapkit","providerPlaceID":"I-POI-1","name":"Cove Café (renamed)","address":"1 Shore Rd, Lisbon","latitude":38.7001,"longitude":-9.1,"isLocality":false}') ->> 'id')::uuid,
          (select experience from ids where label = 'poi'), 'same MapKit identifier resolves to the same experience');
select is((select category from public.experiences where id = (select experience from ids where label = 'poi'))::text, 'food_drink', 'category suggestion stored');
insert into ids select 'tide-a', (public.resolve_place('{"provider":"mapkit","name":"Morning Tide Bakery","address":"5 Rua Nova, Lisbon","countryCode":"PT","countryName":"Portugal","latitude":38.711,"longitude":-9.14,"isLocality":false}') ->> 'id')::uuid;
select isnt((public.resolve_place('{"provider":"mapkit","name":"Morning Tide Bakery","address":"77 Rua Velha, Lisbon","countryCode":"PT","countryName":"Portugal","latitude":38.7201,"longitude":-9.1502,"isLocality":false}') ->> 'id')::uuid,
            (select experience from ids where label = 'tide-a'), 'same name at a different address stays distinct');
select is((public.resolve_place('{"provider":"mapkit","name":"morning tide  bakery","address":"5 rua nova lisbon","countryCode":"PT","latitude":38.7110004,"longitude":-9.1399996,"isLocality":false}') ->> 'id')::uuid,
          (select experience from ids where label = 'tide-a'), 'exact normalized name + address + 6-decimal coordinate reuses the place');
select isnt((public.resolve_place('{"provider":"mapkit","name":"Morning Tide Bakery","address":"5 Rua Nova, Lisbon","countryCode":"PT","latitude":38.71102,"longitude":-9.14,"isLocality":false}') ->> 'id')::uuid,
            (select experience from ids where label = 'tide-a'), 'a different coordinate is a distinct record');
select is((select needs_reconciliation from public.places pl join public.experiences e on e.place_id = pl.id where e.id = (select experience from ids where label = 'tide-a')),
          true, 'identifier-less POIs are flagged for later reconciliation');
insert into ids select 'hakone', (public.resolve_place('{"provider":"mapkit","name":"Hakone","locality":"Hakone","region":"Kanagawa","countryCode":"JP","countryName":"Japan","latitude":35.23,"longitude":139.1,"isLocality":true,"suggestedCategory":"day_trips"}') ->> 'id')::uuid;
select is((public.resolve_place('{"provider":"mapkit","name":"Hakone","locality":"Hakone","region":"Kanagawa","countryCode":"JP","countryName":"Japan","latitude":35.2401,"longitude":139.11,"isLocality":true}') ->> 'id')::uuid,
          (select experience from ids where label = 'hakone'), 'localities without identifiers dedupe by canonical city key');
insert into ids select 'portland-or', (public.resolve_place('{"provider":"mapkit","name":"Portland","locality":"Portland","region":"Oregon","countryCode":"US","countryName":"United States","latitude":45.5,"longitude":-122.6,"isLocality":true}') ->> 'id')::uuid;
select isnt((public.resolve_place('{"provider":"mapkit","name":"Portland","locality":"Portland","region":"Maine","countryCode":"US","countryName":"United States","latitude":43.6,"longitude":-70.2,"isLocality":true}') ->> 'id')::uuid,
            (select experience from ids where label = 'portland-or'), 'same-name localities in different regions stay distinct');
select is(jsonb_typeof(public.match_experiences('[{"id":"k1","provider":"mapkit","providerPlaceID":"I-POI-1","name":"x","latitude":0,"longitude":0}]') -> 'k1'), 'object',
          'search matching finds an existing experience by identifier');
select is(public.match_experiences('[{"id":"k2","provider":"mapkit","providerPlaceID":"I-UNKNOWN","name":"x","latitude":0,"longitude":0}]'), '{}'::jsonb,
          'unknown search hits are not persisted by browsing');

-- Bookmarks ---------------------------------------------------------------------------------------------
select is(public.set_bookmark((select experience from ids where label = 'poi'), true), true, 'save to Want to Go');
select is(public.set_bookmark((select experience from ids where label = 'poi'), true), true, 'duplicate save is idempotent');
select is((select count(*)::int from public.bookmarks where owner_id = 'a1000000-0000-4000-8000-000000000001'), 1, 'one bookmark row');
select is((select count(*)::int from public.visits where owner_id = 'a1000000-0000-4000-8000-000000000001')
          + (select count(*)::int from public.activities where author_id = 'a1000000-0000-4000-8000-000000000001')
          + (select count(*)::int from public.ratings where owner_id = 'a1000000-0000-4000-8000-000000000001'), 0,
          'saving creates no visit, rating or activity');
select is((public.my_library() -> 'bookmarked' ->> 0)::uuid, (select experience from ids where label = 'poi'), 'library reflects the bookmark');
reset role;

-- Ratings for Following-score checks (seeded directly; ranking RPC arrives in M4).
insert into public.ratings (owner_id, experience_id, category, sentiment, group_position, score, rank)
select owner, (select experience from ids where label = 'tide-a'), 'food_drink', 'liked', 0, s, 1
from (values ('b1000000-0000-4000-8000-000000000002'::uuid, 10.0), ('c1000000-0000-4000-8000-000000000003'::uuid, 5.0),
             ('d1000000-0000-4000-8000-000000000004'::uuid, 1.7), ('e1000000-0000-4000-8000-000000000005'::uuid, 6.7),
             ('a1000000-0000-4000-8000-000000000001'::uuid, 8.4)) r(owner, s);
insert into public.follows (follower_id, followee_id) values
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002'),
  ('a1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000004'),
  ('a1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000005');
insert into public.mutes (muter_id, muted_id) values ('a1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000005');
insert into public.blocks (blocker_id, blocked_id) values ('d1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((app_private.experience_summary_json((select experience from ids where label = 'tide-a'), 'a1000000-0000-4000-8000-000000000001') ->> 'followingScore')::numeric,
          8.4, 'Following score = mean(10.0 friend, 6.7 muted-but-followed); self, unfollowed and blocked excluded');
select is((app_private.experience_summary_json((select experience from ids where label = 'tide-a'), 'a1000000-0000-4000-8000-000000000001') ->> 'followingCount')::int,
          2, 'two eligible followed raters');
select is(app_private.experience_summary_json((select experience from ids where label = 'poi'), 'a1000000-0000-4000-8000-000000000001') -> 'followingScore',
          'null'::jsonb, 'no followed ratings means no score, not zero');
select throws_ok(format('select public.set_bookmark(%L, true)', (select experience from ids where label = 'tide-a')), '22023', 'roam:already_rated',
                 'a rated experience cannot be saved to Want to Go');
reset role;

-- Lists and member search across visibility --------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"c1000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(jsonb_array_length(public.want_list('a1000000-0000-4000-8000-000000000001')), 1, 'another member reads a public Want list');
select is((public.want_list('a1000000-0000-4000-8000-000000000001') -> 0 -> 'experience' -> 'viewer' ->> 'isBookmarked')::boolean, false,
          'viewer state describes the viewer, not the owner');
select is(jsonb_array_length(public.been_list('a1000000-0000-4000-8000-000000000001')), 1, 'Been list includes the rated experience');
select is(jsonb_array_length(public.search_members('m3_', null) -> 'items'), 4, 'member search returns every visible match except the searcher');
select is(public.search_members('', null) -> 'items', '[]'::jsonb, 'empty member query returns nothing');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"d1000000-0000-4000-8000-000000000004","role":"authenticated"}';
select throws_ok($$select public.want_list('a1000000-0000-4000-8000-000000000001')$$, 'P0002', 'roam:not_found', 'blocked pair cannot read lists');
select is((select count(*)::int from jsonb_array_elements(public.search_members('m3_owner', null) -> 'items')), 0, 'blocked pair hidden from member search');
reset role;

-- Reports -----------------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"c1000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is((public.submit_report('f1000000-0000-4000-8000-000000000001', 'experience', (select experience from ids where label = 'poi'),
                                'incorrect_place_category', 'This is a bakery') ->> 'status'), 'received', 'report stored with a receipt');
select is((public.submit_report('f1000000-0000-4000-8000-000000000001', 'experience', (select experience from ids where label = 'poi'),
                                'incorrect_place_category', 'This is a bakery') ->> 'id'), 'f1000000-0000-4000-8000-000000000001', 'retry returns the same report');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.reports), 0, 'reports are not visible to other members');
reset role;

select * from finish();
rollback;
