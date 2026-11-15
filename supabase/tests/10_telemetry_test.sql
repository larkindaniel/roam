-- Beta telemetry and bug reports: who can read and write what, how batches are taken in, the settings switches,
-- report rules, the trail a report shows, and clean-up.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

create temp table people as
select * from (values
  ('tester', 'a1000000-0000-4000-8000-000000000001'::uuid),
  ('other',  'a1000000-0000-4000-8000-000000000002'::uuid)
) p(name, id);
insert into auth.users(id, email, aud, role, instance_id)
select id, name || '10@test.local', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000' from people;
grant select on people to authenticated, anon;

create function pg_temp.actor(who text) returns void language sql as $$
  select set_config('request.jwt.claims', jsonb_build_object('sub', id, 'role', 'authenticated')::text, true)
  from people where name = who
$$;
create function pg_temp.anonymous() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"anon"}', true)
$$;
create function pg_temp.session(id uuid, started timestamptz default now()) returns jsonb language sql as $$
  select jsonb_build_object('id', id, 'startedAt', started, 'appVersion', '1.0', 'build', '9', 'osVersion', '26.5',
                            'deviceModel', 'iPhone18,1', 'locale', 'en_CA')
$$;
create function pg_temp.events(first int, last int, at timestamptz default now()) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('seq', n, 'at', at + make_interval(secs => n), 'kind', 'tap', 'name', 'tap-' || n,
                                      'screen', 'feed-root', 'props', jsonb_build_object('x', '1')))
  from generate_series(first, last) n
$$;
grant execute on function pg_temp.actor(text), pg_temp.anonymous(), pg_temp.session(uuid, timestamptz),
  pg_temp.events(int, int, timestamptz) to authenticated, anon;

-- Nobody reads the tables from the app.
set local role authenticated;
select pg_temp.actor('tester');
select throws_ok($$select * from public.app_events$$, '42501', null, 'members cannot read events');
select throws_ok($$select * from public.app_sessions$$, '42501', null, 'members cannot read sessions');
select throws_ok($$select * from public.bug_reports$$, '42501', null, 'members cannot read bug reports');
select throws_ok($$select * from public.telemetry_settings$$, '42501', null, 'members cannot read settings directly');
select throws_ok($$select * from public.bug_report_trail$$, '42501', null, 'members cannot read report trails');
select throws_ok($$select * from public.latency_last_7_days$$, '42501', null, 'members cannot read latency');
reset role;

-- The settings the app reads at launch, signed out too.
set local role anon;
select pg_temp.anonymous();
select is(public.telemetry_settings() ->> 'eventsEnabled', 'true', 'signed-out screens can read the settings');
select is(public.telemetry_settings() ->> 'bugReportsEnabled', 'true', 'bug reports are on by default');

-- Signed-out screens log, and the session is claimed by whoever signs in during it.
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'), pg_temp.events(1, 3)), 3,
          'a signed-out batch is taken in');
reset role;
select is((select user_id from public.app_sessions where id = 'b1000000-0000-4000-8000-000000000001'), null,
          'a signed-out session has no owner yet');
set local role authenticated;
select pg_temp.actor('tester');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'), pg_temp.events(4, 5)), 2,
          'the same session goes on after signing in');
reset role;
select is((select user_id from public.app_sessions where id = 'b1000000-0000-4000-8000-000000000001'),
          'a1000000-0000-4000-8000-000000000001'::uuid, 'signing in claims the session');

-- Its last steps can arrive from the next account on the phone (or signed out), but it never changes hands.
set local role authenticated;
select pg_temp.actor('other');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'), pg_temp.events(6, 6)), 1,
          'a session''s last steps are taken in after the account changes');
select public.mark_session_unclean('b1000000-0000-4000-8000-000000000001');
reset role;
select is((select user_id from public.app_sessions where id = 'b1000000-0000-4000-8000-000000000001'),
          'a1000000-0000-4000-8000-000000000001'::uuid, 'the session still belongs to whoever signed in first');
select is((select ended_uncleanly from public.app_sessions where id = 'b1000000-0000-4000-8000-000000000001'), false,
          'another member cannot mark the session as crashed');

-- Batches: repeats are ignored, unknown kinds and empty names dropped, big batches refused.
set local role authenticated;
select pg_temp.actor('tester');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'), pg_temp.events(4, 5)), 0,
          'a batch sent twice is stored once');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'),
          '[{"seq": 20, "kind": "made-up", "name": "x"}, {"seq": 21, "kind": "tap", "name": ""},
            {"seq": 22, "kind": "timing", "name": "load.feed"}]'::jsonb), 1,
          'unknown kinds and empty names are dropped');
reset role;
select is((select duration_ms from public.app_events where session_id = 'b1000000-0000-4000-8000-000000000001' and seq = 22),
          null, 'an event without a duration stores none, not zero');
set local role authenticated;
select pg_temp.actor('tester');
select throws_ok($$select public.log_events(pg_temp.session(gen_random_uuid()), pg_temp.events(1, 201))$$,
                 'P0001', 'roam:validation:Too many events in one batch.', 'a batch over 200 events is refused');
select public.mark_session_unclean('b1000000-0000-4000-8000-000000000001');
reset role;
select is((select ended_uncleanly from public.app_sessions where id = 'b1000000-0000-4000-8000-000000000001'), true,
          'the owner can mark their last session as crashed');

-- The switches.
update public.telemetry_settings set muted_kinds = '{tap}';
set local role authenticated;
select pg_temp.actor('tester');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'),
          '[{"seq": 30, "kind": "tap", "name": "a"}, {"seq": 31, "kind": "screen", "name": "feed-root"}]'::jsonb), 1,
          'a muted kind is dropped and the rest kept');
