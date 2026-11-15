-- A profile still in setup is nobody's to find: search and suggestions show only people who finished setup. Setup now
-- makes the profile just before Add friends (search needs one) and sends friend requests only when it finishes.

CREATE OR REPLACE FUNCTION public.suggested_members(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('member', app_private.member_json(s.id), 'friendState', app_private.friend_state(me, s.id), 'isSelf', false) order by s.rated desc, s.handle)
    from (
      select p.id, p.handle,
             (select count(*) from public.ratings r where r.owner_id = p.id) as rated,
             exists (select 1 from public.follows f where f.follower_id = p.id and f.followee_id = me) as follows_me
      from public.profiles p
      where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
        and p.setup_checkpoint = 'complete'
        and not exists (select 1 from public.follows f where f.follower_id = me and f.followee_id = p.id)
      order by rated desc, p.handle
      limit least(greatest(coalesce(p_limit, 10), 1), 30)
    ) s), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_members(p_query text, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := app_private.require_member();
  q text := lower(btrim(coalesce(p_query, '')));
  rows jsonb;
begin
  if q = '' then
    return jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null);
  end if;
  with page as (
    select p.id, p.handle from public.profiles p
    where p.id <> me and p.deactivated_at is null and not app_private.is_blocked_pair(me, p.id)
      and p.setup_checkpoint = 'complete'
      and (strpos(lower(p.handle), q) > 0 or strpos(lower(p.display_name), q) > 0)
      and (p_cursor is null or p.handle > p_cursor)
    -- Handles are unique and lowercase, so this is also the cursor's stable tie-break.
    order by p.handle limit 31)
  select jsonb_agg(jsonb_build_object(
           'member', app_private.member_json(page.id),
           'friendState', app_private.friend_state(me, page.id),
           'isSelf', false) order by page.handle)
  into rows from page;
  rows := coalesce(rows, '[]'::jsonb);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value order by ordinal), '[]'::jsonb)
              from jsonb_array_elements(rows) with ordinality as item(value, ordinal) where ordinal <= 30),
    'nextCursor', case when jsonb_array_length(rows) > 30 then rows -> 29 -> 'member' ->> 'handle' end);
end;
$function$;
