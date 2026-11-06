-- M4: authoritative roam-category-v1 replay, per-category revisions and atomic mutation receipts.
-- Lock order: actor/operation advisory -> experience row -> actor/category revision -> media rows.

create or replace function app_private.assert_json_keys(p_value jsonb, p_allowed text[])
returns void language plpgsql set search_path = '' as $$
begin
  if jsonb_typeof(p_value) is distinct from 'object' then
    perform app_private.validation_error('This save contains unsupported fields.');
  end if;
  if exists (select 1 from jsonb_object_keys(p_value) k where not k = any(p_allowed)) then
    perform app_private.validation_error('This save contains unsupported fields.');
  end if;
end;
$$;

create or replace function app_private.rating_intent_digest(p_intent text, p_payload jsonb)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(jsonb_build_object('intent', p_intent, 'payload', p_payload)::text, 'UTF8'), 'sha256'), 'hex')
$$;

create or replace function app_private.rating_receipt(p_actor uuid, p_operation uuid, p_intent text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  receipt app_private.mutation_receipts;
begin
  if p_operation is null then
    perform app_private.validation_error('This save needs an operation identifier.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text || ':' || p_operation::text, 0));
  select * into receipt from app_private.mutation_receipts where actor_id = p_actor and operation_id = p_operation;
  if found then
    if receipt.intent <> p_intent or receipt.intent_hash <> app_private.rating_intent_digest(p_intent, p_payload) then
      raise exception 'roam:operation_conflict' using errcode = '23505';
    end if;
    return receipt.result;
  end if;
  return null;
end;
$$;

create or replace function app_private.store_rating_receipt(p_actor uuid, p_operation uuid, p_intent text, p_payload jsonb, p_result jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into app_private.mutation_receipts(actor_id, operation_id, intent, intent_hash, result)
  values (p_actor, p_operation, p_intent, app_private.rating_intent_digest(p_intent, p_payload), p_result)
$$;

create or replace function app_private.lock_category_revision(p_actor uuid, p_category public.experience_category)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  revision bigint;
begin
  insert into public.category_revisions(owner_id, category) values (p_actor, p_category) on conflict do nothing;
  select version into revision from public.category_revisions where owner_id = p_actor and category = p_category for update;
  return revision;
end;
$$;

-- Normalize the structural visit payload before looking for a receipt. Authorization/state checks
-- happen later, because a successful retry's media will already be attached.
create or replace function app_private.normalized_visit_payload(p_visit jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  payload jsonb := case when p_visit is null or p_visit = 'null'::jsonb then '{}'::jsonb else p_visit end;
  date_text text;
  visit_date date;
  zone text;
  note text;
  media_ids jsonb;
begin
  perform app_private.assert_json_keys(payload, array['date', 'timeZoneIdentifier', 'publicNote', 'mediaIDs']);
  if (payload ? 'date' and payload -> 'date' <> 'null'::jsonb and jsonb_typeof(payload -> 'date') <> 'string')
    or (payload ? 'timeZoneIdentifier' and payload -> 'timeZoneIdentifier' <> 'null'::jsonb and jsonb_typeof(payload -> 'timeZoneIdentifier') <> 'string')
    or (payload ? 'publicNote' and jsonb_typeof(payload -> 'publicNote') <> 'string')
    or (payload ? 'mediaIDs' and jsonb_typeof(payload -> 'mediaIDs') <> 'array') then
    perform app_private.validation_error('Check the visit details.');
  end if;
  date_text := payload ->> 'date';
  if date_text is not null then
    if date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      perform app_private.validation_error('Use a calendar date for this visit.');
    end if;
    begin
      visit_date := date_text::date;
    exception when datetime_field_overflow or invalid_datetime_format then
      perform app_private.validation_error('Use a valid calendar date for this visit.');
    end;
  end if;
  zone := nullif(payload ->> 'timeZoneIdentifier', '');
  if zone is not null and not exists (select 1 from pg_timezone_names where name = zone) then
    perform app_private.validation_error('Use a valid time zone for this visit.');
  end if;
  note := coalesce(payload ->> 'publicNote', '');
  if char_length(note) > 5000 then
    perform app_private.validation_error('Use 5,000 characters or fewer for your public note.');
  end if;
  begin
    select coalesce(jsonb_agg((value #>> '{}')::uuid::text order by ordinal), '[]'::jsonb) into media_ids
    from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) with ordinality item(value, ordinal);
  exception when invalid_text_representation then
    perform app_private.validation_error('A photo reference is invalid.');
  end;
  if exists (select 1 from jsonb_array_elements(coalesce(payload -> 'mediaIDs', '[]'::jsonb)) item where jsonb_typeof(item) <> 'string')
    or jsonb_array_length(media_ids) > 6
    or (select count(distinct value) from jsonb_array_elements(media_ids)) <> jsonb_array_length(media_ids) then
    perform app_private.validation_error('Choose up to six different photos for this visit.');
  end if;
  return jsonb_build_object('date', visit_date, 'timeZoneIdentifier', zone, 'publicNote', note, 'mediaIDs', media_ids);
end;
$$;

create or replace function app_private.validate_rating_visit(p_actor uuid, p_payload jsonb, p_anchor uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  ids uuid[] := array(select value::uuid from jsonb_array_elements_text(p_payload -> 'mediaIDs'));
  eligible integer;
begin
  if (p_payload ->> 'date')::date > (now() at time zone coalesce(p_payload ->> 'timeZoneIdentifier', 'UTC'))::date then
    perform app_private.validation_error('A completed visit cannot be in the future.');
  end if;
  -- Stable media locking prevents two concurrent drafts from attaching one staged asset twice.
  perform id from public.media where id = any(ids) order by id for update;
  select count(*)::integer into eligible
  from public.media m join storage.objects o on o.bucket_id = m.bucket and o.name = m.object_path
  where m.id = any(ids) and m.owner_id = p_actor and m.purpose = 'visit' and m.bucket = 'visit-media'
    and split_part(m.object_path, '/', 1) = p_actor::text
    and ((m.state = 'staged' and m.visit_id is null) or (p_anchor is not null and m.state = 'attached' and m.visit_id = p_anchor))
    and o.metadata ->> 'mimetype' = 'image/jpeg'
    and (o.metadata ->> 'size')::bigint between 1 and 3145728;
  if eligible <> cardinality(ids) then
    perform app_private.validation_error('A photo is not uploaded, owned by you, or available for this visit.');
  end if;
end;
$$;

create or replace function app_private.write_rating_visit(p_actor uuid, p_experience uuid, p_operation uuid, p_payload jsonb, p_anchor uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_visit uuid := p_anchor;
  asset record;
begin
  perform app_private.validate_rating_visit(p_actor, p_payload, p_anchor);
  if v_visit is null then
    insert into public.visits(owner_id, experience_id, visit_date, date_precision, time_zone, public_note, source_operation_id)
    values (p_actor, p_experience, (p_payload ->> 'date')::date,
            case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
            p_payload ->> 'timeZoneIdentifier', p_payload ->> 'publicNote', p_operation)
    returning id into v_visit;
  else
    update public.visits set visit_date = (p_payload ->> 'date')::date,
      date_precision = case when p_payload ->> 'date' is null then 'unknown' else 'day' end,
      time_zone = p_payload ->> 'timeZoneIdentifier', public_note = p_payload ->> 'publicNote'
    where id = v_visit and owner_id = p_actor and experience_id = p_experience;
    if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
    delete from public.media m where m.visit_id = v_visit and m.owner_id = p_actor
      and not m.id::text in (select value from jsonb_array_elements_text(p_payload -> 'mediaIDs'));
  end if;
  for asset in select value, ordinal from jsonb_array_elements_text(p_payload -> 'mediaIDs') with ordinality item(value, ordinal) loop
    update public.media set state = 'attached', visit_id = v_visit,
      position = asset.ordinal - 1, attached_at = coalesce(attached_at, now()) where id = asset.value::uuid;
  end loop;
  return v_visit;
end;
$$;

create or replace function app_private.replay_insertion(p_groups uuid[], p_answers jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  lo integer := 0;
  hi integer := cardinality(coalesce(p_groups, '{}'::uuid[]));
  mid integer;
  answer jsonb;
  choice text;
  compared uuid;
  outcome jsonb;
begin
  if jsonb_typeof(p_answers) is distinct from 'array' then
    perform app_private.validation_error('Comparison answers must be an ordered list.');
  end if;
  for answer in select value from jsonb_array_elements(p_answers) loop
    if outcome is not null or lo >= hi then perform app_private.validation_error('This save contains extra comparison answers.'); end if;
    perform app_private.assert_json_keys(answer, array['compared_rating_id', 'choice']);
    if jsonb_typeof(answer -> 'compared_rating_id') is distinct from 'string' or jsonb_typeof(answer -> 'choice') is distinct from 'string' then
      perform app_private.validation_error('A comparison answer is incomplete.');
    end if;
    begin compared := (answer ->> 'compared_rating_id')::uuid;
    exception when invalid_text_representation then perform app_private.validation_error('A comparison reference is invalid.'); end;
    mid := (lo + hi) / 2;
    if compared <> p_groups[mid + 1] then perform app_private.validation_error('The comparison answers do not match this ranking.'); end if;
    choice := answer ->> 'choice';
    case choice
      when 'prefer_new' then hi := mid;
      when 'prefer_existing' then lo := mid + 1;
      when 'too_tough' then outcome := jsonb_build_object('kind', 'join_group', 'position', mid, 'approximate', false);
      when 'skip' then outcome := jsonb_build_object('kind', 'new_group', 'position', mid, 'approximate', true);
      else perform app_private.validation_error('Choose a supported comparison answer.');
    end case;
  end loop;
  if outcome is null then
    if lo < hi then perform app_private.validation_error('Finish the comparisons before saving.'); end if;
    outcome := jsonb_build_object('kind', 'new_group', 'position', lo, 'approximate', false);
  end if;
  return outcome;
end;
$$;

create or replace function app_private.compact_rating_groups(p_actor uuid, p_category public.experience_category, p_excluded uuid default null)
returns void language sql security definer set search_path = '' as $$
  with groups as (
    select sentiment, group_position, (dense_rank() over (partition by sentiment order by group_position) - 1)::integer as position
    from (select distinct sentiment, group_position from public.ratings
          where owner_id = p_actor and category = p_category and (p_excluded is null or id <> p_excluded)) x)
  update public.ratings r set group_position = g.position from groups g
  where r.owner_id = p_actor and r.category = p_category and r.sentiment = g.sentiment and r.group_position = g.group_position
    and (p_excluded is null or r.id <> p_excluded)
$$;

create or replace function app_private.reflow_rating_category(p_actor uuid, p_category public.experience_category)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.compact_rating_groups(p_actor, p_category);
  with scores as (
    select id, group_position, (max(group_position) over (partition by sentiment) + 1)::numeric as group_count,
           case sentiment when 'liked' then 6.7 when 'fine' then 3.4 else 0.0 end as low,
           case sentiment when 'liked' then 10.0 when 'fine' then 6.6 else 3.3 end as high,
           rank() over (order by sentiment, group_position) as competition_rank
    from public.ratings where owner_id = p_actor and category = p_category)
  update public.ratings r set score = round(case when s.group_count = 1 then (s.high + s.low) / 2
                                          else s.high - s.group_position * (s.high - s.low) / (s.group_count - 1) end, 1),
                               rank = s.competition_rank, updated_at = now()
  from scores s where r.id = s.id;
end;
$$;

create or replace function app_private.category_ranking_json(p_actor uuid, p_category public.experience_category)
returns jsonb language sql stable security definer set search_path = '' as $$
  with groups as (
    select r.sentiment, r.group_position,
           jsonb_agg(jsonb_build_object('ratingID', r.id, 'experienceID', r.experience_id, 'name', pl.name, 'locality', pl.locality,
                                       'firstRatedAt', r.first_rated_at) order by r.first_rated_at, r.id) as entries
    from public.ratings r join public.experiences e on e.id = r.experience_id join public.places pl on pl.id = e.place_id
    where r.owner_id = p_actor and r.category = p_category group by r.sentiment, r.group_position),
  partitions as (select sentiment, jsonb_agg(jsonb_build_object('entries', entries) order by group_position) as items from groups group by sentiment)
  select jsonb_build_object('category', p_category,
    'revision', coalesce((select version from public.category_revisions where owner_id = p_actor and category = p_category), 0),
    'liked', coalesce((select items from partitions where sentiment = 'liked'), '[]'::jsonb),
    'fine', coalesce((select items from partitions where sentiment = 'fine'), '[]'::jsonb),
    'disliked', coalesce((select items from partitions where sentiment = 'disliked'), '[]'::jsonb))
$$;

create or replace function public.category_ranking(p_category public.experience_category)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare me uuid := app_private.require_member();
begin
  if p_category is null then perform app_private.validation_error('Choose a category.'); end if;
  return app_private.category_ranking_json(me, p_category);
end;
$$;

create or replace function public.commit_rating(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  operation uuid;
  experience uuid;
  intent text;
  category public.experience_category;
  sentiment public.sentiment;
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
  activity uuid;
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
    category := (p_request ->> 'category')::public.experience_category;
    sentiment := (p_request ->> 'sentiment')::public.sentiment;
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
  payload := jsonb_build_object('experienceID', experience, 'intent', intent, 'category', category, 'sentiment', sentiment,
                               'baseRevision', base_revision, 'answers', answers, 'visit', visit_payload);
  receipt := app_private.rating_receipt(me, operation, 'commit_rating', payload);
  if receipt is not null then return receipt; end if;

  select * into target from public.experiences where id = experience for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  if target.category_locked_at is not null and target.category <> category then
    perform app_private.validation_error('This experience already has a fixed category.');
  end if;
  revision := app_private.lock_category_revision(me, category);
  if revision <> base_revision then raise exception 'roam:stale_revision' using errcode = '40001'; end if;
  select * into previous from public.ratings where owner_id = me and experience_id = experience;
  if intent = 'first_log' and previous.id is not null then raise exception 'roam:already_rated' using errcode = '22023'; end if;
  if intent = 'rerank' and previous.id is null then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  if intent = 'rerank' and previous.category <> category then perform app_private.validation_error('The category cannot change when ranking again.'); end if;
  select array_agg(g.id order by g.group_position) into representatives
  from (select distinct on (r.group_position) r.id, r.group_position from public.ratings r
        where r.owner_id = me and r.category = commit_rating.category and r.sentiment = commit_rating.sentiment
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
  perform app_private.compact_rating_groups(me, category, previous.id);
  if outcome ->> 'kind' = 'new_group' then
    update public.ratings r set group_position = r.group_position + 1
    where r.owner_id = me and r.category = commit_rating.category and r.sentiment = commit_rating.sentiment and r.group_position >= position
      and (previous.id is null or r.id <> previous.id);
  end if;
  if intent = 'first_log' then
    insert into public.ratings(owner_id, experience_id, category, sentiment, group_position, score, rank)
    values (me, experience, category, sentiment, position, 0, 1) returning id into rating;
  else
    rating := previous.id;
    update public.ratings set sentiment = commit_rating.sentiment, group_position = position, updated_at = now() where id = rating;
  end if;
  perform app_private.reflow_rating_category(me, category);
  revision := revision + 1;
  update public.category_revisions cr set version = revision, updated_at = now() where cr.owner_id = me and cr.category = commit_rating.category;
  update public.experiences set category = commit_rating.category, category_source = 'confirmed',
    category_locked_at = coalesce(category_locked_at, now()) where id = experience;
  if intent = 'first_log' then
    anchor := app_private.write_rating_visit(me, experience, operation, visit_payload);
    delete from public.bookmarks where owner_id = me and experience_id = experience;
  elsif visit_payload is not null then
    perform app_private.write_rating_visit(me, experience, operation, visit_payload, anchor);
  end if;
  insert into public.activities(author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, source_operation_id)
  select me, case when intent = 'first_log' then 'rating'::public.activity_type else 'rerank'::public.activity_type end,
         experience, anchor, r.id, r.category, r.score, r.rank, r.sentiment, operation from public.ratings r where r.id = rating
  returning id into activity;
  select jsonb_build_object('ratingID', r.id, 'visitID', case when intent = 'first_log' then anchor end, 'activityID', activity,
                           'category', r.category, 'sentiment', r.sentiment, 'score', r.score, 'rank', r.rank,
                           'groupSize', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category
                                          and g.sentiment = r.sentiment and g.group_position = r.group_position),
                           'categoryCount', (select count(*) from public.ratings g where g.owner_id = me and g.category = r.category), 'revision', revision)
  into result from public.ratings r where r.id = rating;
  perform app_private.store_rating_receipt(me, operation, 'commit_rating', payload, result);
  return result;
end;
$$;

create or replace function public.add_visit(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  operation uuid;
  experience uuid;
  visit_payload jsonb;
  payload jsonb;
  receipt jsonb;
  current_rating public.ratings;
  visit uuid;
  activity uuid;
  result jsonb;
begin
  perform app_private.assert_json_keys(p_request, array['operationID', 'experienceID', 'visit']);
  if jsonb_typeof(p_request -> 'operationID') is distinct from 'string' or jsonb_typeof(p_request -> 'experienceID') is distinct from 'string'
    or jsonb_typeof(p_request -> 'visit') is distinct from 'object' then perform app_private.validation_error('This visit save is incomplete.'); end if;
  begin
    operation := (p_request ->> 'operationID')::uuid;
    experience := (p_request ->> 'experienceID')::uuid;
  exception when invalid_text_representation then perform app_private.validation_error('Check the visit identifiers.'); end;
  visit_payload := app_private.normalized_visit_payload(p_request -> 'visit');
  payload := jsonb_build_object('experienceID', experience, 'visit', visit_payload);
  receipt := app_private.rating_receipt(me, operation, 'add_visit', payload);
  if receipt is not null then return receipt; end if;
  perform id from public.experiences where id = experience for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  if not found then perform app_private.validation_error('Rank this experience first, then add another visit.'); end if;
  perform app_private.lock_category_revision(me, current_rating.category);
  -- A different experience's commit can reflow this category while the lock is pending.
  -- The revisit snapshot must use the score/rank acknowledged after that transaction.
  select * into current_rating from public.ratings where owner_id = me and experience_id = experience;
  visit := app_private.write_rating_visit(me, experience, operation, visit_payload);
  insert into public.activities(author_id, type, experience_id, visit_id, rating_id, category, score_snapshot, rank_snapshot, sentiment_snapshot, source_operation_id)
  values (me, 'revisit', experience, visit, current_rating.id, current_rating.category, current_rating.score, current_rating.rank, current_rating.sentiment, operation)
  returning id into activity;
  result := jsonb_build_object('visitID', visit, 'activityID', activity);
  perform app_private.store_rating_receipt(me, operation, 'add_visit', payload, result);
  return result;
end;
$$;

create or replace function public.remove_rating(p_experience_id uuid, p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  payload jsonb := jsonb_build_object('experienceID', p_experience_id);
  receipt jsonb;
  current_rating public.ratings;
begin
  receipt := app_private.rating_receipt(me, p_operation_id, 'remove_rating', payload);
  if receipt is not null then return receipt; end if;
  perform id from public.experiences where id = p_experience_id for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  select * into current_rating from public.ratings where owner_id = me and experience_id = p_experience_id;
  if found then
    perform app_private.lock_category_revision(me, current_rating.category);
    delete from public.ratings where id = current_rating.id;
    perform app_private.reflow_rating_category(me, current_rating.category);
    update public.category_revisions set version = version + 1, updated_at = now() where owner_id = me and category = current_rating.category;
  end if;
  perform app_private.store_rating_receipt(me, p_operation_id, 'remove_rating', payload, '{}'::jsonb);
  return '{}'::jsonb;
end;
$$;

create or replace function public.delete_visit(p_visit_id uuid, p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  payload jsonb := jsonb_build_object('visitID', p_visit_id);
  receipt jsonb;
  target_visit public.visits;
  current_rating public.ratings;
  removed boolean := false;
  result jsonb;
begin
  receipt := app_private.rating_receipt(me, p_operation_id, 'delete_visit', payload);
  if receipt is not null then return receipt; end if;
  select * into target_visit from public.visits where id = p_visit_id;
  if found and target_visit.owner_id <> me then raise exception 'roam:forbidden' using errcode = '42501'; end if;
  if target_visit.id is not null then
    perform id from public.experiences where id = target_visit.experience_id for update;
    select * into current_rating from public.ratings where owner_id = me and experience_id = target_visit.experience_id;
    if current_rating.id is not null then perform app_private.lock_category_revision(me, current_rating.category); end if;
    -- Another operation may have deleted this Visit while the experience lock was pending.
    perform id from public.visits where id = p_visit_id and owner_id = me for update;
    if found then
      delete from public.media where visit_id = p_visit_id and owner_id = me;
      delete from public.visits where id = p_visit_id and owner_id = me;
      if current_rating.id is not null and not exists (select 1 from public.visits where owner_id = me and experience_id = target_visit.experience_id) then
        delete from public.ratings where id = current_rating.id;
        perform app_private.reflow_rating_category(me, current_rating.category);
        update public.category_revisions set version = version + 1, updated_at = now() where owner_id = me and category = current_rating.category;
        removed := true;
      end if;
    end if;
  end if;
  result := jsonb_build_object('removedRating', removed);
  perform app_private.store_rating_receipt(me, p_operation_id, 'delete_visit', payload, result);
  return result;
end;
$$;

-- A Save that began before first-log must wait for its experience transaction, then recheck the
-- now-current Rating. This closes the check-then-insert race that could recreate Want after log.
create or replace function public.set_bookmark(p_experience_id uuid, p_saved boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare me uuid := app_private.require_member();
begin
  perform id from public.experiences where id = p_experience_id for update;
  if not found then raise exception 'roam:not_found' using errcode = 'P0002'; end if;
  if p_saved then
    if exists (select 1 from public.ratings where owner_id = me and experience_id = p_experience_id) then
      raise exception 'roam:already_rated' using errcode = '22023';
    end if;
    insert into public.bookmarks(owner_id, experience_id) values (me, p_experience_id) on conflict do nothing;
  else
    delete from public.bookmarks where owner_id = me and experience_id = p_experience_id;
  end if;
  return exists (select 1 from public.bookmarks where owner_id = me and experience_id = p_experience_id);
end;
$$;

revoke execute on function public.category_ranking(public.experience_category), public.commit_rating(jsonb), public.add_visit(jsonb),
  public.remove_rating(uuid, uuid), public.delete_visit(uuid, uuid) from public, anon;
grant execute on function public.category_ranking(public.experience_category), public.commit_rating(jsonb), public.add_visit(jsonb),
  public.remove_rating(uuid, uuid), public.delete_visit(uuid, uuid) to authenticated, service_role;
revoke execute on function app_private.assert_json_keys(jsonb, text[]), app_private.rating_intent_digest(text, jsonb),
  app_private.rating_receipt(uuid, uuid, text, jsonb), app_private.store_rating_receipt(uuid, uuid, text, jsonb, jsonb),
  app_private.lock_category_revision(uuid, public.experience_category), app_private.normalized_visit_payload(jsonb),
  app_private.validate_rating_visit(uuid, jsonb, uuid), app_private.write_rating_visit(uuid, uuid, uuid, jsonb, uuid),
  app_private.replay_insertion(uuid[], jsonb), app_private.compact_rating_groups(uuid, public.experience_category, uuid),
  app_private.reflow_rating_category(uuid, public.experience_category), app_private.category_ranking_json(uuid, public.experience_category)
from public, anon, authenticated;
grant execute on function app_private.assert_json_keys(jsonb, text[]), app_private.rating_intent_digest(text, jsonb),
  app_private.rating_receipt(uuid, uuid, text, jsonb), app_private.store_rating_receipt(uuid, uuid, text, jsonb, jsonb),
  app_private.lock_category_revision(uuid, public.experience_category), app_private.normalized_visit_payload(jsonb),
  app_private.validate_rating_visit(uuid, jsonb, uuid), app_private.write_rating_visit(uuid, uuid, uuid, jsonb, uuid),
  app_private.replay_insertion(uuid[], jsonb), app_private.compact_rating_groups(uuid, public.experience_category, uuid),
  app_private.reflow_rating_category(uuid, public.experience_category), app_private.category_ranking_json(uuid, public.experience_category)
to service_role;
