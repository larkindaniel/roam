-- M2 hardening: remove privileges that Supabase's default ACLs grant to client roles but Roam never
-- needs. TRUNCATE in particular would bypass Row Level Security.

revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke truncate, trigger, references on tables from anon, authenticated;

-- New functions are not callable by anonymous or default roles unless granted explicitly.
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;
alter default privileges for role postgres in schema app_private revoke execute on functions from public;

-- Private helpers: only the RLS/storage-policy helpers are executable by signed-in clients
-- (policies evaluate as the querying role). Everything else runs inside security-definer RPCs.
revoke execute on all functions in schema app_private from public, anon, authenticated;
grant execute on function app_private.current_member(), app_private.can_see_member(uuid),
  app_private.can_read_object(text, text), app_private.object_is_attached(text, text) to authenticated;
grant execute on all functions in schema app_private to service_role;
