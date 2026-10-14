-- M6: follow graph, chronological feed and cursors, following score, likes, flat comments,
-- mute (feed only), block (mutual exclusion everywhere), Shared Want to Go and notifications.
begin;
create extension if not exists pgtap with schema extensions;
select plan(97);

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, '', now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now()
from (values ('a6000000-0000-4000-8000-000000000001'::uuid, 'm6-author@test.local'),
             ('b6000000-0000-4000-8000-000000000002'::uuid, 'm6-follower@test.local'),
             ('c6000000-0000-4000-8000-000000000003'::uuid, 'm6-blocked@test.local'),
             ('d6000000-0000-4000-8000-000000000004'::uuid, 'm6-other@test.local'),
             ('e6000000-0000-4000-8000-000000000005'::uuid, 'm6-muter@test.local')) u(id,email);
insert into public.profiles(id,handle,display_name) values
  ('a6000000-0000-4000-8000-000000000001','m6_author','M6 Author'),
  ('b6000000-0000-4000-8000-000000000002','m6_follower','M6 Follower'),
  ('c6000000-0000-4000-8000-000000000003','m6_blocked','M6 Blocked'),
  ('d6000000-0000-4000-8000-000000000004','m6_other','M6 Other'),
  ('e6000000-0000-4000-8000-000000000005','m6_muter','M6 Muter');

create temporary table m6_ids(label text primary key, id uuid) on commit drop;
create temporary table m6_values(label text primary key, value jsonb) on commit drop;
grant select,insert,update on m6_ids, m6_values to authenticated;
create function pg_temp.m6_id(p_label text) returns uuid language sql as $$select id from m6_ids where label=p_label$$;
grant execute on function pg_temp.m6_id(text) to authenticated;

-- Places and posts with controlled publication times (the feed orders by publication, not visit date).
create function pg_temp.m6_place(p_label text) returns uuid language plpgsql as $$
declare v_place uuid:=gen_random_uuid(); v_experience uuid:=gen_random_uuid();
begin
  insert into public.places(id,provider,name,normalized_name,latitude,longitude) values(v_place,'mapkit','M6 '||p_label,'m6 '||p_label,40.4,-3.7);
  insert into public.experiences(id,place_id,category) values(v_experience,v_place,'culture');
  insert into m6_ids values(p_label,v_experience);
  return v_experience;
end$$;
create function pg_temp.m6_post(p_label text, p_author uuid, p_experience uuid, p_age interval, p_visit_date date default null)
returns uuid language plpgsql as $$
declare v_visit uuid; v_activity uuid;
begin
  insert into public.visits(owner_id,experience_id,visit_date,date_precision,public_note)
  values(p_author,p_experience,p_visit_date,case when p_visit_date is null then 'unknown' else 'day' end,'Note '||p_label) returning id into v_visit;
  insert into public.activities(author_id,type,experience_id,visit_id,category,score_snapshot,published_at,source_operation_id)
  values(p_author,'revisit',p_experience,v_visit,'culture',8.4,now()-p_age,gen_random_uuid()) returning id into v_activity;
  insert into m6_ids values(p_label,v_activity);
  return v_activity;
