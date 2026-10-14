-- M6: chronological feed, posts, likes, flat comments, follow graph pages, mute/block, Shared Want
-- to Go and in-app notifications. Every RPC derives the actor from the JWT; block rules are enforced
-- in these queries, not by hiding buttons.

-- Cursors are opaque base64 JSON; invalid input is a validation error, never a silent first page.
create or replace function app_private.decode_cursor(p_cursor text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare v_value jsonb;
begin
  if p_cursor is null then return null; end if;
  begin
    v_value := convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
  exception when others then
    perform app_private.validation_error('This page has an invalid cursor. Refresh and try again.');
  end;
  if jsonb_typeof(v_value) is distinct from 'object' or v_value->>'id' is null then
    perform app_private.validation_error('This page has an invalid cursor. Refresh and try again.');
  end if;
  return v_value;
end$$;

create or replace function app_private.encode_cursor(p_value jsonb)
returns text language sql immutable set search_path='' as $$
  select translate(encode(convert_to(p_value::text,'UTF8'),'base64'),E'\n','')
$$;

-- Keyset page: up to 31 ordered rows in, 30 items plus the 30th row's key out.
create or replace function app_private.page_json(p_rows jsonb, p_key text)
returns jsonb language sql immutable set search_path='' as $$
  select jsonb_build_object(
    'items',(select coalesce(jsonb_agg(value order by ordinal),'[]'::jsonb) from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) with ordinality t(value,ordinal) where ordinal<=30),
    'nextCursor',case when jsonb_array_length(coalesce(p_rows,'[]'::jsonb))>30
      then app_private.encode_cursor(jsonb_build_object(p_key,p_rows->29->>p_key,'id',p_rows->29->>'id')) end)
$$;

-- A post is visible to an active member when its author is active and not blocked either way.
create or replace function app_private.activity_visible(p_activity uuid, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.activities a join public.profiles p on p.id=a.author_id and p.deactivated_at is null
                where a.id=p_activity and (a.author_id=p_viewer or not app_private.is_blocked_pair(p_viewer,a.author_id)))
$$;

