# Roam build-run instructions

Repository: `/Users/daniellarkin/Desktop/projects/capstone`.

These instructions govern the **separate implementation run** once the user requests it. Writing these documents did not start implementation. Read `SPEC.md`, `MILESTONES.md` and `DECISIONS.md` before code; use `PLAN.md` for confirmed background and `docs/roam-reference-map.md` for screenshot lookup. Latest explicit user instructions override documents; SPEC is the current v1 contract. Historical inventory/capture-gap prose and PLAN's old draft milestone list cannot reintroduce deferred features.

## Execution rules

- Complete M1–M8 in order. Make each milestone buildable, run meaningful checks, launch and visually inspect its screens, fix failures, save evidence and commit task-owned changes with the milestone name. Inspect `git status` first; preserve unrelated work. Never use `git add .` without checking every staged file.
- Do not stop between milestones for routine product questions. Confirmed choices and defaults in DECISIONS are effective requirements. Record additional small judgments and continue; do not silently change scope, providers, ranking rules or the globe requirement. External credentials/device access may require user action; finish independent work and report precisely what remains blocked.
- Never hand-edit `.pbxproj`; edit `project.yml` and rerun XcodeGen. Do not commit generated `*.xcodeproj`, DerivedData, build logs, secrets or local database volumes. Record dependency versions and commit the project's chosen reproducible SwiftPM resolution artifact outside ignored generated output if needed.
- No implementation of deferred guides, list sharing, imports, leaderboard, curated/trending discovery or city scores; no placeholder routes/buttons for them. In-app notifications are v1; remote push is deferred. Native Apple sign-in remains required.
- Keep `reference/beli/`, screenshots, `flows.md` and capture-workflow evidence unchanged. No iPhone Mirroring, Beli account action, decompilation or private Beli API. Use fictional fixture data and original Roam assets, not real captured people/content.
- Test business logic, authorization, retries/races and observable journeys. Avoid tests that merely restate constants or mirror view implementations. No test can call mocked Apple auth, a newer iOS runtime or a screenshot-only scaffold a completed real integration.
- Local development and disposable local fixture changes are within the build run. Do not deploy, push a remote schema, reset remote data, submit to App Store or modify real reference-account records. A destructive reset below is only for this project's explicitly disposable local fixture database; preserve any user-created local data first.

## Stack and files the build must create

Confirmed: iOS 18.0+, SwiftUI, MapKit, XcodeGen, local Supabase Docker, Supabase Swift SDK via SPM, native Sign in with Apple plus email/password.

Signing: `PRODUCT_BUNDLE_IDENTIFIER = com.daniellarkin.roam`, `DEVELOPMENT_TEAM = H5V24G3F3D` (Somang Larkin), automatic signing. **Never use `6KKPN7P748`.** Device signing and Apple capability setup are distinct from unsigned simulator builds; simulator success alone does not verify Apple authentication.

M1 creates `project.yml` generating `Roam.xcodeproj` with shared `Roam` scheme and targets `Roam`, `RoamTests`, `RoamUITests`; scheme test action includes both test bundles. Organize Swift by feature, with independent ranking/geography services and dependency-injected Auth/Place/Storage providers. Use `@Observable`, structured concurrency and `@MainActor` for UI state. Do not move business invariants into views.

M1/M2 create `supabase/config.toml` (project_id `roam`), migrations, local seed and `supabase/tests/` pgTAP tests. Use local port defaults unless a collision is verified; record any changes. Create checked-in config example, ignored `Config/Local.xcconfig`, ignored server env and fixture setup commands. Update `.gitignore` for these ignored files before writing values. Mobile config includes only API URL and publishable/anon client key; RLS protects it. Service-role keys, Apple signing/revocation secrets and credentials remain server-side, never in app/seed/logs. Never print a full secrets-bearing `supabase status -o env` into build evidence.

Build tests should have separate deterministic fixture mode and real local-backend mode. M2 creates a reproducible local fixture setup using Auth admin/service access only in the test/server runner. No debug auth bypass may enter Release. M6 tests at least three users (owner, follower, unrelated/blocked) and anonymous access.

