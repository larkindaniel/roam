-- Correct the commit locals: function-name qualification does not name this DECLARE block.
-- Distinct v_ variables let SQL resolve every category/sentiment column and local explicitly.
create or replace function public.commit_rating(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
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

-- Last-Visit consent must survive concurrent deletions; callers explicitly authorize Rating removal.
drop function public.delete_visit(uuid, uuid);
create or replace function public.delete_visit(p_visit_id uuid, p_operation_id uuid, p_allow_rating_removal boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  payload jsonb := jsonb_build_object('visitID', p_visit_id, 'allowRatingRemoval', coalesce(p_allow_rating_removal, false));
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
      -- Consent is checked against the locked current state, since another client can have
      -- removed the other Visit after the ordinary deletion dialog was opened.
      if current_rating.id is not null and p_allow_rating_removal is not true
        and not exists (select 1 from public.visits where owner_id = me and experience_id = target_visit.experience_id and id <> p_visit_id) then
        raise exception 'roam:confirm_last_visit' using errcode = '22023';
      end if;
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

revoke execute on function public.delete_visit(uuid, uuid, boolean) from public, anon;
grant execute on function public.delete_visit(uuid, uuid, boolean) to authenticated, service_role;
