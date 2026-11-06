-- M5: inspected uploads, attachment authorization, memory edits, private notes, retained public
-- memories, standalone post removal, storage read/delete policy and durable cleanup leases.
begin;
-- This file covers content published to all members and reads over friend edges. Audience and the
-- friend request flow have their own coverage in 07_friends_audience_plans_test.sql.
create function public.test_publish_to_all() returns trigger language plpgsql as $test$ begin new.audience:='public'; return new; end $test$;
create trigger zz_test_publish_to_all before insert on public.visits for each row execute function public.test_publish_to_all();
create trigger zz_test_publish_to_all before insert on public.ratings for each row execute function public.test_publish_to_all();

create extension if not exists pgtap with schema extensions;
select plan(93);

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now()
from (values ('a5000000-0000-4000-8000-000000000001'::uuid, 'm5-owner@test.local'),
             ('b5000000-0000-4000-8000-000000000002'::uuid, 'm5-follower@test.local'),
             ('c5000000-0000-4000-8000-000000000003'::uuid, 'm5-blocked@test.local'),
             ('d5000000-0000-4000-8000-000000000004'::uuid, 'm5-other@test.local'),
             ('e5000000-0000-4000-8000-000000000005'::uuid, 'm5-gone@test.local')) u(id,email);
insert into public.profiles(id,handle,display_name) values
  ('a5000000-0000-4000-8000-000000000001','m5_owner','M5 Owner'),
  ('b5000000-0000-4000-8000-000000000002','m5_follower','M5 Follower'),
  ('c5000000-0000-4000-8000-000000000003','m5_blocked','M5 Blocked'),
  ('d5000000-0000-4000-8000-000000000004','m5_other','M5 Other'),
  ('e5000000-0000-4000-8000-000000000005','m5_gone','M5 Gone');
insert into public.follows(follower_id,followee_id) values ('b5000000-0000-4000-8000-000000000002','a5000000-0000-4000-8000-000000000001');
insert into public.blocks(blocker_id,blocked_id) values ('a5000000-0000-4000-8000-000000000001','c5000000-0000-4000-8000-000000000003');

create temporary table m5_cases(label text primary key, experience uuid, request jsonb, response jsonb) on commit drop;
create temporary table m5_media(label text primary key, id uuid, attempt uuid, path text, etag text) on commit drop;
create temporary table m5_values(label text primary key, value jsonb) on commit drop;
grant select,insert,update on m5_cases, m5_media, m5_values to authenticated;

-- What the Edge inspector does after measuring real bytes: register the exact stored object.
create function pg_temp.m5_upload(p_actor uuid, p_label text, p_purpose public.media_purpose default 'visit')
returns uuid language plpgsql as $$
declare v_attempt uuid := gen_random_uuid(); v_bucket text := case when p_purpose='avatar' then 'avatars' else 'visit-media' end;
  v_path text := p_actor::text||'/'||v_attempt::text||'.jpg'; v_etag text := '"'||md5(p_label)||'"'; v_result jsonb;
begin
  insert into storage.objects(bucket_id,name,owner,metadata) values(v_bucket,v_path,p_actor,
    jsonb_build_object('size',2048,'mimetype','image/jpeg','eTag',v_etag));
  v_result := public.finalize_media_inspection(p_actor,v_attempt,p_purpose,640,480,2048,encode(extensions.digest(p_label,'sha256'),'hex'),v_etag);
  insert into m5_media values(p_label,(v_result->>'id')::uuid,v_attempt,v_path,v_etag);
  return (v_result->>'id')::uuid;
end$$;
create function pg_temp.m5_media_id(p_label text) returns uuid language sql as $$select id from m5_media where label=p_label$$;
create function pg_temp.m5_log(p_label text, p_category text, p_visit jsonb)
returns void language plpgsql as $$
declare v_experience uuid; v_request jsonb;
begin
  v_experience := (public.resolve_place(jsonb_build_object('provider','mapkit','providerPlaceID','I-M5-'||gen_random_uuid()||p_label,
      'name','M5 '||p_label,'latitude',41.39,'longitude',2.17,'isLocality',false,'suggestedCategory',p_category)) ->> 'id')::uuid;
  v_request := jsonb_build_object('operationID',gen_random_uuid(),'intent','first_log','experienceID',v_experience,'category',p_category,
      'sentiment','liked','baseRevision',(public.category_ranking(p_category::public.experience_category)->>'revision')::bigint,
      'answers','[]'::jsonb,'visit',p_visit);
  insert into m5_cases values(p_label,v_experience,v_request,public.commit_rating(v_request));
