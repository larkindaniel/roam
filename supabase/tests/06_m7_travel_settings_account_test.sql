-- M7: travel profile (Visits only, canonical geography, New this year), settings, and account
-- deletion (recent reauthentication, immediate deactivation, leased worker, stale tokens).
begin;
-- This file covers content published to all members and reads over friend edges. Audience and the
-- friend request flow have their own coverage in 07_friends_audience_plans_test.sql.
create function public.test_publish_to_all() returns trigger language plpgsql as $test$ begin new.audience:='public'; return new; end $test$;
create trigger zz_test_publish_to_all before insert on public.visits for each row execute function public.test_publish_to_all();
create trigger zz_test_publish_to_all before insert on public.ratings for each row execute function public.test_publish_to_all();
-- Writes one friend edge directly so these read tests can set up a viewer's graph step by step.
create function public.set_follow(p_user_id uuid, p_following boolean) returns boolean language plpgsql security definer set search_path='' as $test$
declare v_me uuid:=app_private.require_member();
begin
  if p_following then
    insert into public.follows(follower_id,followee_id) values(v_me,p_user_id) on conflict do nothing;
    if found then perform app_private.notify(p_user_id,v_me,'follow',null,null,'follow:'||v_me||':'||p_user_id); end if;
  else
    delete from public.follows where follower_id=v_me and followee_id=p_user_id;
  end if;
  return exists(select 1 from public.follows where follower_id=v_me and followee_id=p_user_id);
end $test$;
grant execute on function public.set_follow(uuid,boolean) to authenticated;

create extension if not exists pgtap with schema extensions;
select plan(94);

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now()
from (values ('a7000000-0000-4000-8000-000000000001'::uuid, 'm7-traveller@test.local'),
             ('b7000000-0000-4000-8000-000000000002'::uuid, 'm7-viewer@test.local'),
             ('c7000000-0000-4000-8000-000000000003'::uuid, 'm7-blocked@test.local'),
             ('d7000000-0000-4000-8000-000000000004'::uuid, 'm7-leaver@test.local'),
             ('e7000000-0000-4000-8000-000000000005'::uuid, 'm7-apple@test.local')) u(id,email);
insert into auth.identities(id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'm7-apple-subject', 'e7000000-0000-4000-8000-000000000005', '{"sub":"m7-apple-subject"}', 'apple', now(), now(), now());
insert into public.profiles(id,handle,display_name) values
  ('a7000000-0000-4000-8000-000000000001','m7_traveller','M7 Traveller'),
  ('b7000000-0000-4000-8000-000000000002','m7_viewer','M7 Viewer'),
  ('c7000000-0000-4000-8000-000000000003','m7_blocked','M7 Blocked'),
  ('d7000000-0000-4000-8000-000000000004','m7_leaver','M7 Leaver'),
  ('e7000000-0000-4000-8000-000000000005','m7_apple','M7 Apple');
insert into public.blocks(blocker_id,blocked_id) values('c7000000-0000-4000-8000-000000000003','a7000000-0000-4000-8000-000000000001');

create temporary table m7_ids(label text primary key, id uuid) on commit drop;
grant select,insert on m7_ids to authenticated;
create function pg_temp.m7_id(p_label text) returns uuid language sql as $$select id from m7_ids where label=p_label$$;
grant execute on function pg_temp.m7_id(text) to authenticated;
-- Signs in as a member; p_auth_age sets the token's authentication-method time (null = no amr).
create function pg_temp.m7_as(p_user uuid, p_auth_age interval default null) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', (jsonb_build_object('sub',p_user,'role','authenticated')
    || case when p_auth_age is null then '{}'::jsonb
            else jsonb_build_object('amr',jsonb_build_array(jsonb_build_object('method','password','timestamp',
                   floor(extract(epoch from now()-p_auth_age))::bigint))) end)::text, true);
end$$;
grant execute on function pg_temp.m7_as(uuid,interval) to authenticated;

