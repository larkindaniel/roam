-- M7: travel profile and New this year (from persisted Visits only), per-member settings, and
-- account deletion with recent reauthentication, immediate deactivation and a server-owned,
-- retryable cleanup job.

-- Travel profile ---------------------------------------------------------------------------
-- Visited means at least one persisted Visit. One pin per Experience; city/country counts use
-- canonical geography; bookmarks and home city never count. New this year counts each Experience
-- once when its earliest known visit date falls in the requested calendar year (the device's
-- current year); experiences visited only on unknown dates are counted separately and excluded.
create or replace function public.travel_profile(p_user_id uuid,p_year integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_result jsonb;
begin
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_year is null or p_year not between 1900 and 2999 then perform app_private.validation_error('Choose a calendar year.'); end if;
  with visited as(
    select v.experience_id,min(v.visit_date) as first_known,bool_and(v.visit_date is null) as only_unknown,count(*) as visits
    from public.visits v where v.owner_id=p_user_id group by v.experience_id),
  place as(
    select x.experience_id,x.first_known,x.only_unknown,x.visits,pl.name,pl.latitude,pl.longitude,pl.country_code,
           coalesce(k.name,pl.country_name,pl.country_code) as country_name,c.city_key,c.name as city_name,c.region as city_region,
           coalesce(r.category,e.category) as category
    from visited x join public.experiences e on e.id=x.experience_id join public.places pl on pl.id=e.place_id
    left join public.cities c on c.id=pl.city_id left join public.countries k on k.code=pl.country_code
    left join public.ratings r on r.owner_id=p_user_id and r.experience_id=x.experience_id)
  select jsonb_build_object(
    'pins',coalesce((select jsonb_agg(jsonb_build_object('experienceID',experience_id,'name',name,'category',category,'latitude',latitude,
                     'longitude',longitude,'countryCode',country_code,'countryName',country_name,'cityKey',city_key,'cityName',city_name,
                     'firstVisitDate',first_known,'visitCount',visits) order by name,experience_id) from place),'[]'::jsonb),
    'countryCount',(select count(distinct country_code) from place where country_code is not null),
    'cityCount',(select count(distinct city_key) from place where city_key is not null),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('category',category,'count',n) order by n desc,category nulls last)
                            from(select category,count(*) n from place group by category)g),'[]'::jsonb),
    'cities',coalesce((select jsonb_agg(jsonb_build_object('cityKey',city_key,'name',city_name,'region',city_region,'countryCode',country_code,
                        'countryName',country_name,'count',n) order by n desc,city_name,city_key)
                        from(select city_key,city_name,city_region,country_code,country_name,count(*) n from place
                             where city_key is not null group by city_key,city_name,city_region,country_code,country_name)g),'[]'::jsonb),
    'countries',coalesce((select jsonb_agg(jsonb_build_object('countryCode',country_code,'name',country_name,'count',n) order by n desc,country_name,country_code)
                           from(select country_code,country_name,count(*) n from place where country_code is not null group by country_code,country_name)g),'[]'::jsonb),
    'placesWithoutCity',(select count(*) from place where city_key is null),
    'newThisYear',jsonb_build_object('year',p_year,
      'count',(select count(*) from place where extract(year from first_known)=p_year),
      'unknownDateCount',(select count(*) from place where only_unknown),
      'experienceIDs',coalesce((select jsonb_agg(experience_id order by first_known desc,name,experience_id) from place
                                where extract(year from first_known)=p_year),'[]'::jsonb)))
  into v_result;
  return v_result;
end$$;

