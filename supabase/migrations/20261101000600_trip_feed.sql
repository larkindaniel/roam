-- The Friends tab: one card per person and trip, with visits outside any trip under Home. A new visit moves
-- its card to the top. Only visits the viewer may see count, so a trip with none visible never appears, and
-- planned places stay hidden unless the trip is shared.
create or replace function app_private.trip_feed_entry(p_visit uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',v.id,'experience',app_private.experience_summary_json(v.experience_id,p_viewer),
    'publicNote',v.public_note,'visitDate',jsonb_build_object('date',v.visit_date,'timeZoneIdentifier',v.time_zone),
    'media',app_private.visit_json(v.id)->'media','createdAt',v.created_at,
    'score',(select r.score from public.ratings r where r.owner_id=v.owner_id and r.experience_id=v.experience_id),
    'activityID',(select a.id from public.activities a where a.visit_id=v.id order by a.published_at desc,a.id desc limit 1))
  from public.visits v where v.id=p_visit
$$;

create or replace function public.trip_feed()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(g.owner_id),'tripID',g.trip_id,
      'tripName',(select t.name from public.trips t where t.id=g.trip_id),'visitCount',g.visits,'latestAt',g.latest,'isOwn',g.owner_id=v_me,
      'entries',(select jsonb_agg(app_private.trip_feed_entry(l.id,v_me) order by l.created_at desc)
                 from(select x.id,x.created_at from public.visits x
                      where x.owner_id=g.owner_id and x.trip_id is not distinct from g.trip_id and app_private.audience_allows(x.owner_id,x.audience,v_me)
                      order by x.created_at desc,x.id desc limit 5)l)) order by g.latest desc,g.owner_id,g.trip_id)
    from(select v.owner_id,v.trip_id,count(*)::int visits,max(v.created_at) latest from public.visits v
         where app_private.audience_allows(v.owner_id,v.audience,v_me)
           and(v.owner_id=v_me or(app_private.are_friends(v_me,v.owner_id)
               and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=v.owner_id)))
         group by v.owner_id,v.trip_id order by latest desc limit 50)g),'[]'::jsonb);
end$$;

create or replace function public.trip_updates(p_owner uuid,p_trip_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.trip_feed_entry(v.id,v_me) order by v.created_at desc,v.id desc)
    from public.visits v where v.owner_id=p_owner and v.trip_id is not distinct from p_trip_id
      and app_private.audience_allows(v.owner_id,v.audience,v_me)),'[]'::jsonb);
end$$;

revoke execute on function app_private.trip_feed_entry(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.trip_feed_entry(uuid,uuid) to service_role;
revoke execute on function public.trip_feed(),public.trip_updates(uuid,uuid) from public,anon;
grant execute on function public.trip_feed(),public.trip_updates(uuid,uuid) to authenticated;