-- Geography fixtures: same-name cities, a destination locality, a remote place with no city, a
-- bookmark-only place, a home city and repeated visits.
insert into public.countries(code,name) values('US','United States'),('IS','Iceland'),('PT','Portugal'),('NZ','New Zealand')
on conflict(code) do nothing;
create function pg_temp.m7_city(p_label text, p_key text, p_name text, p_region text, p_country text) returns void language plpgsql as $$
declare v_id uuid:=gen_random_uuid();
begin
  insert into public.cities(id,city_key,name,region,country_code) values(v_id,p_key,p_name,p_region,p_country);
  insert into m7_ids values(p_label,v_id);
end$$;
create function pg_temp.m7_place(p_label text, p_name text, p_country text, p_city text, p_category public.experience_category,
                                 p_locality boolean default false) returns void language plpgsql as $$
declare v_place uuid:=gen_random_uuid(); v_experience uuid:=gen_random_uuid();
begin
  insert into public.places(id,provider,name,normalized_name,latitude,longitude,country_code,city_id,is_locality,provenance)
  values(v_place,'mapkit',p_name,lower(p_name),45.5,-122.6,p_country,pg_temp.m7_id(p_city),p_locality,
         jsonb_build_object('source','mapkit','resolvedBy','d7000000-0000-4000-8000-000000000004'));
  insert into public.experiences(id,place_id,category) values(v_experience,v_place,p_category);
  insert into m7_ids values(p_label,v_experience);
end$$;
create function pg_temp.m7_visit(p_label text, p_owner uuid, p_experience text, p_date date) returns void language plpgsql as $$
declare v_id uuid;
begin
  insert into public.visits(owner_id,experience_id,visit_date,date_precision)
  values(p_owner,pg_temp.m7_id(p_experience),p_date,case when p_date is null then 'unknown' else 'day' end) returning id into v_id;
  insert into m7_ids values(p_label,v_id);
end$$;
do $$begin
  perform pg_temp.m7_city('portland-or','us|m7 oregon|portland','Portland','M7 Oregon','US');
  perform pg_temp.m7_city('portland-me','us|m7 maine|portland','Portland','M7 Maine','US');
  perform pg_temp.m7_city('reykjavik','is|m7 capital region|reykjavik','Reykjavík','M7 Capital Region','IS');
  perform pg_temp.m7_city('lisbon','pt|m7 lisboa|lisbon','Lisbon','M7 Lisboa','PT');
  perform pg_temp.m7_city('queenstown','nz|m7 otago|queenstown','Queenstown','M7 Otago','NZ');
  perform pg_temp.m7_place('books','M7 Books','US','portland-or','culture');
  perform pg_temp.m7_place('prom','M7 Promenade','US','portland-me','outdoors');
  perform pg_temp.m7_place('reykjavik-day','Reykjavík','IS','reykjavik','day_trips',true);
  perform pg_temp.m7_place('ice-cave','M7 Ice Cave','IS',null,'activities');
  perform pg_temp.m7_place('market','M7 Market','PT','lisbon','food_drink');
  perform pg_temp.m7_place('bay','M7 Bay','NZ','queenstown','outdoors');
  perform pg_temp.m7_visit('books-1','a7000000-0000-4000-8000-000000000001','books','2026-03-01');
  perform pg_temp.m7_visit('books-0','a7000000-0000-4000-8000-000000000001','books','2025-07-04');
  perform pg_temp.m7_visit('prom-1','a7000000-0000-4000-8000-000000000001','prom','2026-05-05');
  perform pg_temp.m7_visit('reykjavik-1','a7000000-0000-4000-8000-000000000001','reykjavik-day',null);
  perform pg_temp.m7_visit('cave-1','a7000000-0000-4000-8000-000000000001','ice-cave','2026-01-10');
  perform pg_temp.m7_visit('cave-2','a7000000-0000-4000-8000-000000000001','ice-cave',null);
  perform pg_temp.m7_visit('market-1','a7000000-0000-4000-8000-000000000001','market','2024-10-10');
end$$;
insert into public.ratings(owner_id,experience_id,category,sentiment,group_position,score,rank)
values('a7000000-0000-4000-8000-000000000001',pg_temp.m7_id('market'),'food_drink','liked',0,10.0,1);
insert into public.bookmarks(owner_id,experience_id) values('a7000000-0000-4000-8000-000000000001',pg_temp.m7_id('bay'));
update public.profiles set home_city_id=pg_temp.m7_id('queenstown') where id='a7000000-0000-4000-8000-000000000001';