-- Settings --------------------------------------------------------------------------------
create or replace function app_private.settings_json(p_user uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('distanceUnit',distance_unit,'hapticsEnabled',haptics_enabled,'notifyFollows',notify_follows,
                            'notifyLikes',notify_likes,'notifyComments',notify_comments)
  from public.user_settings where user_id=p_user
$$;

create or replace function public.my_settings()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  insert into public.user_settings(user_id) values(v_me) on conflict(user_id) do nothing;
  return app_private.settings_json(v_me);
end$$;

-- Desired state: the whole settings object is replaced, so a retried save is harmless.
create or replace function public.update_settings(p_settings jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  perform app_private.assert_json_keys(p_settings,array['distanceUnit','hapticsEnabled','notifyFollows','notifyLikes','notifyComments']);
  if coalesce(p_settings->>'distanceUnit','') not in('km','mi')
    or jsonb_typeof(p_settings->'hapticsEnabled') is distinct from 'boolean' or jsonb_typeof(p_settings->'notifyFollows') is distinct from 'boolean'
    or jsonb_typeof(p_settings->'notifyLikes') is distinct from 'boolean' or jsonb_typeof(p_settings->'notifyComments') is distinct from 'boolean' then
    perform app_private.validation_error('Check your settings.');
  end if;
  insert into public.user_settings(user_id,distance_unit,haptics_enabled,notify_follows,notify_likes,notify_comments)
  values(v_me,p_settings->>'distanceUnit',(p_settings->>'hapticsEnabled')::boolean,(p_settings->>'notifyFollows')::boolean,
         (p_settings->>'notifyLikes')::boolean,(p_settings->>'notifyComments')::boolean)
  on conflict(user_id) do update set distance_unit=excluded.distance_unit,haptics_enabled=excluded.haptics_enabled,
    notify_follows=excluded.notify_follows,notify_likes=excluded.notify_likes,notify_comments=excluded.notify_comments;
  return app_private.settings_json(v_me);
end$$;

-- Profile creation: a token for a removed or deactivated account cannot recreate a profile.
create or replace function public.create_profile(p_display_name text, p_handle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or not exists (select 1 from auth.users where id = uid) then
    raise exception 'roam:not_signed_in' using errcode = '42501';
  end if;
  if exists (select 1 from app_private.account_deletion_jobs where user_id = uid)
     or exists (select 1 from public.profiles where id = uid and deactivated_at is not null) then
    raise exception 'roam:account_disabled' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = uid) then
    -- Retried creation returns the existing profile unchanged.
    return app_private.own_profile_json(uid);
  end if;
  perform app_private.validate_profile_fields(p_display_name, p_handle, '');
  begin
    insert into public.profiles (id, handle, display_name) values (uid, p_handle, btrim(p_display_name));
  exception when unique_violation then
    raise exception 'roam:handle_taken' using errcode = '23505';
  end;
  insert into public.user_settings (user_id) values (uid) on conflict do nothing;
  return app_private.own_profile_json(uid);
end;
$$;

-- Account deletion --------------------------------------------------------------------------
alter table app_private.account_deletion_jobs add column claimed_by uuid;
alter table app_private.account_deletion_jobs add column lease_expires_at timestamptz;
alter table app_private.account_deletion_jobs add column next_attempt_at timestamptz not null default now();
alter table app_private.account_deletion_jobs add column relational_deleted_at timestamptz;

create or replace function app_private.deletion_status_json(p_job app_private.account_deletion_jobs)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_build_object('state',p_job.state,'appleRevocation',p_job.apple_revocation,'storageCleanup',p_job.storage_cleanup,
                            'updatedAt',p_job.updated_at)
$$;

-- Deleting needs a sign-in within the last 10 minutes: the token's authentication-method time,
-- which a token refresh does not renew. The account is hidden and write-disabled at once, and
-- every session and refresh token is revoked; the leased worker then deletes the data.
create or replace function public.request_account_deletion()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_recent boolean; v_job app_private.account_deletion_jobs;
begin
  if v_uid is null then raise exception 'roam:not_signed_in' using errcode='42501'; end if;
  select exists(select 1 from jsonb_array_elements(case when jsonb_typeof(auth.jwt()->'amr')='array' then auth.jwt()->'amr' else '[]'::jsonb end) a
                where jsonb_typeof(a->'timestamp')='number' and (a->>'timestamp')::numeric>=extract(epoch from now())-600)
  into v_recent;
  if not v_recent then raise exception 'roam:reauthentication_required' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account-deletion:'||v_uid,0));
  select * into v_job from app_private.account_deletion_jobs where user_id=v_uid;
  if not found then
    if not exists(select 1 from auth.users where id=v_uid) then raise exception 'roam:not_signed_in' using errcode='42501'; end if;
    insert into app_private.account_deletion_jobs(user_id,apple_revocation)
    values(v_uid,case when exists(select 1 from auth.identities i where i.user_id=v_uid and i.provider='apple') then 'pending' else 'not_applicable' end)
    returning * into v_job;
  end if;
  update public.profiles set deactivated_at=coalesce(deactivated_at,now()) where id=v_uid;
  delete from auth.refresh_tokens where user_id=v_uid::text;
  delete from auth.sessions where user_id=v_uid;
  return app_private.deletion_status_json(v_job);
end$$;

-- Readable with the requesting token even after the account is gone (it reveals only that job).
create or replace function public.account_deletion_status()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_job app_private.account_deletion_jobs;
begin
  if auth.uid() is null then raise exception 'roam:not_signed_in' using errcode='42501'; end if;
  select * into v_job from app_private.account_deletion_jobs where user_id=auth.uid();
  if not found then return null; end if;
  return app_private.deletion_status_json(v_job);
end$$;

-- Server-owned worker steps (service role only); each is idempotent and safe to retry.
create or replace function public.claim_account_deletions(p_worker uuid,p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_jobs jsonb;
begin
  if p_worker is null or p_limit is null or p_limit not between 1 and 50 then perform app_private.validation_error('Invalid deletion claim.'); end if;
  with candidates as(select j.id from app_private.account_deletion_jobs j
      where j.state in('pending','processing','failed') and j.next_attempt_at<=now() and(j.lease_expires_at is null or j.lease_expires_at<=now())
      order by j.requested_at,j.id limit p_limit for update skip locked),
  claimed as(update app_private.account_deletion_jobs j set claimed_by=p_worker,lease_expires_at=now()+interval'300 seconds',
      state='processing',attempts=j.attempts+1,updated_at=now() from candidates c where j.id=c.id returning j.*)
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'userID',user_id,'appleRevocation',apple_revocation,'attempt',attempts)
                            order by requested_at,id),'[]'::jsonb)
  into v_jobs from claimed;
  return v_jobs;