reset role;
update public.telemetry_settings set muted_kinds = '{}', events_enabled = false;
set local role authenticated;
select pg_temp.actor('tester');
select is(public.log_events(pg_temp.session('b1000000-0000-4000-8000-000000000001'), pg_temp.events(40, 41)), 0,
          'with events switched off nothing is stored');
reset role;
update public.telemetry_settings set events_enabled = true, bug_reports_enabled = false;
set local role authenticated;
select pg_temp.actor('tester');
select throws_ok($$select public.submit_bug_report('{"description": "Broken"}')$$, 'P0001', 'roam:unavailable',
                 'with bug reports switched off a report is refused');
reset role;
update public.telemetry_settings set bug_reports_enabled = true;

-- Reports.
set local role authenticated;
select pg_temp.actor('tester');
select throws_ok($$select public.submit_bug_report('{"description": "   "}')$$, 'P0001', 'roam:validation:Say what went wrong.',
                 'a report needs a description');
select throws_ok($$select public.submit_bug_report(jsonb_build_object('description', 'x', 'attachments',
                   jsonb_build_array(jsonb_build_object('path', 'a1000000-0000-4000-8000-000000000002/f.jpg', 'kind', 'screenshot'))))$$,
                 'P0001', 'roam:forbidden', 'a report cannot point at another member''s files');
select throws_ok($$select public.submit_bug_report(jsonb_build_object('description', 'x', 'attachments',
                   (select jsonb_agg(jsonb_build_object('path', 'a1000000-0000-4000-8000-000000000001/' || n || '.jpg', 'kind', 'screenshot'))
                    from generate_series(1, 7) n)))$$,
                 'P0001', 'roam:validation:Attach up to six screenshots or recordings.', 'at most six attachments');
select lives_ok($$select public.submit_bug_report(jsonb_build_object('description', 'The map froze', 'screen', 'city-page',
                  'sessionId', 'b1000000-0000-4000-8000-000000000001', 'lastSeq', 5, 'attachments',
                  jsonb_build_array(jsonb_build_object('path', 'a1000000-0000-4000-8000-000000000001/a.jpg', 'kind', 'screenshot'),
                                    jsonb_build_object('path', 'a1000000-0000-4000-8000-000000000001/b.mp4', 'kind', 'recording'))))$$,
                'a report with its own screenshot and recording is saved');
reset role;
select is((select jsonb_array_length(attachments) from public.bug_reports where description = 'The map froze'), 2,
          'both attachments are kept');
select is((select user_id from public.bug_reports where description = 'The map froze'),
          'a1000000-0000-4000-8000-000000000001'::uuid, 'the report belongs to whoever sent it');

set local role anon;
select pg_temp.anonymous();
select lives_ok($$select public.submit_bug_report('{"description": "Sign in button does nothing"}')$$,
                'a signed-out tester can send words only');
select throws_ok($$select public.submit_bug_report(jsonb_build_object('description', 'x', 'attachments',
                   jsonb_build_array(jsonb_build_object('path', 'anything/f.jpg', 'kind', 'screenshot'))))$$,
                 'P0001', 'roam:forbidden', 'a signed-out tester cannot attach files');
reset role;

-- The trail a report shows: this session up to the report.
select is((select count(*)::int from public.bug_report_trail t join public.bug_reports r on r.id = t.report_id
           where r.description = 'The map froze' and t.session = 'this'), 5,
          'the trail stops at the event the report was sent after');

-- ...with the previous session first when it was active just before this one began.
set local role authenticated;
select pg_temp.actor('tester');
select public.log_events(pg_temp.session('b1000000-0000-4000-8000-0000000000aa', now() - interval '20 minutes'),
                         pg_temp.events(1, 4, now() - interval '20 minutes'));
select public.log_events(pg_temp.session('b1000000-0000-4000-8000-0000000000bb', now() + interval '1 minute'),
                         pg_temp.events(1, 2, now() + interval '1 minute'));
select public.submit_bug_report('{"description": "Crashed, reopened", "sessionId": "b1000000-0000-4000-8000-0000000000bb", "lastSeq": 2}');
reset role;
-- The session from 20 minutes ago is too old; the one active just before is the previous session.
select is((select count(*)::int from public.bug_report_trail t join public.bug_reports r on r.id = t.report_id
           where r.description = 'Crashed, reopened' and t.session = 'previous'),
          (select count(*)::int from public.app_events where session_id = 'b1000000-0000-4000-8000-000000000001'),
          'the previous session is the one active just before, not an older one');
select is((select min(part) from public.bug_report_trail t join public.bug_reports r on r.id = t.report_id
           where r.description = 'Crashed, reopened' and t.session = 'previous'), 1, 'and sort before this session''s');

-- The server reads reports and records the issue it opened.
set local role service_role;
select lives_ok($$update public.bug_reports set github_issue_url = 'https://example.test/1' where description = 'The map froze'$$,
                'the server can record the issue url');
select ok((select count(*) > 0 from public.bug_report_trail), 'the server can read report trails');
reset role;

-- Clean-up drops events past the retention window and keeps the rest.
insert into public.app_events (session_id, seq, at, kind, name)
values ('b1000000-0000-4000-8000-000000000001', 900, now() - interval '40 days', 'tap', 'old');
select app_private.prune_app_events();
select is((select count(*)::int from public.app_events where session_id = 'b1000000-0000-4000-8000-000000000001' and seq = 900),
          0, 'events older than the retention window are deleted');
select ok((select count(*) > 0 from public.app_events where session_id = 'b1000000-0000-4000-8000-000000000001'),
          'recent events are kept');
select is((select count(*)::int from cron.job where jobname = 'prune-app-events'), 1, 'clean-up runs daily');

select * from finish();
rollback;