-- 1. Privileges ---------------------------------------------------------------------------------
select ok(not has_function_privilege('anon','public.travel_profile(uuid,integer)','execute')
          and not has_function_privilege('anon','public.my_settings()','execute')
          and not has_function_privilege('anon','public.update_settings(jsonb)','execute')
          and not has_function_privilege('anon','public.request_account_deletion()','execute'),
          'anonymous callers have no travel, settings or deletion RPCs');
select ok(not has_function_privilege('authenticated','public.claim_account_deletions(uuid,integer)','execute')
          and not has_function_privilege('authenticated','public.process_account_deletion(uuid,uuid,text)','execute')
          and not has_function_privilege('authenticated','public.refresh_account_deletion(uuid)','execute')
          and not has_function_privilege('authenticated','public.fail_account_deletion(uuid,uuid,text)','execute'),
          'members cannot run deletion worker steps');
select ok(has_function_privilege('service_role','public.claim_account_deletions(uuid,integer)','execute')
          and has_function_privilege('service_role','public.process_account_deletion(uuid,uuid,text)','execute')
          and has_function_privilege('service_role','public.refresh_account_deletion(uuid)','execute'),
          'the server worker role runs deletion steps');
select ok(not has_function_privilege('authenticated','app_private.settings_json(uuid)','execute')
          and not has_table_privilege('authenticated','app_private.account_deletion_jobs','select'),
          'members cannot read private settings serializers or deletion jobs directly');

-- 2. Travel profile ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.m7_as('a7000000-0000-4000-8000-000000000001');
create temporary table m7_travel on commit drop as select public.travel_profile('a7000000-0000-4000-8000-000000000001',2026) as t;
select is(jsonb_array_length((select t->'pins' from m7_travel)),5,'one pin per visited Experience; repeats, bookmarks and home city add none');
select is((select (t->>'countryCount')::int from m7_travel),3,'countries count canonical country codes from Visits only');
select is((select (t->>'cityCount')::int from m7_travel),4,'same-name cities in different regions stay distinct');
select is((select (t->>'placesWithoutCity')::int from m7_travel),1,'a remote place counts its country and pin without a city');
select ok((select t->'cities' @> '[{"cityKey":"us|m7 oregon|portland","count":1},{"cityKey":"us|m7 maine|portland","count":1}]' from m7_travel),
          'city rows keep both Portlands with visited-experience counts');
select ok((select t->'cities' @> '[{"cityKey":"is|m7 capital region|reykjavik","count":1}]' from m7_travel),
          'a destination locality counts its own city');
select ok((select not (t->'countries' @> '[{"countryCode":"NZ"}]') and not (t->'cities' @> '[{"cityKey":"nz|m7 otago|queenstown"}]') from m7_travel),
          'a bookmark and the home city never count as travel');
select ok((select t->'countries' @> '[{"countryCode":"US","count":2},{"countryCode":"IS","count":2},{"countryCode":"PT","count":1}]' from m7_travel),
          'country rows count distinct visited experiences, not visits');
select is((select jsonb_array_length(t->'categories') from m7_travel),5,'category rows cover each visited category');
select ok((select t->'pins' @> jsonb_build_array(jsonb_build_object('experienceID',pg_temp.m7_id('books'),'visitCount',2,'firstVisitDate','2025-07-04',
                                                                     'cityName','Portland','countryCode','US')) from m7_travel),
          'a pin carries its first known visit date and visit count');
select is((select (t->'newThisYear'->>'count')::int from m7_travel),2,'New this year counts experiences first visited this year');
select ok((select t->'newThisYear'->'experienceIDs' @> jsonb_build_array(pg_temp.m7_id('prom'),pg_temp.m7_id('ice-cave'))
                  and not (t->'newThisYear'->'experienceIDs' @> jsonb_build_array(pg_temp.m7_id('books'))) from m7_travel),
          'a place first visited last year does not count again for a revisit this year');
select is((select (t->'newThisYear'->>'unknownDateCount')::int from m7_travel),1,'places visited only on unknown dates are excluded and reported');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2025)->'newThisYear'->>'count')::int,1,'each year counts its own first visits');
select is((public.public_profile('a7000000-0000-4000-8000-000000000001')->>'countryCount')::int
          ||'/'||(public.public_profile('a7000000-0000-4000-8000-000000000001')->>'cityCount'),'3/4','profile header totals match the travel profile');
