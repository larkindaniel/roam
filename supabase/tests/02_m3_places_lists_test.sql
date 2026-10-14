-- M3: place identity, bookmarks, Following score, list visibility, member search and reports.
begin;
create extension if not exists pgtap with schema extensions;
select plan(83);

-- A fresh namespace makes exact assertions independent of profiles left by real integration
-- runs. Nothing is deleted: these rows and relationships roll back with the pgTAP transaction.
do $$
begin
  perform set_config('roam.test.member_token', substr(replace(gen_random_uuid()::text, '-', ''), 1, 8), true);
  perform set_config('roam.test.member_prefix', 'm3_' || current_setting('roam.test.member_token') || '_', true);
  perform set_config('roam.test.page_prefix', 'page' || current_setting('roam.test.member_token') || '_', true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
from (values ('a1000000-0000-4000-8000-000000000001'::uuid, 'm3owner@test.local'), ('b1000000-0000-4000-8000-000000000002'::uuid, 'm3friend@test.local'),
             ('c1000000-0000-4000-8000-000000000003'::uuid, 'm3other@test.local'), ('d1000000-0000-4000-8000-000000000004'::uuid, 'm3blocked@test.local'),
             ('e1000000-0000-4000-8000-000000000005'::uuid, 'm3muted@test.local')) u(id, email);
insert into public.profiles (id, handle, display_name)
select id, current_setting('roam.test.member_prefix') || suffix, display_name
from (values ('a1000000-0000-4000-8000-000000000001'::uuid, 'owner', 'Owner'),
             ('b1000000-0000-4000-8000-000000000002'::uuid, 'friend', 'Friend'),
             ('c1000000-0000-4000-8000-000000000003'::uuid, 'other', current_setting('roam.test.page_prefix') || 'Self'),
             ('d1000000-0000-4000-8000-000000000004'::uuid, 'blocked', 'Blocked'),
             ('e1000000-0000-4000-8000-000000000005'::uuid, 'muted', 'Muted')) p(id, suffix, display_name);

create temporary table search_fixtures (
  id uuid primary key default gen_random_uuid(),
  handle text not null,
  display_name text not null,
  kind text not null,
  sequence integer
) on commit drop;
-- The original m3_ bug also matched display names such as "Test bm3c58b42c".
insert into search_fixtures (handle, display_name, kind)
values ('b' || replace(current_setting('roam.test.member_prefix'), '_', 'x') || 'leak',
        'Test b' || replace(current_setting('roam.test.member_prefix'), '_', 'x') || 'leak', 'collision');
insert into search_fixtures (handle, display_name, kind)
select 'lit' || current_setting('roam.test.member_token') || suffix,
       marker || current_setting('roam.test.member_token') || name_suffix, kind
from (values ('_und', 'Literal', '_Name', 'underscore'), ('_ux', 'Literal', 'xName', 'underscore_collision'),
             ('_pct', 'Percent', '%Name', 'percent'), ('_px', 'Percent', 'Name', 'percent_collision'),
             ('_slash', 'Slash', E'\\Name', 'backslash'), ('_sx', 'Slash', 'Name', 'backslash_collision'),
             ('_mix', 'Mixed', E'_\\%Name', 'mixed')) p(suffix, marker, name_suffix, kind);
insert into search_fixtures (handle, display_name, kind, sequence)
select current_setting('roam.test.page_prefix') || lpad(n::text, 3, '0'), 'Page member ' || n, 'page', n
from generate_series(1, 65) n;
insert into search_fixtures (handle, display_name, kind)
select current_setting('roam.test.page_prefix') || suffix, 'Hidden page member', kind
from (values ('000', 'blocked_out'), ('066', 'blocked_in'), ('067', 'inactive')) p(suffix, kind);
grant select on search_fixtures to authenticated;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       id::text || '@m3-search.test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()
from search_fixtures;
insert into public.profiles (id, handle, display_name, deactivated_at)
select id, handle, display_name, case when kind = 'inactive' then now() end from search_fixtures;
insert into public.blocks (blocker_id, blocked_id)
select 'c1000000-0000-4000-8000-000000000003'::uuid, id from search_fixtures where kind = 'blocked_out'
union all
select id, 'c1000000-0000-4000-8000-000000000003'::uuid from search_fixtures where kind = 'blocked_in';
insert into public.follows (follower_id, followee_id)
select 'c1000000-0000-4000-8000-000000000003'::uuid, id from search_fixtures where sequence = 1
union all
select id, 'c1000000-0000-4000-8000-000000000003'::uuid from search_fixtures where sequence = 2;

-- The migration must close both existing serializers and the creator's defaults for future
-- private functions. The probe is created as postgres and disappears at transaction rollback.
create function app_private.m3_future_helper_privilege_probe()
returns boolean language sql security definer set search_path = '' as $$select true$$;
select is((select count(*)::int from (values
             ('app_private.following_score(uuid,uuid)'), ('app_private.experience_summary_json(uuid,uuid)'),
             ('app_private.visit_json(uuid)'), ('app_private.activity_json(uuid,uuid)'),
             ('app_private.list_entry_json(uuid,uuid,uuid,timestamp with time zone)')) f(signature)
           where has_function_privilege('authenticated', signature, 'EXECUTE')),
          0, 'authenticated has no EXECUTE on any M3 serializer or Following-score helper');
select is((select count(*)::int from (values
             ('app_private.following_score(uuid,uuid)'), ('app_private.experience_summary_json(uuid,uuid)'),
             ('app_private.visit_json(uuid)'), ('app_private.activity_json(uuid,uuid)'),
             ('app_private.list_entry_json(uuid,uuid,uuid,timestamp with time zone)')) f(signature)
           where has_function_privilege('anon', signature, 'EXECUTE')),
          0, 'anon has no EXECUTE on any M3 serializer or Following-score helper');
select is(has_function_privilege('authenticated', 'app_private.m3_future_helper_privilege_probe()', 'EXECUTE'), false,
          'future postgres-created private helpers do not inherit authenticated EXECUTE');
select is(has_function_privilege('anon', 'app_private.m3_future_helper_privilege_probe()', 'EXECUTE'), false,
          'future postgres-created private helpers do not inherit anonymous EXECUTE');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}';