end$$;
create function pg_temp.m5_case(p_label text, p_key text) returns uuid language sql as $$select (response->>p_key)::uuid from m5_cases where label=p_label$$;
create function pg_temp.m5_experience(p_label text) returns uuid language sql as $$select experience from m5_cases where label=p_label$$;
create function pg_temp.m5_attempt(p_media uuid) returns text language sql as $$
  select format('select pg_temp.m5_log(%L,%L,%L::jsonb)','attempt-'||gen_random_uuid(),'culture',
                jsonb_build_object('date','2020-05-01','timeZoneIdentifier','Europe/Madrid','publicNote','','mediaIDs',jsonb_build_array(p_media)))
$$;
create function pg_temp.m5_delete_object(p_name text) returns integer language plpgsql as $$
declare v_count integer;
begin
  delete from storage.objects where bucket_id='visit-media' and name=p_name;
  get diagnostics v_count = row_count;
  return v_count;
end$$;
grant execute on function pg_temp.m5_media_id(text), pg_temp.m5_log(text,text,jsonb), pg_temp.m5_case(text,text), pg_temp.m5_experience(text), pg_temp.m5_attempt(uuid), pg_temp.m5_delete_object(text) to authenticated;

-- 1. Privileges --------------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated','public.finalize_media_inspection(uuid,uuid,public.media_purpose,integer,integer,integer,text,text)','execute'),
          'members cannot submit their own inspection results');
select ok(has_function_privilege('service_role','public.finalize_media_inspection(uuid,uuid,public.media_purpose,integer,integer,integer,text,text)','execute'),
          'only the server inspector role can register inspected media');
select ok(not has_function_privilege('authenticated','public.sweep_media_orphans()','execute')
          and not has_function_privilege('authenticated','public.claim_media_cleanup(uuid,integer)','execute')
          and not has_function_privilege('authenticated','public.finish_media_cleanup(bigint,uuid,text)','execute'),
          'members cannot sweep, claim or finish cleanup jobs');
select ok(not has_function_privilege('anon','public.public_memories(uuid,text)','execute') and not has_function_privilege('anon','public.update_visit(uuid,jsonb,uuid)','execute')
          and not has_function_privilege('anon','public.save_private_note(uuid,text,uuid)','execute') and not has_function_privilege('anon','public.delete_activity(uuid)','execute'),
          'anonymous callers have no memory, private-note or post RPCs');
select ok(has_function_privilege('authenticated','public.update_visit(uuid,jsonb,uuid)','execute') and has_function_privilege('authenticated','public.delete_activity(uuid)','execute')
          and has_function_privilege('authenticated','public.public_memories(uuid,text)','execute'),
          'members edit memories, read public memories and remove posts only through RPCs');

-- 2. Inspection registration -------------------------------------------------------------------
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','first'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','second'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','spare'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','expiring'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','replaced'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','tomb'); end$$;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','post-photo'); end$$;
do $$begin perform pg_temp.m5_upload('b5000000-0000-4000-8000-000000000002','foreign'); end$$;
select throws_ok(format('select public.finalize_media_inspection(%L,%L,%L,640,480,100,%L,%L)','a5000000-0000-4000-8000-000000000001',gen_random_uuid(),'visit',repeat('b',64),'"x"'),
                 '22023',null,'an attempt with no stored object cannot be registered');
insert into storage.objects(bucket_id,name,owner,metadata) values('visit-media','a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000001.jpg',
  'a5000000-0000-4000-8000-000000000001','{"size":100,"mimetype":"image/jpeg","eTag":"\"abc\""}');
select throws_ok($$select public.finalize_media_inspection('a5000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','visit',640,480,200,repeat('c',64),'"abc"')$$,
                 '22023',null,'a measurement whose size differs from the stored object is rejected');
select throws_ok($$select public.finalize_media_inspection('a5000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','visit',640,480,100,repeat('c',64),'"other"')$$,
                 '22023',null,'a measurement of different stored bytes (eTag) is rejected');
