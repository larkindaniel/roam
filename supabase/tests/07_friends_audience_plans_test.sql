-- Two-way friend requests, audience enforcement, trips, lists, direct shares and taste, across an owner,
-- a friend, an unrelated member, a blocked member and anonymous access.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(59);

do $$
declare u record;
begin
  for u in select * from (values
    ('a1000000-0000-4000-8000-000000000001'::uuid,'owner7'),('b1000000-0000-4000-8000-000000000002'::uuid,'friend7'),
    ('c1000000-0000-4000-8000-000000000003'::uuid,'stranger7'),('d1000000-0000-4000-8000-000000000004'::uuid,'blocked7')) t(id,handle) loop
    insert into auth.users(id,email,aud,role,instance_id) values(u.id,u.handle||'@test.local','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
    insert into public.profiles(id,handle,display_name,setup_checkpoint) values(u.id,u.handle,u.handle,'complete');
  end loop;
end $$;
create temp table ids7 as select gen_random_uuid() as place, gen_random_uuid() as experience, gen_random_uuid() as second_place, gen_random_uuid() as second_experience;
grant select on ids7 to authenticated;
insert into public.places(id,name,normalized_name,latitude,longitude,provider,provider_place_id) select place,'Seven Cafe','seven cafe',10,10,'fixture','seven-1' from ids7;
insert into public.places(id,name,normalized_name,latitude,longitude,provider,provider_place_id) select second_place,'Seven Park','seven park',11,11,'fixture','seven-2' from ids7;
insert into public.experiences(id,place_id,category) select experience,place,'food_drink' from ids7;
insert into public.experiences(id,place_id,category) select second_experience,second_place,'outdoors' from ids7;
create temp table v7(label text primary key, value jsonb);
grant all on v7 to authenticated;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true); end $f$;
grant execute on function pg_temp.as_user(uuid) to authenticated;

-- Friend requests ----------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
select is(public.friend_action('b1000000-0000-4000-8000-000000000002','request'),'sent','a request starts pending');
select is(public.friend_action('b1000000-0000-4000-8000-000000000002','request'),'sent','repeating a request changes nothing');
select is((select count(*)::int from public.follows where 'a1000000-0000-4000-8000-000000000001' in(follower_id,followee_id)),0,'a pending request grants no edge');
select is((public.public_profile('b1000000-0000-4000-8000-000000000002')->'relationship'->>'friendState'),'sent','the sender sees sent');
select throws_ok($$select public.set_follow('b1000000-0000-4000-8000-000000000002',true)$$,'42883',null,'members can no longer create a one-way follow');
select throws_ok($$insert into public.follows(follower_id,followee_id) values('a1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003')$$,'42501',null,'members cannot write friend edges directly');
select throws_ok($$select public.friend_action('b1000000-0000-4000-8000-000000000002','hack')$$,'22023',null,'unknown actions are rejected');
select pg_temp.as_user('b1000000-0000-4000-8000-000000000002');
select is(public.friend_action('a1000000-0000-4000-8000-000000000001','remove'),'received','removing does not answer a request');
select is(public.incoming_friend_requests(null)->'items'->0->'member'->>'handle','owner7','the recipient sees the request');
select is((select count(*)::int from public.notifications where type='friend_request'),1,'the recipient is notified once');
select is(public.friend_action('a1000000-0000-4000-8000-000000000001','decline'),'none','declining clears the request');
select is((select count(*)::int from public.notifications where type='friend_request'),0,'declining clears its notification');
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
select is(public.friend_action('b1000000-0000-4000-8000-000000000002','request'),'sent','asking again works after a decline');
select is(public.friend_action('b1000000-0000-4000-8000-000000000002','cancel'),'none','the sender can cancel');
select is(public.friend_action('b1000000-0000-4000-8000-000000000002','request'),'sent','asking once more');
select pg_temp.as_user('b1000000-0000-4000-8000-000000000002');
select is(public.friend_action('a1000000-0000-4000-8000-000000000001','request'),'friends','asking someone who already asked you accepts, with no duplicate');
select is((select count(*)::int from public.friend_requests),0,'accepting clears the request');
select is((select count(*)::int from public.follows where follower_id in('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002')
           and followee_id in('a1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002')),2,'a friendship has both directions');
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
select is((public.public_profile('b1000000-0000-4000-8000-000000000002')->'relationship'->>'friendState'),'friends','both people see friends');
select is((select count(*)::int from public.notifications where type='friend_accept'),1,'the sender hears it was accepted');
-- Blocked pair
select is(public.friend_action('d1000000-0000-4000-8000-000000000004','request'),'sent','a request to the soon-blocked member');
select is(public.set_block('d1000000-0000-4000-8000-000000000004',true),true,'blocking');
select is((select count(*)::int from public.friend_requests),0,'blocking removes open requests');
select pg_temp.as_user('d1000000-0000-4000-8000-000000000004');
select throws_ok($$select public.friend_action('a1000000-0000-4000-8000-000000000001','request')$$,'P0002',null,'a blocked member cannot send a request');

