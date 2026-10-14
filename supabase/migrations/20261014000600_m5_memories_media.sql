-- M5: memory edits, retained public memories, inspected private uploads, standalone post removal
-- and durable media cleanup.
alter table public.media add column inspected_at timestamptz;
alter table public.media add column content_sha256 text check(content_sha256 is null or content_sha256 ~ '^[a-f0-9]{64}$');
alter table public.media add column upload_attempt_id uuid;
alter table public.media add column expires_at timestamptz;
-- The exact stored object the inspector measured. A later replacement at the same path is a
-- different object and can never inherit this inspection.
alter table public.media add column storage_object_id uuid;
create unique index media_owner_attempt on public.media(owner_id,upload_attempt_id) where upload_attempt_id is not null;
create index visits_public_memories on public.visits(experience_id,created_at desc,id desc);
alter table app_private.storage_cleanup add column claimed_by uuid;
alter table app_private.storage_cleanup add column lease_expires_at timestamptz;
alter table app_private.storage_cleanup add column next_attempt_at timestamptz not null default now();

create or replace function public.visit(p_visit_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_owner uuid;
begin
  select owner_id into v_owner from public.visits where id=p_visit_id;
  if v_owner is null or not app_private.can_see_member(v_owner) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return app_private.visit_json(p_visit_id);
end$$;

-- Visit-backed public memories outlive rating activity: removing a ranking keeps them here.
create or replace function public.public_memories(p_experience_id uuid,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb; v_date timestamptz; v_id uuid; v_rows jsonb;
begin
  if not exists(select 1 from public.experiences where id=p_experience_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if p_cursor is not null then
    begin
      v_cursor:=convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
      v_date:=(v_cursor->>'createdAt')::timestamptz; v_id:=(v_cursor->>'id')::uuid;
      if v_date is null or v_id is null then raise exception 'invalid cursor'; end if;
    exception when others then perform app_private.validation_error('This memory page has an invalid cursor.'); end;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
    'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),'publicNote',v.public_note,
    'media',app_private.visit_json(v.id)->'media','createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',v.owner_id=v_me,
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1))
    order by v.created_at desc,v.id desc),'[]') into v_rows
  from(select x.* from public.visits x join public.profiles p on p.id=x.owner_id and p.deactivated_at is null
       where x.experience_id=p_experience_id and not app_private.is_blocked_pair(v_me,x.owner_id)
         and(p_cursor is null or(x.created_at,x.id)<(v_date,v_id)) order by x.created_at desc,x.id desc limit 31)v;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value order by ordinal),'[]') from jsonb_array_elements(v_rows) with ordinality t(value,ordinal) where ordinal<=30),
    'nextCursor',case when jsonb_array_length(v_rows)>30 then translate(encode(convert_to(jsonb_build_object('createdAt',v_rows->29->>'createdAt','id',v_rows->29->>'id')::text,'UTF8'),'base64'),E'\n','') end);
end$$;

