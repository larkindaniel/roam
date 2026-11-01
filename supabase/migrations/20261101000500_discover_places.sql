-- Discover's list: places people rated, with their community score, the friends who rated them and a
-- cover photo. Only ratings and photos this viewer may see count.
create or replace function public.discover_places(p_min_lat double precision default null,p_max_lat double precision default null,
                                                  p_min_lon double precision default null,p_max_lon double precision default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('experience',app_private.experience_summary_json(x.id,v_me),
      'communityScore',x.score,'communityCount',x.raters,
      'friendNames',coalesce((select jsonb_agg(p.display_name order by p.display_name)
                              from public.ratings r join public.profiles p on p.id=r.owner_id
                              where r.experience_id=x.id and r.owner_id<>v_me and app_private.are_friends(v_me,r.owner_id)
                                and app_private.audience_allows(r.owner_id,r.audience,v_me)),'[]'::jsonb),
      'coverPath',(select m.bucket||'/'||m.object_path from public.media m join public.visits v on v.id=m.visit_id
                   where v.experience_id=x.id and m.state='attached' and app_private.audience_allows(v.owner_id,v.audience,v_me)
                   order by v.created_at desc,m.position limit 1)) order by x.score desc,x.id)
    from(select e.id,round(avg(r.score),1) score,count(*)::int raters
         from public.experiences e join public.places pl on pl.id=e.place_id
         join public.ratings r on r.experience_id=e.id and app_private.audience_allows(r.owner_id,r.audience,v_me)
         where (p_min_lat is null or pl.latitude between p_min_lat and p_max_lat)
           and (p_min_lon is null or pl.longitude between p_min_lon and p_max_lon)
         group by e.id order by score desc,e.id limit 40)x),'[]'::jsonb);
end$$;
revoke execute on function public.discover_places(double precision,double precision,double precision,double precision) from public,anon;
grant execute on function public.discover_places(double precision,double precision,double precision,double precision) to authenticated;
