-- User queries are literal substrings, including _, % and backslash. LIKE treated these
-- differently across handle/display-name predicates and admitted unrelated fixture members.
create or replace function public.search_members(p_query text, p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
      and (strpos(lower(p.handle), q) > 0 or strpos(lower(p.display_name), q) > 0)
      and (p_cursor is null or p.handle > p_cursor)
    -- Handles are unique and lowercase, so this is also the cursor's stable tie-break.
    order by p.handle limit 31)
  select jsonb_agg(jsonb_build_object(
           'member', app_private.member_json(page.id),
           'isFollowing', exists (select 1 from public.follows f where f.follower_id = me and f.followee_id = page.id),
           'followsViewer', exists (select 1 from public.follows f where f.follower_id = page.id and f.followee_id = me),
           'isSelf', false) order by page.handle)
  into rows from page;
  rows := coalesce(rows, '[]'::jsonb);
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(value order by ordinal), '[]'::jsonb)
              from jsonb_array_elements(rows) with ordinality as item(value, ordinal) where ordinal <= 30),
    'nextCursor', case when jsonb_array_length(rows) > 30 then rows -> 29 -> 'member' ->> 'handle' end);
end;
$$;

revoke execute on function public.search_members(text, text) from public, anon;
grant execute on function public.search_members(text, text) to authenticated;
