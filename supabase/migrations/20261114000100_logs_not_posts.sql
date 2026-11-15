-- A visit is a log, and a log is the only record: there are no posts. Likes, comments and notifications point at
-- logs (visits), the Friends tab and profiles read logs, and a log only shows to whoever its audience allows. Only me
-- means nobody else sees it, anywhere.

-- Likes, comments and notifications move from posts onto the log each post was for. Their read rules follow the log.
drop policy read_visible_likes on public.likes;
drop policy read_visible_comments on public.comments;
drop policy read_visible_activities on public.activities;
alter table public.likes add column visit_id uuid references public.visits (id) on delete cascade;
update public.likes l set visit_id = a.visit_id from public.activities a where a.id = l.activity_id;
delete from public.likes where visit_id is null;
delete from public.likes l using public.likes d
  where l.actor_id = d.actor_id and l.visit_id = d.visit_id and l.ctid > d.ctid;
drop trigger like_removed on public.likes;
alter table public.likes drop constraint likes_pkey;
alter table public.likes drop column activity_id;
alter table public.likes alter column visit_id set not null;
alter table public.likes add primary key (actor_id, visit_id);
create index likes_visit on public.likes (visit_id);

alter table public.comments add column visit_id uuid references public.visits (id) on delete cascade;
update public.comments c set visit_id = a.visit_id from public.activities a where a.id = c.activity_id;
delete from public.comments where visit_id is null;
alter table public.comments drop column activity_id;
alter table public.comments alter column visit_id set not null;
create index comments_visit on public.comments (visit_id, created_at, id);

alter table public.notifications add column visit_id uuid references public.visits (id) on delete cascade;
update public.notifications n set visit_id = a.visit_id from public.activities a where a.id = n.activity_id;
delete from public.notifications where type in ('like', 'comment') and visit_id is null;
delete from public.notifications n using public.notifications d
  where n.type = 'like' and d.type = 'like' and n.actor_id = d.actor_id and n.visit_id = d.visit_id and n.created_at > d.created_at;
update public.notifications set event_key = 'like:' || actor_id || ':' || visit_id where type = 'like';
alter table public.notifications drop column activity_id;

-- Whether a viewer may see a log: its owner is active and not blocked, and its audience lets them (Only me: never).
create or replace function app_private.log_visible(p_visit uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.visits v join public.profiles p on p.id = v.owner_id and p.deactivated_at is null
                 where v.id = p_visit
                   and (v.owner_id = p_viewer or not app_private.is_blocked_pair(p_viewer, v.owner_id))
                   and app_private.audience_allows(v.owner_id, v.audience, p_viewer))
$$;

create policy read_visible_likes on public.likes for select
  using (app_private.can_see_member(actor_id) and app_private.log_visible(visit_id, app_private.current_member()));
create policy read_visible_comments on public.comments for select
  using (app_private.can_see_member(author_id) and app_private.log_visible(visit_id, app_private.current_member()));

-- The post functions go with the posts.
drop function public.activity(uuid);
drop function public.delete_activity(uuid);
drop function public.feed(text);
drop function public.friends_activity(text);
drop function public.profile_activity(uuid, text);
drop function public.comments(uuid, text);
drop function public.post_comment(uuid, text, uuid);
drop function public.set_like(uuid, boolean);
drop function app_private.activity_visible(uuid, uuid);
drop function app_private.activity_json(uuid, uuid);
drop function app_private.activity_allowed(uuid, uuid);
drop function app_private.notify(uuid, uuid, public.notification_type, uuid, uuid, text);

