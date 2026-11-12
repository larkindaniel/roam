-- Exercise the normal RPCs using independent sessions for each role.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create temp table people as
select * from (values
  ('owner','af000000-0000-4000-8000-000000000001'::uuid),
  ('friend','af000000-0000-4000-8000-000000000002'::uuid),
  ('outsider','af000000-0000-4000-8000-000000000003'::uuid),
  ('blocked','af000000-0000-4000-8000-000000000004'::uuid)
) p(name,id);
insert into auth.users(id,email,aud,role,instance_id)
select id,name||'9@test.local','authenticated','authenticated','00000000-0000-0000-0000-000000000000' from people;
insert into public.profiles(id,handle,display_name,setup_checkpoint)
select id,name||'9',name,'complete' from people;
create temp table place_ids as
select gen_random_uuid() place,gen_random_uuid() experience,code
from (values ('CA'::char(2)),('PT'::char(2))) countries(code);
insert into public.countries(code,name) values ('CA','Canada'),('PT','Portugal') on conflict do nothing;
insert into public.places(id,name,normalized_name,latitude,longitude,provider,provider_place_id,country_code,locality,region)
select place,'Social Cafe','social cafe',43,-80,'fixture','social-cafe-9-'||code,code,
  case when code='CA' then 'Toronto' else 'Lisbon' end, case when code='CA' then 'Ontario' else 'Lisboa' end from place_ids;
insert into public.experiences(id,place_id,category)
select experience,place,'food_drink' from place_ids;
create temp table results(name text primary key, value jsonb);
grant select on people,place_ids to authenticated;
grant all on results to authenticated;

create function pg_temp.actor(who text) returns void language sql as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub',id,'role','authenticated')::text,true)
  from people where name=who
$$;
create function pg_temp.person(who text) returns uuid language sql as $$select id from people where name=who$$;
create function pg_temp.result_id(label text, key text default 'id') returns uuid language sql as $$
  select (value->>key)::uuid from results where name=label
$$;
create function pg_temp.log_visit(details jsonb, country char(2) default 'CA') returns jsonb language sql as $$
  select public.add_visit(jsonb_build_object('operationID',gen_random_uuid(),'experienceID',experience,
    'visit',jsonb_build_object('date','2025-07-01','mediaIDs','[]'::jsonb)||details)) from place_ids where code=country
$$;
grant execute on function pg_temp.actor(text),pg_temp.person(text),pg_temp.result_id(text,text),pg_temp.log_visit(jsonb,char) to authenticated;

select ok(not has_function_privilege('anon','public.friends_activity(text)','EXECUTE'),'anonymous feed access is denied');
select ok(not has_function_privilege('anon','public.set_trip_membership(uuid,uuid,text)','EXECUTE'),'anonymous membership changes are denied');
select ok(not has_table_privilege('authenticated','public.visit_companions','SELECT'),'companion rows are private');
select ok(not has_table_privilege('authenticated','public.trip_members','SELECT'),'membership rows are private');

set local role authenticated;
select pg_temp.actor('owner');
select public.friend_action(pg_temp.person('friend'),'request');
select public.set_block(pg_temp.person('blocked'),true);
select pg_temp.actor('friend');
select public.friend_action(pg_temp.person('owner'),'accept');
select pg_temp.actor('owner');

insert into results select 'trip',public.save_trip(null,'Toronto weekend','',null,null,'planning');
select throws_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('outsider'),'invite')$$,
  '42501',null,'the owner can invite only friends');
select throws_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('blocked'),'invite')$$,
  '42501',null,'blocked members cannot be invited');
select lives_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'invite')$$,'invite a friend');
select lives_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'invite')$$,'retry an invitation');

select throws_ok($$select pg_temp.log_visit(jsonb_build_object('companionIDs',jsonb_build_array(pg_temp.person('outsider'))))$$,
  '22023',null,'reject tagging a non-friend');
select throws_ok($$select pg_temp.log_visit(jsonb_build_object('companionIDs',jsonb_build_array(pg_temp.person('blocked'))))$$,
  '22023',null,'reject tagging a blocked member');
select throws_ok($$select pg_temp.log_visit(jsonb_build_object('companionIDs',jsonb_build_array(pg_temp.person('owner'))))$$,
  '22023',null,'reject tagging oneself');
select throws_ok($$select pg_temp.log_visit('{"companionIDs": "not an array"}')$$,'22023',null,'reject malformed tags');

insert into results select 'public_visit',pg_temp.log_visit(jsonb_build_object('audience','public',
  'tripID',pg_temp.result_id('trip'),'companionIDs',jsonb_build_array(pg_temp.person('friend'))));
insert into results select 'private_visit',pg_temp.log_visit(jsonb_build_object('audience','only_me',
  'tripID',pg_temp.result_id('trip'),'companionIDs',jsonb_build_array(pg_temp.person('friend'))));