-- Editing a Visit changes its public projection in place; publication time never moves.
create or replace function public.update_visit(p_visit_id uuid,p_payload jsonb,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_payload jsonb:=app_private.normalized_visit_payload(p_payload); v_receipt jsonb; v_visit public.visits; v_result jsonb;
begin
  v_receipt:=app_private.rating_receipt(v_me,p_operation_id,'update_visit',jsonb_build_object('visitID',p_visit_id,'visit',v_payload));
  if v_receipt is not null then return v_receipt; end if;
  select * into v_visit from public.visits where id=p_visit_id;
  if v_visit.id is null then raise exception 'roam:not_found' using errcode='P0002'; end if;
  if v_visit.owner_id<>v_me then raise exception 'roam:forbidden' using errcode='42501'; end if;
  perform id from public.experiences where id=v_visit.experience_id for update;
  perform id from public.visits where id=p_visit_id and owner_id=v_me for update;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
  perform app_private.write_rating_visit(v_me,v_visit.experience_id,p_operation_id,v_payload,p_visit_id);
  v_result:=app_private.visit_json(p_visit_id);
  perform app_private.store_rating_receipt(v_me,p_operation_id,'update_visit',jsonb_build_object('visitID',p_visit_id,'visit',v_payload),v_result);
  return v_result;
end$$;

create or replace function public.my_private_note(p_experience_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_result jsonb;
begin
  select jsonb_build_object('experienceID',experience_id,'text',body,'updatedAt',updated_at) into v_result from public.private_notes where owner_id=v_me and experience_id=p_experience_id;
  return v_result;
end$$;

create or replace function public.save_private_note(p_experience_id uuid,p_text text,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_payload jsonb:=jsonb_build_object('experienceID',p_experience_id,'text',p_text); v_receipt jsonb; v_result jsonb;
begin
  v_receipt:=app_private.rating_receipt(v_me,p_operation_id,'save_private_note',v_payload);
  if v_receipt is not null then return v_receipt; end if;
  if p_text is null or char_length(p_text)<1 or char_length(p_text)>10000 then perform app_private.validation_error('Use 1–10,000 characters for your private note.'); end if;
  perform id from public.experiences where id=p_experience_id for update;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
  insert into public.private_notes(owner_id,experience_id,body) values(v_me,p_experience_id,p_text)
  on conflict(owner_id,experience_id) do update set body=excluded.body,updated_at=now();
  v_result:=public.my_private_note(p_experience_id);
  perform app_private.store_rating_receipt(v_me,p_operation_id,'save_private_note',v_payload,v_result);
  return v_result;
end$$;

create or replace function public.delete_private_note(p_experience_id uuid,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_payload jsonb:=jsonb_build_object('experienceID',p_experience_id); v_receipt jsonb;
begin
  v_receipt:=app_private.rating_receipt(v_me,p_operation_id,'delete_private_note',v_payload);
  if v_receipt is not null then return v_receipt; end if;
  perform id from public.experiences where id=p_experience_id for update;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
  delete from public.private_notes where owner_id=v_me and experience_id=p_experience_id;
  perform app_private.store_rating_receipt(v_me,p_operation_id,'delete_private_note',v_payload,'{}');
  return '{}';
end$$;

-- Removing a post alone keeps the Rating and Visit. Its likes, comments and their notifications
-- cascade with it. Repeating the removal is a no-op.
create or replace function public.delete_activity(p_activity_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_author uuid;
begin
  select author_id into v_author from public.activities where id=p_activity_id for update;
  if v_author is null then return false; end if;
  if v_author<>v_me then raise exception 'roam:forbidden' using errcode='42501'; end if;
  delete from public.activities where id=p_activity_id and author_id=v_me;
  return true;
end$$;

-- Only the verified Edge inspector may submit measured data. Client-declared MIME/dimensions
-- are insufficient. Each immutable upload path can be inspected/retried without duplicate IDs,
-- and the eTag binds the measurement to the exact stored bytes the inspector downloaded.
create or replace function public.finalize_media_inspection(p_actor uuid,p_attempt uuid,p_purpose public.media_purpose,
  p_width integer,p_height integer,p_byte_size integer,p_sha256 text,p_etag text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_bucket text:=case when p_purpose='avatar' then 'avatars' else 'visit-media' end;
  v_path text:=p_actor::text||'/'||p_attempt::text||'.jpg'; v_object storage.objects; v_media public.media; v_expiry timestamptz;
begin
  if p_actor is null or p_attempt is null or p_purpose is null or p_width not between 1 and 2048 or p_height not between 1 and 2048
    or p_byte_size not between 1 and 3145728 or p_sha256 is null or p_sha256!~'^[a-f0-9]{64}$' or nullif(p_etag,'') is null then
    perform app_private.validation_error('Invalid inspected photo.');
  end if;
  if not exists(select 1 from public.profiles where id=p_actor and deactivated_at is null) then raise exception 'roam:account_disabled' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('media:'||v_bucket||':'||v_path,0));
  select * into v_media from public.media where owner_id=p_actor and bucket=v_bucket and object_path=v_path for update;
  -- A queued cleanup is a tombstone: an expired or discarded path is never revived.
  if exists(select 1 from app_private.storage_cleanup where bucket=v_bucket and object_path=v_path) then raise exception 'roam:media_expired' using errcode='22023'; end if;
  select * into v_object from storage.objects where bucket_id=v_bucket and name=v_path;
  if not found then perform app_private.validation_error('The photo has not finished uploading.'); end if;
  if (v_object.metadata->>'size')::bigint is distinct from p_byte_size::bigint or (v_object.metadata->>'eTag') is distinct from p_etag then
    perform app_private.validation_error('The photo changed while it was being checked. Retry the upload.');
  end if;
  v_expiry:=v_object.created_at+interval'24 hours';
  if v_media.state is distinct from 'attached' and v_expiry<=now() then
    perform app_private.enqueue_storage_cleanup(v_bucket,v_path,'expired_upload');
    raise exception 'roam:media_expired' using errcode='22023';
  end if;
  if v_media.content_sha256 is not null and(v_media.content_sha256<>p_sha256 or v_media.purpose<>p_purpose) then raise exception 'roam:operation_conflict' using errcode='23505'; end if;
  if v_media.id is null then
    insert into public.media(owner_id,purpose,bucket,object_path,byte_size,width,height,inspected_at,content_sha256,upload_attempt_id,expires_at,storage_object_id)
    values(p_actor,p_purpose,v_bucket,v_path,p_byte_size,p_width,p_height,now(),p_sha256,p_attempt,v_expiry,v_object.id) returning * into v_media;
  else
    update public.media set byte_size=p_byte_size,width=p_width,height=p_height,inspected_at=now(),content_sha256=p_sha256,
      upload_attempt_id=p_attempt,expires_at=v_expiry,storage_object_id=v_object.id where id=v_media.id returning * into v_media;
  end if;
  return jsonb_build_object('id',v_media.id,'path',v_media.bucket||'/'||v_media.object_path,'width',v_media.width,'height',v_media.height,
    'expiresAt',case when v_media.state='staged' then v_media.expires_at end);
end$$;

revoke execute on function public.register_media(text,text,public.media_purpose,integer,integer) from public,anon,authenticated;

-- Newly attached photos must be unexpired, inspected and still the exact measured object. Photos
-- already attached to this Visit were accepted when attached and may simply be kept or reordered.
create or replace function app_private.validate_rating_visit(p_actor uuid,p_payload jsonb,p_anchor uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_ids uuid[]:=array(select value::uuid from jsonb_array_elements_text(p_payload->'mediaIDs')); v_count integer;
begin
  if(p_payload->>'date')::date>(now() at time zone coalesce(p_payload->>'timeZoneIdentifier','UTC'))::date then perform app_private.validation_error('A completed visit cannot be in the future.'); end if;
  perform id from public.media where id=any(v_ids) order by id for update;
  if exists(select 1 from public.media where id=any(v_ids) and owner_id=p_actor and state='staged' and coalesce(expires_at,created_at+interval'24 hours')<=now()) then raise exception 'roam:media_expired' using errcode='22023'; end if;
  select count(*)::integer into v_count from public.media m join storage.objects o on o.bucket_id=m.bucket and o.name=m.object_path
  where m.id=any(v_ids) and m.owner_id=p_actor and m.purpose='visit' and m.bucket='visit-media'
    and split_part(m.object_path,'/',1)=p_actor::text and m.byte_size between 1 and 3145728
    and((m.state='staged' and m.visit_id is null and m.expires_at>now() and m.inspected_at is not null and m.content_sha256 is not null
         and o.id=m.storage_object_id and(o.metadata->>'size')::bigint=m.byte_size)
      or(p_anchor is not null and m.state='attached' and m.visit_id=p_anchor));
  if v_count<>cardinality(v_ids) then perform app_private.validation_error('A photo is not inspected, uploaded, owned by you, or available for this visit.'); end if;
end$$;

-- Registered objects change only through server-owned media lifecycle and cleanup. Clients may
-- delete only their own unregistered uploads (for example an abandoned attempt).
create or replace function app_private.object_is_registered(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.media m where m.bucket=p_bucket and m.object_path=p_name)
    or(p_bucket='avatars' and exists(select 1 from public.profiles p where p.avatar_path=p_name))
$$;
revoke execute on function app_private.object_is_registered(text,text) from public,anon;
grant execute on function app_private.object_is_registered(text,text) to authenticated,service_role;
drop policy roam_objects_delete on storage.objects;
create policy roam_objects_delete on storage.objects for delete to authenticated using(
  bucket_id in('visit-media','avatars')
  and(storage.foldername(name))[1]=(select auth.uid()::text)
  and not app_private.object_is_registered(bucket_id,name)
);

create or replace function public.sweep_media_orphans()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_media record; v_object record; v_registered integer:=0; v_unregistered integer:=0;
begin
  for v_media in select id from public.media where state='staged' and coalesce(expires_at,created_at+interval'24 hours')<=now() order by id for update skip locked loop
    delete from public.media where id=v_media.id and state='staged'; v_registered:=v_registered+1;
  end loop;
  for v_object in select bucket_id,name from storage.objects where bucket_id in('avatars','visit-media') and created_at<=now()-interval'24 hours' loop
    perform pg_advisory_xact_lock(hashtextextended('media:'||v_object.bucket_id||':'||v_object.name,0));
    if not app_private.object_is_registered(v_object.bucket_id,v_object.name)
      and not exists(select 1 from app_private.storage_cleanup j where j.bucket=v_object.bucket_id and j.object_path=v_object.name and j.done_at is null) then
      perform app_private.enqueue_storage_cleanup(v_object.bucket_id,v_object.name,'unregistered_upload'); v_unregistered:=v_unregistered+1;
    end if;
  end loop;
  return jsonb_build_object('registered',v_registered,'unregistered',v_unregistered);
end$$;

create or replace function public.claim_media_cleanup(p_worker uuid,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_jobs jsonb;
begin
  if p_worker is null or p_limit not between 1 and 100 then perform app_private.validation_error('Invalid cleanup claim.'); end if;
  with candidates as(select j.id from app_private.storage_cleanup j where j.done_at is null and j.next_attempt_at<=now()
      and(j.lease_expires_at is null or j.lease_expires_at<=now())
      and not app_private.object_is_registered(j.bucket,j.object_path)
      order by j.created_at,j.id limit p_limit for update skip locked),
  claimed as(update app_private.storage_cleanup j set claimed_by=p_worker,lease_expires_at=now()+interval'120 seconds',attempts=j.attempts+1
      from candidates c where j.id=c.id returning j.id,j.bucket,j.object_path,j.attempts)
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'bucket',bucket,'path',object_path,'attempt',attempts) order by id),'[]') into v_jobs from claimed;
  return v_jobs;
end$$;

create or replace function public.finish_media_cleanup(p_job bigint,p_worker uuid,p_error text default null)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  update app_private.storage_cleanup set done_at=case when p_error is null then now() end,
    last_error=case when p_error is null then null else left(p_error,500) end,
    next_attempt_at=case when p_error is null then now() else now()+make_interval(secs=>least(3600,60*power(2,least(attempts,6)))::integer) end,
    claimed_by=null,lease_expires_at=null where id=p_job and claimed_by=p_worker and done_at is null;
  return found;
end$$;

revoke execute on function public.visit(uuid),public.public_memories(uuid,text),public.update_visit(uuid,jsonb,uuid),public.my_private_note(uuid),
  public.save_private_note(uuid,text,uuid),public.delete_private_note(uuid,uuid),public.delete_activity(uuid) from public,anon;
grant execute on function public.visit(uuid),public.public_memories(uuid,text),public.update_visit(uuid,jsonb,uuid),public.my_private_note(uuid),
  public.save_private_note(uuid,text,uuid),public.delete_private_note(uuid,uuid),public.delete_activity(uuid) to authenticated;
revoke execute on function public.finalize_media_inspection(uuid,uuid,public.media_purpose,integer,integer,integer,text,text),public.sweep_media_orphans(),
  public.claim_media_cleanup(uuid,integer),public.finish_media_cleanup(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.finalize_media_inspection(uuid,uuid,public.media_purpose,integer,integer,integer,text,text),public.sweep_media_orphans(),
  public.claim_media_cleanup(uuid,integer),public.finish_media_cleanup(bigint,uuid,text) to service_role;

-- Avatar publication uses the same inspection boundary as Visit media.
create or replace function public.update_profile(p_display_name text, p_handle text, p_bio text, p_home_city jsonb, p_avatar_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := app_private.require_member();
  v_city uuid;
  old_avatar text;
  -- Clients send bucket-qualified storage paths; the table stores the object path.
  v_avatar text := nullif(regexp_replace(coalesce(p_avatar_path, ''), '^avatars/', ''), '');
begin
  perform app_private.validate_profile_fields(p_display_name, p_handle, coalesce(p_bio, ''));
  if p_home_city is not null and jsonb_typeof(p_home_city) = 'object' then
    v_city := app_private.upsert_city(p_home_city ->> 'countryCode', p_home_city ->> 'countryName', p_home_city ->> 'region',
                                    p_home_city ->> 'name', (p_home_city ->> 'latitude')::double precision,
                                    (p_home_city ->> 'longitude')::double precision);
    if v_city is null then
      perform app_private.validation_error('Choose a home city from the search results.');
    end if;
  end if;
  select avatar_path into old_avatar from public.profiles where id = me;
  if v_avatar is not null and v_avatar is distinct from old_avatar then
    update public.media m set state = 'attached', attached_at = now()
    where m.object_path = v_avatar and m.owner_id = me and m.purpose = 'avatar' and m.bucket = 'avatars'
      and m.inspected_at is not null and m.content_sha256 is not null
      and (m.state = 'attached' or m.expires_at > now())
      and exists (select 1 from storage.objects o where o.bucket_id = 'avatars' and o.name = v_avatar and o.id = m.storage_object_id);
    if not found then
      raise exception 'roam:forbidden:avatar_not_owned' using errcode = '42501';
    end if;
  end if;
  begin
    update public.profiles
    set display_name = btrim(p_display_name), handle = p_handle, bio = coalesce(p_bio, ''),
        home_city_id = v_city, avatar_path = v_avatar
    where id = me;
  exception when unique_violation then
    raise exception 'roam:handle_taken' using errcode = '23505';
  end;
  if old_avatar is not null and old_avatar is distinct from v_avatar then
    delete from public.media where object_path = old_avatar and owner_id = me and purpose = 'avatar';
  end if;
  return app_private.own_profile_json(me);
end;
$$;