select is((select state::text from public.media where id=pg_temp.m5_media_id('first')),'staged','inspection registers a private staged upload');
select ok((select m.inspected_at is not null and m.content_sha256=encode(extensions.digest('first','sha256'),'hex')
                  and m.storage_object_id=(select o.id from storage.objects o where o.bucket_id='visit-media' and o.name=m.object_path)
                  and m.expires_at>now() and m.expires_at<=now()+interval '24 hours'
           from public.media m where m.id=pg_temp.m5_media_id('first')),'the measured digest is bound to the exact stored object and expires within 24 hours');
select is((public.finalize_media_inspection('a5000000-0000-4000-8000-000000000001',(select attempt from m5_media where label='first'),'visit',640,480,2048,
             encode(extensions.digest('first','sha256'),'hex'),(select etag from m5_media where label='first'))->>'id')::uuid,
          pg_temp.m5_media_id('first'),'retrying the same upload attempt returns the same media');
select throws_ok(format('select public.finalize_media_inspection(%L,%L,%L,640,480,2048,%L,%L)','a5000000-0000-4000-8000-000000000001',
                        (select attempt from m5_media where label='first'),'visit',repeat('d',64),(select etag from m5_media where label='first')),
                 '23505',null,'one upload attempt cannot be re-registered for different content');
insert into storage.objects(bucket_id,name,owner,metadata,created_at) values('visit-media','a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000002.jpg',
  'a5000000-0000-4000-8000-000000000001','{"size":100,"mimetype":"image/jpeg","eTag":"\"old\""}',now()-interval '25 hours');
select throws_ok($$select public.finalize_media_inspection('a5000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000002','visit',640,480,100,repeat('e',64),'"old"')$$,
                 '22023','roam:media_expired','an upload older than 24 hours cannot be registered');
update public.profiles set deactivated_at=now() where id='e5000000-0000-4000-8000-000000000005';
insert into storage.objects(bucket_id,name,owner,metadata) values('visit-media','e5000000-0000-4000-8000-000000000005/f5000000-0000-4000-8000-000000000003.jpg',
  'e5000000-0000-4000-8000-000000000005','{"size":100,"mimetype":"image/jpeg","eTag":"\"gone\""}');
select throws_ok($$select public.finalize_media_inspection('e5000000-0000-4000-8000-000000000005','f5000000-0000-4000-8000-000000000003','visit',640,480,100,repeat('f',64),'"gone"')$$,
                 '42501',null,'a deactivated account cannot register uploads');

-- 3. Attachment authorization and read rules ---------------------------------------------------
insert into public.media(owner_id,purpose,bucket,object_path,byte_size,width,height)
values('a5000000-0000-4000-8000-000000000001','visit','visit-media','a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000001.jpg',100,64,64);
insert into m5_media(label,id,path) select 'uninspected',id,object_path from public.media where object_path='a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000001.jpg';
set local storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='replaced');
insert into storage.objects(bucket_id,name,owner,metadata) select 'visit-media',path,'a5000000-0000-4000-8000-000000000001',
  jsonb_build_object('size',2048,'mimetype','image/jpeg','eTag',etag) from m5_media where label='replaced';
update public.media set expires_at=now()-interval '1 minute' where id=pg_temp.m5_media_id('expiring');

set local role authenticated;
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok(pg_temp.m5_attempt(pg_temp.m5_media_id('foreign')),'22023',null,'another member''s inspected upload cannot attach');
select throws_ok(pg_temp.m5_attempt(pg_temp.m5_media_id('uninspected')),'22023',null,'an uninspected upload cannot attach');
select throws_ok(pg_temp.m5_attempt(pg_temp.m5_media_id('replaced')),'22023',null,'an object replaced after inspection cannot attach');
select throws_ok(pg_temp.m5_attempt(pg_temp.m5_media_id('expiring')),'22023','roam:media_expired','an expired staged upload is a definite media_expired rejection');
select is((select count(*)::int from m5_cases),0,'rejected attachments created no rating, visit or activity');
do $$begin perform pg_temp.m5_log('photos','culture',jsonb_build_object('date','2020-05-01','timeZoneIdentifier','Europe/Madrid',
  'publicNote','Original memory','mediaIDs',jsonb_build_array(pg_temp.m5_media_id('second'),pg_temp.m5_media_id('first')))); end$$;
