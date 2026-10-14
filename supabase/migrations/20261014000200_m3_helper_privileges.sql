-- Schema-scoped default ACL revocation cannot subtract EXECUTE inherited from the creator's
-- global PUBLIC default. Revoke that global default before creating any later private helpers.
alter default privileges for role postgres revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema app_private revoke execute on functions from public, anon, authenticated;

-- Serializers accept trusted IDs/viewers from public RPCs. They must never be a client entry
-- point: SECURITY DEFINER public RPCs check actor/visibility before calling them as their owner.
revoke execute on function
  app_private.following_score(uuid, uuid),
  app_private.experience_summary_json(uuid, uuid),
  app_private.visit_json(uuid),
  app_private.activity_json(uuid, uuid),
  app_private.list_entry_json(uuid, uuid, uuid, timestamptz)
from public, anon, authenticated;

grant execute on function
  app_private.following_score(uuid, uuid),
  app_private.experience_summary_json(uuid, uuid),
  app_private.visit_json(uuid),
  app_private.activity_json(uuid, uuid),
  app_private.list_entry_json(uuid, uuid, uuid, timestamptz)
to service_role;