end$$;

-- Deletes every member-owned row (the profile cascade), queues every stored object in the member's
-- folders for the durable Storage cleanup worker, strips the member's id from shared place
-- provenance and removes the auth user (identities, sessions and refresh tokens cascade).
-- Reports keep a null reporter (M2 decision); places and experiences are shared and stay.
create or replace function public.process_account_deletion(p_job uuid,p_worker uuid,p_apple_revocation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job app_private.account_deletion_jobs; v_object record;
begin
  select * into v_job from app_private.account_deletion_jobs where id=p_job and claimed_by=p_worker and lease_expires_at>now() for update;
  if not found then raise exception 'roam:forbidden:not_leased' using errcode='42501'; end if;
  if p_apple_revocation is null or p_apple_revocation not in('not_applicable','completed','not_configured','failed')
     or (v_job.apple_revocation='not_applicable' and p_apple_revocation<>'not_applicable') then
    perform app_private.validation_error('Invalid revocation state.');
  end if;
  if v_job.relational_deleted_at is null then
    update public.places set provenance=provenance-'resolvedBy' where provenance->>'resolvedBy'=v_job.user_id::text;
    delete from public.profiles where id=v_job.user_id;
    delete from auth.users where id=v_job.user_id;
    update app_private.account_deletion_jobs set relational_deleted_at=now() where id=p_job returning * into v_job;
  end if;
  for v_object in select o.bucket_id,o.name from storage.objects o
      where o.bucket_id in('avatars','visit-media') and (storage.foldername(o.name))[1]=v_job.user_id::text loop
    if not exists(select 1 from app_private.storage_cleanup j where j.bucket=v_object.bucket_id and j.object_path=v_object.name and j.done_at is null) then
      perform app_private.enqueue_storage_cleanup(v_object.bucket_id,v_object.name,'account_deleted');
    end if;
  end loop;
  update app_private.account_deletion_jobs set apple_revocation=p_apple_revocation,last_error=null,claimed_by=null,lease_expires_at=null,
    next_attempt_at=now()+interval'30 seconds',updated_at=now()
  where id=p_job returning * into v_job;
  return public.refresh_account_deletion(p_job);
end$$;

-- Completes a job once its member's Storage folders are empty; otherwise it stays processing
-- (storage cleanup pending) and is retried. Idempotent.
create or replace function public.refresh_account_deletion(p_job uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job app_private.account_deletion_jobs; v_pending boolean;
begin
  select * into v_job from app_private.account_deletion_jobs where id=p_job for update;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if v_job.relational_deleted_at is not null and v_job.state<>'completed' then
    select exists(select 1 from storage.objects o where o.bucket_id in('avatars','visit-media')
                  and (storage.foldername(o.name))[1]=v_job.user_id::text) into v_pending;
    update app_private.account_deletion_jobs set storage_cleanup=case when v_pending then 'pending' else 'completed' end,
      state=case when v_pending then 'processing'::public.deletion_state else 'completed'::public.deletion_state end,
      completed_at=case when v_pending then null else now() end,updated_at=now()
    where id=p_job returning * into v_job;
  end if;
  return app_private.deletion_status_json(v_job);
end$$;

create or replace function public.fail_account_deletion(p_job uuid,p_worker uuid,p_error text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  update app_private.account_deletion_jobs set state='failed',last_error=left(coalesce(p_error,'unknown'),500),claimed_by=null,lease_expires_at=null,
    next_attempt_at=now()+make_interval(secs=>least(3600,60*power(2,least(attempts,6)))::integer),updated_at=now()
  where id=p_job and claimed_by=p_worker;
  return found;
end$$;

revoke execute on function public.travel_profile(uuid,integer),public.my_settings(),public.update_settings(jsonb),
  public.request_account_deletion(),public.account_deletion_status() from public,anon;
grant execute on function public.travel_profile(uuid,integer),public.my_settings(),public.update_settings(jsonb),
  public.request_account_deletion(),public.account_deletion_status() to authenticated;
revoke execute on function public.claim_account_deletions(uuid,integer),public.process_account_deletion(uuid,uuid,text),
  public.refresh_account_deletion(uuid),public.fail_account_deletion(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.claim_account_deletions(uuid,integer),public.process_account_deletion(uuid,uuid,text),
  public.refresh_account_deletion(uuid),public.fail_account_deletion(uuid,uuid,text) to service_role;
revoke execute on function app_private.settings_json(uuid),app_private.deletion_status_json(app_private.account_deletion_jobs)
  from public,anon,authenticated;
grant execute on function app_private.settings_json(uuid),app_private.deletion_status_json(app_private.account_deletion_jobs) to service_role;
