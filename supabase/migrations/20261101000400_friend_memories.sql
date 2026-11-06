-- What friends said about one place, listed apart from other travellers. Only entries the viewer may
-- see are returned, each with that friend's current score when they ranked the place.
create or replace function public.friend_memories(p_experience_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'author',app_private.member_json(v.owner_id),'experienceID',v.experience_id,
      'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),'publicNote',v.public_note,
      'media',app_private.visit_json(v.id)->'media','createdAt',v.created_at,'updatedAt',v.updated_at,'isOwn',false,
      'score',(select r.score from public.ratings r where r.owner_id=v.owner_id and r.experience_id=v.experience_id))
      order by v.created_at desc,v.id desc)
    from(select x.* from public.visits x
         where x.experience_id=p_experience_id and x.owner_id<>v_me and app_private.are_friends(v_me,x.owner_id)
           and app_private.audience_allows(x.owner_id,x.audience,v_me)
         order by x.created_at desc,x.id desc limit 30)v),'[]'::jsonb);
end$$;
revoke execute on function public.friend_memories(uuid) from public,anon;
grant execute on function public.friend_memories(uuid) to authenticated;