-- Audience -----------------------------------------------------------------------------------
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
insert into v7 select 'friends',public.add_visit(jsonb_build_object('operationID',gen_random_uuid(),'experienceID',(select experience from ids7),'visit',jsonb_build_object('publicNote','for friends','mediaIDs','[]'::jsonb)));
select ok((select value ? 'visitID' from v7 where label='friends'),'a place logs without ranking, and defaults to friends');
select is((select audience from public.visits where id=(select (value->>'visitID')::uuid from v7 where label='friends')),'friends','the default audience is friends');
select is((select count(*)::int from public.ratings where owner_id='a1000000-0000-4000-8000-000000000001'),0,'logging creates no rating');
select is((public.been_list('a1000000-0000-4000-8000-000000000001')->0->>'isRanked')::boolean,false,'it appears in Been there unranked');
insert into v7 select 'private',public.add_visit(jsonb_build_object('operationID',gen_random_uuid(),'experienceID',(select second_experience from ids7),'visit',jsonb_build_object('publicNote','just me','mediaIDs','[]'::jsonb,'audience','only_me')));
select throws_ok($$select public.add_visit(jsonb_build_object('operationID',gen_random_uuid(),'experienceID',(select experience from ids7),'visit',jsonb_build_object('audience','everyone')))$$,'22023',null,'an unknown audience is rejected');
select pg_temp.as_user('b1000000-0000-4000-8000-000000000002');
select is(jsonb_array_length(public.public_memories((select experience from ids7),null)->'items'),1,'a friend sees a friends entry');
select is(jsonb_array_length(public.public_memories((select second_experience from ids7),null)->'items'),0,'a friend cannot see an only-me entry');
select throws_ok(format($$select public.visit(%L)$$,(select (value->>'visitID')::uuid from v7 where label='private')),'P0002',null,'nor read it by ID');
select is(jsonb_array_length(public.feed(null)->'items'),1,'the Friends tab shows only the friends entry');
select is(jsonb_array_length(public.been_list('a1000000-0000-4000-8000-000000000001')),1,'a friend''s view of Been there hides only-me places');
select is(jsonb_array_length(public.friend_memories((select experience from ids7))),1,'a friend''s note appears under friends');
select is(public.friend_memories((select experience from ids7))->0->>'publicNote','for friends','with what they said');
select is(jsonb_array_length(public.friend_memories((select second_experience from ids7))),0,'an only-me note never does');
select is((select count(*)::int from jsonb_array_elements(public.trip_feed()) c where c->'author'->>'handle'='owner7'),1,'a friend sees one card for a person''s untripped visits');
select ok((select c->'tripID'='null'::jsonb and c->>'tripName' is null from jsonb_array_elements(public.trip_feed()) c where c->'author'->>'handle'='owner7'),'those visits sit under Home');
select is(jsonb_array_length(public.trip_updates('a1000000-0000-4000-8000-000000000001',null)),1,'opening the card lists only what the friend may see');
select pg_temp.as_user('c1000000-0000-4000-8000-000000000003');
select is((select count(*)::int from jsonb_array_elements(public.trip_feed()) c where c->'author'->>'handle'='owner7'),0,'someone who is not a friend gets no card');
select is(jsonb_array_length(public.friend_memories((select experience from ids7))),0,'someone who is not a friend sees none');
select ok(not exists(select 1 from jsonb_array_elements(public.discover_places()) d where d->'experience'->>'name' like 'Seven%'),'private entries never reach anyone''s Discover');
select is(jsonb_array_length(public.public_memories((select experience from ids7),null)->'items'),0,'an unrelated member cannot see a friends entry');
select throws_ok(format($$select public.visit(%L)$$,(select (value->>'visitID')::uuid from v7 where label='friends')),'P0002',null,'nor read it by ID');
select is((select count(*)::int from public.visits where owner_id='a1000000-0000-4000-8000-000000000001'),0,'row security hides those visits too');