select throws_ok($$select app_private.following_score('a1000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000')$$,
                 '42501', null, 'authenticated cannot directly request a different viewer Following score');
select throws_ok($$select app_private.experience_summary_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003')$$,
                 '42501', null, 'authenticated cannot directly serialize a different viewer state');
select throws_ok($$select app_private.visit_json('00000000-0000-0000-0000-000000000000')$$,
                 '42501', null, 'authenticated cannot directly serialize a visit');
select throws_ok($$select app_private.activity_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003')$$,
                 '42501', null, 'authenticated cannot directly serialize an activity');
select throws_ok($$select app_private.list_entry_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', null)$$,
                 '42501', null, 'authenticated cannot directly serialize an unchecked list owner');

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

-- Deliberately identical POI/locality snapshots without a country: locality identity cannot
-- fall back to a business address, either when matching or when resolving a new experience.
create temporary table unkeyed_candidates (kind text primary key, candidate jsonb) on commit drop;
insert into unkeyed_candidates
select kind, jsonb_build_object('id', kind, 'provider', 'mapkit', 'name', 'Unkeyed ' || current_setting('roam.test.member_token'),
                               'address', '1 Identity Lane ' || current_setting('roam.test.member_token'),
                               'latitude', 21.125, 'longitude', 44.25, 'isLocality', is_locality, 'suggestedCategory', category)
from (values ('poi', false, 'food_drink'), ('locality', true, 'day_trips')) c(kind, is_locality, category);
insert into ids select 'unkeyed-poi', (public.resolve_place(candidate) ->> 'id')::uuid from unkeyed_candidates where kind = 'poi';
select is(public.match_experiences(jsonb_build_array((select candidate from unkeyed_candidates where kind = 'locality'))), '{}'::jsonb,
          'matching a locality without country never falls back to the identical POI');
insert into ids select 'unkeyed-locality', (public.resolve_place(candidate) ->> 'id')::uuid from unkeyed_candidates where kind = 'locality';
select isnt((select experience from ids where label = 'unkeyed-locality'), (select experience from ids where label = 'unkeyed-poi'),
            'resolving a locality without country never merges into the identical POI');
select is((public.experience_detail((select experience from ids where label = 'unkeyed-locality')) ->> 'isLocality')::boolean, true,
          'unkeyed locality retains its locality kind');
select is((select pl.needs_reconciliation from public.places pl join public.experiences e on e.place_id = pl.id
            where e.id = (select experience from ids where label = 'unkeyed-locality')), true,
          'locality without provider or canonical city identity is flagged for reconciliation');
select isnt((public.resolve_place((select candidate from unkeyed_candidates where kind = 'locality')) ->> 'id')::uuid,
            (select experience from ids where label = 'unkeyed-locality'), 'repeated unkeyed localities stay distinct until identity is known');
select is((public.match_experiences(jsonb_build_array((select candidate from unkeyed_candidates where kind = 'poi'))) -> 'poi' ->> 'id')::uuid,
          (select experience from ids where label = 'unkeyed-poi'), 'POI fallback still matches the POI after an identical locality is stored');