## Environment verified October 13, 2026

| Tool / resource | Observed |
|---|---|
| Xcode | 26.3, build 17C529 at `/Applications/Xcode.app` |
| XcodeGen | 2.46.0 |
| xcbeautify | 3.2.1 |
| Supabase CLI | 2.120.0 at `/opt/homebrew/bin/supabase` |
| Docker CLI | 29.7.2; daemon **not running** at documentation check |
| Installed simulator runtime | iOS 26.2 only |
| Default simulator | iPhone 17 Pro, `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C` |
| Smaller simulator | iPhone 16e, `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` |
| iOS 18 runtime validation | **Deferred by the user (2026-10-13):** this build run tests on iOS 26.2 only. Do not download or install an iOS 18 runtime. Keep the 18.0 deployment target and availability checks; iOS 18 runtime validation is a separate pass after the run. |

Recheck before execution; UUIDs/tool versions may change. The commands below have valid CLI forms checked via local help; they have **not** been run against a Roam project because no app exists yet. Supabase help needs its per-user settings directory and simulator tools need CoreSimulator access; sandbox failures are not proof those services are broken. Use the execution environment's normal permission mechanism if needed, without weakening macOS security or repurposing `$HOME`/`$CODEX_HOME`.

## Preflight and local backend

Run from this repository. Do not install/update working tools just to match a guessed version.

```sh
cd /Users/daniellarkin/Desktop/projects/capstone
git status --short
xcode-select -p
xcodebuild -version
xcodegen --version
xcbeautify --version
supabase --version
docker info --format '{{.ServerVersion}}'
xcrun simctl list runtimes
xcrun simctl list devices available
```

If Docker is not running, open the installed Docker app and wait for its engine to become ready; retry `docker info`. Do not treat an arbitrary sleep as a readiness check. M1 runs `supabase init` once **only if `supabase/config.toml` does not exist**, then sets project_id/config and creates migrations before service checks. The following commands are for the build run, not documentation preparation:

```sh
supabase start
supabase migration up --local
supabase test db --local
```

`supabase test db --local` is the installed CLI command, **not** `supabase db test`. It runs the repository pgTAP tests after migrations exist. Seed fixtures reproducibly with the M2 documented local fixture procedure. Only to recreate this project's disposable local fixture DB:

```sh
supabase db reset --local
supabase test db --local
```

Reset destroys local rows and reapplies migrations/seed. Never add `--linked`, `--db-url` pointing elsewhere or `--project-ref` to these commands. For normal iterative schema changes use migrations, not repeated resets of meaningful user data. Stop local containers when requested with `supabase stop`; do not indiscriminately stop other Docker projects.

Read local endpoint/client configuration privately from `supabase status`, placing only public client values in ignored local config. The iOS simulator uses the Mac's loopback endpoint (normally `http://127.0.0.1:54321`); a physical phone cannot use its own loopback to reach the Mac. Configure a reachable protected development endpoint for device checks, with only narrowly scoped Debug networking exceptions if necessary, not a global Release transport-security bypass. Local Auth mail viewer address comes from local status; do not assume production email delivery.

## Generate, build and test

Once M1 has created `project.yml`, source/test targets and local configuration, use zsh with pipeline failure propagation. These variables are task-specific; use the same working shell or reassign them per block.

```sh
set -o pipefail
ROAM_SIMULATOR_ID=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p build/evidence build/results
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project Roam.xcodeproj -scheme Roam
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "build/evidence/build-$ROAM_RUN_ID.log" | xcbeautify
```

Do not proceed after a failed pipeline. Keep the raw log for diagnosing compilation errors. Build actual iOS 18-compatible sources; use availability checks for any newer API. Use engine tests for deterministic scoring and the database fixture suite for authoritative RPC parity.

```sh
set -o pipefail
ROAM_SIMULATOR_ID=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/results/tests-$ROAM_RUN_ID.xcresult" \
  CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "build/evidence/tests-$ROAM_RUN_ID.log" | xcbeautify
supabase test db --local
```