-- Trips and lists ---------------------------------------------------------------------------
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
insert into v7 select 'trip',public.save_trip(null,'Seven trip','',null,null,'planning');
select throws_ok($$select public.save_trip(null,'Backwards','','2026-02-02','2026-01-01','planning')$$,'22023',null,'a trip cannot end before it starts');
select lives_ok(format($$select public.set_trip_place(%L,%L,'Stop',true)$$,(select (value->>'id')::uuid from v7 where label='trip'),(select experience from ids7)),'planning a place');
select is((public.trip_detail((select (value->>'id')::uuid from v7 where label='trip'))->'places'->0->>'isVisited')::boolean,false,'planning does not create a visit');
insert into v7 select 'list',public.save_list(null,'Seven list','');
select lives_ok(format($$select public.set_list_item(%L,%L,'note',true)$$,(select (value->>'id')::uuid from v7 where label='list'),(select experience from ids7)),'adding to a list');
select pg_temp.as_user('b1000000-0000-4000-8000-000000000002');
select throws_ok(format($$select public.trip_detail(%L)$$,(select (value->>'id')::uuid from v7 where label='trip')),'P0002',null,'an unshared trip is hidden, even from a friend');
select throws_ok(format($$select public.list_detail(%L)$$,(select (value->>'id')::uuid from v7 where label='list')),'P0002',null,'an unshared list is hidden');

-- Sharing -----------------------------------------------------------------------------------
select pg_temp.as_user('a1000000-0000-4000-8000-000000000001');
insert into v7 select 'op',to_jsonb(gen_random_uuid());
select lives_ok(format($$select public.send_share('b1000000-0000-4000-8000-000000000002',null,%L,null,'try this',%L)$$,(select (value->>'id')::uuid from v7 where label='list'),(select value #>> '{}' from v7 where label='op')),'sharing a list with a friend');
select lives_ok(format($$select public.send_share('b1000000-0000-4000-8000-000000000002',null,%L,null,'try this',%L)$$,(select (value->>'id')::uuid from v7 where label='list'),(select value #>> '{}' from v7 where label='op')),'retrying the same share');
select throws_ok(format($$select public.send_share('c1000000-0000-4000-8000-000000000003',%L,null,null,'',gen_random_uuid())$$,(select experience from ids7)),'42501',null,'sharing needs a friendship');
select pg_temp.as_user('b1000000-0000-4000-8000-000000000002');
select is(jsonb_array_length(public.shared_with_me()),1,'the retry made one share, and it shows in For You');
select is((public.list_detail((select (value->>'id')::uuid from v7 where label='list'))->>'itemCount')::int,1,'the recipient can read the shared list');
select is(public.friend_action('a1000000-0000-4000-8000-000000000001','remove'),'none','removing the friendship');
select is(jsonb_array_length(public.shared_with_me()),0,'access based on the friendship ends with it');

select * from finish();
rollback;
