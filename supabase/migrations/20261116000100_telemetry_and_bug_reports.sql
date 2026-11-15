-- Beta telemetry and bug reports.
--
-- One pipeline for everything the app tells us about itself:
--   app_sessions    one row per app launch: device, OS, app version, who was signed in, whether it ended cleanly.
--   app_events      the trail inside a session: screens, taps, navigation, actions, network calls and timings,
--                   errors and crashes. Ordered by (session_id, seq), so a session can be replayed step by step.
--   bug_reports     what a tester wrote, with optional screenshot or screen recording, tied to the session and the
--                   event it was sent from, so the trail before it can be pulled up next to it.
--   telemetry_settings  one row that switches each of these on or off for every install (read at launch).
--
-- Storage is kept small on purpose: device details live once per session rather than on every event, props are
-- capped, batches are capped, and a daily job drops events older than 30 days (bug reports and sessions stay).

-- Settings: the one place to turn things on and off.
create table public.telemetry_settings (
  id boolean primary key default true check (id),
  events_enabled boolean not null default true,
  bug_reports_enabled boolean not null default true,
  -- Event kinds to stop sending (for example '{network}' if network events get too noisy).
  muted_kinds text[] not null default '{}',
  event_retention_days integer not null default 30 check (event_retention_days between 1 and 365),
  updated_at timestamptz not null default now()
);
insert into public.telemetry_settings default values;
alter table public.telemetry_settings enable row level security;

create table public.app_sessions (
  id uuid primary key,
  user_id uuid references auth.users (id) on delete cascade,
  started_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  app_version text not null check (char_length(app_version) <= 32),
  build text not null check (char_length(build) <= 32),
  os_version text not null check (char_length(os_version) <= 32),
  device_model text not null check (char_length(device_model) <= 64),
  locale text check (char_length(locale) <= 32),
  -- Set when the next launch finds this session ended while the app was open (a crash, hang or memory kill).
  ended_uncleanly boolean not null default false
);
create index app_sessions_user_started on public.app_sessions (user_id, started_at desc);
alter table public.app_sessions enable row level security;

create table public.app_events (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.app_sessions (id) on delete cascade,
  seq integer not null,
  at timestamptz not null,
  received_at timestamptz not null default now(),
  kind text not null check (kind in ('screen', 'tap', 'nav', 'action', 'network', 'timing', 'error', 'crash', 'lifecycle')),
  name text not null check (char_length(name) between 1 and 120),
  screen text check (char_length(screen) <= 80),
  duration_ms integer check (duration_ms >= 0),
  props jsonb check (props is null or pg_column_size(props) <= 16384),
  unique (session_id, seq)
);
create index app_events_at on public.app_events (at);
create index app_events_kind_name_at on public.app_events (kind, name, at desc);
alter table public.app_events enable row level security;

create table public.bug_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  session_id uuid references public.app_sessions (id) on delete set null,
  -- The event the report was sent after, so "what happened before" is everything up to this seq.
  last_seq integer,
  created_at timestamptz not null default now(),
  description text not null check (char_length(btrim(description)) between 1 and 4000),
  screen text check (char_length(screen) <= 80),
  -- Screenshots and recordings, each {"path": "<user>/<file>", "kind": "screenshot" | "recording"}; up to six.
  attachments jsonb not null default '[]' check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 6),
  app_version text check (char_length(app_version) <= 32),
  build text check (char_length(build) <= 32),
  os_version text check (char_length(os_version) <= 32),
  device_model text check (char_length(device_model) <= 64),
  status text not null default 'new' check (status in ('new', 'triaged', 'fixed', 'wontfix')),
  github_issue_url text
);
create index bug_reports_created on public.bug_reports (created_at desc);
alter table public.bug_reports enable row level security;

-- Nobody reads these tables from the app; they're written only through the functions below and read by the team in
-- SQL (or the dashboard) with the service role.
revoke all on public.telemetry_settings, public.app_sessions, public.app_events, public.bug_reports from anon, authenticated;