-- A log as the Friends tab, profiles and a place's page show it.
create or replace function app_private.log_json(p_visit uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', v.id,
    -- A first log of the place, or going back.
    'type', case when exists (select 1 from public.visits e where e.owner_id = v.owner_id and e.experience_id = v.experience_id
                               and (e.created_at, e.id) < (v.created_at, v.id)) then 'revisit' else 'rating' end,
    'author', app_private.member_json(v.owner_id),
    'experience', app_private.experience_summary_json(v.experience_id, p_viewer),
    'category', coalesce(r.category, x.category, 'activities'),
    'scoreSnapshot', r.score, 'rankSnapshot', r.rank, 'sentimentSnapshot', r.sentiment,
    'visitID', v.id,
    'trip', (select jsonb_build_object('id', t.id, 'name', t.name) from public.trips t
             where t.id = v.trip_id and app_private.can_read_trip(t.id, p_viewer)),
    'companions', app_private.visit_companion_json(v.id, p_viewer),
    'visitDate', jsonb_build_object('date', v.visit_date, 'timeZoneIdentifier', v.time_zone),
    'note', coalesce(v.public_note, ''),
    'media', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'path', m.bucket || '/' || m.object_path, 'width', m.width,
                                                           'height', m.height, 'position', m.position) order by m.position)
                       from public.media m where m.visit_id = v.id and m.state = 'attached'), '[]'::jsonb),
    'publishedAt', v.created_at,
    'likeCount', (select count(*) from public.likes l join public.profiles p on p.id = l.actor_id
                  where l.visit_id = v.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, l.actor_id)),
    'commentCount', (select count(*) from public.comments c join public.profiles p on p.id = c.author_id
                     where c.visit_id = v.id and p.deactivated_at is null and not app_private.is_blocked_pair(p_viewer, c.author_id)),
    'likedByViewer', exists (select 1 from public.likes l where l.visit_id = v.id and l.actor_id = p_viewer),
    'isOwn', v.owner_id = p_viewer)
  from public.visits v
  join public.experiences x on x.id = v.experience_id
  left join public.ratings r on r.owner_id = v.owner_id and r.experience_id = v.experience_id
  where v.id = p_visit
$$;

-- Friends' dated logs, newest first.
create or replace function public.friends_logs(p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := app_private.require_member(); cursor_data jsonb := app_private.decode_cursor(p_cursor); rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.log_json(x.id, me) order by x.created_at desc, x.id desc), '[]') into rows
  from (
    select v.id, v.created_at from public.visits v
    where app_private.is_active_friend(me, v.owner_id)
      and v.visit_date is not null
      and app_private.log_visible(v.id, me)
      and not exists (select 1 from public.mutes where muter_id = me and muted_id = v.owner_id)
      and (cursor_data is null or (v.created_at, v.id) < ((cursor_data->>'publishedAt')::timestamptz, (cursor_data->>'id')::uuid))
    order by v.created_at desc, v.id desc limit 31
  ) x;
  return app_private.page_json(rows, 'publishedAt');
end $$;

-- One member's logs that the viewer may see.
create or replace function public.profile_logs(p_user_id uuid, p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := app_private.require_member(); cursor_data jsonb := app_private.decode_cursor(p_cursor); rows jsonb;
begin
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(app_private.log_json(x.id, me) order by x.created_at desc, x.id desc), '[]') into rows
  from (
    select v.id, v.created_at from public.visits v
    where v.owner_id = p_user_id and app_private.log_visible(v.id, me)
      and (cursor_data is null or (v.created_at, v.id) < ((cursor_data->>'publishedAt')::timestamptz, (cursor_data->>'id')::uuid))
    order by v.created_at desc, v.id desc limit 31
  ) x;
  return app_private.page_json(rows, 'publishedAt');
end $$;

