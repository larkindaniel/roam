# Roam continuation ledger

Updated October 14, 2026. Branch `codex/sol-max-handoff`. One lead (Claude) owns every file; the earlier Codex worker lanes no longer exist. Per-milestone detail lives in `docs/m3-verification.md` to `docs/m7-verification.md`. This ledger keeps only the current state and the exact next action.

## Milestone status

| Milestone | Status | Evidence / remaining work |
| --- | --- | --- |
| M1 | Verified checkpoint | `b7de0d8`; iOS 18 runtime validation deferred by the user |
| M2 | Verified checkpoint; real Apple authorization outstanding | `be0c4e1`; needs real Apple credentials/device |
| M3 | Verified | `f081e2e`, `checkpoint/m3-verified-2026-10-13` |
| M4 | Verified | `97da54e`, `checkpoint/m4-verified-2026-10-14` |
| M5 | Verified | `966a0d9`, `checkpoint/m5-verified-2026-10-14` |
| M6 | Verified | `a1094ab`, `checkpoint/m6-verified-2026-10-14` |
| M7 | Verified; committing | See `docs/m7-verification.md`; tag `checkpoint/m7-verified-2026-10-14`. Apple revocation recorded `not_configured` (release blocker) |
| M8 | In progress | Drafts in `build/m8-drafts/` (git-ignored): combined two-account UI journey, seven-category session, accessibility audit, layout stress scenario/test, Reduce Motion check, real-backend journey test |

## Local environment (checked October 14, 2026)

- Xcode 26.3 (17C529), Swift 6.2.4, XcodeGen 2.46.0, Supabase CLI 2.120.0, Docker 29.7.2, Python 3.9.6. Simulators: iPhone 17 Pro `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`, iPhone 16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` (iOS 26.2).
- Local stack `*_roam`: Postgres 17.11, GoTrue v2.197.0, PostgREST v16.4, Storage v1.79.36, Edge Runtime v1.77.4, Mailpit v1.31.3. Migrations applied through `20261014000900` (M7). Applied migrations are immutable; fix forward.
- SwiftPM (`Config/Package.resolved`): supabase-swift 2.55.3, swift-crypto 4.5.2, swift-asn1 1.7.3, swift-http-types 1.8.0, swift-clocks 1.1.1, swift-concurrency-extras 1.4.2, xctest-dynamic-overlay 1.13.1.
- Backups: `build/backups/m5-pre006-*` and `build/backups/m7-pre009-db-20261014-150541.dump`.
- Deno is not installed; `inspector_test.ts` cases run against the live function through the Swift integration suite instead.
- Disk: the Mac's disk ran low earlier (about 0.5 GB free). Unreferenced, superseded result bundles were removed (their logs stay in `build/evidence/`). Check `df -h /` before long runs.

## M7 final evidence

pgTAP **538/538** (94 new; `m7-db-final-claude-20261014-200154`). Full run on the 17 Pro: RoamTests 262 executed, 260 passed, 2 opt-in skips; RoamUITests M1–M7 53/54, and the one failed journey's fixed test then passed (`m7-final-full-claude-20261014-193157`, `m7-ui-editprofile-claude-20261014-200005`). Workers 4/4 + 4/4 plus live tests (`m7-workers-final-claude-20261014-200110`). M7 UI on the 16e **10/10** (`m7-ui-compact-claude-20261014-200103`).

## Next executable action

1. If the M7 commit/tag is missing: run `git diff --check` and `scripts/check-secrets.sh`, stage the M7 files explicitly (never `build/m8-drafts`), commit "M7: …" and tag `checkpoint/m7-verified-2026-10-14`.
2. M8:
   - Move `build/m8-drafts/*` into place: `FixtureState+Stress.swift` in `Roam/Backend/Fixture/` (make `nextID`/`rankingSnapshot` internal and call `seedStress()` for scenario `stress`), the UI tests in `RoamUITests/`, and `M8JourneyIntegrationTests.swift` in `RoamTests/Integration/`.
   - Add the Reduce Motion line to `ComponentCatalogView` (`catalog-reduce-motion`).
   - Remove the unused `AppRoute.findPeople` and the `UnavailableRouteView` fallback.
   - Run the M8 suites: on the 16e with Reduce Motion on, then the final full suite, the clean-checkout build and the handoff.

## External checks (not local verification)

Real Apple capability/provider/token exchange, Sign in with Apple reauthentication for deletion, and Apple token revocation need the user's credentials and a device. iOS 18 runtime validation is deferred by the user. Hosted Supabase/SMTP, the hosted cleanup and deletion schedules, public legal/support pages and operational moderation are release setup.
