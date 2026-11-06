# Roam

Roam is a native iOS travel app: rank the places that made your trips within seven categories, keep visit memories, follow other travellers and see your travels on a globe. It is built with SwiftUI, MapKit and a local Supabase backend in Docker.

- **The product overhaul** (branch `kieran/roam-product-overhaul`) supersedes much of v1:
  - `docs/product-overhaul.md` covers how the app works now.
  - `docs/design-language.md` covers how screens look and which shared components to use.
- What the original v1 does: `SPEC.md`, `MILESTONES.md` and `DECISIONS.md` (decisions made during the build are logged at the end).
- Where the build stands, with evidence: `docs/build-status.md` and `docs/m3-verification.md` to `docs/m8-verification.md`.
- Backend runbook (migrations, fixtures, cleanup and deletion workers, operator queries): `docs/local-backend.md`.

## Requirements

Xcode 26.3 or newer with an iOS simulator runtime (the deployment target is iOS 18.0), XcodeGen, the Supabase CLI and Docker Desktop. The exact versions used are recorded in `docs/m8-verification.md`.

## Start the backend

```sh
supabase start                 # local stack for project "roam"; applies migrations and seed
./scripts/configure-local.sh   # writes git-ignored Config/Local.xcconfig and scripts/.fixture-env (prints no keys)
./scripts/backend-health.sh    # containers, Auth, roam_health() and Storage
python3 -I scripts/fixtures/setup.py   # fictional fixture accounts (password roam-fixture-pass)
```

Only ever target this project's local stack. Never add `--linked`, `--db-url` or `--project-ref`.

To explore the app with real places, load the demo data instead of the test accounts, then sign in as `kieran@roam.test` with the same password:

```sh
supabase db reset --local
python3 -I scripts/fixtures/demo.py
```

Real-backend tests need the test accounts, so run `supabase db reset --local` and `scripts/fixtures/setup.py` before them.

## Build and run

```sh
./scripts/generate.sh          # XcodeGen: project.yml -> Roam.xcodeproj (generated, not committed)
./scripts/build.sh             # Debug build for the iPhone 17 Pro simulator
```

Open `Roam.xcodeproj` and run the `Roam` scheme, or install `build/DerivedData/Build/Products/Debug-iphonesimulator/Roam.app` with `xcrun simctl install`. Sign in with a fixture account such as `maya@roam.test`. Debug builds also accept `-roam-backend fixture -roam-fixture-account maya` for the in-memory fixture backend that the UI tests use.

## Test

```sh
supabase test db --local                                  # pgTAP: schema, RLS and every RPC
TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild -project Roam.xcodeproj -scheme Roam \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath build/DerivedData \
  -resultBundlePath build/results/tests-$(date +%Y%m%d-%H%M%S).xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test   # unit, real-backend integration and UI journeys
python3 -I scripts/tests/test_media_cleanup.py            # cleanup worker (add ROAM_LIVE_CLEANUP=1 for the live test)
python3 -I scripts/tests/test_account_deletion.py         # deletion worker (add ROAM_LIVE_DELETION=1 for the live test)
./scripts/export-screenshots.sh build/results/<run>.xcresult m8   # named screenshots into screenshots/m8/
```

Without `TEST_RUNNER_ROAM_BACKEND_TESTS=1` the real-backend integration tests skip, and a skip is not a pass.

## Not verified locally

Real Sign in with Apple (token exchange, reauthentication and revocation) needs Apple credentials and a device. An iOS 18 runtime or device pass is still outstanding. Hosted Supabase and SMTP, scheduled cleanup and deletion workers, public privacy/terms/support pages and a moderation owner are release setup. See `docs/m8-verification.md`.
