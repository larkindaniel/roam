-- The authenticated deletion function creates the job. Only a server-side caller can record
-- whether Apple accepted revocation of a token obtained from that same member's recent code.
create or replace function public.set_account_deletion_apple_revocation(p_user uuid,p_state text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_user is null or p_state not in ('completed','failed') then
    perform app_private.validation_error('Invalid Apple revocation result.');
  end if;
  update app_private.account_deletion_jobs
    set apple_revocation=case when apple_revocation='completed' then 'completed' else p_state end,
        updated_at=now()
    where user_id=p_user and apple_revocation<>'not_applicable';
  return found;
end$$;
revoke execute on function public.set_account_deletion_apple_revocation(uuid,text) from public,anon,authenticated;
grant execute on function public.set_account_deletion_apple_revocation(uuid,text) to service_role;

-- A leased cleanup worker can race the Apple request. Preserve a recorded result even when
-- it claimed the job while revocation was still pending.
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
  update app_private.account_deletion_jobs
    set apple_revocation=case when v_job.apple_revocation in ('completed','failed') then v_job.apple_revocation else p_apple_revocation end,
        last_error=null,claimed_by=null,lease_expires_at=null,
        next_attempt_at=now()+interval'30 seconds',updated_at=now()
    where id=p_job returning * into v_job;
  return public.refresh_account_deletion(p_job);
end$$;