Result-bundle paths must be new per run. Use `-only-testing:RoamTests` or an exact test identifier for focused iterations; final M8 runs both unit and UI suites plus local DB/integration tests. Do not report a skipped UI suite as passed. Use built-in XCTest/Swift Testing for appropriate tests; add test dependencies only when needed. Keep fixture-mode screenshots distinct from backend-integration evidence.

## Simulator launch and visual verification

Boot only the selected simulator; don't erase all simulators or alter the user's phone. Re-query IDs if unavailable.

```sh
ROAM_SIMULATOR_ID=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C
open -a Simulator
xcrun simctl bootstatus "$ROAM_SIMULATOR_ID" -b
xcrun simctl install "$ROAM_SIMULATOR_ID" \
  build/DerivedData/Build/Products/Debug-iphonesimulator/Roam.app
xcrun simctl launch --terminate-running-process "$ROAM_SIMULATOR_ID" \
  com.daniellarkin.roam
mkdir -p screenshots/m1
xcrun simctl io "$ROAM_SIMULATOR_ID" screenshot screenshots/m1/01-launch.png
```

Choose the actual milestone directory/state filename on subsequent runs. Navigate with configured MobileBuildMCP when available or XCTest UI automation/available native simulator controls; inspect tool schemas before using them. `simctl` can boot/install/launch/capture but is not a general tap API. Do not fall back to iPhone Mirroring. If simulator navigation tools are unavailable, use UI tests to drive the journey and screenshots to verify results; don't claim manual taps occurred.

Open each distinct screen/state screenshot and compare against the reference map's relevant active S IDs, checking layout, typography hierarchy, empty/error behavior, safe areas and accessible alternatives. Travel adaptations and chosen score/publication behavior take precedence over competitor screens. Capture loading, empty, error and populated variants where acceptance requires them. Do not pixel-match Beli branding.

Use iPhone 16e for compact layouts, large Dynamic Type and Reduce Motion. An iOS 18 device/runtime is a separate validation target; if absent, record the limitation, continue current-runtime tests and do not claim full minimum-OS runtime coverage. Record any requirement for runtime download/device access accurately.

## Signing, Apple auth and external checks

Keep team/bundle/capability declarations in `project.yml` and entitlements. Simulator builds use `CODE_SIGNING_ALLOWED=NO`; a signed device build must use normal automatic signing and the confirmed team. Do not create/revoke unrelated certificates or substitute a personal team to hide errors. Configure Apple provider allowed audience for the native app and validate token/nonce against Supabase. Check current official provider instructions while implementing rather than inventing secret requirements.

Primary references consulted for this handoff: [Supabase Swift native ID-token sign-in](https://supabase.com/docs/reference/swift/auth-signinwithidtoken), [Supabase Apple provider setup](https://supabase.com/docs/guides/auth/social-login/auth-apple), and [Apple MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem). Use the selected SDK's availability annotations for deployment compatibility. These support integration setup, not Roam's product/scoring rules.

Apple token exchange, revocation on account deletion and provider-specific failure handling need real configuration evidence before release. Continue email/local fixture work if an external setup check is blocked, retaining the Apple path and reporting its precise status. Do not read secrets from unrelated apps or paste them into the conversation. Legal agreements and actual account actions remain subject to the execution environment's authorization rules.

## Milestone and final evidence

For each milestone record: requirement IDs, implemented behavior, commands/results, simulator/runtime and screenshot paths, fixture-vs-real provider distinction, decisions added, and any exact blocker. Fix new failures before marking that milestone complete. Commit only code/docs/tests belonging to the milestone after checking staged diff; do not reset user work.

Final handoff must include reproducible startup/build/test commands, completion status for all eight milestones, test summaries and evidence paths, changes to DECISIONS defaults, and unresolved external checks/release setup. A clean build with stubbed network behavior is not the completed app. No deployment/App Store upload is part of this build run.
