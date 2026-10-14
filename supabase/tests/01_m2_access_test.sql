-- M2 authorization tests: owner, follower, unrelated, blocked and anonymous callers.
begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('a0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('b0000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'follower@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('c0000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'unrelated@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d0000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'blocked@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

-- Anonymous callers read nothing ---------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select * from public.profiles$$, '42501', null, 'anon cannot select profiles');
select throws_ok($$select * from public.visits$$, '42501', null, 'anon cannot select visits');
select throws_ok($$select public.my_profile()$$, '42501', null, 'anon cannot call my_profile');
select throws_ok($$select public.create_profile('Anon', 'anon_user')$$, '42501', null, 'anon cannot create a profile');
select is((public.roam_health() ->> 'service'), 'roam', 'health check stays available without member data');
reset role;

-- Profile creation and validation -----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.my_profile(), null, 'no profile before setup');
select throws_ok($$select public.create_profile('Owner', 'Bad Handle')$$, '22023', null, 'invalid handle rejected');
select throws_ok($$select public.create_profile('', 'owner_one')$$, '22023', null, 'empty display name rejected');
select is((public.create_profile('Owner One', 'owner_one') ->> 'handle'), 'owner_one', 'owner profile created');
select is((public.create_profile('Changed', 'other_handle') ->> 'handle'), 'owner_one', 'retried creation returns the existing profile unchanged');
select is(public.check_handle('owner_one'), 'available', 'own handle is available to its owner');
select is((public.set_setup_checkpoint('complete') ->> 'setupCheckpoint'), 'complete', 'checkpoint advances');
select is((public.set_setup_checkpoint('profile_created') ->> 'setupCheckpoint'), 'complete', 'checkpoint never moves backwards');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"b0000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.check_handle('owner_one'), 'taken', 'handle availability check sees the taken handle');
select throws_ok($$select public.create_profile('Follower', 'owner_one')$$, '23505', 'roam:handle_taken', 'duplicate handle loses the race cleanly');
select is((public.create_profile('Follower', 'follower_two') ->> 'handle'), 'follower_two', 'follower profile created after choosing a new handle');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-4000-8000-000000000003","role":"authenticated"}';
select lives_ok($$select public.create_profile('Unrelated', 'unrelated_three')$$, 'unrelated profile created');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"d0000000-0000-4000-8000-000000000004","role":"authenticated"}';
select lives_ok($$select public.create_profile('Blocked', 'blocked_four')$$, 'blocked-user profile created');
reset role;

-- Owner-private data is seeded directly (writes are RPC-only for clients).
with pl as (
  insert into public.places (provider, provider_place_id, name, normalized_name, latitude, longitude, country_code)
  values ('fixture', 'test-place', 'Test Place', 'test place', 1, 1, app_private.upsert_country('PT', 'Portugal'))
  returning id
), e as (
  insert into public.experiences (place_id) select id from pl returning id
)
insert into public.private_notes (owner_id, experience_id, body)
select 'a0000000-0000-4000-8000-000000000001', e.id, 'Owner-only memory' from e;

-- Unrelated signed-in member: public profile yes; private data no -----------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-4000-8000-000000000001'), 1, 'unrelated member reads public profile row');
select is((public.public_profile('a0000000-0000-4000-8000-000000000001') -> 'member' ->> 'handle'), 'owner_one', 'unrelated member reads public profile RPC');
select throws_ok($$select setup_checkpoint from public.profiles where id = 'a0000000-0000-4000-8000-000000000001'$$, '42501', null, 'owner-only profile columns are not readable');
select is((select count(*)::int from public.user_settings where user_id = 'a0000000-0000-4000-8000-000000000001'), 0, 'settings are owner-only');
select is((select count(*)::int from public.private_notes where owner_id = 'a0000000-0000-4000-8000-000000000001'), 0, 'private notes are owner-only');
select throws_ok($$select email from auth.users$$, '42501', null, 'auth contact data is not readable');
select throws_ok($$insert into public.profiles (id, handle, display_name) values ('c0000000-0000-4000-8000-000000000003', 'sneaky', 'S')$$, '42501', null, 'direct profile insert denied');
select throws_ok($$update public.profiles set bio = 'hacked' where id = 'a0000000-0000-4000-8000-000000000001'$$, '42501', null, 'foreign profile update denied');
select throws_ok($$insert into public.ratings (owner_id, experience_id, category, sentiment, group_position, score, rank) select 'c0000000-0000-4000-8000-000000000003', id, 'culture', 'liked', 0, 10, 1 from public.experiences limit 1$$, '42501', null, 'direct rating insert denied');
select throws_ok($$delete from public.private_notes$$, '42501', null, 'direct private note delete denied');
select throws_ok($$truncate public.visits$$, '42501', null, 'truncate denied');
reset role;

-- Owner sees own private data ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.private_notes), 1, 'owner reads own private note');
select is((select count(*)::int from public.user_settings), 1, 'owner reads own settings');
reset role;

-- Follow graph and notifications -------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"b0000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.set_follow('a0000000-0000-4000-8000-000000000001', true), true, 'follower follows owner');
select is(public.set_follow('a0000000-0000-4000-8000-000000000001', true), true, 'repeated follow is a safe no-op');
select throws_ok($$select public.set_follow('b0000000-0000-4000-8000-000000000002', true)$$, '22023', null, 'self-follow rejected');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.notifications where type = 'follow'), 1, 'owner receives exactly one follow notification');
reset role;

-- Blocked pair: mutual invisibility enforced server-side -----------------------------------------------
insert into public.blocks (blocker_id, blocked_id) values ('a0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000004');
set local role authenticated;
set local request.jwt.claims to '{"sub":"d0000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-4000-8000-000000000001'), 0, 'blocked member cannot read blocker profile');
select throws_ok($$select public.public_profile('a0000000-0000-4000-8000-000000000001')$$, 'P0002', 'roam:not_found', 'blocked member gets not found');
select throws_ok($$select public.set_follow('a0000000-0000-4000-8000-000000000001', true)$$, 'P0002', 'roam:not_found', 'blocked member cannot follow');
reset role;

-- Storage ownership ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-4000-8000-000000000003","role":"authenticated"}';
select throws_ok($$insert into storage.objects (bucket_id, name, owner) values ('visit-media', 'a0000000-0000-4000-8000-000000000001/x.jpg', 'c0000000-0000-4000-8000-000000000003')$$,
  '42501', null, 'cannot upload into another member''s folder');
select throws_ok($$select public.register_media('visit-media', 'a0000000-0000-4000-8000-000000000001/x.jpg', 'visit', 10, 10)$$, '42501', null, 'cannot register another member''s object');
-- M5: registration requires server-side inspection, so clients cannot call it at all.
select throws_ok($$select public.register_media('visit-media', 'c0000000-0000-4000-8000-000000000003/missing.jpg', 'visit', 10, 10)$$, '42501', null, 'clients cannot register media without server inspection');
reset role;

select * from finish();
rollback;