create or replace function app_private.member_row_json(p_member uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('member',app_private.member_json(p_member),
    'isFollowing',exists(select 1 from public.follows f where f.follower_id=p_viewer and f.followee_id=p_member),
    'followsViewer',exists(select 1 from public.follows f where f.follower_id=p_member and f.followee_id=p_viewer),
    'isSelf',p_member=p_viewer)
$$;

create or replace function app_private.comment_json(p_comment uuid, p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',c.id,'activityID',c.activity_id,'author',app_private.member_json(c.author_id),'body',c.body,
                            'createdAt',c.created_at,'isOwn',c.author_id=p_viewer)
  from public.comments c where c.id=p_comment
$$;

-- Feed ---------------------------------------------------------------------------------------
-- Own posts plus currently followed, unmuted, unblocked, active authors, newest publication first.
create or replace function public.feed(p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.activity_json(x.id,v_me) order by x.published_at desc,x.id desc),'[]') into v_rows
  from(select a.id,a.published_at from public.activities a join public.profiles p on p.id=a.author_id and p.deactivated_at is null
       where(a.author_id=v_me or(exists(select 1 from public.follows f where f.follower_id=v_me and f.followee_id=a.author_id)
                                 and not exists(select 1 from public.mutes m where m.muter_id=v_me and m.muted_id=a.author_id)
                                 and not app_private.is_blocked_pair(v_me,a.author_id)))
         and(v_cursor is null or(a.published_at,a.id)<((v_cursor->>'publishedAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by a.published_at desc,a.id desc limit 31)x;
  return app_private.page_json(v_rows,'publishedAt');
end$$;

-- A member's own posts on their profile; muting affects the feed only.
create or replace function public.profile_activity(p_user_id uuid,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(app_private.activity_json(x.id,v_me) order by x.published_at desc,x.id desc),'[]') into v_rows
  from(select a.id,a.published_at from public.activities a where a.author_id=p_user_id
         and(v_cursor is null or(a.published_at,a.id)<((v_cursor->>'publishedAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by a.published_at desc,a.id desc limit 31)x;
  return app_private.page_json(v_rows,'publishedAt');
end$$;

create or replace function public.activity(p_activity_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if not app_private.activity_visible(p_activity_id,v_me) then raise exception 'roam:unavailable' using errcode='P0002'; end if;
  return app_private.activity_json(p_activity_id,v_me);
end$$;

-- Likes: desired state; a new like notifies the author once per event key.
create or replace function public.set_like(p_activity_id uuid,p_liked boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_author uuid;
begin
  if not app_private.activity_visible(p_activity_id,v_me) then raise exception 'roam:unavailable' using errcode='P0002'; end if;
  select author_id into v_author from public.activities where id=p_activity_id;
  if p_liked then
    insert into public.likes(actor_id,activity_id) values(v_me,p_activity_id) on conflict do nothing;
    if found then perform app_private.notify(v_author,v_me,'like',p_activity_id,null,'like:'||v_me||':'||p_activity_id); end if;
  else
    delete from public.likes where actor_id=v_me and activity_id=p_activity_id;
  end if;
  return exists(select 1 from public.likes where actor_id=v_me and activity_id=p_activity_id);
end$$;

-- Comments: flat, chronological, 2,000 characters, idempotent per operation UUID ---------------
create or replace function public.comments(p_activity_id uuid,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  if not app_private.activity_visible(p_activity_id,v_me) then raise exception 'roam:unavailable' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(app_private.comment_json(x.id,v_me) order by x.created_at,x.id),'[]') into v_rows
  from(select c.id,c.created_at from public.comments c join public.profiles p on p.id=c.author_id and p.deactivated_at is null
       where c.activity_id=p_activity_id and(c.author_id=v_me or not app_private.is_blocked_pair(v_me,c.author_id))
         and(v_cursor is null or(c.created_at,c.id)>((v_cursor->>'createdAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by c.created_at,c.id limit 31)x;
  return app_private.page_json(v_rows,'createdAt');
end$$;

create or replace function public.post_comment(p_activity_id uuid,p_body text,p_operation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_existing public.comments; v_author uuid; v_id uuid;
begin
  if p_operation_id is null then perform app_private.validation_error('This comment needs an operation identifier.'); end if;
  perform pg_advisory_xact_lock(hashtextextended(v_me::text||':comment:'||p_operation_id::text,0));
  select * into v_existing from public.comments where author_id=v_me and operation_id=p_operation_id;
  if found then
    if v_existing.activity_id<>p_activity_id or v_existing.body<>p_body then raise exception 'roam:operation_conflict' using errcode='23505'; end if;
    return app_private.comment_json(v_existing.id,v_me);
  end if;
  if p_body is null or btrim(p_body)='' then perform app_private.validation_error('Write a comment first.'); end if;
  if char_length(p_body)>2000 then perform app_private.validation_error('Use 2,000 characters or fewer for your comment.'); end if;
  if not app_private.activity_visible(p_activity_id,v_me) then raise exception 'roam:unavailable' using errcode='P0002'; end if;
  select author_id into v_author from public.activities where id=p_activity_id for share;
  insert into public.comments(activity_id,author_id,body,operation_id) values(p_activity_id,v_me,p_body,p_operation_id) returning id into v_id;
  perform app_private.notify(v_author,v_me,'comment',p_activity_id,v_id,'comment:'||v_id);
  return app_private.comment_json(v_id,v_me);
end$$;

-- Comment authors delete their own comments; the comment's notification cascades with it.
create or replace function public.delete_comment(p_comment_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_author uuid;
begin
  select author_id into v_author from public.comments where id=p_comment_id for update;
  if v_author is null then return false; end if;
  if v_author<>v_me then raise exception 'roam:forbidden' using errcode='42501'; end if;
  delete from public.comments where id=p_comment_id and author_id=v_me;
  return true;
end$$;

-- Follow graph pages: visible members, literal handle/name filter, stable handle keyset ---------
create or replace function app_private.follow_page(p_user uuid,p_followers boolean,p_query text,p_cursor text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); q text:=lower(btrim(coalesce(p_query,''))); v_rows jsonb;
begin
  if not app_private.can_see_member(p_user) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(app_private.member_row_json(x.id,v_me)||jsonb_build_object('id',x.id,'handle',x.handle) order by x.handle),'[]') into v_rows
  from(select p.id,p.handle from public.follows f join public.profiles p on p.id=case when p_followers then f.follower_id else f.followee_id end
       where(case when p_followers then f.followee_id else f.follower_id end)=p_user and p.deactivated_at is null
         and(p.id=v_me or not app_private.is_blocked_pair(v_me,p.id))
         and(q='' or strpos(lower(p.handle),q)>0 or strpos(lower(p.display_name),q)>0)
         and(p_cursor is null or p.handle>p_cursor)
       order by p.handle limit 31)x;
  return jsonb_build_object(
    'items',(select coalesce(jsonb_agg(value-'id'-'handle' order by ordinal),'[]'::jsonb) from jsonb_array_elements(v_rows) with ordinality t(value,ordinal) where ordinal<=30),
    'nextCursor',case when jsonb_array_length(v_rows)>30 then v_rows->29->>'handle' end);
end$$;

create or replace function public.followers(p_user_id uuid,p_query text default '',p_cursor text default null)
returns jsonb language sql stable security definer set search_path='' as $$select app_private.follow_page(p_user_id,true,p_query,p_cursor)$$;
create or replace function public.following(p_user_id uuid,p_query text default '',p_cursor text default null)
returns jsonb language sql stable security definer set search_path='' as $$select app_private.follow_page(p_user_id,false,p_query,p_cursor)$$;

-- Mute and block -----------------------------------------------------------------------------
create or replace function public.set_mute(p_user_id uuid,p_muted boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_user_id=v_me then perform app_private.validation_error('You can''t mute yourself.'); end if;
  if p_muted then
    if not app_private.can_see_member(p_user_id) then raise exception 'roam:not_found' using errcode='P0002'; end if;
    insert into public.mutes(muter_id,muted_id) values(v_me,p_user_id) on conflict do nothing;
  else
    delete from public.mutes where muter_id=v_me and muted_id=p_user_id;
  end if;
  return exists(select 1 from public.mutes where muter_id=v_me and muted_id=p_user_id);
end$$;

-- Blocking removes both follow edges; unblocking never restores them.
create or replace function public.set_block(p_user_id uuid,p_blocked boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_user_id=v_me then perform app_private.validation_error('You can''t block yourself.'); end if;
  if p_blocked then
    if not exists(select 1 from public.profiles where id=p_user_id and deactivated_at is null) then raise exception 'roam:not_found' using errcode='P0002'; end if;
    insert into public.blocks(blocker_id,blocked_id) values(v_me,p_user_id) on conflict do nothing;
    delete from public.follows where(follower_id=v_me and followee_id=p_user_id) or(follower_id=p_user_id and followee_id=v_me);
  else
    delete from public.blocks where blocker_id=v_me and blocked_id=p_user_id;
  end if;
  return exists(select 1 from public.blocks where blocker_id=v_me and blocked_id=p_user_id);
end$$;

create or replace function public.blocked_members()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.member_json(b.blocked_id) order by p.handle) from public.blocks b
                   join public.profiles p on p.id=b.blocked_id where b.blocker_id=v_me),'[]'::jsonb);
end$$;

create or replace function public.muted_members()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return coalesce((select jsonb_agg(app_private.member_json(m.muted_id) order by p.handle) from public.mutes m
                   join public.profiles p on p.id=m.muted_id and p.deactivated_at is null
                   where m.muter_id=v_me and not app_private.is_blocked_pair(v_me,m.muted_id)),'[]'::jsonb);
end$$;

-- Shared Want to Go: the exact Experience-ID intersection of two Want lists, newest viewer save first.
create or replace function public.shared_wants(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  if p_other=v_me then perform app_private.validation_error('Choose another member to compare with.'); end if;
  if not app_private.can_see_member(p_other) then raise exception 'roam:not_found' using errcode='P0002'; end if;
  return coalesce((select jsonb_agg(app_private.list_entry_json(b.experience_id,v_me,v_me,b.saved_at) order by b.saved_at desc,b.experience_id desc)
                   from public.bookmarks b
                   where b.owner_id=v_me and exists(select 1 from public.bookmarks o where o.owner_id=p_other and o.experience_id=b.experience_id)),'[]'::jsonb);
end$$;

-- Notifications ------------------------------------------------------------------------------
create or replace function app_private.notification_visible(p_notification public.notifications, p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select p_notification.recipient_id=p_viewer
    and exists(select 1 from public.profiles p where p.id=p_notification.actor_id and p.deactivated_at is null)
    and not app_private.is_blocked_pair(p_viewer,p_notification.actor_id)
$$;

create or replace function app_private.notification_json(p_id uuid,p_viewer uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',n.id,'type',n.type,'actor',app_private.member_json(n.actor_id),'activityID',n.activity_id,
    'experienceName',(select pl.name from public.activities a join public.experiences e on e.id=a.experience_id join public.places pl on pl.id=e.place_id where a.id=n.activity_id),
    'commentPreview',(select left(c.body,140) from public.comments c where c.id=n.comment_id),
    'createdAt',n.created_at,'readAt',n.read_at,
    'targetAvailable',case when n.type='follow' then app_private.can_see_member(n.actor_id)
                           else n.activity_id is not null and app_private.activity_visible(n.activity_id,p_viewer) end)
  from public.notifications n where n.id=p_id
$$;

create or replace function public.notifications(p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member(); v_cursor jsonb:=app_private.decode_cursor(p_cursor); v_rows jsonb;
begin
  select coalesce(jsonb_agg(app_private.notification_json(x.id,v_me) order by x.created_at desc,x.id desc),'[]') into v_rows
  from(select n.id,n.created_at from public.notifications n
       where n.recipient_id=v_me and app_private.notification_visible(n,v_me)
         and(v_cursor is null or(n.created_at,n.id)<((v_cursor->>'createdAt')::timestamptz,(v_cursor->>'id')::uuid))
       order by n.created_at desc,n.id desc limit 31)x;
  return app_private.page_json(v_rows,'createdAt');
end$$;

create or replace function public.unread_notification_count()
returns integer language plpgsql stable security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  return(select count(*)::integer from public.notifications n where n.recipient_id=v_me and n.read_at is null and app_private.notification_visible(n,v_me));
end$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification_id and recipient_id=v_me;
end$$;

create or replace function public.mark_all_notifications_read()
returns void language plpgsql security definer set search_path='' as $$
declare v_me uuid:=app_private.require_member();
begin
  update public.notifications set read_at=now() where recipient_id=v_me and read_at is null;
end$$;

-- Privileges ---------------------------------------------------------------------------------
revoke execute on function app_private.decode_cursor(text),app_private.encode_cursor(jsonb),app_private.page_json(jsonb,text),
  app_private.activity_visible(uuid,uuid),app_private.member_row_json(uuid,uuid),app_private.comment_json(uuid,uuid),
  app_private.follow_page(uuid,boolean,text,text),app_private.notification_visible(public.notifications,uuid),app_private.notification_json(uuid,uuid)
from public,anon,authenticated;
grant execute on function app_private.decode_cursor(text),app_private.encode_cursor(jsonb),app_private.page_json(jsonb,text),
  app_private.activity_visible(uuid,uuid),app_private.member_row_json(uuid,uuid),app_private.comment_json(uuid,uuid),
  app_private.follow_page(uuid,boolean,text,text),app_private.notification_visible(public.notifications,uuid),app_private.notification_json(uuid,uuid)
to service_role;
revoke execute on function public.feed(text),public.profile_activity(uuid,text),public.activity(uuid),public.set_like(uuid,boolean),
  public.comments(uuid,text),public.post_comment(uuid,text,uuid),public.delete_comment(uuid),public.followers(uuid,text,text),
  public.following(uuid,text,text),public.set_mute(uuid,boolean),public.set_block(uuid,boolean),public.blocked_members(),
  public.muted_members(),public.shared_wants(uuid),public.notifications(text),public.unread_notification_count(),
  public.mark_notification_read(uuid),public.mark_all_notifications_read()
from public,anon;
grant execute on function public.feed(text),public.profile_activity(uuid,text),public.activity(uuid),public.set_like(uuid,boolean),
  public.comments(uuid,text),public.post_comment(uuid,text,uuid),public.delete_comment(uuid),public.followers(uuid,text,text),
  public.following(uuid,text,text),public.set_mute(uuid,boolean),public.set_block(uuid,boolean),public.blocked_members(),
  public.muted_members(),public.shared_wants(uuid),public.notifications(text),public.unread_notification_count(),
  public.mark_notification_read(uuid),public.mark_all_notifications_read()
to authenticated;