select is((select jsonb_agg(id order by position) from public.media where visit_id=pg_temp.m5_case('photos','visitID') and state='attached'),
          jsonb_build_array(pg_temp.m5_media_id('second'),pg_temp.m5_media_id('first')),'inspected owned uploads attach atomically in the chosen order');
insert into m5_values select 'published', to_jsonb(published_at) from public.activities where id=pg_temp.m5_case('photos','activityID');

set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is((select count(*)::int from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='first')),1,
          'publication makes the attached photo readable to another member');
select is((select count(*)::int from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='spare')),0,
          'a staged upload stays private to its owner');
select is((select count(*)::int from public.media where id in (pg_temp.m5_media_id('spare'),pg_temp.m5_media_id('first'))),1,
          'media rows expose attached photos but not staged uploads to other members');
set local request.jwt.claims to '{"sub":"c5000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is((select count(*)::int from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='first')),0,
          'a blocked member cannot read the attached photo');
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='spare')),1,
          'the owner can read their own staged upload');

-- 4. Memory edits ------------------------------------------------------------------------------
insert into m5_values values('edit-op',to_jsonb(gen_random_uuid()::text)),
  ('edit-payload',jsonb_build_object('date','2020-05-02','timeZoneIdentifier','Europe/Madrid','publicNote','Edited memory',
                                     'mediaIDs',jsonb_build_array(pg_temp.m5_media_id('first'),pg_temp.m5_media_id('post-photo'))));
