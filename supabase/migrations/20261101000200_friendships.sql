-- Two-way friendships. A request stays pending until the other member accepts. An accepted friendship
-- is stored as a pair of follows rows, so every query that reads follows sees friends only. Members can
-- no longer write a one-way edge: set_follow is removed.

create table public.friend_requests (
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
-- One open request per pair, whichever side sent it.
create unique index friend_requests_pair on public.friend_requests (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friend_requests_addressee on public.friend_requests (addressee_id, created_at desc);
alter table public.friend_requests enable row level security;
create policy read_own_friend_requests on public.friend_requests for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));
revoke all on public.friend_requests from anon, authenticated;
grant select on public.friend_requests to authenticated;

-- A one-way follow was never agreed by both people: it becomes a pending request. Mutual follows
-- are already friendships.
insert into public.friend_requests (requester_id, addressee_id, created_at)
select f.follower_id, f.followee_id, f.created_at from public.follows f
where not exists (select 1 from public.follows r where r.follower_id = f.followee_id and r.followee_id = f.follower_id);
delete from public.follows f
where not exists (select 1 from public.follows r where r.follower_id = f.followee_id and r.followee_id = f.follower_id);

drop function public.set_follow(uuid, boolean);

create or replace function app_private.friend_state(p_viewer uuid, p_member uuid)
returns text language sql stable security definer set search_path='' as $$
  select case
    when exists(select 1 from public.follows f where f.follower_id=p_viewer and f.followee_id=p_member) then 'friends'
    when exists(select 1 from public.friend_requests r where r.requester_id=p_viewer and r.addressee_id=p_member) then 'sent'
    when exists(select 1 from public.friend_requests r where r.requester_id=p_member and r.addressee_id=p_viewer) then 'received'
    else 'none' end
$$;

create or replace function app_private.make_friends(p_a uuid, p_b uuid)
returns void language sql security definer set search_path='' as $$
  delete from public.friend_requests where (requester_id=p_a and addressee_id=p_b) or (requester_id=p_b and addressee_id=p_a);
  insert into public.follows(follower_id,followee_id) values (p_a,p_b),(p_b,p_a) on conflict do nothing;
$$;

-- request, accept, decline, cancel and remove. Each is a desired state, safe to repeat, and returns the
-- resulting friend state. A request to someone who already asked you accepts theirs.
create or replace function public.friend_action(p_user_id uuid, p_action text)
returns text language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_state text;
begin
  if p_action is null or p_action not in ('request','accept','decline','cancel','remove') then
    perform app_private.validation_error('That friend action is not available.');
  end if;
  if p_user_id=v_me then perform app_private.validation_error('You can''t add yourself as a friend.'); end if;
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(v_me,p_user_id)::text||':friend:'||greatest(v_me,p_user_id)::text,0));
  v_state:=app_private.friend_state(v_me,p_user_id);
  if p_action='request' and v_state='none' then
    insert into public.friend_requests(requester_id,addressee_id) values(v_me,p_user_id);
    perform app_private.notify(p_user_id,v_me,'friend_request',null,null,'friend_request:'||v_me||':'||p_user_id);
  elsif p_action in ('request','accept') and v_state='received' then
    perform app_private.make_friends(v_me,p_user_id);
    delete from public.notifications where event_key='friend_request:'||p_user_id||':'||v_me;
    perform app_private.notify(p_user_id,v_me,'friend_accept',null,null,'friend_accept:'||v_me||':'||p_user_id);
  elsif p_action='decline' and v_state='received' then
    delete from public.friend_requests where requester_id=p_user_id and addressee_id=v_me;
    delete from public.notifications where event_key='friend_request:'||p_user_id||':'||v_me;
  elsif p_action='cancel' and v_state='sent' then
    delete from public.friend_requests where requester_id=v_me and addressee_id=p_user_id;
    delete from public.notifications where event_key='friend_request:'||v_me||':'||p_user_id;
  elsif p_action='remove' and v_state='friends' then
    delete from public.follows where (follower_id=v_me and followee_id=p_user_id) or (follower_id=p_user_id and followee_id=v_me);
    delete from public.notifications where event_key in ('friend_accept:'||v_me||':'||p_user_id,'friend_accept:'||p_user_id||':'||v_me);
  end if;
  return app_private.friend_state(v_me,p_user_id);