end$$;
do $$begin
  perform pg_temp.m6_place('x'); perform pg_temp.m6_place('y'); perform pg_temp.m6_place('z');
  perform pg_temp.m6_post('a-old','a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('x'),'3 hours');
  perform pg_temp.m6_post('a-new','a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('y'),'1 hour');
  perform pg_temp.m6_post('a-backdated','a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('z'),'30 minutes','2001-02-03');
  perform pg_temp.m6_post('b-own','b6000000-0000-4000-8000-000000000002',pg_temp.m6_id('x'),'2 hours');
  perform pg_temp.m6_post('d-unfollowed','d6000000-0000-4000-8000-000000000004',pg_temp.m6_id('x'),'10 minutes');
end$$;

create function pg_temp.m6_as(p_user uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims',json_build_object('sub',p_user,'role','authenticated')::text,true); end$$;
grant execute on function pg_temp.m6_as(uuid) to authenticated;
create function pg_temp.m6_feed_labels(p_page jsonb) returns text[] language sql as $$
  select array_agg(l.label order by i.ordinal) from jsonb_array_elements(p_page->'items') with ordinality i(value,ordinal)
  join m6_ids l on l.id=(i.value->>'id')::uuid
$$;
grant execute on function pg_temp.m6_feed_labels(jsonb) to authenticated;

-- 1. Privileges ---------------------------------------------------------------------------------
select ok(not has_function_privilege('anon','public.feed(text)','execute') and not has_function_privilege('anon','public.set_block(uuid,boolean)','execute')
          and not has_function_privilege('anon','public.notifications(text)','execute') and not has_function_privilege('anon','public.post_comment(uuid,text,uuid)','execute'),
          'anonymous callers have no social RPCs');
select ok(not has_function_privilege('authenticated','app_private.follow_page(uuid,boolean,text,text)','execute')
          and not has_function_privilege('authenticated','app_private.notification_json(uuid,uuid)','execute')
          and not has_function_privilege('authenticated','app_private.comment_json(uuid,uuid)','execute'),
          'members cannot call private serializers directly');

-- 2. Follow graph -------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select throws_ok($$select public.set_follow('b6000000-0000-4000-8000-000000000002',true)$$,'22023',null,'members cannot follow themselves');
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',true),true,'a member follows another');
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',true),true,'repeating a follow is a harmless desired state');
select is((select count(*)::int from public.follows where follower_id='b6000000-0000-4000-8000-000000000002' and followee_id='a6000000-0000-4000-8000-000000000001'),1,
          'a follow is one directional edge');
select is((public.public_profile('a6000000-0000-4000-8000-000000000001')->>'followerCount')::int,1,'follower counts persist');
select is((public.public_profile('a6000000-0000-4000-8000-000000000001')->'relationship'->>'followsViewer')::boolean,false,'follows are one-way');
set local request.jwt.claims to '{"sub":"e6000000-0000-4000-8000-000000000005","role":"authenticated"}';
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',true),true,'a second member follows the author');
set local request.jwt.claims to '{"sub":"c6000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',true),true,'the soon-blocked member follows the author');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.set_follow('c6000000-0000-4000-8000-000000000003',true),true,'the author follows back');
select is((select count(*)::int from public.notifications where recipient_id='a6000000-0000-4000-8000-000000000001' and type='follow'),3,
          'each new follower creates exactly one follow notification');
select is((select jsonb_agg(i->'member'->>'handle' order by ordinal) from jsonb_array_elements(public.followers('a6000000-0000-4000-8000-000000000001','',null)->'items') with ordinality t(i,ordinal)),
          '["m6_blocked","m6_follower","m6_muter"]'::jsonb,'followers are visible members in stable handle order');
select is((select jsonb_agg(i->'member'->>'handle') from jsonb_array_elements(public.followers('a6000000-0000-4000-8000-000000000001','MUT',null)->'items') i),
          '["m6_muter"]'::jsonb,'follower search is a case-insensitive literal filter');
select ok((public.followers('a6000000-0000-4000-8000-000000000001','m6_follower',null)->'items'->0->>'followsViewer')::boolean
          and not (public.followers('a6000000-0000-4000-8000-000000000001','m6_follower',null)->'items'->0->>'isFollowing')::boolean,
          'rows report follow state both ways (follows you, not followed back)');
select is((public.following('a6000000-0000-4000-8000-000000000001','',null)->'items'->0->'member'->>'handle'),'m6_blocked','following lists the members someone follows');

-- 3. Feed ----------------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into m6_values select 'feed',public.feed(null);
select is(pg_temp.m6_feed_labels((select value from m6_values where label='feed')),array['a-backdated','a-new','b-own','a-old'],
          'the feed holds own and followed posts by publication time, including an old visit date posted recently');
select ok(not ('d-unfollowed'=any(pg_temp.m6_feed_labels((select value from m6_values where label='feed')))),'unfollowed members never appear');
select is((select value->'items'->0->>'scoreSnapshot' from m6_values where label='feed'),'8.4','cards carry the score at posting');
reset role;
do $$begin for n in 1..33 loop perform pg_temp.m6_post('page-'||n,'a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('x'),make_interval(days=>n)); end loop; end$$;
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into m6_values select 'page1',public.feed(null);
insert into m6_values select 'page2',public.feed((select value->>'nextCursor' from m6_values where label='page1'));
select is((select jsonb_array_length(value->'items') from m6_values where label='page1'),30,'feed pages hold 30 posts');
select is((select jsonb_array_length(value->'items') from m6_values where label='page2'),7,'the cursor returns exactly the remaining posts');
select is((select count(distinct i->>'id')::int from m6_values, jsonb_array_elements(value->'items') i where label in ('page1','page2')),37,'feed pages never overlap');
select ok((select bool_and((value->'items'->(n-1)->>'publishedAt')::timestamptz>=(value->'items'->n->>'publishedAt')::timestamptz)
           from m6_values, generate_series(1,29) n where label='page1'),'each page is ordered newest first');
select throws_ok($$select public.feed('not-a-cursor')$$,'22023',null,'an invalid cursor is rejected, not treated as the first page');
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',false),false,'a member unfollows');
select is(pg_temp.m6_feed_labels(public.feed(null)),array['b-own'],'unfollowing removes that member''s posts immediately');
select is(public.set_follow('a6000000-0000-4000-8000-000000000001',true),true,'following again restores the eligible history');

-- 4. Mute is feed-only --------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"e6000000-0000-4000-8000-000000000005","role":"authenticated"}';
select is(public.set_mute('a6000000-0000-4000-8000-000000000001',true),true,'a member mutes someone they follow');
select is(jsonb_array_length(public.feed(null)->'items'),0,'muted members disappear from the feed');
select ok(jsonb_array_length(public.profile_activity('a6000000-0000-4000-8000-000000000001',null)->'items')>0,'a muted member''s profile still shows their posts');
select is((public.public_profile('a6000000-0000-4000-8000-000000000001')->'relationship'->>'isFollowing')::boolean,true,'muting keeps the follow');
select is((select jsonb_agg(m->>'handle') from jsonb_array_elements(public.muted_members()) m),'["m6_author"]'::jsonb,'the muter sees their muted list');
select is(public.set_mute('a6000000-0000-4000-8000-000000000001',false),false,'unmuting');
select ok(jsonb_array_length(public.feed(null)->'items')>0,'unmuting restores eligible feed history');

-- 5. Following score ----------------------------------------------------------------------------
reset role;
insert into public.ratings(owner_id,experience_id,category,sentiment,group_position,score,rank)
values('a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('x'),'culture','liked',0,8.4,1),
      ('d6000000-0000-4000-8000-000000000004',pg_temp.m6_id('x'),'culture','fine',0,5.0,1);
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.set_follow('d6000000-0000-4000-8000-000000000004',true),true,'following a second rater');
select is((public.experience_detail(pg_temp.m6_id('x'))->'summary'->>'followingScore')::numeric,6.7,'the Following score is the mean of one rating per followed member');
select is((public.experience_detail(pg_temp.m6_id('x'))->'summary'->>'followingCount')::int,2,'the rater count is distinct followed members');
reset role;
insert into public.visits(owner_id,experience_id,visit_date,date_precision) values('a6000000-0000-4000-8000-000000000001',pg_temp.m6_id('x'),'2020-01-01','day');
update public.ratings set score=10.0 where owner_id='a6000000-0000-4000-8000-000000000001' and experience_id=pg_temp.m6_id('x');
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is((public.experience_detail(pg_temp.m6_id('x'))->'summary'->>'followingCount')::int,2,'repeat visits never add samples');
select is((public.experience_detail(pg_temp.m6_id('x'))->'summary'->>'followingScore')::numeric,7.5,'a re-ranked score is reflected');
select is(public.set_follow('d6000000-0000-4000-8000-000000000004',false),false,'unfollowing a rater');
select is((public.experience_detail(pg_temp.m6_id('x'))->'summary'->>'followingScore')::numeric,10.0,'unfollowing recomputes the score');
reset role;
delete from public.ratings where owner_id='a6000000-0000-4000-8000-000000000001' and experience_id=pg_temp.m6_id('x');
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.experience_detail(pg_temp.m6_id('x'))->'summary'->'followingScore','null'::jsonb,'with zero raters there is no score, not zero');