insert into m5_values select 'edit-result', public.update_visit(pg_temp.m5_case('photos','visitID'),(select value from m5_values where label='edit-payload'),
                                                                (select (value#>>'{}')::uuid from m5_values where label='edit-op'));
select is((select value->>'publicNote' from m5_values where label='edit-result'),'Edited memory','the owner edits the public note');
select is((select jsonb_agg(m->>'id' order by (m->>'position')::int) from m5_values, jsonb_array_elements(value->'media') m where label='edit-result'),
          jsonb_build_array(pg_temp.m5_media_id('first')::text,pg_temp.m5_media_id('post-photo')::text),'the edit keeps, reorders and adds inspected photos');
select is((select to_jsonb(published_at) from public.activities where id=pg_temp.m5_case('photos','activityID')),(select value from m5_values where label='published'),
          'editing a memory never moves the post''s publication time');
select is((select count(*)::int from public.activities where experience_id=pg_temp.m5_experience('photos')),1,'editing a memory publishes no new activity');
select is(public.update_visit(pg_temp.m5_case('photos','visitID'),(select value from m5_values where label='edit-payload'),(select (value#>>'{}')::uuid from m5_values where label='edit-op')),
          (select value from m5_values where label='edit-result'),'retrying the same edit returns the original acknowledged result');
select throws_ok(format('select public.update_visit(%L,%L::jsonb,%L)',pg_temp.m5_case('photos','visitID'),
                        jsonb_build_object('publicNote','Different change','mediaIDs','[]'::jsonb),(select value#>>'{}' from m5_values where label='edit-op')),
                 '23505',null,'one operation cannot be reused for a different edit');
select throws_ok(format('select public.update_visit(%L,%L::jsonb,%L)',pg_temp.m5_case('photos','visitID'),
                        jsonb_build_object('date','9999-01-01','publicNote','','mediaIDs','[]'::jsonb),gen_random_uuid()),
                 '22023',null,'a completed visit cannot move into the future');
select throws_ok(format('select public.update_visit(%L,%L::jsonb,%L)',pg_temp.m5_case('photos','visitID'),
                        jsonb_build_object('publicNote',repeat('x',5001),'mediaIDs','[]'::jsonb),gen_random_uuid()),
                 '22023',null,'public notes are limited to 5,000 characters');
select is(public.update_visit(pg_temp.m5_case('photos','visitID'),jsonb_build_object('date',null,'timeZoneIdentifier',null,'publicNote','Edited memory',
            'mediaIDs',jsonb_build_array(pg_temp.m5_media_id('first'),pg_temp.m5_media_id('post-photo'))),gen_random_uuid())->'visitDate'->>'date',
          null,'a visit date can be cleared to unknown');
select is((select date_precision from public.visits where id=pg_temp.m5_case('photos','visitID')),'unknown','an unknown date is stored as unknown, not fabricated');
select is(public.update_visit(pg_temp.m5_case('photos','visitID'),jsonb_build_object('date','2020-03-01','timeZoneIdentifier','Pacific/Kiritimati','publicNote','Edited memory',
            'mediaIDs',jsonb_build_array(pg_temp.m5_media_id('first'),pg_temp.m5_media_id('post-photo'))),gen_random_uuid())->'visitDate'->>'date',
          '2020-03-01','a destination time zone never shifts the stored calendar date');
set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok(format('select public.update_visit(%L,%L::jsonb,%L)',pg_temp.m5_case('photos','visitID'),
                        jsonb_build_object('publicNote','Hijacked','mediaIDs','[]'::jsonb),gen_random_uuid()),
                 '42501',null,'another member cannot edit the memory');
select is((select (elem->>'note') from jsonb_array_elements(public.experience_detail(pg_temp.m5_experience('photos'))->'publicActivity') elem limit 1),
          'Edited memory','the post projection shows the edited note without republishing');

-- 5. Private notes -----------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into m5_values values('note-op',to_jsonb(gen_random_uuid()::text));
select is(public.save_private_note(pg_temp.m5_experience('photos'),'secret-m5-note',(select (value#>>'{}')::uuid from m5_values where label='note-op'))->>'text',
          'secret-m5-note','the owner saves a private note');
select is(public.save_private_note(pg_temp.m5_experience('photos'),'secret-m5-note',(select (value#>>'{}')::uuid from m5_values where label='note-op'))->>'text',
          'secret-m5-note','retrying the same private-note save is idempotent');
select throws_ok(format('select public.save_private_note(%L,%L,%L)',pg_temp.m5_experience('photos'),'changed text',(select value#>>'{}' from m5_values where label='note-op')),
                 '23505',null,'one operation cannot save different private text');
select throws_ok(format('select public.save_private_note(%L,%L,%L)',pg_temp.m5_experience('photos'),repeat('p',10001),gen_random_uuid()),'22023',null,'private notes are limited to 10,000 characters');
select throws_ok(format('select public.save_private_note(%L,%L,%L)',pg_temp.m5_experience('photos'),'',gen_random_uuid()),'22023',null,'an empty private note is not saved');
select is(public.my_private_note(pg_temp.m5_experience('photos'))->>'text','secret-m5-note','the owner reads the private note');
select ok((public.experience_detail(pg_temp.m5_experience('photos'))->>'hasPrivateNote')::boolean
          and position('secret-m5-note' in public.experience_detail(pg_temp.m5_experience('photos'))::text)=0,
          'the owner''s detail flags the private note without serializing its text');
set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.my_private_note(pg_temp.m5_experience('photos')),null,'another member gets no private note');
select is((select count(*)::int from public.private_notes),0,'another member cannot select private notes directly');
select ok(position('secret-m5-note' in public.experience_detail(pg_temp.m5_experience('photos'))::text)=0
          and position('secret-m5-note' in public.public_memories(pg_temp.m5_experience('photos'))::text)=0
          and position('secret-m5-note' in public.visit(pg_temp.m5_case('photos','visitID'))::text)=0
          and not (public.experience_detail(pg_temp.m5_experience('photos'))->>'hasPrivateNote')::boolean,
          'public detail, memory and visit projections never contain or reveal the private note');
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into m5_values values('delete-note-op',to_jsonb(gen_random_uuid()::text));
select is(public.delete_private_note(pg_temp.m5_experience('photos'),(select (value#>>'{}')::uuid from m5_values where label='delete-note-op')),'{}'::jsonb,'the owner deletes the private note');
select is(public.my_private_note(pg_temp.m5_experience('photos')),null,'a deleted private note is gone');
select is(public.delete_private_note(pg_temp.m5_experience('photos'),(select (value#>>'{}')::uuid from m5_values where label='delete-note-op')),'{}'::jsonb,'retrying the deletion is safe');

-- 6. Public memories ---------------------------------------------------------------------------
reset role;
insert into public.visits(owner_id,experience_id,visit_date,date_precision,public_note,created_at)
values('e5000000-0000-4000-8000-000000000005',pg_temp.m5_experience('photos'),'2020-01-01','day','Deactivated author memory',now()-interval '1 day');
insert into public.visits(owner_id,experience_id,visit_date,date_precision,public_note,created_at)
select 'd5000000-0000-4000-8000-000000000004',pg_temp.m5_experience('photos'),null,'unknown','Paged memory '||n,now()-make_interval(hours=>n+2)
from generate_series(1,32) n;
set local role authenticated;
set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into m5_values select 'page1',public.public_memories(pg_temp.m5_experience('photos'),null);
select is((select jsonb_array_length(value->'items') from m5_values where label='page1'),30,'public memories page in 30s');
select ok((select value->'items'->0->>'publicNote'='Edited memory' and value->'items'->0->>'isOwn'='false'
                  and (value->'items'->0->>'activityID')::uuid=pg_temp.m5_case('photos','activityID') and jsonb_array_length(value->'items'->0->'media')=2
           from m5_values where label='page1'),'another member sees the newest memory with note, photos, author and its post');
select ok(not exists(select 1 from m5_values, jsonb_array_elements(value->'items') i where label='page1' and i->>'publicNote'='Deactivated author memory'),
          'a deactivated author''s memories are hidden');
insert into m5_values select 'page2',public.public_memories(pg_temp.m5_experience('photos'),(select value->>'nextCursor' from m5_values where label='page1'));
select is((select jsonb_array_length(value->'items') from m5_values where label='page2'),3,'the stable cursor returns exactly the remaining memories');
select is((select count(distinct i->>'id')::int from m5_values, jsonb_array_elements(value->'items') i where label in ('page1','page2')),33,'pages never overlap');
select is((select value->>'nextCursor' from m5_values where label='page2'),null,'the last page has no cursor');
select ok((select bool_and(((value->'items'->(n-1))->>'createdAt')::timestamptz>=((value->'items'->n)->>'createdAt')::timestamptz)
           from m5_values, generate_series(1,29) n where label='page1'),'memories are ordered newest first by creation');
select throws_ok(format('select public.public_memories(%L,%L)',pg_temp.m5_experience('photos'),'not-a-cursor'),'22023',null,'an invalid memory cursor is rejected');
set local request.jwt.claims to '{"sub":"c5000000-0000-4000-8000-000000000003","role":"authenticated"}';
select ok(not exists(select 1 from jsonb_array_elements(public.public_memories(pg_temp.m5_experience('photos'),null)->'items') i
                     where i->'author'->>'id'='a5000000-0000-4000-8000-000000000001'),'a blocked member never receives the blocker''s memories');
select throws_ok(format('select public.visit(%L)',pg_temp.m5_case('photos','visitID')),'P0002',null,'a blocked member cannot open the Visit');
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((public.public_memories(pg_temp.m5_experience('photos'),null)->'items'->0->>'isOwn')::boolean,true,'the owner''s memory is marked as their own');
select is(public.remove_rating(pg_temp.m5_experience('photos'),gen_random_uuid()),'{}'::jsonb,'the owner removes the ranking');
set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
select ok((select i->>'publicNote'='Edited memory' and jsonb_array_length(i->'media')=2 and i->'activityID'='null'::jsonb
           from jsonb_array_elements(public.public_memories(pg_temp.m5_experience('photos'),null)->'items') i
           where (i->>'id')::uuid=pg_temp.m5_case('photos','visitID')),'removing a ranking retains the populated public memory without its post');
select is((select count(*)::int from storage.objects where bucket_id='visit-media' and name=(select path from m5_media where label='first')),1,
          'retained memory photos stay readable through the Visit');
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.delete_visit(pg_temp.m5_case('photos','visitID'),gen_random_uuid(),false),'{"removedRating": false}'::jsonb,'deleting the retained Visit needs no rating consent');
select ok(not exists(select 1 from jsonb_array_elements(public.public_memories(pg_temp.m5_experience('photos'),null)->'items') i
                     where (i->>'id')::uuid=pg_temp.m5_case('photos','visitID')),'deleting a Visit removes its memory');
select is((select count(*)::int from public.media where id in (pg_temp.m5_media_id('first'),pg_temp.m5_media_id('post-photo'))),0,'deleting a Visit removes its photos');

-- 7. Standalone post removal -------------------------------------------------------------------
do $$begin perform pg_temp.m5_log('post','outdoors',jsonb_build_object('date','2020-06-01','timeZoneIdentifier','UTC','publicNote','Post memory','mediaIDs','[]'::jsonb)); end$$;
reset role;
insert into public.likes(actor_id,activity_id) values('b5000000-0000-4000-8000-000000000002',pg_temp.m5_case('post','activityID'));
insert into public.comments(activity_id,author_id,body,operation_id) values(pg_temp.m5_case('post','activityID'),'b5000000-0000-4000-8000-000000000002','Lovely',gen_random_uuid());
insert into public.notifications(recipient_id,actor_id,type,activity_id,event_key)
values('a5000000-0000-4000-8000-000000000001','b5000000-0000-4000-8000-000000000002','like',pg_temp.m5_case('post','activityID'),'like:m5:'||gen_random_uuid());
set local role authenticated;
set local request.jwt.claims to '{"sub":"b5000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok(format('select public.delete_activity(%L)',pg_temp.m5_case('post','activityID')),'42501',null,'another member cannot remove the post');
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.delete_activity(pg_temp.m5_case('post','activityID')),true,'the author removes the post');
select ok(exists(select 1 from public.ratings where id=pg_temp.m5_case('post','ratingID')) and exists(select 1 from public.visits where id=pg_temp.m5_case('post','visitID')),
          'removing a post keeps the Rating and Visit');
reset role;
select is((select count(*)::int from public.likes where activity_id=pg_temp.m5_case('post','activityID'))
          +(select count(*)::int from public.comments where activity_id=pg_temp.m5_case('post','activityID'))
          +(select count(*)::int from public.notifications where activity_id=pg_temp.m5_case('post','activityID')),0,
          'the removed post takes its likes, comments and notifications with it');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.delete_activity(pg_temp.m5_case('post','activityID')),false,'repeating the removal is a harmless no-op');
select ok((public.add_visit(jsonb_build_object('operationID',gen_random_uuid(),'experienceID',pg_temp.m5_experience('post'),
            'visit',jsonb_build_object('publicNote','Later visit','mediaIDs','[]'::jsonb)))->>'activityID') is not null,
          'automatic publication still happens for a later completion after a removed post');

-- 8. Storage delete policy and avatars ---------------------------------------------------------
select is(pg_temp.m5_delete_object((select path from m5_media where label='spare')),0,
          'a member cannot delete their registered upload behind the server''s back');
select is(pg_temp.m5_delete_object('a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000001.jpg'),0,
          'an object referenced by a media row is protected even when uninspected');
reset role;
insert into storage.objects(bucket_id,name,owner,metadata) values('visit-media','a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000009.jpg',
  'a5000000-0000-4000-8000-000000000001','{"size":10,"mimetype":"image/jpeg","eTag":"\"abandoned\""}');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(pg_temp.m5_delete_object('a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000009.jpg'),1,'a member can delete their own abandoned unregistered upload');
select throws_ok($$select public.update_profile('M5 Owner','m5_owner','',null,'avatars/a5000000-0000-4000-8000-000000000001/not-inspected.jpg')$$,'42501',null,
                 'an uninspected avatar cannot be published');
reset role;
do $$begin perform pg_temp.m5_upload('a5000000-0000-4000-8000-000000000001','avatar','avatar'); end$$;
set local role authenticated;
set local request.jwt.claims to '{"sub":"a5000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.update_profile('M5 Owner','m5_owner','',null,'avatars/'||(select path from m5_media where label='avatar'))->>'avatarPath',
          'avatars/'||(select path from m5_media where label='avatar'),'an inspected avatar is published');

-- 9. Durable cleanup ---------------------------------------------------------------------------
reset role;
set local storage.allow_delete_query = 'false';
-- Other local jobs are leased away inside this rolled-back transaction so assertions see only ours.
update app_private.storage_cleanup set claimed_by='99999999-0000-4000-8000-000000000000',lease_expires_at=now()+interval '1 hour' where done_at is null;
update public.media set expires_at=now()-interval '1 minute' where id=pg_temp.m5_media_id('tomb');
insert into storage.objects(bucket_id,name,owner,metadata,created_at) values('visit-media','a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000010.jpg',
  'a5000000-0000-4000-8000-000000000001','{"size":10,"mimetype":"image/jpeg","eTag":"\"orphan\""}',now()-interval '25 hours');
update storage.objects set created_at=now()-interval '25 hours' where bucket_id='avatars' and name=(select path from m5_media where label='avatar');
insert into m5_values select 'sweep',public.sweep_media_orphans();
select is((select count(*)::int from public.media where id=pg_temp.m5_media_id('tomb')),0,'the sweep deletes an expired staged upload');
select is((select reason from app_private.storage_cleanup where object_path=(select path from m5_media where label='tomb') and done_at is null),'media_removed',
          'an expired upload''s object is queued for durable deletion');
select is((select reason from app_private.storage_cleanup where object_path='a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000010.jpg'),'unregistered_upload',
          'a never-registered object older than 24 hours is queued');
select is((select count(*)::int from app_private.storage_cleanup where object_path in ((select path from m5_media where label='spare'),(select path from m5_media where label='avatar'))),0,
          'an unexpired staged upload and an old published avatar are not queued');
select throws_ok(format('select public.finalize_media_inspection(%L,%L,%L,640,480,2048,%L,%L)','a5000000-0000-4000-8000-000000000001',(select attempt from m5_media where label='tomb'),
                        'visit',encode(extensions.digest('tomb','sha256'),'hex'),(select etag from m5_media where label='tomb')),
                 '22023','roam:media_expired','a cleaned-up path is a tombstone and cannot be revived');
insert into m5_values select 'claim1',public.claim_media_cleanup('a1111111-0000-4000-8000-000000000000',100);
select ok((select bool_or(j->>'path'=(select path from m5_media where label='tomb')) and bool_or(j->>'path'='a5000000-0000-4000-8000-000000000001/f5000000-0000-4000-8000-000000000010.jpg')
           from m5_values, jsonb_array_elements(value) j where label='claim1'),'a worker claims expired and unregistered objects');
select is(jsonb_array_length(public.claim_media_cleanup('b2222222-0000-4000-8000-000000000000',100)),0,'a leased job is not claimed twice');
select is(public.finish_media_cleanup((select (j->>'id')::bigint from m5_values, jsonb_array_elements(value) j where label='claim1' and j->>'path'=(select path from m5_media where label='tomb')),
                                      'b2222222-0000-4000-8000-000000000000',null),false,'only the leasing worker can finish a job');
select is(public.finish_media_cleanup((select (j->>'id')::bigint from m5_values, jsonb_array_elements(value) j where label='claim1' and j->>'path'=(select path from m5_media where label='tomb')),
                                      'a1111111-0000-4000-8000-000000000000','Storage delete HTTP 503'),true,'a failed deletion is recorded for retry');
select ok((select done_at is null and attempts=1 and next_attempt_at>now() and last_error='Storage delete HTTP 503' and claimed_by is null
           from app_private.storage_cleanup where object_path=(select path from m5_media where label='tomb')),'a failed job backs off instead of being lost');
select ok(not exists(select 1 from jsonb_array_elements(public.claim_media_cleanup('b2222222-0000-4000-8000-000000000000',100)) j
                     where j->>'path'=(select path from m5_media where label='tomb')),'a backed-off job is not retried early');
update app_private.storage_cleanup set next_attempt_at=now()-interval '1 second' where object_path=(select path from m5_media where label='tomb');
insert into m5_values select 'claim2',public.claim_media_cleanup('c3333333-0000-4000-8000-000000000000',100);
select is(public.finish_media_cleanup((select (j->>'id')::bigint from m5_values, jsonb_array_elements(value) j where label='claim2' and j->>'path'=(select path from m5_media where label='tomb')),
                                      'c3333333-0000-4000-8000-000000000000',null),true,'a retried deletion completes');
select ok((select done_at is not null and attempts=2 from app_private.storage_cleanup where object_path=(select path from m5_media where label='tomb')),'completion is durable');
insert into app_private.storage_cleanup(bucket,object_path,reason) values('visit-media',(select path from m5_media where label='spare'),'manual');
select ok(not exists(select 1 from jsonb_array_elements(public.claim_media_cleanup('d4444444-0000-4000-8000-000000000000',100)) j
                     where j->>'path'=(select path from m5_media where label='spare')),'a job for a still-registered object is never claimed');

select * from finish();
rollback;