end$$;

create or replace function app_private.member_row_json(p_member uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('member',app_private.member_json(p_member),
    'friendState',app_private.friend_state(p_viewer,p_member),'isSelf',p_member=p_viewer)
$$;

-- People waiting on the signed-in member's answer, newest first.
create or replace function public.incoming_friend_requests(p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.member_row_json(x.id,v_me)||jsonb_build_object('id',x.id,'createdAt',x.created_at) order by x.created_at desc,x.id desc),'[]') into v_rows
  from(select r.requester_id id,r.created_at from public.friend_requests r join public.profiles p on p.id=r.requester_id and p.deactivated_at is null
       where r.addressee_id=v_me and not app_private.is_blocked_pair(v_me,r.requester_id)
         and(v_cursor is null or(r.created_at,r.requester_id)<((v_cursor->>'createdAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by r.created_at desc,r.requester_id desc limit 31)x;
  return app_private.page_json(v_rows,'createdAt');
end$$;

CREATE OR REPLACE FUNCTION public.public_profile(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  result jsonb;
begin
  if not app_private.can_see_member(p_user_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'member', app_private.member_json(p.id),
    'bio', p.bio,
    'homeCityName', (select c.name || coalesce(', ' || c.region, '') || ', ' || k.name from public.cities c
                     join public.countries k on k.code = c.country_code where c.id = p.home_city_id),
    'joinedAt', p.created_at,
    'followerCount', (select count(*) from public.follows f join public.profiles x on x.id = f.follower_id
                      where f.followee_id = p.id and x.deactivated_at is null and not app_private.is_blocked_pair(me, f.follower_id)),
    'followingCount', (select count(*) from public.follows f join public.profiles x on x.id = f.followee_id
                       where f.follower_id = p.id and x.deactivated_at is null and not app_private.is_blocked_pair(me, f.followee_id)),
    'rankedCount', (select count(*) from public.ratings r where r.owner_id = p.id),
    'wantCount', (select count(*) from public.bookmarks b where b.owner_id = p.id),
    'countryCount', (select count(distinct pl.country_code) from public.visits v join public.experiences e on e.id = v.experience_id
                     join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.country_code is not null),
    'cityCount', (select count(distinct pl.city_id) from public.visits v join public.experiences e on e.id = v.experience_id
                  join public.places pl on pl.id = e.place_id where v.owner_id = p.id and pl.city_id is not null),
    'relationship', jsonb_build_object(
      'isSelf', p.id = me,
      'friendState', app_private.friend_state(me, p.id),
      'isMuted', exists (select 1 from public.mutes where muter_id = me and muted_id = p.id),
      'isBlocked', exists (select 1 from public.blocks where blocker_id = me and blocked_id = p.id)))
  into result
  from public.profiles p where p.id = p_user_id;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_members(p_query text, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  q text := lower(btrim(coalesce(p_query, '')));
  rows jsonb;
begin
  if q = '' then
    return jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null);
  end if;
  with page as (
    select p.id, p.handle from public.profiles p
    where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
      and (strpos(lower(p.handle), q) > 0 or strpos(lower(p.display_name), q) > 0)
      and (p_cursor is null or p.handle > p_cursor)
    -- Handles are unique and lowercase, so this is also the cursor's stable tie-break.
    order by p.handle limit 31)
  select jsonb_agg(jsonb_build_object(
           'member', app_private.member_json(page.id),
           'friendState', app_private.friend_state(me, page.id),
           'isSelf', false) order by page.handle)
  into rows from page;
  rows := coalesce(rows, '[]'::jsonb);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value order by ordinal), '[]'::jsonb)
              from jsonb_array_elements(rows) with ordinality as item(value, ordinal) where ordinal <= 30),
    'nextCursor', case when jsonb_array_length(rows) > 30 then rows -> 29 -> 'member' ->> 'handle' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.suggested_members(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('member', app_private.member_json(s.id), 'friendState', app_private.friend_state(me, s.id), 'isSelf', false) order by s.rated desc, s.handle)
    from (
      select p.id, p.handle,
             (select count(*) from public.ratings r where r.owner_id = p.id) as rated,
             exists (select 1 from public.follows f where f.follower_id = p.id and f.followee_id = me) as follows_me
      from public.profiles p
      where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
        and not exists (select 1 from public.follows f where f.follower_id = me and f.followee_id = p.id)
      order by rated desc, p.handle
      limit least(greatest(coalesce(p_limit, 10), 1), 30)
    ) s), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.notify(p_recipient uuid, p_actor uuid, p_type notification_type, p_activity uuid, p_comment uuid, p_event_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  prefs public.user_settings;
begin
  if p_recipient = p_actor or app_private.is_blocked_pair(p_recipient, p_actor) then
    return;
  end if;
  select * into prefs from public.user_settings where user_id = p_recipient;
  if found and ((p_type in ('follow', 'friend_request', 'friend_accept') and not prefs.notify_follows) or (p_type = 'like' and not prefs.notify_likes)
                or (p_type = 'comment' and not prefs.notify_comments)) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, activity_id, comment_id, event_key)
  values (p_recipient, p_actor, p_type, p_activity, p_comment, p_event_key)
  on conflict (event_key) do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.notification_json(p_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('id',n.id,'type',n.type,'actor',app_private.member_json(n.actor_id),'activityID',n.activity_id,
    'experienceName',(select pl.name from public.activities a join public.experiences e on e.id=a.experience_id join public.places pl on pl.id=e.place_id where a.id=n.activity_id),
    'commentPreview',(select left(c.body,140) from public.comments c where c.id=n.comment_id),
    'createdAt',n.created_at,'readAt',n.read_at,
    'targetAvailable',case when n.type in ('follow','friend_request','friend_accept') then app_private.can_see_member(n.actor_id)
                           else n.activity_id is not null and app_private.activity_visible(n.activity_id,p_viewer) end)
  from public.notifications n where n.id=p_id
$function$;

CREATE OR REPLACE FUNCTION public.set_block(p_user_id uuid, p_blocked boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member();
begin
  if p_user_id=v_me then perform app_private.validation_error('You can''t block yourself.'); end if;
  if p_blocked then
    if not exists(select 1 from public.profiles where id=p_user_id and deactivated_at is null) then raise exception 'roam:not_found' using errcode='P0002'; end if;
    insert into public.blocks(blocker_id,blocked_id) values(v_me,p_user_id) on conflict do nothing;
    delete from public.follows where(follower_id=v_me and followee_id=p_user_id) or(follower_id=p_user_id and followee_id=v_me);
    delete from public.friend_requests where(requester_id=v_me and addressee_id=p_user_id) or(requester_id=p_user_id and addressee_id=v_me);
  else
    delete from public.blocks where blocker_id=v_me and blocked_id=p_user_id;
  end if;
  return exists(select 1 from public.blocks where blocker_id=v_me and blocked_id=p_user_id);
end$function$;

revoke execute on function app_private.friend_state(uuid,uuid),app_private.make_friends(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.friend_state(uuid,uuid),app_private.make_friends(uuid,uuid) to service_role;
revoke execute on function public.friend_action(uuid,text),public.incoming_friend_requests(text) from public,anon;
grant execute on function public.friend_action(uuid,text),public.incoming_friend_requests(text) to authenticated;