select throws_ok($$select public.travel_profile('a7000000-0000-4000-8000-000000000001',12)$$,'22023',null,'the year must be a calendar year');

select pg_temp.m7_as('b7000000-0000-4000-8000-000000000002');
select is(public.travel_profile('a7000000-0000-4000-8000-000000000001',2026),(select t from m7_travel),'another member sees the same public travel data');
select pg_temp.m7_as('c7000000-0000-4000-8000-000000000003');
select throws_ok($$select public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)$$,'P0002',null,'a blocked pair cannot read travel');
reset role;

-- Derived rules: revisits, earliest-visit edits and deletions recompute; a Rating removal does not.
select pg_temp.m7_visit('prom-2','a7000000-0000-4000-8000-000000000001','prom','2026-08-01');
update public.visits set visit_date='2026-02-02' where id=pg_temp.m7_id('books-0');
set local role authenticated;
select pg_temp.m7_as('a7000000-0000-4000-8000-000000000001');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->'newThisYear'->>'count')::int,3,
          'moving the earliest visit into this year recomputes New this year; a revisit adds nothing');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2025)->'newThisYear'->>'count')::int,0,'and removes it from the earlier year');
reset role;
delete from public.visits where id=pg_temp.m7_id('cave-1');
delete from public.ratings where owner_id='a7000000-0000-4000-8000-000000000001' and experience_id=pg_temp.m7_id('market');
set local role authenticated;
select pg_temp.m7_as('a7000000-0000-4000-8000-000000000001');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->'newThisYear'->>'unknownDateCount')::int,2,
          'deleting the only dated visit leaves an unknown-date place excluded');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->>'countryCount')::int,3,'removing only a Rating keeps travel counts');
select ok(public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->'pins' @> jsonb_build_array(jsonb_build_object('experienceID',pg_temp.m7_id('market'),'category','food_drink')),
          'an unrated visited place keeps its pin and canonical category');
reset role;
delete from public.visits where id=pg_temp.m7_id('market-1');
set local role authenticated;
select pg_temp.m7_as('a7000000-0000-4000-8000-000000000001');
select is((public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->>'countryCount')::int
          ||'/'||(public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->>'cityCount')
          ||'/'||jsonb_array_length(public.travel_profile('a7000000-0000-4000-8000-000000000001',2026)->'pins'),'2/3/4',
          'removing the last Visit removes the pin and decrements city and country counts');

-- 3. Settings ----------------------------------------------------------------------------------
select is(public.my_settings(),'{"distanceUnit":"km","hapticsEnabled":true,"notifyFollows":true,"notifyLikes":true,"notifyComments":true}'::jsonb,
          'defaults are kilometres, haptics on and every in-app event on');
select is(public.update_settings('{"distanceUnit":"mi","hapticsEnabled":false,"notifyFollows":true,"notifyLikes":false,"notifyComments":true}'),
          '{"distanceUnit":"mi","hapticsEnabled":false,"notifyFollows":true,"notifyLikes":false,"notifyComments":true}'::jsonb,'a settings save returns the stored values');
select is(public.update_settings('{"distanceUnit":"mi","hapticsEnabled":false,"notifyFollows":true,"notifyLikes":false,"notifyComments":true}')->>'distanceUnit','mi',
          'a retried save is a harmless desired state');
select is(public.my_settings()->>'distanceUnit','mi','settings persist per member');
select throws_ok($$select public.update_settings('{"distanceUnit":"leagues","hapticsEnabled":false,"notifyFollows":true,"notifyLikes":false,"notifyComments":true}')$$,
                 '22023',null,'unknown units are rejected');
select throws_ok($$select public.update_settings('{"distanceUnit":"km","hapticsEnabled":"yes","notifyFollows":true,"notifyLikes":false,"notifyComments":true}')$$,
                 '22023',null,'settings must be booleans');
select throws_ok($$select public.update_settings('{"distanceUnit":"km","hapticsEnabled":true,"notifyFollows":true,"notifyLikes":true}')$$,
                 '22023',null,'a partial settings object is rejected');