insert into results select 'undated_visit',pg_temp.log_visit('{"date":null}');
select is(public.visit(pg_temp.result_id('private_visit','visitID'))->'companions'->0->>'handle','friend9','owner sees private tags');

select pg_temp.actor('outsider');
select is(jsonb_array_length(public.trip_invitations()),0,'unrelated user sees no invites');
select is(jsonb_array_length(public.friends_activity(null)->'items'),0,'public posts do not appear in a non-friend feed');
select is(jsonb_array_length(public.activity(pg_temp.result_id('public_visit','activityID'))->'companions'),0,'public visit does not reveal a tag to a stranger');
select ok(public.visit(pg_temp.result_id('public_visit','visitID'))->>'tripID' is null,'public visit does not reveal a trip ID');
select throws_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'accept')$$,'42501',null,'only the recipient can accept');
select throws_ok($$select public.set_trip_dates(pg_temp.result_id('trip'),null,null,'planning')$$,'P0002',null,'outsider cannot edit dates');

select pg_temp.actor('blocked');
select is(jsonb_array_length(public.friends_activity(null)->'items'),0,'blocked user sees no activity');
select throws_ok($$select public.activity(pg_temp.result_id('public_visit','activityID'))$$,'P0002',null,'blocked user cannot open the public activity by ID');

select pg_temp.actor('friend');
select is(jsonb_array_length(public.trip_invitations()),1,'recipient sees one pending invite');
select throws_ok($$select public.trip_detail(pg_temp.result_id('trip'))$$,'P0002',null,'pending invitation grants no itinerary access');
select is(jsonb_array_length(public.friends_activity(null)->'items'),1,'feed shows one dated visible activity and omits undated history');
select is(public.friends_activity(null)->'items'->0->'companions'->0->>'handle','friend9','friend sees their tag immediately');
select ok(public.friends_activity(null)->'items'->0->>'trip' is null,'pending member sees no trip link');
select lives_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'accept')$$,'accept invitation');
select lives_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'accept')$$,'retry acceptance');
select is(public.trip_detail(pg_temp.result_id('trip'))->>'canEdit','true','accepted member can edit itinerary');
select is(public.friends_activity(null)->'items'->0->'trip'->>'name','Toronto weekend','accepted member sees the trip link');
select is(jsonb_array_length(public.trip_updates(null,pg_temp.result_id('trip'))),1,'trip visit list applies per-visit privacy');
select throws_ok($$select public.save_trip(pg_temp.result_id('trip'),'Other name','',null,null,'planning')$$,
  'P0002',null,'trip identity stays owner-only');
select lives_ok($$select public.set_trip_dates(pg_temp.result_id('trip'),'2025-06-01','2025-06-03','past')$$,'member may change dates');
select lives_ok($$select public.set_trip_city(pg_temp.result_id('trip'),
  '{"name":"Toronto","region":"Ontario","countryCode":"CA","countryName":"Canada","latitude":43.65,"longitude":-79.38}',true)$$,'member may add a city');
select throws_ok($$select public.set_trip_place(pg_temp.result_id('trip'),(select experience from place_ids where code='CA'),'',true)$$,
  'P0002',null,'legacy trip place edits stay owner-only');
insert into results select 'friend_visit',pg_temp.log_visit(jsonb_build_object('tripID',pg_temp.result_id('trip')));
select is(jsonb_array_length(public.trip_updates(null,pg_temp.result_id('trip'))),2,'member can log their own visit on the trip');

select lives_ok($$select public.remove_my_visit_tag(pg_temp.result_id('public_visit','visitID'))$$,'tagged friend may remove their tag');
select is(jsonb_array_length(public.activity(pg_temp.result_id('public_visit','activityID'))->'companions'),0,'tag removal updates the activity');
select lives_ok($$select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'leave')$$,'member may leave');
select throws_ok($$select public.trip_detail(pg_temp.result_id('trip'))$$,'P0002',null,'leaving revokes itinerary access');
select ok(public.visit(pg_temp.result_id('friend_visit','visitID'))->>'tripID' is null,'member keeps their own visit after leaving');
select throws_ok($$select pg_temp.log_visit(jsonb_build_object('tripID',pg_temp.result_id('trip')))$$,
  'P0002',null,'former member cannot add another visit to the trip');

select pg_temp.actor('owner');
insert into results select 'list',public.save_list(null,'Weekend picks','');
select public.send_share(pg_temp.person('friend'),null,pg_temp.result_id('list'),null,'Try these',gen_random_uuid());
select public.send_share(pg_temp.person('friend'),(select experience from place_ids where code='CA'),null,null,'Try the coffee',gen_random_uuid());
select is(jsonb_array_length(public.list_recipients(pg_temp.result_id('list'))),1,'owner can see who has list access');
select pg_temp.actor('friend');
select is(jsonb_array_length(public.shared_with_me()),2,'recipient can find their list and place shares');
select is((select pick->>'message' from jsonb_array_elements(public.shared_with_me()) pick where pick->>'experience' is not null),
  'Try the coffee','received place carries its sender note');
