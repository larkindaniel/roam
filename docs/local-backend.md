# Local backend runbook (Supabase in Docker)

All commands run from the repository root and target only this project's local stack (`project_id = "roam"`).
Never add `--linked`, `--db-url` or `--project-ref` to these commands.

## Start, configure and check

```sh
supabase start                 # pulls images on first run; applies migrations + seed
./scripts/configure-local.sh   # writes ignored Config/Local.xcconfig (URL + publishable key only)
                               # and ignored scripts/.fixture-env (server-side fixture runner values)
./scripts/backend-health.sh    # containers, Auth health, roam_health() RPC, Storage version
```

`configure-local.sh` never prints keys. Do not paste `supabase status -o env` output into evidence.

Services enabled: Postgres 17, Auth (GoTrue), PostgREST, Storage, Mailpit (local email at the
`MAILPIT_URL` from `supabase status`, normally http://127.0.0.1:54324) and the Edge runtime. Realtime,
Studio and analytics are disabled to keep the stack small. Default ports are used (API 54321, DB 54322,
mail 54324); no collision was found on this machine.

Auth settings for local development: email confirmation required, minimum password length 12, redirect
allow-list `roam://auth-callback` and `roam://auth-callback/recovery`, Apple provider enabled with the
bundle ID `com.daniellarkin.roam` as allowed ID-token audience (no secret configured locally). Rate limits
are raised locally only so fixture setup and integration tests are not throttled.

## Migrations and tests

```sh
supabase migration up --local
supabase test db --local       # pgTAP tests in supabase/tests/
```

## Disposable fixture database

Only for this project's disposable local fixture database (destroys local rows, reapplies migrations and seed):

```sh
supabase db reset --local
supabase test db --local
```

Fixture accounts and content (test-only, local only):

```sh
python3 scripts/fixtures/setup.py   # idempotent; run after start or reset
./scripts/check-secrets.sh          # service/secret keys absent from tracked files and the built app
```

The runner uses the local service-role key from `scripts/.fixture-env` and never prints it.

Real-backend Swift integration tests run with `TEST_RUNNER_ROAM_BACKEND_TESTS=1` (otherwise they are skipped and
reported as skipped):

```sh
TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild -project Roam.xcodeproj -scheme Roam \
  -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test -only-testing:RoamTests
```

## Stop

```sh
supabase stop   # stops only the roam containers
```