select throws_ok($$select public.update_settings('{"distanceUnit":"km","hapticsEnabled":true,"notifyFollows":true,"notifyLikes":true,"notifyComments":true,"push":true}')$$,
                 '22023',null,'unsupported settings such as push are rejected');
select is(public.my_settings()->>'notifyLikes','false','a rejected save changes nothing');
select is((select count(*)::int from public.user_settings where user_id='a7000000-0000-4000-8000-000000000001'),1,'members can read their own settings row');
select pg_temp.m7_as('b7000000-0000-4000-8000-000000000002');
select is((select count(*)::int from public.user_settings where user_id='a7000000-0000-4000-8000-000000000001'),0,'another member cannot read settings');
select is(public.my_settings()->>'distanceUnit','km','each member has their own settings');
reset role;
insert into public.visits(id,owner_id,experience_id,date_precision) values('a7a00000-0000-4000-8000-00000000000a','a7000000-0000-4000-8000-000000000001',pg_temp.m7_id('prom'),'unknown');
insert into public.activities(id,author_id,type,experience_id,visit_id,category,score_snapshot,published_at,source_operation_id)
values(gen_random_uuid(),'a7000000-0000-4000-8000-000000000001','revisit',pg_temp.m7_id('prom'),'a7a00000-0000-4000-8000-00000000000a','outdoors',8.0,now(),gen_random_uuid());
insert into m7_ids select 'post',id from public.activities where author_id='a7000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.m7_as('b7000000-0000-4000-8000-000000000002');
select is(public.set_like(pg_temp.m7_id('post'),true),true,'a member likes the traveller''s post');
select is(public.set_follow('a7000000-0000-4000-8000-000000000001',true),true,'and follows the traveller');
reset role;
select is((select count(*)::int from public.notifications where recipient_id='a7000000-0000-4000-8000-000000000001' and type='like'),0,
          'turning off like notifications stops new like notifications');
select is((select count(*)::int from public.notifications where recipient_id='a7000000-0000-4000-8000-000000000001' and type='follow'),1,
          'follow notifications stay on');

-- 4. Account deletion -------------------------------------------------------------------------
-- The leaver's data: visits, rating, bookmark, private note, follows, a comment and like on another
-- member's post, a post with a comment from someone else, a report, media rows and stored objects.
insert into public.visits(owner_id,experience_id,visit_date,date_precision,public_note)
values('d7000000-0000-4000-8000-000000000004',pg_temp.m7_id('books'),'2026-04-04','day','Leaver note');
insert into public.ratings(owner_id,experience_id,category,sentiment,group_position,score,rank)
values('d7000000-0000-4000-8000-000000000004',pg_temp.m7_id('books'),'culture','liked',0,10.0,1);
insert into public.bookmarks(owner_id,experience_id) values('d7000000-0000-4000-8000-000000000004',pg_temp.m7_id('bay'));
insert into public.private_notes(owner_id,experience_id,body) values('d7000000-0000-4000-8000-000000000004',pg_temp.m7_id('books'),'Secret');
insert into public.follows(follower_id,followee_id) values('d7000000-0000-4000-8000-000000000004','a7000000-0000-4000-8000-000000000001'),
                                                         ('b7000000-0000-4000-8000-000000000002','d7000000-0000-4000-8000-000000000004');
insert into public.activities(id,author_id,type,experience_id,category,score_snapshot,published_at,source_operation_id)
select gen_random_uuid(),'d7000000-0000-4000-8000-000000000004','rating',pg_temp.m7_id('books'),'culture',10.0,now(),gen_random_uuid();
insert into m7_ids select 'leaver-post',id from public.activities where author_id='d7000000-0000-4000-8000-000000000004';
insert into public.comments(activity_id,author_id,body,operation_id) values
  (pg_temp.m7_id('post'),'d7000000-0000-4000-8000-000000000004','Leaver comment',gen_random_uuid()),
  (pg_temp.m7_id('leaver-post'),'b7000000-0000-4000-8000-000000000002','Viewer comment',gen_random_uuid());
