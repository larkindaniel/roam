-- Roam's suggestions (#4): a fixed set of people and places with the order each surface must give, and proof that
-- Only me entries, blocked people (either way), deactivated accounts and former friends never change a score, a
-- count or a reason line.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(55);

-- People ----------------------------------------------------------------------------------------------------------
-- viewer · friends Maya, Theo, Pia (only shares Only me) · strangers S1–S5 who post publicly · Bex (a friend the viewer
-- has blocked) · Bo (a friend who blocked the viewer) · Dee (a deactivated friend) · Lu (a former friend who shared a list)
do $$
declare u record;
begin
  for u in select * from (values
    ('a8000000-0000-4000-8000-000000000001'::uuid,'viewer8','Vic Viewer'),('a8000000-0000-4000-8000-000000000002'::uuid,'maya8','Maya Ito'),
    ('a8000000-0000-4000-8000-000000000003'::uuid,'theo8','Theo Park'),('a8000000-0000-4000-8000-000000000004'::uuid,'pia8','Pia Private'),
    ('a8000000-0000-4000-8000-000000000005'::uuid,'s1_8','Sol One'),('a8000000-0000-4000-8000-000000000006'::uuid,'s2_8','Sol Two'),
    ('a8000000-0000-4000-8000-000000000007'::uuid,'s3_8','Sol Three'),('a8000000-0000-4000-8000-000000000008'::uuid,'bex8','Bex Blocked'),
    ('a8000000-0000-4000-8000-000000000009'::uuid,'bo8','Bo Blocker'),('a8000000-0000-4000-8000-00000000000a'::uuid,'dee8','Dee Gone'),
    ('a8000000-0000-4000-8000-00000000000b'::uuid,'lu8','Lu Former'),('a8000000-0000-4000-8000-00000000000c'::uuid,'s4_8','Sol Four'),
    ('a8000000-0000-4000-8000-00000000000d'::uuid,'s5_8','Sol Five')) t(id,handle,name) loop
    insert into auth.users(id,email,aud,role,instance_id) values(u.id,u.handle||'@test.local','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
    insert into public.profiles(id,handle,display_name,setup_checkpoint) values(u.id,u.handle,u.name,'complete');
  end loop;
end $$;
create function pg_temp.id(p text) returns uuid language sql immutable as $f$
  select ('a8000000-0000-4000-8000-0000000000'||lpad(case p when 'viewer' then '01' when 'maya' then '02' when 'theo' then '03' when 'pia' then '04'
    when 's1' then '05' when 's2' then '06' when 's3' then '07' when 'bex' then '08' when 'bo' then '09' when 'dee' then '0a' when 'lu' then '0b' when 's4' then '0c' when 's5' then '0d' end,2,'0'))::uuid $f$;
grant execute on function pg_temp.id(text) to authenticated;
-- Friendships (both directions) with everyone but the strangers.
insert into public.follows(follower_id,followee_id)
  select pg_temp.id('viewer'),pg_temp.id(f) from unnest(array['maya','theo','pia','bex','bo','dee']) f
  union all select pg_temp.id(f),pg_temp.id('viewer') from unnest(array['maya','theo','pia','bex','bo','dee']) f;

-- Places ----------------------------------------------------------------------------------------------------------
insert into public.countries(code,name) values('PT','Portugal'),('JP','Japan'),('ES','Spain'),('CA','Canada') on conflict do nothing;
create temp table c8(label text primary key, id uuid not null default gen_random_uuid());
insert into c8(label) values('Lisbon'),('Porto'),('Tokyo'),('Madrid'),('Toronto');
insert into public.cities(id,city_key,name,region,country_code,latitude,longitude) select id, 'test8|'||label, label, null,
  case label when 'Lisbon' then 'PT' when 'Porto' then 'PT' when 'Tokyo' then 'JP' when 'Madrid' then 'ES' else 'CA' end,
  case label when 'Lisbon' then 38.72 when 'Porto' then 41.15 when 'Tokyo' then 35.68 when 'Madrid' then 40.42 else 43.65 end,
  case label when 'Lisbon' then -9.14 when 'Porto' then -8.61 when 'Tokyo' then 139.69 when 'Madrid' then -3.70 else -79.38 end from c8;
create temp table p8(label text primary key, place uuid not null default gen_random_uuid(), experience uuid not null default gen_random_uuid(),
  city text not null, category public.experience_category not null, google numeric, ptype text);
insert into p8(label,city,category,google,ptype) values
  ('Cafe Sent','Lisbon','food_drink',4.2,'MKPOICategoryCafe'),('Crowd Favourite','Lisbon','activities',4.6,null),
  ('Fine Diner','Lisbon','food_drink',4.1,'MKPOICategoryRestaurant'),('Garden Listed','Lisbon','outdoors',4.4,null),('Bar Loved','Lisbon','nightlife',4.0,null),
  ('Museum Been','Lisbon','culture',4.5,null),('Popular Spot','Lisbon','activities',4.8,null),('Disliked Diner','Lisbon','food_drink',4.9,'MKPOICategoryRestaurant'),
  ('Private Pick','Lisbon','culture',4.9,null),('Blocked Fave','Lisbon','culture',4.9,null),('Later Logged','Lisbon','culture',4.9,null),
  ('Porto One','Porto','food_drink',null,'MKPOICategoryCafe'),('Porto Two','Porto','food_drink',null,'MKPOICategoryCafe'),
  ('Porto Three','Porto','food_drink',null,'MKPOICategoryCafe'),
  ('Madrid Plaza','Madrid','culture',4.1,null),('Toronto Bakery','Toronto','food_drink',4.3,null);
grant select on p8, c8 to authenticated;
insert into public.places(id,name,normalized_name,latitude,longitude,provider,provider_place_id,locality,country_code,country_name,city_id,google_rating,provider_category)
  select p.place,p.label,lower(p.label),c.latitude+0.001*row_number() over (),c.longitude,'fixture','test8-'||p.label,p.city,c.country_code,
         (select name from public.countries where code=c.country_code),c.id,p.google,p.ptype
  from p8 p join c8 k on k.label=p.city join public.cities c on c.id=k.id;
insert into public.experiences(id,place_id,category) select experience,place,category from p8;
create function pg_temp.exp(p text) returns uuid language sql stable as $f$ select experience from p8 where label=p $f$;
grant execute on function pg_temp.exp(text) to authenticated;

-- Logs: a visit (which sets the rating's audience), then optionally a rating.
create function pg_temp.log(who text, p_place text, p_audience text, p_sentiment public.sentiment default null, p_score numeric default 5) returns void language plpgsql as $f$
begin
  insert into public.visits(owner_id,experience_id,visit_date,date_precision,audience) values(pg_temp.id(who),pg_temp.exp(p_place),null,'unknown',p_audience);
  if p_sentiment is not null then
    insert into public.ratings(owner_id,experience_id,category,sentiment,group_position,score,rank)
      select pg_temp.id(who),pg_temp.exp(p_place),p8.category,p_sentiment,0,p_score,1 from p8 where label=p_place;
  end if;
end $f$;

-- What the viewer's friends and Roam know before any noise is added.
select pg_temp.log('maya','Bar Loved','friends','liked',9);
select pg_temp.log('theo','Bar Loved','public','liked',8);
select pg_temp.log('maya','Museum Been','friends');
select pg_temp.log('s1','Popular Spot','public','liked',8);
select pg_temp.log('s2','Popular Spot','public','liked',8);
select pg_temp.log('s3','Popular Spot','public','fine',6);
select pg_temp.log(w,'Crowd Favourite','public','liked',8) from unnest(array['s1','s2','s3','s4','s5']) w;
select pg_temp.log('s1','Fine Diner','public','fine',5);
select pg_temp.log('theo','Disliked Diner','public','disliked',2);
select pg_temp.log('maya','Later Logged','public','liked',9);
select pg_temp.log('maya','Madrid Plaza','friends');
select pg_temp.log('theo','Toronto Bakery','public','liked',9);
-- The viewer: three Liked cafés in Porto, so they lean to food and drink, and to cafés in particular.
select pg_temp.log('viewer','Porto One','only_me','liked',9);
select pg_temp.log('viewer','Porto Two','only_me','liked',8);
select pg_temp.log('viewer','Porto Three','only_me','liked',7);
-- Theo sends Cafe Sent; Maya shares her Lisbon list with Garden Listed on it.
insert into public.direct_shares(sender_id,recipient_id,experience_id,operation_id) values(pg_temp.id('theo'),pg_temp.id('viewer'),pg_temp.exp('Cafe Sent'),gen_random_uuid());
insert into public.lists(id,owner_id,title) values('a8000000-0000-4000-8000-0000000000f1','a8000000-0000-4000-8000-000000000002','Lisbon');
insert into public.list_items(list_id,experience_id) values('a8000000-0000-4000-8000-0000000000f1',pg_temp.exp('Garden Listed'));
insert into public.direct_shares(sender_id,recipient_id,list_id,operation_id) values(pg_temp.id('maya'),pg_temp.id('viewer'),'a8000000-0000-4000-8000-0000000000f1',gen_random_uuid());
-- Home in Toronto, Madrid on the wishlist, Tokyo on an upcoming trip.
insert into public.home_cities(owner_id,city_id) select pg_temp.id('viewer'),id from c8 where label='Toronto';
insert into public.saved_cities(owner_id,city_id) select pg_temp.id('viewer'),id from c8 where label='Madrid';
insert into public.trips(id,owner_id,name,start_date,end_date,status) values('a8000000-0000-4000-8000-0000000000f2',pg_temp.id('viewer'),'Japan trip',current_date+30,current_date+40,'upcoming');
insert into public.trip_cities(trip_id,city_id) select 'a8000000-0000-4000-8000-0000000000f2',id from c8 where label='Tokyo';
-- Already blocked or gone before anything is read: Bex (blocked by the viewer, the friendship rows left in place to
-- prove the block alone is enough), Bo (blocked the viewer), Dee (deactivated).
insert into public.blocks(blocker_id,blocked_id) values(pg_temp.id('viewer'),pg_temp.id('bex')),(pg_temp.id('bo'),pg_temp.id('viewer'));
update public.profiles set deactivated_at=now() where id=pg_temp.id('dee');

create temp table r8(label text primary key, value jsonb);
grant all on r8 to authenticated;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true); end $f$;
grant execute on function pg_temp.as_user(uuid) to authenticated;
create function pg_temp.names(j jsonb) returns text[] language sql immutable as $f$ select coalesce(array_agg(coalesce(e->'experience'->>'name',e->>'name') order by o),'{}') from jsonb_array_elements(j) with ordinality t(e,o) $f$;
create function pg_temp.cities(j jsonb) returns text[] language sql immutable as $f$ select coalesce(array_agg(e->'destination'->>'name' order by o),'{}') from jsonb_array_elements(j) with ordinality t(e,o) $f$;
create function pg_temp.place(j jsonb, n text) returns jsonb language sql immutable as $f$ select e from jsonb_array_elements(j) e where e->'experience'->>'name'=n $f$;
grant execute on function pg_temp.names(jsonb),pg_temp.cities(jsonb),pg_temp.place(jsonb,text) to authenticated;
create function pg_temp.lisbon() returns jsonb language sql stable as $f$ select public.suggested_places(38.5,39.0,-9.5,-8.9) $f$;
grant execute on function pg_temp.lisbon() to authenticated;

-- The fixed order ---------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user(pg_temp.id('viewer'));
insert into r8 values('places',pg_temp.lisbon()),('cities',public.suggested_cities()),('portugal',public.suggested_cities('pt')),
  ('onboarding',public.onboarding_places(38.5,39.0,-9.5,-8.9));
select is(pg_temp.names((select value from r8 where label='places')),
  array['Cafe Sent','Bar Loved','Garden Listed','Later Logged','Crowd Favourite','Museum Been','Fine Diner','Popular Spot'],
  'Lisbon: sent café (40 + 10 taste), two friends loved (30), shared list (25), one loved (15), then popular, been and half-taste (5 each, Google breaks the tie), then 3 keen ratings (0)');
select is((pg_temp.place((select value from r8 where label='places'),'Cafe Sent')->>'points')::numeric,50.0,'a sent food place in a food lover''s list scores 40 + 10');
select is((pg_temp.place((select value from r8 where label='places'),'Bar Loved')->>'points')::numeric,30.0,'two friends who loved it score 15 each');
select is((pg_temp.place((select value from r8 where label='places'),'Garden Listed')->>'points')::numeric,25.0,'a place on a shared list scores 25');
select is(pg_temp.cities((select value from r8 where label='cities')),array['Lisbon','Tokyo','Madrid'],
  'Discover: Lisbon''s best five places (125), then the trip city (30), then the saved city a friend has been to (15)');
select ok(not ('Toronto'=any(pg_temp.cities((select value from r8 where label='cities')))),'your home city is never pitched as a trip idea');
select ok(not ('Porto'=any(pg_temp.cities((select value from r8 where label='cities')))),'nor a city you''ve been to');
select is(pg_temp.cities((select value from r8 where label='portugal')),array['Lisbon'],'a country page only suggests its own cities');
select is((select e->'evidence'->>'tripName' from jsonb_array_elements((select value from r8 where label='cities')) e where e->'destination'->>'name'='Tokyo'),
  'Japan trip','a trip city says which trip');

-- Reason-line facts --------------------------------------------------------------------------------------------------
select is(pg_temp.place((select value from r8 where label='places'),'Cafe Sent')->'evidence'->'sentBy','["Theo Park"]','who sent it');
select is(pg_temp.place((select value from r8 where label='places'),'Garden Listed')->'evidence'->'list','{"owner":"Maya Ito","title":"Lisbon"}','whose list it''s on');
select is(pg_temp.place((select value from r8 where label='places'),'Bar Loved')->'evidence'->'friendsLoved','["Maya Ito","Theo Park"]','who loved it');
select is(pg_temp.place((select value from r8 where label='places'),'Museum Been')->'evidence'->'friendsBeen','["Maya Ito"]','who''s been');
select is((pg_temp.place((select value from r8 where label='places'),'Popular Spot')->'evidence'->>'isPopular')::boolean,false,'3 ratings averaging 7.3 are not enough to be popular (smoothed 6.5)');
select is((pg_temp.place((select value from r8 where label='places'),'Crowd Favourite')->'evidence'->>'isPopular')::boolean,true,'5 ratings of 8 are (smoothed 7.0)');
select is((pg_temp.place((select value from r8 where label='places'),'Fine Diner')->>'points')::numeric,5.0,'for someone who has only liked cafés, a restaurant gets half the taste points a café does');
select is(pg_temp.place((select value from r8 where label='places'),'Cafe Sent')->'evidence'->>'likedType','MKPOICategoryCafe','the kind of place you loved, for "Like the cafés you loved"');
select ok(not (pg_temp.place((select value from r8 where label='places'),'Fine Diner')->'evidence' ? 'likedType'),'no place type is claimed when you have not liked enough of it');
select is((pg_temp.place((select value from r8 where label='places'),'Cafe Sent')->'evidence'->>'likedInCategory')::int,3,'how many food places you liked');
select is(pg_temp.place((select value from r8 where label='places'),'Bar Loved')->'experience'->>'followingCount','2','friends rated this: 2');

-- Left out ---------------------------------------------------------------------------------------------------------
select ok(pg_temp.place((select value from r8 where label='places'),'Disliked Diner') is null,'a place your only friend there didn''t like is not suggested');
select ok(pg_temp.place((select value from r8 where label='places'),'Private Pick') is null,'a place only known through an Only me entry is not suggested');
select ok(pg_temp.place((select value from r8 where label='places'),'Blocked Fave') is null,'nor one only known through a blocked person');
select is((pg_temp.names((select value from r8 where label='onboarding')))[1:2],array['Bar Loved','Disliked Diner'],
  'onboarding offers places the most friends have been to first (ties by most ratings, then name)');

-- Noise that must change nothing ---------------------------------------------------------------------------------------
reset role;
-- Pia (a friend) logs everything Only me, with top scores.
select pg_temp.log('pia',l,'only_me','liked',10) from unnest(array['Cafe Sent','Garden Listed','Bar Loved','Museum Been','Popular Spot','Disliked Diner','Private Pick']) l;
-- A stranger's Only me and Friends entries.
select pg_temp.log('s1',l,'only_me','liked',10) from unnest(array['Museum Been','Private Pick']) l;
select pg_temp.log('s2',l,'friends','liked',10) from unnest(array['Museum Been','Garden Listed']) l;
-- Bex (blocked by the viewer) and Bo (blocked the viewer) rate publicly and send things.
select pg_temp.log(w,l,'public','liked',10) from unnest(array['bex','bo']) w, unnest(array['Museum Been','Popular Spot','Blocked Fave','Garden Listed']) l;
insert into public.direct_shares(sender_id,recipient_id,experience_id,operation_id)
  select pg_temp.id(w),pg_temp.id('viewer'),pg_temp.exp(l),gen_random_uuid() from unnest(array['bex','bo','dee']) w, unnest(array['Popular Spot','Museum Been']) l;
-- Dee (deactivated) rates publicly.
select pg_temp.log('dee',l,'public','liked',10) from unnest(array['Museum Been','Popular Spot']) l;
-- Lu, never a friend, shares a list.
insert into public.lists(id,owner_id,title) values('a8000000-0000-4000-8000-0000000000f3',pg_temp.id('lu'),'Lu''s Lisbon');
insert into public.list_items(list_id,experience_id) values('a8000000-0000-4000-8000-0000000000f3',pg_temp.exp('Museum Been')),('a8000000-0000-4000-8000-0000000000f3',pg_temp.exp('Popular Spot'));
insert into public.direct_shares(sender_id,recipient_id,list_id,operation_id) values(pg_temp.id('lu'),pg_temp.id('viewer'),'a8000000-0000-4000-8000-0000000000f3',gen_random_uuid());

set local role authenticated;
select pg_temp.as_user(pg_temp.id('viewer'));
select is(pg_temp.lisbon(),(select value from r8 where label='places'),'Only me, blocked (either way), deactivated and non-friend entries change no place, point or reason');
select is(public.suggested_cities(),(select value from r8 where label='cities'),'nor any city');
select is(public.suggested_cities('PT'),(select value from r8 where label='portugal'),'nor a country page');
select is(public.onboarding_places(38.5,39.0,-9.5,-8.9),(select value from r8 where label='onboarding'),'nor onboarding');
reset role;
select is((app_private.experience_summary_json(pg_temp.exp('Private Pick'),pg_temp.id('viewer'))->>'followingCount')::int,0,
  'a friend''s Only me rating no longer counts in "friends rated this"');
select is((app_private.experience_summary_json(pg_temp.exp('Private Pick'),pg_temp.id('viewer'))->>'followingScore'),null,'nor in friends'' average');
select is((app_private.experience_summary_json(pg_temp.exp('Bar Loved'),pg_temp.id('viewer'))->>'followingScore')::numeric,8.5,
  'friends'' average is Maya''s 9 and Theo''s 8 only');

-- Changes that must show up ------------------------------------------------------------------------------------------
-- Maya makes her Bar Loved visit Only me: she drops out of its reason and its points.
update public.visits set audience='only_me' where owner_id=pg_temp.id('maya') and experience_id=pg_temp.exp('Bar Loved');
set local role authenticated;
select pg_temp.as_user(pg_temp.id('viewer'));
select is(pg_temp.place(pg_temp.lisbon(),'Bar Loved')->'evidence'->'friendsLoved','["Theo Park"]','a visit changed to Only me leaves the reason line');
select is((pg_temp.place(pg_temp.lisbon(),'Bar Loved')->>'points')::numeric,15.0,'and the points');
-- The viewer blocks Theo: his send and his rating go at once.
select is(public.set_block(pg_temp.id('theo'),true),true,'blocking Theo');
select ok(pg_temp.place(pg_temp.lisbon(),'Cafe Sent') is null,'what a blocked friend sent stops counting');
select ok(pg_temp.place(pg_temp.lisbon(),'Bar Loved') is null,'and what they loved');
select ok(not (pg_temp.lisbon()::text like '%Theo%'),'no reason line names them');
select is(public.set_block(pg_temp.id('theo'),false),false,'unblocking');
select ok(pg_temp.place(pg_temp.lisbon(),'Cafe Sent') is null,'unblocking does not bring the friendship, or their picks, back');
-- Maya unfriends: her shared list goes.
select is(public.friend_action(pg_temp.id('maya'),'remove'),'none','Maya and the viewer stop being friends');
select ok(pg_temp.place(pg_temp.lisbon(),'Garden Listed') is null,'a former friend''s shared list stops counting');
select ok(not (pg_temp.lisbon()::text like '%Maya%'),'and nothing names her');

-- The viewer logs a place in Lisbon: it leaves the suggestions and onboarding, and Lisbon leaves Discover.
reset role;
select pg_temp.log('viewer','Later Logged','only_me');
set local role authenticated;
select pg_temp.as_user(pg_temp.id('viewer'));
select ok(pg_temp.place(pg_temp.lisbon(),'Later Logged') is null,'a place you''ve been to is not suggested');
select ok(not ('Later Logged'=any(pg_temp.names(public.onboarding_places(38.5,39.0,-9.5,-8.9)))),'nor offered in onboarding');
select ok(not ('Lisbon'=any(pg_temp.cities(public.suggested_cities()))),'and a city you''ve been to leaves Discover');

-- Not interested ---------------------------------------------------------------------------------------------------
select is(public.hide_suggestion(pg_temp.exp('Popular Spot')),true,'hiding a place');
select ok(pg_temp.place(pg_temp.lisbon(),'Popular Spot') is null,'a hidden place is gone');
select is(public.hide_suggestion(pg_temp.exp('Popular Spot'),null,false),false,'unhiding it');
select ok(pg_temp.place(pg_temp.lisbon(),'Popular Spot') is not null,'brings it back');
select is(public.hide_suggestion(null,(select id from c8 where label='Tokyo')),true,'hiding a city');
select ok(not ('Tokyo'=any(pg_temp.cities(public.suggested_cities()))),'a hidden city is gone, trip or not');
select throws_ok($$select public.hide_suggestion()$$,'22023',null,'hiding needs a place or a city');
select pg_temp.as_user(pg_temp.id('maya'));
select throws_ok($$select count(*) from public.hidden_suggestions$$,'42501',null,'nobody can read hidden suggestions directly, their own or anyone else''s');

-- Access -----------------------------------------------------------------------------------------------------------
reset role;
set local role anon;
select throws_ok($$select public.suggested_places()$$,'42501',null,'signed-out people cannot ask for suggestions');
select throws_ok($$select public.suggested_cities()$$,'42501',null,'nor cities');

select * from finish();
rollback;
