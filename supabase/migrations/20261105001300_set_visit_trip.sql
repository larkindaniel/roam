-- Editing a visit can change which of your trips it was part of (or none, for home).
create or replace function public.set_visit_trip(p_visit_id uuid,p_trip_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_trip_id is not null and not exists(select 1 from public.trips t where t.id=p_trip_id and t.owner_id=v_me) then
    raise exception 'roam:not_found' using errcode='P0002';
  end if;
  update public.visits set trip_id=p_trip_id,updated_at=now() where id=p_visit_id and owner_id=v_me;
  if not found then raise exception 'roam:not_found' using errcode='P0002'; end if;
end$$;

revoke execute on function public.set_visit_trip(uuid,uuid) from public,anon;
grant execute on function public.set_visit_trip(uuid,uuid) to authenticated;