insert into public.likes(actor_id,activity_id) values('d7000000-0000-4000-8000-000000000004',pg_temp.m7_id('post'));
insert into public.reports(id,reporter_id,target_type,target_id,reason) values(gen_random_uuid(),'d7000000-0000-4000-8000-000000000004','member',
  'c7000000-0000-4000-8000-000000000003','spam');
insert into storage.objects(bucket_id,name,owner,metadata) values
  ('visit-media','d7000000-0000-4000-8000-000000000004/f7000000-0000-4000-8000-000000000001.jpg','d7000000-0000-4000-8000-000000000004','{"size":100}'),
  ('visit-media','d7000000-0000-4000-8000-000000000004/f7000000-0000-4000-8000-000000000002.jpg','d7000000-0000-4000-8000-000000000004','{"size":100}'),
  ('avatars','d7000000-0000-4000-8000-000000000004/f7000000-0000-4000-8000-000000000003.jpg','d7000000-0000-4000-8000-000000000004','{"size":100}');
insert into public.media(owner_id,purpose,visit_id,bucket,object_path,state,byte_size,width,height,inspected_at,storage_object_id)
select 'd7000000-0000-4000-8000-000000000004','visit',(select id from public.visits where owner_id='d7000000-0000-4000-8000-000000000004'),
       'visit-media',o.name,'attached',100,10,10,now(),o.id
from storage.objects o where o.name='d7000000-0000-4000-8000-000000000004/f7000000-0000-4000-8000-000000000001.jpg';
insert into public.media(owner_id,purpose,bucket,object_path,state,byte_size,width,height,inspected_at,storage_object_id)
select 'd7000000-0000-4000-8000-000000000004','avatar','avatars',o.name,'attached',100,10,10,now(),o.id
from storage.objects o where o.bucket_id='avatars' and o.name like 'd7000000-0000-4000-8000-000000000004/%';
update public.profiles set avatar_path='d7000000-0000-4000-8000-000000000004/f7000000-0000-4000-8000-000000000003.jpg'
where id='d7000000-0000-4000-8000-000000000004';
insert into auth.sessions(id,user_id,created_at,updated_at) values('f7000000-0000-4000-8000-0000000000aa','d7000000-0000-4000-8000-000000000004',now(),now());
insert into auth.refresh_tokens(token,user_id,revoked,created_at,updated_at,session_id)
values('m7-refresh-token','d7000000-0000-4000-8000-000000000004',false,now(),now(),'f7000000-0000-4000-8000-0000000000aa');

set local role authenticated;
select pg_temp.m7_as('b7000000-0000-4000-8000-000000000002');
select ok(exists(select 1 from jsonb_array_elements(public.feed()->'items') i where i->'author'->>'id'='d7000000-0000-4000-8000-000000000004')
          and jsonb_array_length(public.search_members('m7_leaver')->'items')=1
          and exists(select 1 from jsonb_array_elements(public.comments(pg_temp.m7_id('post'))->'items') c where c->>'body'='Leaver comment'),
          'before deletion a follower sees their post, finds them and reads their comment');
select pg_temp.m7_as('d7000000-0000-4000-8000-000000000004');
select throws_ok($$select public.request_account_deletion()$$,'42501','roam:reauthentication_required','deletion needs a recent sign-in');
select pg_temp.m7_as('d7000000-0000-4000-8000-000000000004','1 hour');
select throws_ok($$select public.request_account_deletion()$$,'42501','roam:reauthentication_required','a refreshed token from an old sign-in is not enough');
select is(public.account_deletion_status(),null,'no deletion is pending before a request');
select pg_temp.m7_as('d7000000-0000-4000-8000-000000000004','2 minutes');
select is(public.request_account_deletion()->>'state','pending','a recent sign-in can request deletion');
select is(public.request_account_deletion()->>'appleRevocation','not_applicable','a repeated request returns the same job; email accounts need no Apple revocation');
select is(public.account_deletion_status()->>'storageCleanup','pending','status reports pending cleanup honestly');
select throws_ok($$select public.friend_action('c7000000-0000-4000-8000-000000000003','request')$$,'42501','roam:account_disabled','writes stop immediately');
select throws_ok($$select public.create_profile('Again','m7_again')$$,'42501','roam:account_disabled','a deactivated account cannot create a profile');
select throws_ok($$select public.my_settings()$$,'42501','roam:account_disabled','settings are unavailable once deletion starts');
select pg_temp.m7_as('b7000000-0000-4000-8000-000000000002');
select throws_ok($$select public.public_profile('d7000000-0000-4000-8000-000000000004')$$,'P0002',null,'the profile is hidden immediately');
select ok(not exists(select 1 from jsonb_array_elements(public.feed()->'items') i where i->'author'->>'id'='d7000000-0000-4000-8000-000000000004'),
          'their posts leave the feed immediately');
