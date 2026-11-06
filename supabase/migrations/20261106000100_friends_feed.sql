-- The Friends tab: friends' visits you may see, each with its trip and its author's home countries, plus yours. The app
-- groups them: by trip; city by city in a country either of you lives in; otherwise by country. Visits logged without a
-- date aren't on the Friends tab.
create or replace function app_private.home_countries(p_owner uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(distinct c.country_code::text),'[]'::jsonb)
  from public.home_cities h join public.cities c on c.id=h.city_id where h.owner_id=p_owner
$$;

create or replace function public.friends_feed()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return jsonb_build_object('myHomeCountries',app_private.home_countries(v_me),
    'visits',coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(v.owner_id),'tripID',v.trip_id,
        'tripName',(select t.name from public.trips t where t.id=v.trip_id),'homeCountries',app_private.home_countries(v.owner_id),
        'entry',app_private.trip_feed_entry(v.id,v_me)) order by v.created_at desc,v.id desc)
      from(select x.id,x.owner_id,x.trip_id,x.created_at from public.visits x
           where x.owner_id<>v_me and x.visit_date is not null and app_private.audience_allows(x.owner_id,x.audience,v_me)
             and app_private.are_friends(v_me,x.owner_id)
             and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=x.owner_id)
           order by x.created_at desc,x.id desc limit 500)v),'[]'::jsonb));
end$$;

revoke execute on function app_private.home_countries(uuid) from public,anon,authenticated;
revoke execute on function public.friends_feed() from public,anon;
grant execute on function public.friends_feed() to authenticated;
