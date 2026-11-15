# Beta telemetry: event trail, bug reports, latency and crashes

All of it goes through one pipeline into Supabase. There's no third-party SDK and no extra account.

```
app ──Log.*──▶ Telemetry (memory + a file per session) ──every 15 s / on background──▶ log_events() ──▶ app_events
                                                                                                      app_sessions
bug button ──▶ Report a bug ──▶ bug-reports bucket + submit_bug_report() ──▶ bug_reports ──▶ bug-report-issue ──▶ GitHub issue
```

## What gets recorded on its own

| Kind | From | What |
|---|---|---|
| `screen` | `.screenIdentifier(_:)` | each time a screen shows, with `since_tap_ms` (how long after the tap that opened it) |
| `tap` | `.tapID(_:)` and `TapRecorder` | named buttons by their id, system bar buttons by their label, anything else as `unnamed` with x/y |
| `nav` | `AppRouter`, setup steps | tab changes, push, back, pop to root, sheets opening and closing |
| `network` | `NetworkRecorder` (URLSession metrics) | every request: `rpc.<function>`, `auth.*`, `storage.<method>.<bucket>`, `fn.<function>`, with status, bytes and ms |
| `timing` | `Log.span` / `Log.measure` | main screen loads (`load.feed`, `load.discover`, `load.place`, …) and heavy work (`compute.image_prepare`) |
| `error` | `SessionStore.handle` | every error a screen shows |
| `crash` | `CrashRecorder` | `unclean_exit` (the last session ended while the app was open), MetricKit `crash` and `hang` reports with stacks |
| `lifecycle` | app | launch, foreground, background, MetricKit daily summaries |

Signed-out screens log too; a session is tied to whoever signs in during it.

## Adding to it when you build something

- **Buttons:** use `.tapID("thing-action")` instead of `.accessibilityIdentifier` on every button, link and toggle.
  It's the UI-test id and the name its taps log under.
- **Screens:** give each new screen `.screenIdentifier("name")`.
- **Things that matter:** `Log.action("log.saved", ["score": "8.1"])`.
- **Failures you handle quietly:** `Log.error("photo.upload", error)`.
- **Slow things:** `let span = Log.span("load.trip"); defer { span.end() }`, or wrap in `Log.measure("x") { … }`.
- **Never** log what people type (notes, messages, search text, passwords) or anything secret. Ids and place names
  are fine.

## Switching things on and off

One row, read by the app at launch:

```sql
update telemetry_settings set events_enabled = false;          -- stop the trail
update telemetry_settings set bug_reports_enabled = false;     -- hide the bug button
update telemetry_settings set muted_kinds = '{network}';       -- drop one kind (screen, tap, nav, network, …)
update telemetry_settings set event_retention_days = 14;       -- how long events are kept
```

## Keeping storage small

- Device and app details are stored once per session, not on each event.
- Props are capped at 500 characters each and 16 KB in total, and batches at 200 events.
- A daily `pg_cron` job (`prune-app-events`) deletes events past the retention window (30 days by default). Sessions
  and bug reports stay.
- Roughly 200 bytes per event. A tester using the app for 20 minutes makes about 400 events, so 80 KB. 50 testers
  doing that every day is about 4 MB a day: roughly 120 MB at 30 days' retention, or about 250 MB with indexes. The
  free tier holds 500 MB. If it gets tight, lower `event_retention_days` or mute `network`.
- Each install keeps at most 2,000 unsent events on the phone, and drops leftovers older than a week.

## Reading it

```sql
-- A bug report, and the steps that led up to it
select * from bug_reports order by created_at desc;
select * from bug_report_trail where report_id = '…';

-- Everything someone did in a session
select seq, at, kind, name, screen, duration_ms, props from app_events where session_id = '…' order by seq;

-- What's slow: p50 / p95 per call, screen load and computation over the last week
select * from latency_last_7_days;

-- Crashes, hangs and unclean exits
select * from recent_crashes;
```

Screenshots and recordings are in the private `bug-reports` bucket (Dashboard → Storage).

MetricKit stacks aren't symbolicated. Symbolicate them against the build's dSYM, or use TestFlight's own crash
reports (App Store Connect → TestFlight → Crashes), which are.

## GitHub issues

The `bug-report-issue` edge function opens an issue for each report. The issue has the description, a 30-day link to
the screenshot or recording, the device, the last 40 steps, and the SQL for the whole trail. To turn it on for the
hosted beta:

1. On GitHub, create a fine-grained personal access token that only covers this repository, with **Issues: read and
   write**.
2. Run `supabase secrets set GITHUB_TOKEN=… GITHUB_REPO=larkindaniel/roam --project-ref xnjzuotytfzyppubjcfi`
3. Run `supabase functions deploy bug-report-issue --project-ref xnjzuotytfzyppubjcfi`

Without those secrets the function does nothing, and the reports are still saved. Locally, put the two values in
`supabase/functions/.env` and restart Supabase. Issues get `bug` and `beta-report` labels when the repository has them.

## Why not a hosted tool

Sentry (crashes, traces, breadcrumbs) or PostHog (product analytics and session replay) would give dashboards and
symbolicated stacks for free. But each is another SDK, another account and another place the data lives. At beta
scale Postgres handles this volume easily, and percentiles in SQL are enough. ClickHouse only pays off at millions of
events a day. If crash stacks become the bottleneck, add Sentry for crashes alone and keep this trail.