select is(jsonb_array_length(public.search_members('m7_leaver')->'items'),0,'they leave member search immediately');
select ok(not exists(select 1 from jsonb_array_elements(public.comments(pg_temp.m7_id('post'))->'items') c where c->>'body'='Leaver comment'),
          'their comments are hidden immediately');
reset role;
select is((select count(*)::int from auth.sessions where user_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from auth.refresh_tokens where user_id='d7000000-0000-4000-8000-000000000004'),0,
          'every session and refresh token is revoked at request time');
select is((select count(*)::int from app_private.account_deletion_jobs where user_id='d7000000-0000-4000-8000-000000000004'),1,'one durable job per member');

-- Worker: lease, process, Storage cleanup and completion. Jobs and cleanup rows left by other local
-- runs are parked inside this rolled-back transaction so the test's worker only sees its own.
update app_private.account_deletion_jobs set next_attempt_at=now()+interval'1 day'
where user_id not in('d7000000-0000-4000-8000-000000000004','e7000000-0000-4000-8000-000000000005');
update app_private.storage_cleanup set next_attempt_at=now()+interval'1 day'
where done_at is null and object_path not like 'd7000000-0000-4000-8000-000000000004/%';
select throws_ok($$select public.claim_account_deletions(gen_random_uuid(),0)$$,'22023',null,'claims are bounded');
create temporary table m7_claim on commit drop as
  select public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b1',10) as jobs;