create or replace function public.log(p_visit_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := app_private.require_member();
begin
  if not app_private.log_visible(p_visit_id, me) then raise exception 'roam:unavailable' using errcode = 'P0002'; end if;
  return app_private.log_json(p_visit_id, me);
end $$;

create or replace function app_private.notify(p_recipient uuid, p_actor uuid, p_type public.notification_type, p_visit uuid,
                                              p_comment uuid, p_event_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare prefs public.user_settings;
begin
  if p_recipient = p_actor or app_private.is_blocked_pair(p_recipient, p_actor) then return; end if;
  select * into prefs from public.user_settings where user_id = p_recipient;
  if found and ((p_type in ('follow', 'friend_request', 'friend_accept') and not prefs.notify_follows) or (p_type = 'like' and not prefs.notify_likes)
                or (p_type = 'comment' and not prefs.notify_comments)) then
    return;
  end if;
  insert into public.notifications (recipient_id, actor_id, type, visit_id, comment_id, event_key)
  values (p_recipient, p_actor, p_type, p_visit, p_comment, p_event_key)
  on conflict (event_key) do nothing;
end $$;

create or replace function public.set_like(p_visit_id uuid, p_liked boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.require_member(); owner uuid;
begin
  if not app_private.log_visible(p_visit_id, me) then raise exception 'roam:unavailable' using errcode = 'P0002'; end if;
  select owner_id into owner from public.visits where id = p_visit_id;
  if p_liked then
    insert into public.likes (actor_id, visit_id) values (me, p_visit_id) on conflict do nothing;
    if found then perform app_private.notify(owner, me, 'like', p_visit_id, null, 'like:' || me || ':' || p_visit_id); end if;
  else
    delete from public.likes where actor_id = me and visit_id = p_visit_id;
  end if;
  return exists (select 1 from public.likes where actor_id = me and visit_id = p_visit_id);
end $$;

create or replace function app_private.like_removed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.notifications where event_key = 'like:' || old.actor_id || ':' || old.visit_id;
  return old;
end $$;
create trigger like_removed after delete on public.likes for each row execute function app_private.like_removed();

create or replace function app_private.comment_json(p_comment uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'visitID', c.visit_id, 'author', app_private.member_json(c.author_id), 'body', c.body,
                            'createdAt', c.created_at, 'isOwn', c.author_id = p_viewer)
  from public.comments c where c.id = p_comment
$$;

create or replace function public.comments(p_visit_id uuid, p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := app_private.require_member(); cursor_data jsonb := app_private.decode_cursor(p_cursor); rows jsonb;
begin
  if not app_private.log_visible(p_visit_id, me) then raise exception 'roam:unavailable' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(app_private.comment_json(x.id, me) order by x.created_at, x.id), '[]') into rows
  from (select c.id, c.created_at from public.comments c join public.profiles p on p.id = c.author_id and p.deactivated_at is null
        where c.visit_id = p_visit_id and (c.author_id = me or not app_private.is_blocked_pair(me, c.author_id))
          and (cursor_data is null or (c.created_at, c.id) > ((cursor_data->>'createdAt')::timestamptz, (cursor_data->>'id')::uuid))
        order by c.created_at, c.id limit 31) x;
  return app_private.page_json(rows, 'createdAt');
end $$;

create or replace function public.post_comment(p_visit_id uuid, p_body text, p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.require_member(); existing public.comments; owner uuid; new_id uuid;
begin
  if p_operation_id is null then perform app_private.validation_error('This comment needs an operation identifier.'); end if;
  perform pg_advisory_xact_lock(hashtextextended(me::text || ':comment:' || p_operation_id::text, 0));
  select * into existing from public.comments where author_id = me and operation_id = p_operation_id;
  if found then
    if existing.visit_id <> p_visit_id or existing.body <> p_body then raise exception 'roam:operation_conflict' using errcode = '23505'; end if;
    return app_private.comment_json(existing.id, me);
  end if;
  if p_body is null or btrim(p_body) = '' then perform app_private.validation_error('Write a comment first.'); end if;
  if char_length(p_body) > 2000 then perform app_private.validation_error('Use 2,000 characters or fewer for your comment.'); end if;
  if not app_private.log_visible(p_visit_id, me) then raise exception 'roam:unavailable' using errcode = 'P0002'; end if;
  select owner_id into owner from public.visits where id = p_visit_id for share;
  insert into public.comments (visit_id, author_id, body, operation_id) values (p_visit_id, me, p_body, p_operation_id) returning id into new_id;
  perform app_private.notify(owner, me, 'comment', p_visit_id, new_id, 'comment:' || new_id);
  return app_private.comment_json(new_id, me);
end $$;

create or replace function app_private.notification_json(p_id uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', n.id, 'type', n.type, 'actor', app_private.member_json(n.actor_id), 'visitID', n.visit_id,
    'experienceName', (select pl.name from public.visits v join public.experiences e on e.id = v.experience_id
                       join public.places pl on pl.id = e.place_id where v.id = n.visit_id),
    'commentPreview', (select left(c.body, 140) from public.comments c where c.id = n.comment_id),
    'createdAt', n.created_at, 'readAt', n.read_at,
    'targetAvailable', case when n.type in ('follow', 'friend_request', 'friend_accept') then app_private.can_see_member(n.actor_id)
                            else n.visit_id is not null and app_private.log_visible(n.visit_id, p_viewer) end)
  from public.notifications n where n.id = p_id
$$;

CREATE OR REPLACE FUNCTION public.commit_rating(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  operation uuid;
  experience uuid;
  intent text;
  v_category public.experience_category;
  v_sentiment public.sentiment;
  base_revision bigint;
  revision bigint;
  answers jsonb := '[]'::jsonb;
  answer jsonb;
  compared uuid;
  visit_payload jsonb;
  payload jsonb;
  receipt jsonb;
  target public.experiences;
  previous public.ratings;
  rating uuid;
  anchor uuid;
  representatives uuid[];
  outcome jsonb;
  position integer;
  result jsonb;
begin
  perform app_private.assert_json_keys(p_request, array['operationID', 'intent', 'experienceID', 'category', 'sentiment', 'baseRevision', 'answers', 'visit']);
  if jsonb_typeof(p_request -> 'operationID') is distinct from 'string'
    or jsonb_typeof(p_request -> 'experienceID') is distinct from 'string'
    or jsonb_typeof(p_request -> 'intent') is distinct from 'string'
    or jsonb_typeof(p_request -> 'category') is distinct from 'string'
    or jsonb_typeof(p_request -> 'sentiment') is distinct from 'string'
    or jsonb_typeof(p_request -> 'baseRevision') is distinct from 'number'
    or (p_request ->> 'baseRevision') !~ '^[0-9]+$'
    or jsonb_typeof(p_request -> 'answers') is distinct from 'array' then
    perform app_private.validation_error('This ranking save is incomplete.');
  end if;
  begin
    operation := (p_request ->> 'operationID')::uuid;
    experience := (p_request ->> 'experienceID')::uuid;
    v_category := (p_request ->> 'category')::public.experience_category;
    v_sentiment := (p_request ->> 'sentiment')::public.sentiment;
    base_revision := (p_request ->> 'baseRevision')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    perform app_private.validation_error('Check the ranking identifiers, category and revision.');
  end;
  intent := p_request ->> 'intent';
  if intent not in ('first_log', 'rerank') then perform app_private.validation_error('Choose a supported ranking action.'); end if;
  for answer in select value from jsonb_array_elements(p_request -> 'answers') loop
    perform app_private.assert_json_keys(answer, array['compared_rating_id', 'choice']);
    if jsonb_typeof(answer -> 'compared_rating_id') is distinct from 'string'
      or jsonb_typeof(answer -> 'choice') is distinct from 'string'
      or answer ->> 'choice' not in ('prefer_new', 'prefer_existing', 'too_tough', 'skip') then
      perform app_private.validation_error('Check the comparison answers.');
    end if;
    begin compared := (answer ->> 'compared_rating_id')::uuid;
    exception when invalid_text_representation then perform app_private.validation_error('A comparison reference is invalid.'); end;
    answers := answers || jsonb_build_array(jsonb_build_object('compared_rating_id', compared, 'choice', answer ->> 'choice'));
  end loop;
  if intent = 'first_log' or (p_request -> 'visit' is not null and p_request -> 'visit' <> 'null'::jsonb) then
    visit_payload := app_private.normalized_visit_payload(p_request -> 'visit');
  end if;
  payload := jsonb_build_object('experienceID', experience, 'intent', intent, 'category', v_category, 'sentiment', v_sentiment,
                               'baseRevision', base_revision, 'answers', answers, 'visit', visit_payload);
  receipt := app_private.rating_receipt(me, operation, 'commit_rating', payload);
  if receipt is not null then return receipt; end if;

  select * into target from public.experiences where id = experience for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  if target.category_locked_at is not null and target.category <> v_category then
    perform app_private.validation_error('This experience already has a fixed category.');
  end if;
  revision := app_private.lock_category_revision(me, v_category);
  if revision <> base_revision then raise exception 'roam:stale_revision' using errcode = '40001'; end if;
  select * into previous from public.ratings where owner_id = me and experience_id = experience;
  if intent = 'first_log' and previous.id is not null then raise exception 'roam:already_rated' using errcode = '22023'; end if;
  if intent = 'rerank' and previous.id is null then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  if intent = 'rerank' and previous.category <> v_category then perform app_private.validation_error('The category cannot change when ranking again.'); end if;
  select array_agg(g.id order by g.group_position) into representatives
  from (select distinct on (r.group_position) r.id, r.group_position from public.ratings r
        where r.owner_id = me and r.category = v_category and r.sentiment = v_sentiment
          and (previous.id is null or r.id <> previous.id)
        order by r.group_position, r.first_rated_at, r.id) g;
  outcome := app_private.replay_insertion(coalesce(representatives, '{}'::uuid[]), answers);
  position := (outcome ->> 'position')::integer;
  if intent = 'rerank' then
    select id into anchor from public.visits where owner_id = me and experience_id = experience
      order by visit_date desc nulls last, created_at desc, id limit 1 for update;
    if visit_payload is not null and anchor is null then perform app_private.validation_error('There is no retained visit to edit.'); end if;
  end if;
  if visit_payload is not null then perform app_private.validate_rating_visit(me, visit_payload, anchor); end if;
  perform app_private.compact_rating_groups(me, v_category, previous.id);
  if outcome ->> 'kind' = 'new_group' then
    update public.ratings r set group_position = r.group_position + 1
    where r.owner_id = me and r.category = v_category and r.sentiment = v_sentiment and r.group_position >= position
      and (previous.id is null or r.id <> previous.id);
  end if;
  if intent = 'first_log' then
    insert into public.ratings(owner_id, experience_id, category, sentiment, group_position, score, rank)
    values (me, experience, v_category, v_sentiment, position, 0, 1) returning id into rating;
  else
    rating := previous.id;
    update public.ratings set sentiment = v_sentiment, group_position = position, updated_at = now() where id = rating;
  end if;
  perform app_private.reflow_rating_category(me, v_category);
  revision := revision + 1;
  update public.category_revisions cr set version = revision, updated_at = now() where cr.owner_id = me and cr.category = v_category;
  update public.experiences set category = v_category, category_source = 'confirmed',
    category_locked_at = coalesce(category_locked_at, now()) where id = experience;
  if intent = 'first_log' then
    anchor := app_private.write_rating_visit(me, experience, operation, visit_payload);
    delete from public.bookmarks where owner_id = me and experience_id = experience;
  elsif visit_payload is not null then
    perform app_private.write_rating_visit(me, experience, operation, visit_payload, anchor);
  end if;
  select jsonb_build_object('ratingID', r.id, 'visitID', case when intent = 'first_log' then anchor end,
                           'category', r.category, 'sentiment', r.sentiment, 'score', r.score, 'rank', r.rank,
                           'groupSize', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category
                                          and g.sentiment = r.sentiment and g.group_position = r.group_position),
                           'categoryCount', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category), 'revision', revision)
  into result from public.ratings r where r.id = rating;
  perform app_private.store_rating_receipt(me, operation, 'commit_rating', payload, result);
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.add_visit(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  operation uuid;
  experience uuid;
  visit_payload jsonb;
  payload jsonb;
  receipt jsonb;
  current_rating public.ratings;
  visit uuid;
  result jsonb;
  unranked_category public.experience_category;
begin
  perform app_private.assert_json_keys(p_request, array['operationID', 'experienceID', 'visit', 'category']);
  if jsonb_typeof(p_request -> 'operationID') is distinct from 'string' or jsonb_typeof(p_request -> 'experienceID') is distinct from 'string'
    or jsonb_typeof(p_request -> 'visit') is distinct from 'object' then perform app_private.validation_error('This visit save is incomplete.'); end if;
  begin
    operation := (p_request ->> 'operationID')::uuid;
    experience := (p_request ->> 'experienceID')::uuid;
  exception when invalid_text_representation then perform app_private.validation_error('Check the visit identifiers.'); end;
  visit_payload := app_private.normalized_visit_payload(p_request -> 'visit');
  payload := jsonb_build_object('experienceID', experience, 'visit', visit_payload, 'category', p_request ->> 'category');
  receipt := app_private.rating_receipt(me, operation, 'add_visit', payload);
  if receipt is not null then return receipt; end if;
  perform id from public.experiences where id = experience for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  if not found then
    -- Logging never requires ranking: the visit stands alone until the member chooses to rank it.
    begin
      unranked_category := coalesce((p_request ->> 'category')::public.experience_category, (select category from public.experiences where id = experience));
    exception when invalid_text_representation then perform app_private.validation_error('Choose a category for this place.'); end;
    if unranked_category is null then perform app_private.validation_error('Choose a category for this place.'); end if;
    update public.experiences set category = unranked_category where id = experience and category is null;
    visit := app_private.write_rating_visit(me, experience, operation, visit_payload);
    result := jsonb_build_object('visitID', visit);
    perform app_private.store_rating_receipt(me, operation, 'add_visit', payload, result);
    return result;
  end if;
  perform app_private.lock_category_revision(me, current_rating.category);
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  visit := app_private.write_rating_visit(me, experience, operation, visit_payload);
  result := jsonb_build_object('visitID', visit);
  perform app_private.store_rating_receipt(me, operation, 'add_visit', payload, result);
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.experience_detail(p_experience_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  result jsonb;
begin
  if not exists (select 1 from public.experiences where id = p_experience_id) then
    raise exception 'roam:not_found' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'summary', app_private.experience_summary_json(e.id, me),
    'address', pl.address, 'phone', pl.phone, 'website', pl.website, 'timeZoneIdentifier', pl.time_zone,
    'provider', pl.provider, 'providerStatus', pl.status, 'isLocality', pl.is_locality,
    'categoryLocked', e.category_locked_at is not null,
    'myRating', (select jsonb_build_object('ratingID', r.id, 'category', r.category, 'sentiment', r.sentiment, 'score', r.score,
                                           'rank', r.rank,
                                           'groupSize', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category
                                                         and g.sentiment = r.sentiment and g.group_position = r.group_position),
                                           'categoryCount', (select count(*) from public.ratings c where c.owner_id = me and c.category = r.category),
                                           'firstRatedAt', r.first_rated_at)
                 from public.ratings r where r.owner_id = me and r.experience_id = e.id),
    'myVisits', coalesce((select jsonb_agg(app_private.visit_json(v.id)
                                           order by v.visit_date desc nulls last, v.created_at desc, v.id)
                          from public.visits v where v.owner_id = me and v.experience_id = e.id), '[]'::jsonb),
    'hasPrivateNote', exists (select 1 from public.private_notes n where n.owner_id = me and n.experience_id = e.id),
    'publicLogs', coalesce((select jsonb_agg(app_private.log_json(x.id, me) order by x.created_at desc, x.id desc)
                            from (select v.id, v.created_at from public.visits v
                                  where v.experience_id = e.id and app_private.log_visible(v.id, me)
                                  order by v.created_at desc, v.id desc limit 30) x), '[]'::jsonb))
  into result
  from public.experiences e join public.places pl on pl.id = e.place_id
  where e.id = p_experience_id;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION app_private.place_memories(p_experience_id uuid, p_cursor text, p_friend_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me uuid := app_private.require_member();
  cursor_data jsonb; cursor_date timestamptz; cursor_id uuid; rows jsonb;
begin
  if not exists(select 1 from public.experiences where id=p_experience_id) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  if p_friend_id is not null and not app_private.is_active_friend(me,p_friend_id) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  if p_cursor is not null then
    begin
      cursor_data := convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
      cursor_date := (cursor_data->>'createdAt')::timestamptz;
      cursor_id := (cursor_data->>'id')::uuid;
      if cursor_date is null or cursor_id is null then raise exception 'invalid cursor'; end if;
    exception when others then perform app_private.validation_error('This memory page has an invalid cursor.');
    end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
    'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),
    'publicNote',v.public_note,'audience',v.audience,
    'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,me),
    'createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',v.owner_id=me) order by v.created_at desc,v.id desc),'[]') into rows
  from (
    select x.* from public.visits x join public.profiles p on p.id=x.owner_id and p.deactivated_at is null
    where x.experience_id=p_experience_id and (p_friend_id is null or x.owner_id=p_friend_id)
      and app_private.audience_allows(x.owner_id,x.audience,me)
      and (p_cursor is null or (x.created_at,x.id)<(cursor_date,cursor_id))
    order by x.created_at desc,x.id desc limit 31
  ) v;
  return app_private.page_json(rows,'createdAt');
end$function$
;

CREATE OR REPLACE FUNCTION app_private.trip_feed_entry(p_visit uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('id',v.id,'experience',app_private.experience_summary_json(v.experience_id,p_viewer),
    'publicNote',v.public_note,'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),
    'media',app_private.visit_json(v.id)->'media','companions',app_private.visit_companion_json(v.id,p_viewer),'author',app_private.member_json(v.owner_id),'createdAt',v.created_at,
    'score',(select r.score from public.ratings r where r.owner_id=v.owner_id and r.experience_id=v.experience_id))
  from public.visits v where v.id=p_visit
$function$
;

-- Nothing refers to posts any more.
drop table public.activities;
drop type public.activity_type;

revoke execute on function app_private.log_visible(uuid, uuid), app_private.log_json(uuid, uuid),
  app_private.notify(uuid, uuid, public.notification_type, uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.friends_logs(text), public.profile_logs(uuid, text), public.log(uuid),
  public.set_like(uuid, boolean), public.comments(uuid, text), public.post_comment(uuid, text, uuid) from public, anon;
grant execute on function public.friends_logs(text), public.profile_logs(uuid, text), public.log(uuid),
  public.set_like(uuid, boolean), public.comments(uuid, text), public.post_comment(uuid, text, uuid) to authenticated;