-- 6. Likes and notifications -------------------------------------------------------------------
select is(public.set_like(pg_temp.m6_id('a-new'),true),true,'a follower likes a post');
select is(public.set_like(pg_temp.m6_id('a-new'),true),true,'liking again is a harmless desired state');
select is((public.activity(pg_temp.m6_id('a-new'))->>'likeCount')::int,1,'one like per member and post');
select is((public.activity(pg_temp.m6_id('a-new'))->>'likedByViewer')::boolean,true,'the viewer''s like state is reported');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.set_like(pg_temp.m6_id('a-new'),true),true,'authors may like their own post');
select is((select count(*)::int from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='like'),1,
          'one like notification; self-likes notify no one');
select is((select n->>'experienceName' from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='like'),'M6 y',
          'a like notification names the place');
select is(public.unread_notification_count(),4,'unread count covers the follow and like events');
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.set_like(pg_temp.m6_id('a-new'),false),false,'unliking');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='like'),0,'an undone like removes its notification');
reset role;
insert into public.user_settings(user_id,notify_likes) values('a6000000-0000-4000-8000-000000000001',false)
on conflict(user_id) do update set notify_likes=false;
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.set_like(pg_temp.m6_id('a-old'),true),true,'another like after the author turned like notifications off');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='like'),0,'recipient preferences govern new notifications');
insert into m6_values select 'first-note',public.notifications(null)->'items'->0;
select lives_ok(format('select public.mark_notification_read(%L)',(select value->>'id' from m6_values where label='first-note')),'a notification is marked read on open');
select ok((select (n->>'readAt') is not null from jsonb_array_elements(public.notifications(null)->'items') n where n->>'id'=(select value->>'id' from m6_values where label='first-note')),
          'read state persists');