select is((select jsonb_array_length(jobs) from m7_claim),1,'the worker claims the pending job');
insert into m7_ids select 'job',(jobs->0->>'id')::uuid from m7_claim;
select is(jsonb_array_length(public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b2',10)),0,'a leased job is not claimed twice');
select throws_ok($$select public.process_account_deletion(pg_temp.m7_id('job'),'f7000000-0000-4000-8000-0000000000b2','not_applicable')$$,
                 '42501','roam:forbidden:not_leased','only the leaseholder processes a job');
select throws_ok($$select public.process_account_deletion(pg_temp.m7_id('job'),'f7000000-0000-4000-8000-0000000000b1','completed')$$,
                 '22023',null,'an email account cannot record an Apple revocation');
create temporary table m7_processed on commit drop as
  select public.process_account_deletion(pg_temp.m7_id('job'),'f7000000-0000-4000-8000-0000000000b1','not_applicable') as status;
select is((select status->>'state' from m7_processed),'processing','relational data is gone but the job waits for Storage cleanup');
select is((select count(*)::int from auth.users where id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.profiles where id='d7000000-0000-4000-8000-000000000004'),0,'the auth user and profile are deleted');
select is((select count(*)::int from public.visits where owner_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.ratings where owner_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.bookmarks where owner_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.private_notes where owner_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.media where owner_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.activities where author_id='d7000000-0000-4000-8000-000000000004'),0,
          'visits, ratings, bookmarks, private notes, media and posts are deleted');
select is((select count(*)::int from public.follows where 'd7000000-0000-4000-8000-000000000004' in(follower_id,followee_id))
          +(select count(*)::int from public.comments where author_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.likes where actor_id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.comments where body='Viewer comment'),0,
          'follows, their comments and likes, and comments on their posts are deleted');
select is((select count(*)::int from public.reports where reporter_id is null and target_id='c7000000-0000-4000-8000-000000000003'),1,
          'their reports remain for moderation without the reporter');
select is((select count(*)::int from public.places where provenance->>'resolvedBy'='d7000000-0000-4000-8000-000000000004'),0,
          'shared places no longer name them as resolver');
select is((select count(*)::int from public.places where name='M7 Books'),1,'shared places and experiences stay');
select is((select count(*)::int from app_private.storage_cleanup where object_path like 'd7000000-0000-4000-8000-000000000004/%' and done_at is null),3,
          'every stored object in their folders is queued for cleanup');
create temporary table m7_cleanup on commit drop as select public.claim_media_cleanup('f7000000-0000-4000-8000-0000000000c1',100) as jobs;
select is((select count(*)::int from m7_cleanup, jsonb_array_elements(jobs) j where j->>'path' like 'd7000000-0000-4000-8000-000000000004/%'),3,
          'their objects are unregistered now, so the Storage cleanup worker can claim them');
select is(public.refresh_account_deletion(pg_temp.m7_id('job'))->>'state','processing','the job stays open while objects remain');
set local storage.allow_delete_query = 'true';
delete from storage.objects where name like 'd7000000-0000-4000-8000-000000000004/%';
set local storage.allow_delete_query = 'false';
select is(public.refresh_account_deletion(pg_temp.m7_id('job'))->>'state','completed','the job completes once Storage is clean');
select is(public.refresh_account_deletion(pg_temp.m7_id('job'))->>'storageCleanup','completed','completion is idempotent and reports cleanup done');
select is(jsonb_array_length(public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b1',10)),0,'a completed job is never claimed again');

-- Stale tokens after deletion cannot recreate data.
set local role authenticated;
select pg_temp.m7_as('d7000000-0000-4000-8000-000000000004','3 minutes');
select is(app_private.current_member(),null,'a stale token is no longer a member');
select throws_ok($$select public.create_profile('Back','m7_back')$$,'42501','roam:not_signed_in','a stale token cannot recreate a profile');
select throws_ok($$select public.set_bookmark(pg_temp.m7_id('bay'),true)$$,'42501',null,'a stale token cannot save places');
select throws_ok($$select public.submit_report(gen_random_uuid(),'member','c7000000-0000-4000-8000-000000000003','spam',null)$$,'42501',null,
                 'a stale token cannot file reports');
select is(public.account_deletion_status()->>'state','completed','the requesting token can still read the completed status');
select is(public.request_account_deletion()->>'state','completed','a repeated request after completion recreates nothing');
reset role;
select is((select count(*)::int from public.profiles where id='d7000000-0000-4000-8000-000000000004')
          +(select count(*)::int from public.bookmarks where owner_id='d7000000-0000-4000-8000-000000000004'),0,'no data was recreated');

-- Failure and retry; an Apple account records that revocation is not configured locally.
set local role authenticated;
select pg_temp.m7_as('e7000000-0000-4000-8000-000000000005','1 minute');
select is(public.request_account_deletion()->>'appleRevocation','pending','an Apple account needs token revocation');
reset role;
select is(jsonb_array_length(public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b3',10)),1,'the worker claims the Apple job');
insert into m7_ids select 'apple-job',id from app_private.account_deletion_jobs where user_id='e7000000-0000-4000-8000-000000000005';
select is(public.fail_account_deletion(pg_temp.m7_id('apple-job'),'f7000000-0000-4000-8000-0000000000b4','boom'),false,'only the leaseholder can fail a job');
select is(public.fail_account_deletion(pg_temp.m7_id('apple-job'),'f7000000-0000-4000-8000-0000000000b3','transient'),true,'a failed attempt is recorded');
select is(jsonb_array_length(public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b3',10)),0,'a failed job backs off before retrying');
update app_private.account_deletion_jobs set next_attempt_at=now()-interval'1 second' where id=pg_temp.m7_id('apple-job');
select is(jsonb_array_length(public.claim_account_deletions('f7000000-0000-4000-8000-0000000000b5',10)),1,'after the backoff another worker retries it');
select is(public.process_account_deletion(pg_temp.m7_id('apple-job'),'f7000000-0000-4000-8000-0000000000b5','not_configured')->>'state','completed',
          'with no Storage objects the retry completes');
select is((select apple_revocation||'/'||attempts from app_private.account_deletion_jobs where id=pg_temp.m7_id('apple-job')),'not_configured/2',
          'the missing Apple revocation configuration is recorded, not reported as revoked');
select is((select count(*)::int from auth.identities where user_id='e7000000-0000-4000-8000-000000000005'),0,'provider identities are removed with the user');

select * from finish();
rollback;
