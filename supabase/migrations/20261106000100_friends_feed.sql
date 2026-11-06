-- The Friends tab: friends' visits you may see, newest logged first; the app groups them into a card per friend and city.
-- Visits logged without a date aren't on the Friends tab.
drop function if exists app_private.home_countries(uuid);

create or replace function public.friends_feed()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('author',app_private.member_json(v.owner_id),
        'entry',app_private.trip_feed_entry(v.id,v_me)) order by v.created_at desc,v.id desc)
      from(select x.id,x.owner_id,x.created_at from public.visits x
           where x.owner_id<>v_me and x.visit_date is not null and app_private.audience_allows(x.owner_id,x.audience,v_me)
             and app_private.are_friends(v_me,x.owner_id)
             and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=x.owner_id)
           order by x.created_at desc,x.id desc limit 500)v),'[]'::jsonb);
end$$;

revoke execute on function public.friends_feed() from public,anon;
grant execute on function public.friends_feed() to authenticated;
