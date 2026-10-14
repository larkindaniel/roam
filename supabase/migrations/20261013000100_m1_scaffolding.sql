-- M1 scaffolding: private helper schema and an operational health check.
-- The v1 domain schema arrives in later migrations; deferred features get no tables.

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create extension if not exists pgcrypto with schema extensions;

-- Operational health check. Returns no member data, so it is callable before sign-in.
create or replace function public.roam_health()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'service', 'roam',
    'scaffolding', 'm1',
    'database_time', now()
  );
$$;

revoke all on function public.roam_health() from public;
grant execute on function public.roam_health() to anon, authenticated, service_role;
