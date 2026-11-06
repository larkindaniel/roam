-- The Friends tab: one card per person and country, a new visit moving its card to the top. Only visits the
-- viewer may see count, so a country with none visible never appears.
create or replace function public.country_feed()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(g.owner_id),'countryCode',g.country_code,
      'countryName',g.country_name,'placeCount',g.places,'latestAt',g.latest,'isOwn',g.owner_id=v_me,
      'entries',(select jsonb_agg(app_private.trip_feed_entry(l.id,v_me) order by l.created_at desc)
                 from(select x.id,x.created_at from public.visits x
                      join public.experiences e on e.id=x.experience_id join public.places pl on pl.id=e.place_id
                      where x.owner_id=g.owner_id and pl.country_code is not distinct from g.country_code
                        and app_private.audience_allows(x.owner_id,x.audience,v_me)
                      order by x.created_at desc,x.id desc limit 5)l)) order by g.latest desc,g.owner_id,g.country_code)
    from(select v.owner_id,pl.country_code,max(pl.country_name) country_name,count(distinct v.experience_id)::int places,max(v.created_at) latest
         from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
         where app_private.audience_allows(v.owner_id,v.audience,v_me)
           and(v.owner_id=v_me or(app_private.are_friends(v_me,v.owner_id)
               and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=v.owner_id)))
         group by v.owner_id,pl.country_code order by latest desc limit 50)g),'[]'::jsonb);
end$$;

create or replace function public.country_updates(p_owner uuid,p_country_code text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.trip_feed_entry(v.id,v_me) order by v.created_at desc,v.id desc)
    from public.visits v join public.experiences e on e.id=v.experience_id join public.places pl on pl.id=e.place_id
    where v.owner_id=p_owner and pl.country_code is not distinct from p_country_code
      and app_private.audience_allows(v.owner_id,v.audience,v_me)),'[]'::jsonb);
end$$;

revoke execute on function public.country_feed(),public.country_updates(uuid,text) from public,anon;
grant execute on function public.country_feed(),public.country_updates(uuid,text) to authenticated;
