-- Trip cards are titled by where the visible visits were.
CREATE OR REPLACE FUNCTION public.trip_feed()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(g.owner_id),'tripID',g.trip_id,
      'tripName',(select t.name from public.trips t where t.id=g.trip_id),'visitCount',g.visits,'latestAt',g.latest,'isOwn',g.owner_id=v_me,
      'locations',(select coalesce(jsonb_agg(distinct jsonb_build_object('city',pl.locality,'countryCode',pl.country_code,'country',pl.country_name)),'[]'::jsonb)
                   from public.visits x join public.experiences e on e.id=x.experience_id join public.places pl on pl.id=e.place_id
                   where x.owner_id=g.owner_id and x.trip_id is not distinct from g.trip_id and app_private.audience_allows(x.owner_id,x.audience,v_me)),
      'entries',(select jsonb_agg(app_private.trip_feed_entry(l.id,v_me) order by l.created_at desc)
                 from(select x.id,x.created_at from public.visits x
                      where x.owner_id=g.owner_id and x.trip_id is not distinct from g.trip_id and app_private.audience_allows(x.owner_id,x.audience,v_me)
                      order by x.created_at desc,x.id desc limit 5)l)) order by g.latest desc,g.owner_id,g.trip_id)
    from(select v.owner_id,v.trip_id,count(*)::int visits,max(v.created_at) latest from public.visits v
         where app_private.audience_allows(v.owner_id,v.audience,v_me)
           and(v.owner_id=v_me or(app_private.are_friends(v_me,v.owner_id)
               and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=v.owner_id)))
         group by v.owner_id,v.trip_id order by latest desc limit 50)g),'[]'::jsonb);
end$function$;