-- What the app reads at launch.
create or replace function public.telemetry_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'eventsEnabled', s.events_enabled,
    'bugReportsEnabled', s.bug_reports_enabled,
    'mutedKinds', to_jsonb(s.muted_kinds))
  from public.telemetry_settings s
$$;
revoke execute on function public.telemetry_settings() from public;
grant execute on function public.telemetry_settings() to anon, authenticated;

-- Takes one session's batch of events. Signed-out screens (welcome, sign-in) log too, so anon may call it; the
-- session is claimed by whoever signs in during it, and a signed-in session can't be taken over by someone else.
create or replace function public.log_events(p_session jsonb, p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings public.telemetry_settings;
  v_session uuid := (p_session ->> 'id')::uuid;
  actor uuid := auth.uid();
  owner uuid;
  inserted integer;
begin
  select * into settings from public.telemetry_settings;
  if not settings.events_enabled then return 0; end if;
  if v_session is null or jsonb_typeof(p_events) <> 'array' then raise exception 'roam:validation:Bad batch.'; end if;
  if jsonb_array_length(p_events) > 200 then raise exception 'roam:validation:Too many events in one batch.'; end if;

  select user_id into owner from public.app_sessions where id = v_session;
  if found and owner is not null and owner is distinct from actor then
    raise exception 'roam:forbidden';
  end if;

  insert into public.app_sessions as s (id, user_id, started_at, app_version, build, os_version, device_model, locale)
  values (v_session, actor,
          coalesce((p_session ->> 'startedAt')::timestamptz, now()),
          left(coalesce(p_session ->> 'appVersion', '?'), 32),
          left(coalesce(p_session ->> 'build', '?'), 32),
          left(coalesce(p_session ->> 'osVersion', '?'), 32),
          left(coalesce(p_session ->> 'deviceModel', '?'), 64),
          left(p_session ->> 'locale', 32))
  on conflict (id) do update
    set last_seen_at = now(),
        user_id = coalesce(s.user_id, excluded.user_id);

  insert into public.app_events (session_id, seq, at, kind, name, screen, duration_ms, props)
  select v_session,
         (e ->> 'seq')::integer,
         least(coalesce((e ->> 'at')::timestamptz, now()), now() + interval '5 minutes'),
         e ->> 'kind',
         left(e ->> 'name', 120),
         left(e ->> 'screen', 80),
         case when e ? 'durationMs' then greatest((e ->> 'durationMs')::integer, 0) end,
         case when jsonb_typeof(e -> 'props') = 'object' and pg_column_size(e -> 'props') <= 16384 then e -> 'props' end
  from jsonb_array_elements(p_events) e
  where e ->> 'kind' <> all (settings.muted_kinds)
    and e ->> 'kind' in ('screen', 'tap', 'nav', 'action', 'network', 'timing', 'error', 'crash', 'lifecycle')
    and coalesce(e ->> 'name', '') <> ''
  on conflict (session_id, seq) do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;
revoke execute on function public.log_events(jsonb, jsonb) from public;
grant execute on function public.log_events(jsonb, jsonb) to anon, authenticated;

-- Marks a previous launch as having ended while the app was open. Same ownership rule as log_events.
create or replace function public.mark_session_unclean(p_session_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.app_sessions set ended_uncleanly = true
  where id = p_session_id and (user_id is null or user_id = auth.uid());
$$;
revoke execute on function public.mark_session_unclean(uuid) from public;
grant execute on function public.mark_session_unclean(uuid) to anon, authenticated;

-- A tester's report. Signed out (welcome, sign-in) it's words only; signed in it can carry up to six screenshots or
-- recordings from the reporter's own folder of the bug-reports bucket.
create or replace function public.submit_bug_report(p_report jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  files jsonb := coalesce(p_report -> 'attachments', '[]');
  report_id uuid;
begin
  if not (select bug_reports_enabled from public.telemetry_settings) then
    raise exception 'roam:unavailable';
  end if;
  if char_length(btrim(coalesce(p_report ->> 'description', ''))) = 0 then
    raise exception 'roam:validation:Say what went wrong.';
  end if;
  if jsonb_typeof(files) <> 'array' or jsonb_array_length(files) > 6 then
    raise exception 'roam:validation:Attach up to six screenshots or recordings.';
  end if;
  if jsonb_array_length(files) > 0 and (actor is null or exists (
       select 1 from jsonb_array_elements(files) f
       where split_part(f ->> 'path', '/', 1) <> actor::text
          or char_length(f ->> 'path') > 300
          or coalesce(f ->> 'kind', '') not in ('screenshot', 'recording'))) then
    raise exception 'roam:forbidden';
  end if;
  if actor is not null and (select count(*) from public.bug_reports where user_id = actor and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'roam:validation:That''s a lot of reports in an hour. Try again later.';
  end if;
  if actor is null and (select count(*) from public.bug_reports where user_id is null and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'roam:validation:Too many reports right now. Try again later.';
  end if;

  insert into public.bug_reports (user_id, session_id, last_seq, description, screen, attachments,
                                  app_version, build, os_version, device_model)
  values (actor,
          (select id from public.app_sessions where id = (p_report ->> 'sessionId')::uuid and (user_id is null or user_id = actor)),
          (p_report ->> 'lastSeq')::integer,
          left(btrim(p_report ->> 'description'), 4000),
          left(p_report ->> 'screen', 80),
          (select coalesce(jsonb_agg(jsonb_build_object('path', f ->> 'path', 'kind', f ->> 'kind')), '[]') from jsonb_array_elements(files) f),
          left(p_report ->> 'appVersion', 32), left(p_report ->> 'build', 32),
          left(p_report ->> 'osVersion', 32), left(p_report ->> 'deviceModel', 64))
  returning id into report_id;
  return report_id;
end;
$$;
revoke execute on function public.submit_bug_report(jsonb) from public;
grant execute on function public.submit_bug_report(jsonb) to anon, authenticated;

-- Screenshots and recordings: private, written by the reporter into their own folder, read only by the team.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bug-reports', 'bug-reports', false, 52428800, array['image/jpeg', 'image/png', 'video/mp4', 'video/quicktime'])
on conflict (id) do nothing;

create policy roam_bug_report_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'bug-reports'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

-- For the team: a report with the steps that led up to it, oldest first.
create or replace view public.bug_report_trail as
select r.id as report_id, e.seq, e.at, e.kind, e.name, e.screen, e.duration_ms, e.props
from public.bug_reports r
join public.app_events e on e.session_id = r.session_id and (r.last_seq is null or e.seq <= r.last_seq)
order by r.id, e.seq;

-- For the team: how long things take over the last week, slowest first.
create or replace view public.latency_last_7_days as
select kind, name,
       count(*) as samples,
       round(percentile_cont(0.5) within group (order by duration_ms))::integer as p50_ms,
       round(percentile_cont(0.95) within group (order by duration_ms))::integer as p95_ms,
       max(duration_ms) as max_ms,
       count(*) filter (where props ->> 'ok' = 'false') as failures
from public.app_events
where duration_ms is not null and at > now() - interval '7 days'
group by kind, name
order by p95_ms desc;

-- For the team: crashes and unclean exits, newest first.
create or replace view public.recent_crashes as
select e.at, e.name, s.app_version, s.build, s.os_version, s.device_model, s.user_id, e.session_id, e.props
from public.app_events e
join public.app_sessions s on s.id = e.session_id
where e.kind = 'crash'
order by e.at desc;

revoke all on public.bug_report_trail, public.latency_last_7_days, public.recent_crashes from anon, authenticated;

-- Keeps the event table small: drops events past the retention window once a day.
create or replace function app_private.prune_app_events()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.app_events
  where at < now() - make_interval(days => (select event_retention_days from public.telemetry_settings));
$$;
revoke execute on function app_private.prune_app_events() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('prune-app-events', '17 4 * * *', 'select app_private.prune_app_events()');