select is(public.match_experiences(jsonb_build_array((select candidate from unkeyed_candidates where kind = 'locality'))), '{}'::jsonb,
          'persisting unkeyed localities does not invent a canonical locality match');
select is((select pl.needs_reconciliation from public.places pl join public.experiences e on e.place_id = pl.id
            where e.id = (select experience from ids where label = 'hakone')), false,
          'a locality with canonical city identity does not need reconciliation');
insert into ids select 'identified-locality', (public.resolve_place(candidate || jsonb_build_object('providerPlaceID', 'I-LOCALITY-' || current_setting('roam.test.member_token'))) ->> 'id')::uuid
from unkeyed_candidates where kind = 'locality';
select is((public.resolve_place((select candidate from unkeyed_candidates where kind = 'locality')
                               || jsonb_build_object('providerPlaceID', 'I-LOCALITY-' || current_setting('roam.test.member_token'), 'latitude', 21.126)) ->> 'id')::uuid,
          (select experience from ids where label = 'identified-locality'), 'provider identifier remains authoritative for a locality without country');
select is((select pl.needs_reconciliation from public.places pl join public.experiences e on e.place_id = pl.id
            where e.id = (select experience from ids where label = 'identified-locality')), false,
          'a locality with provider identity does not need reconciliation');

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
select is((public.experience_detail((select experience from ids where label = 'tide-a')) -> 'summary' ->> 'followingScore')::numeric,
          8.4, 'Following score = mean(10.0 friend, 6.7 muted-but-followed); self, unfollowed and blocked excluded');
select is((public.experience_detail((select experience from ids where label = 'tide-a')) -> 'summary' ->> 'followingCount')::int,
          2, 'two eligible followed raters');
select is(public.experience_detail((select experience from ids where label = 'poi')) -> 'summary' -> 'followingScore',
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
select is(jsonb_array_length(public.search_members(current_setting('roam.test.member_prefix'), null) -> 'items'), 4,
          'literal underscores match exactly four visible handles, excluding self and the collision fixture');
select is(public.search_members('', null) -> 'items', '[]'::jsonb, 'empty member query returns nothing');
select is(public.search_members(upper('  ' || current_setting('roam.test.member_prefix') || '  '), null),
          public.search_members(current_setting('roam.test.member_prefix'), null), 'member query ignores case and surrounding spaces');
select is(public.search_members(null, null), public.search_members('   ', null), 'null and blank queries both return an empty terminal page');
select is(public.search_members('   ', null) -> 'nextCursor', 'null'::jsonb, 'blank query has no next cursor');

select is(public.search_members((select display_name from search_fixtures where kind = 'underscore'), null) -> 'items' -> 0 -> 'member' ->> 'id',
          (select id::text from search_fixtures where kind = 'underscore'), 'display-name underscore is literal');
select is(jsonb_array_length(public.search_members((select display_name from search_fixtures where kind = 'underscore'), null) -> 'items'),
          1, 'display-name underscore does not admit its wildcard collision');
select is(public.search_members((select display_name from search_fixtures where kind = 'percent'), null) -> 'items' -> 0 -> 'member' ->> 'id',
          (select id::text from search_fixtures where kind = 'percent'), 'display-name percent is literal, not stripped');
select is(jsonb_array_length(public.search_members((select display_name from search_fixtures where kind = 'percent'), null) -> 'items'),
          1, 'display-name percent does not admit the percent-free collision');
select is(public.search_members((select display_name from search_fixtures where kind = 'backslash'), null) -> 'items' -> 0 -> 'member' ->> 'id',
          (select id::text from search_fixtures where kind = 'backslash'), 'display-name backslash is literal');
select is(jsonb_array_length(public.search_members((select display_name from search_fixtures where kind = 'backslash'), null) -> 'items'),
          1, 'display-name backslash does not act as an escape');
select is(public.search_members(upper((select display_name from search_fixtures where kind = 'mixed')), null) -> 'items' -> 0 -> 'member' ->> 'id',
          (select id::text from search_fixtures where kind = 'mixed'), 'combined underscore, percent and backslash remain literal after case folding');
select is(public.search_members(current_setting('roam.test.member_prefix') || '%', null) -> 'items', '[]'::jsonb,
          'percent added to a handle query is not removed');
select is(public.search_members(current_setting('roam.test.member_prefix') || E'\\', null) -> 'items', '[]'::jsonb,
          'backslash added to a handle query is literal');

create temporary table search_pages (ordinal integer primary key, response jsonb) on commit drop;
insert into search_pages values (1, public.search_members(current_setting('roam.test.page_prefix'), null));
insert into search_pages select 2, public.search_members(current_setting('roam.test.page_prefix'), response ->> 'nextCursor') from search_pages where ordinal = 1;
insert into search_pages select 3, public.search_members(current_setting('roam.test.page_prefix'), response ->> 'nextCursor') from search_pages where ordinal = 2;
select is(jsonb_array_length((select response -> 'items' from search_pages where ordinal = 1)), 30, 'first member page has thirty visible rows');
select is((select response ->> 'nextCursor' from search_pages where ordinal = 1), current_setting('roam.test.page_prefix') || '030', 'first cursor is the thirtieth handle');
select is(jsonb_array_length((select response -> 'items' from search_pages where ordinal = 2)), 30, 'second member page crosses the first boundary');
select is((select response ->> 'nextCursor' from search_pages where ordinal = 2), current_setting('roam.test.page_prefix') || '060', 'second cursor is the sixtieth handle');
select is(jsonb_array_length((select response -> 'items' from search_pages where ordinal = 3)), 5, 'third member page contains the five remaining rows');
select is((select response -> 'nextCursor' from search_pages where ordinal = 3), 'null'::jsonb, 'last member page has no cursor');
select is((select jsonb_agg(item.value -> 'member' ->> 'handle' order by page.ordinal, item.ordinal)
             from search_pages page, jsonb_array_elements(page.response -> 'items') with ordinality item(value, ordinal)),
          (select jsonb_agg(handle order by handle) from search_fixtures where kind = 'page'), 'all pages contain exactly the sixty-five handles in stable order');
select is((select count(distinct item.value -> 'member' ->> 'id')::int from search_pages page, jsonb_array_elements(page.response -> 'items') item(value)),
          65, 'member pages never duplicate a record');
select is((select count(*)::int from search_pages page, jsonb_array_elements(page.response -> 'items') item(value)
            where item.value -> 'member' ->> 'id' = 'c1000000-0000-4000-8000-000000000003'
               or item.value -> 'member' ->> 'id' in (select id::text from search_fixtures where kind in ('blocked_out', 'blocked_in', 'inactive'))),
          0, 'self, both block directions and deactivated profiles are excluded before paging');
select is((select response -> 'items' -> 0 -> 'isFollowing' from search_pages where ordinal = 1), 'true'::jsonb, 'paged results include outgoing follow state');
select is((select response -> 'items' -> 1 -> 'followsViewer' from search_pages where ordinal = 1), 'true'::jsonb, 'paged results include incoming follow state');
select is(public.search_members(current_setting('roam.test.page_prefix'), null), (select response from search_pages where ordinal = 1), 'refresh reproduces the first member page');
select is(public.search_members(current_setting('roam.test.page_prefix'), (select response ->> 'nextCursor' from search_pages where ordinal = 1)),
          (select response from search_pages where ordinal = 2), 'retrying a cursor reproduces the second member page');
select is(public.search_members(current_setting('roam.test.page_prefix'), current_setting('roam.test.page_prefix') || 'zzz'),
          jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null), 'a cursor beyond all matches returns an empty terminal page');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"d1000000-0000-4000-8000-000000000004","role":"authenticated"}';