select lives_ok($$select public.mark_all_notifications_read()$$,'mark all read');
select is(public.unread_notification_count(),0,'nothing is unread after mark all');

-- 7. Comments -----------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into m6_values values('comment-op',to_jsonb(gen_random_uuid()::text));
insert into m6_values select 'comment',public.post_comment(pg_temp.m6_id('a-new'),'Great tip!',(select (value#>>'{}')::uuid from m6_values where label='comment-op'));
select is((select value->>'body' from m6_values where label='comment'),'Great tip!','a follower comments');
select is(public.post_comment(pg_temp.m6_id('a-new'),'Great tip!',(select (value#>>'{}')::uuid from m6_values where label='comment-op'))->>'id',
          (select value->>'id' from m6_values where label='comment'),'retrying the same comment operation never duplicates it');
select throws_ok(format('select public.post_comment(%L,%L,%L)',pg_temp.m6_id('a-new'),'Different words',(select value#>>'{}' from m6_values where label='comment-op')),
                 '23505',null,'one comment operation cannot post different text');
select throws_ok(format('select public.post_comment(%L,%L,%L)',pg_temp.m6_id('a-new'),'   ',gen_random_uuid()),'22023',null,'whitespace-only comments are rejected');
select throws_ok(format('select public.post_comment(%L,%L,%L)',pg_temp.m6_id('a-new'),repeat('c',2001),gen_random_uuid()),'22023',null,'comments are limited to 2,000 characters');
set local request.jwt.claims to '{"sub":"d6000000-0000-4000-8000-000000000004","role":"authenticated"}';
select is((public.comments(pg_temp.m6_id('a-new'),null)->'items'->0->>'body'),'Great tip!','other members read the flat comment list');
select is((public.activity(pg_temp.m6_id('a-new'))->>'commentCount')::int,1,'the post counts its comment');
select throws_ok(format('select public.delete_comment(%L)',(select value->>'id' from m6_values where label='comment')),'42501',null,'only the comment''s author can delete it');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select n->>'commentPreview' from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='comment'),'Great tip!','the author is notified with a preview');
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(public.delete_comment((select (value->>'id')::uuid from m6_values where label='comment')),true,'the comment author deletes it');
select is((public.activity(pg_temp.m6_id('a-new'))->>'commentCount')::int,0,'deleting updates the count');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select count(*)::int from jsonb_array_elements(public.notifications(null)->'items') n where n->>'type'='comment'),0,'a deleted comment takes its notification with it');
reset role;
insert into public.comments(activity_id,author_id,body,operation_id,created_at)
select pg_temp.m6_id('a-old'),'d6000000-0000-4000-8000-000000000004','Comment '||n,gen_random_uuid(),now()-make_interval(mins=>40-n) from generate_series(1,31) n;
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
insert into m6_values select 'comments1',public.comments(pg_temp.m6_id('a-old'),null);
select is((select jsonb_array_length(value->'items') from m6_values where label='comments1'),30,'comments page in 30s');
select is((select value->'items'->0->>'body' from m6_values where label='comments1'),'Comment 1','comments read oldest first');
select is(jsonb_array_length(public.comments(pg_temp.m6_id('a-old'),(select value->>'nextCursor' from m6_values where label='comments1'))->'items'),1,
          'the comment cursor returns the remainder');

-- 8. Shared Want to Go --------------------------------------------------------------------------
reset role;
insert into public.bookmarks(owner_id,experience_id,saved_at) values
  ('b6000000-0000-4000-8000-000000000002',pg_temp.m6_id('y'),now()-interval '2 days'),
  ('b6000000-0000-4000-8000-000000000002',pg_temp.m6_id('z'),now()-interval '1 day'),
  ('d6000000-0000-4000-8000-000000000004',pg_temp.m6_id('z'),now()-interval '5 days'),
  ('d6000000-0000-4000-8000-000000000004',pg_temp.m6_id('x'),now()-interval '5 days');
set local role authenticated;
set local request.jwt.claims to '{"sub":"b6000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is((select jsonb_agg(e->'experience'->>'id') from jsonb_array_elements(public.shared_wants('d6000000-0000-4000-8000-000000000004')) e),
          jsonb_build_array(pg_temp.m6_id('z')::text),'Shared Want to Go is the exact intersection of Experience IDs');
select is(public.set_bookmark(pg_temp.m6_id('z'),false),false,'removing a bookmark');
select is(jsonb_array_length(public.shared_wants('d6000000-0000-4000-8000-000000000004')),0,'the intersection follows bookmark changes');
select throws_ok($$select public.shared_wants('b6000000-0000-4000-8000-000000000002')$$,'22023',null,'there is no shared list with yourself');

-- 9. Block --------------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"c6000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(public.set_like(pg_temp.m6_id('a-backdated'),true),true,'a member likes before being blocked');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is(public.set_block('c6000000-0000-4000-8000-000000000003',true),true,'the author blocks a member');
select is((select count(*)::int from public.follows where (follower_id='a6000000-0000-4000-8000-000000000001' and followee_id='c6000000-0000-4000-8000-000000000003')
                                                     or (follower_id='c6000000-0000-4000-8000-000000000003' and followee_id='a6000000-0000-4000-8000-000000000001')),0,
          'blocking removes both follow edges');
select ok(not exists(select 1 from jsonb_array_elements(public.notifications(null)->'items') n where n->'actor'->>'id'='c6000000-0000-4000-8000-000000000003'),
          'the blocked member''s notifications are hidden');
select is((public.activity(pg_temp.m6_id('a-backdated'))->>'likeCount')::int,0,'the blocked member''s like no longer counts for the author');
select throws_ok($$select public.public_profile('c6000000-0000-4000-8000-000000000003')$$,'P0002',null,'the blocker cannot open the blocked profile');
set local request.jwt.claims to '{"sub":"c6000000-0000-4000-8000-000000000003","role":"authenticated"}';
select is(jsonb_array_length(public.feed(null)->'items'),0,'the blocked member''s feed excludes the blocker');
select throws_ok(format('select public.activity(%L)',pg_temp.m6_id('a-new')),'P0002','roam:unavailable','the blocked member cannot open the blocker''s post');
select throws_ok(format('select public.set_like(%L,true)',pg_temp.m6_id('a-new')),'P0002','roam:unavailable','or like it');
select throws_ok(format('select public.post_comment(%L,%L,%L)',pg_temp.m6_id('a-new'),'Hello',gen_random_uuid()),'P0002','roam:unavailable','or comment on it');
select throws_ok($$select public.public_profile('a6000000-0000-4000-8000-000000000001')$$,'P0002',null,'or open the blocker''s profile');
select throws_ok($$select public.want_list('a6000000-0000-4000-8000-000000000001')$$,'P0002',null,'or read the blocker''s lists');
select throws_ok($$select public.shared_wants('a6000000-0000-4000-8000-000000000001')$$,'P0002',null,'or compare Want to Go lists');
select throws_ok($$select public.set_follow('a6000000-0000-4000-8000-000000000001',true)$$,'P0002',null,'or follow again');
select ok(not exists(select 1 from jsonb_array_elements(public.search_members('m6_author',null)->'items') i where i->'member'->>'handle'='m6_author'),
          'member search excludes the blocker');
set local request.jwt.claims to '{"sub":"a6000000-0000-4000-8000-000000000001","role":"authenticated"}';
select is((select jsonb_agg(m->>'handle') from jsonb_array_elements(public.blocked_members()) m),'["m6_blocked"]'::jsonb,'the blocker sees their blocked list');
select is(public.set_block('c6000000-0000-4000-8000-000000000003',false),false,'unblocking');
select is((select count(*)::int from public.follows where follower_id in ('a6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000003')
                                                    and followee_id in ('a6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000003')),0,
          'unblocking does not restore follows');
select ok((public.public_profile('c6000000-0000-4000-8000-000000000003')->'member'->>'handle')='m6_blocked','unblocking restores visibility');

reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select throws_ok($$select public.feed(null)$$,'42501',null,'anonymous callers cannot read the feed');
reset role;

select * from finish();
rollback;