select throws_ok($$select public.revoke_list_share(pg_temp.result_id('list'),pg_temp.person('friend'))$$,
  'P0002',null,'a recipient cannot manage list access');
select pg_temp.actor('owner');
select lives_ok($$select public.revoke_list_share(pg_temp.result_id('list'),pg_temp.person('friend'))$$,'owner may revoke list access');
select pg_temp.actor('friend');
select throws_ok($$select public.list_detail(pg_temp.result_id('list'))$$,'P0002',null,'revoked list cannot be reopened');
select is(jsonb_array_length(public.shared_with_me()),1,'revoking a list keeps a separately shared place');

select pg_temp.actor('owner');
select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'invite');
select public.update_visit(pg_temp.result_id('public_visit','visitID'),
  jsonb_build_object('date','2025-07-01','publicNote','Updated note','companionIDs',jsonb_build_array(pg_temp.person('friend'))),
  gen_random_uuid());
select pg_temp.actor('friend');
select public.set_trip_membership(pg_temp.result_id('trip'),pg_temp.person('friend'),'accept');
select public.friend_action(pg_temp.person('owner'),'remove');
select is(jsonb_array_length(public.shared_with_me()),0,'unfriending removes old shares');
select throws_ok($$select public.trip_detail(pg_temp.result_id('trip'))$$,'P0002',null,'unfriending revokes membership');
select public.friend_action(pg_temp.person('owner'),'request');
select pg_temp.actor('owner');
select public.friend_action(pg_temp.person('friend'),'accept');
select is(jsonb_array_length(public.activity(pg_temp.result_id('public_visit','activityID'))->'companions'),0,'a new friendship does not restore tags');

select pg_temp.log_visit('{"audience":"only_me"}','PT');
select ok(public.passport(pg_temp.person('owner')) @> '[{"code":"PT"}]'::jsonb,'owner sees country from a private visit');
select pg_temp.actor('friend');
select ok(public.passport(pg_temp.person('owner')) @> '[{"code":"CA","otherPlaceCount":1}]'::jsonb,'friend passport counts visible places');
select ok(not (public.passport(pg_temp.person('owner')) @> '[{"code":"PT"}]'::jsonb),'private visits do not expose their country to friends');

select ok(not has_function_privilege('anon','public.friend_area_activity(text,text[],text,uuid)','EXECUTE'),'anonymous friend area access is denied');
select ok(not has_function_privilege('anon','public.friend_place_memories(uuid,uuid,text)','EXECUTE'),'anonymous friend visit access is denied');
select is(public.friend_area_activity('CA',null,null,null)->0->'cities'->0->>'name','Toronto','country rows show friends’ visible cities');
select is(jsonb_array_length(public.friend_area_activity('CA',array['on','ontario'],'Toronto',pg_temp.person('owner'))->0->'places'),
  1,'city detail returns distinct visible places');
select is(public.friend_area_activity('CA',array['quebec'],null,null),'[]'::jsonb,'state rows exclude other regions');
select is(public.friend_area_activity('CA',null,'Ottawa',null),'[]'::jsonb,'city rows exclude other cities');
select is(public.friend_area_activity('PT',null,null,null),'[]'::jsonb,'area rows exclude private visits');
select is(jsonb_array_length(public.friend_place_memories((select experience from place_ids where code='CA'),pg_temp.person('owner'),null)->'items'),
  2,'place detail returns only this friend’s visible visits');
select ok(public.friend_place_memories((select experience from place_ids where code='CA'),pg_temp.person('owner'),null)->'items'
  @> '[{"publicNote":"Updated note"}]'::jsonb,'friend detail includes the note from the visible visit');
select pg_temp.actor('outsider');
select is(public.friend_area_activity('CA',null,null,pg_temp.person('owner')),'[]'::jsonb,'a non-friend cannot see friend area data');
select throws_ok($$select public.friend_place_memories((select experience from place_ids where code='CA'),pg_temp.person('owner'),null)$$,
  'P0002',null,'a non-friend cannot use the friend detail endpoint');
select pg_temp.actor('blocked');
select is(public.friend_area_activity('CA',null,null,pg_temp.person('owner')),'[]'::jsonb,'a blocked user cannot see friend area data');
select throws_ok($$select public.friend_place_memories((select experience from place_ids where code='CA'),pg_temp.person('owner'),null)$$,
  'P0002',null,'a blocked user cannot open friend visits');

select * from finish();
rollback;