select throws_ok($$select public.want_list('a1000000-0000-4000-8000-000000000001')$$, 'P0002', 'roam:not_found', 'blocked pair cannot read lists');
select is((select count(*)::int from jsonb_array_elements(public.search_members(current_setting('roam.test.member_prefix') || 'owner', null) -> 'items')), 0,
          'blocked pair hidden from member search');
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

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select public.search_members('page', null)$$, '42501', null, 'anonymous callers cannot execute member search');
select throws_ok($$select app_private.following_score('a1000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000')$$,
                 '42501', null, 'anonymous callers cannot directly request Following scores');
select throws_ok($$select app_private.experience_summary_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003')$$,
                 '42501', null, 'anonymous callers cannot directly serialize viewer state');
select throws_ok($$select app_private.visit_json('00000000-0000-0000-0000-000000000000')$$,
                 '42501', null, 'anonymous callers cannot directly serialize a visit');
select throws_ok($$select app_private.activity_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003')$$,
                 '42501', null, 'anonymous callers cannot directly serialize an activity');
select throws_ok($$select app_private.list_entry_json('00000000-0000-0000-0000-000000000000', 'c1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', null)$$,
                 '42501', null, 'anonymous callers cannot directly serialize a list entry');
reset role;
set local role authenticated;
set local request.jwt.claims to '{}';
select throws_ok($$select public.search_members('page', null)$$, '42501', 'roam:not_signed_in', 'member search requires an authenticated actor');
do $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', (select id from search_fixtures where kind = 'inactive'), 'role', 'authenticated')::text, true);
end;
$$;
select throws_ok($$select public.search_members('page', null)$$, '42501', 'roam:account_disabled', 'deactivated callers cannot search members');
reset role;

select * from finish();
rollback;
