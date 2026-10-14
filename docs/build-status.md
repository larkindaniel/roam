# Roam continuation ledger

Updated October 13, 2026. Continuation of `1b338ee` on `codex/sol-max-handoff`.
Baseline remains `checkpoint/claude-handoff-2026-10-13` (`621ec90`).

## Milestone status

| Milestone | Status | Evidence / remaining work |
| --- | --- | --- |
| M1 | Existing checkpoint; preserve evidence | `b7de0d8`; iOS 18 runtime separately deferred |
| M2 | Existing checkpoint; Apple integration outstanding | `be0c4e1`; real Apple authorization remains unverified |
| M3 | Discovery baseline verified; rating/media/social actions continue in owning milestones | Final identity/backend11/11 + affected compactUI3/3; all seven discovery journeys have passing compact evidence; pgTAP124/124; 25 captures directly reviewed. Full app acceptance remains pending M4–M8. |
| M4 | Pending M3 acceptance | Existing engine and fixture code; required real RPC/UI incomplete |
| M5 | Pending M4 | Notes/media/persistence acceptance incomplete |
| M6 | Pending M5 | Social/feed/notification acceptance incomplete |
| M7 | Pending M6 | Travel/settings/lifecycle acceptance incomplete |
| M8 | Pending M1–M7 | Combined verification and reproducibility pending |

## Active ownership and resource rules

| Owner | Exact paths / responsibility |
| --- | --- |
| Lead | Shared domain/services/app/fixture/backend infrastructure; documentation; Git index/commits/tags; generation/build/simulator/screenshots/migrations/test execution |
| discovery_ui (A) | `RoamUITests/M3DiscoveryUITests.swift`, `Roam/Features/Lists/FilterSheet.swift`, `Roam/Features/Lists/PersonalListsView.swift`; authorized M3 filter/compact/refresh fixes |
| member_search (B) | `supabase/migrations/20261014000100_m3_literal_member_search.sql`, `supabase/tests/02_m3_places_lists_test.sql`, `RoamTests/Integration/M3PlacesIntegrationTests.swift`; authorized literal-search and pagination fixes |
| acceptance_audit (C) | Full M3 acceptance and screenshot audit; transferred `Roam/Features/Search/SearchModels.swift`, `SearchRootView.swift`, new `RoamTests/M3SearchFailureTests.swift` for search race/failure fixes |

No worker stages/commits, recursively delegates, runs shared tests/builds, modifies simulator/backend state, or edits another lane without explicit transfer. Only lead applies migrations and integrates shared contracts. Tests that mutate the shared fixture backend and pgTAP run serially.

## Environment and baseline

- Clean checkout on expected branch; no project build process observed. Existing Claude processes alone do not establish active writes.
- Xcode 26.3 (17C529), XcodeGen 2.46.0. iOS 26.2 simulator iPhone 17 Pro `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`; iPhone 16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` installed.
- Confirmed local Docker project containers `*_roam` running, database/auth/storage healthy. No reset, configuration overwrite, deployment or dependency update.
- `supabase test db --local`: **71 assertions, 1 failed**, `build/evidence/m3-baseline-db-20261013-sol.log`. Known member literal-match error reproduced.
- UI baseline command: `./scripts/generate.sh`; `xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug -destination 'platform=iOS Simulator,id=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C' -derivedDataPath build/DerivedData -resultBundlePath build/results/m3-ui-baseline-sol-20261013.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test -only-testing:RoamUITests/M3DiscoveryUITests`, piped with `set -euo pipefail` through tee/xcbeautify. **4 passed / 1 failed** (106.914 s), original `experience-row-Aster House` assertion; baseline failure reproduced.

## Contracts / acceptance coverage

SPEC/DECISIONS/MILESTONES unchanged. M3 literal handle/display-name search must consistently escape `_`, `%`, and backslash; deliberate collision and actual multi-page tests required. Filters remain staged, with OR within each facet and AND across facets. UI fixture evidence is distinct from real backend/privacy evidence. Audit will map every acceptance item before a verified checkpoint.

## External checks

Real Apple capability/provider/token exchange and revocation require credentials/device evidence. iOS 18 runtime checks are deferred; keep deployment target 18 and use installed iOS 26.2. Hosted backend/SMTP, public legal/support and operational moderation are separate release setup. None counts as completed local verification.

## Next executable action

Complete and review A/B/C edits plus lead Location/Explore fixes, review corrective migration, apply locally, run focused Swift/integration/pgTAP/UI checks, inspect new screenshots, fill full M3 acceptance audit. Commit and tag M3 only after required local acceptance passes, then dispatch M4 lanes.

### M3 audit findings under repair

- Real location timeout task group could wait forever for a suspended callback continuation; lead replaces it with bounded callback completion, cancellation and coalesced taps; new `M3LocationTests` exercise the real bridge.
- Old member page could append after query change; enrichment could swallow cancellation and backend failures. C owns search fixes/tests.
- Explore failed map loads hid errors and list errors cleared usable content; lead retains acknowledged pins and retries the requested area, with viewport race/retry tests.
- Later milestones still own Log/Add visit/rerank and activity routes; those remain visible acceptance dependencies, not verified features.

### First combined corrected check

- Forward migration `20261014000100_m3_literal_member_search.sql` applied locally; no data removed. `build/evidence/m3-migration-sol-20261013.log`.
- Corrected pgTAP: **100 assertions passed, 0 failed**, `build/evidence/m3-db-corrected-sol-20261013.log`.
- `TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild ... test -only-testing:RoamTests`: **100 executed, 98 passed, 2 skipped, 0 failures**, `build/results/m3-logic-backend-sol-20261013.xcresult`, `build/evidence/m3-logic-backend-sol-20261013.log`. Real backend: M2 12/12, M3 8/8, including public-RPC 30+5 member pagination. Two MapKit feasibility tests require their opt-in flag; these skips are not provider passes.
- Search failure/race14, real location bridge5, Explore3 and bookmark failure/account-reset2 pass. Existing Swift actor warning in ProfileSetupFlowView avatar label remains for cleanup.
- Further audit fixes: action-level guards around resolve+bookmark, previous-results disclaimer for failed destination refresh, native map deselection on closing selection, annotation payload refresh after category changes; verification pending for these later changes.

### Final focused M3 logic/provider check

- `TEST_RUNNER_ROAM_BACKEND_TESTS=1 TEST_RUNNER_ROAM_LIVE_MAPKIT=1 xcodebuild ... test` selecting `M3ListRefreshTests`, `M3MapSelectionTests`, `M3PlacesIntegrationTests`, `MapKitFeasibilityTests`: **16/16 passed, 0 skipped, 0 failures**, `build/results/m3-focused-live-repeat-sol-20261013.xcresult` and raw log of same basename under `build/evidence`.
- Native callback tests prove Close deselects and the same pin can be selected again; cluster-controller selection zooms to members without selecting an experience. This is native-map logic evidence, distinct from an actual UI cluster tap.
- Live MapKit resolved Golden Gate Park with stable identifier/round-trip and Hakone locality; both opt-in feasibility tests passed on iOS 26.2. This does not validate iOS 18 runtime.
- Repeated M3 backend8/8 on the used database, followed by pgTAP **100/100** (`build/evidence/m3-db-after-repeat-sol-20261013.log`). No fixture purge/reset used to obtain these results.
- Corrected UI7 currently running in `build/results/m3-ui-corrected-sol-20261013.xcresult`; selected-place/viewport journey passed. Compact run and direct screenshot review pending.

### M3 final audit and current executable state

- All worker implementation lanes have returned ownership to lead except A, who currently owns `RoamUITests/M3DiscoveryUITests.swift` to stabilize scrolling within the visible filter viewport. No other source writer. B/C available idle after read-only reviews.
- `LibraryStore.refresh` now rejects an older snapshot after same-account mutation acknowledgement; lists accept latest uncancelled load only. New continuation-gated regressions authored by C/A respectively. `ExploreModel` cancelled initial loads return to idle and reissue on reappearance instead of staying loading. These focused logic cases passed in the current compact run.
- SQL helper effective privileges audit found newly created M3 serializers callable by client roles (app_private is not REST exposed). Forward `20261014000200_m3_helper_privileges.sql` revokes client access and global/default PUBLIC execute; pgTAP **114/114**.
- Forward `20261014000300_m3_locality_identity.sql` prevents unidentified localities from reusing a POI and marks missing canonical identity for reconciliation. pgTAP **124/124**, `build/evidence/m3-db-identity-sol-20261013.log`. New real-backend mixed-batch identity regression and client candidate-ID separation are awaiting focused compile/run.
- `m3-ui-corrected-sol-20261013`: **7 executed, 6 passed / 1 failed**. Kyoto selected-state assertion correctly catches a row hidden under the footer despite XCUITest isHittable=true; raw debug frame y813.3...887.3, screen874. `build/results/m3-ui-corrected-sol-20261013.xcresult`.
- Compact current run: `build/results/m3-compact-final-sol-20261013.xcresult`, iPhone16e iOS26.2, logic refresh/cancellation cases pass, map selection/viewport and denied-manual transitions pass; AX Kyoto scrolling oscillates under full List swipes, so A is changing only gesture distance, retaining full visible-frame and selected-state assertions. Run still executing; not accepted.
- Direct visual review of corrected17Pro states16/17/20–25 finds usable controls/card/highlight/viewport and distinct Kyoto-denial vs Lisbon map. Add available addresses to distinguish same-name Explore businesses (lead changed row statusLine). AX selected-checkbox capture will be recaptured after scrolling fix. Manual focus can leave Search this area visible due MapKit aspect-ratio adjustment; do not describe that capture as panning proof; actual pan/replacement journey24–25 provides evidence.
- Next: finish compact run, integrate frozen UI gesture helper, run focused identity/backend and failed filter/AX/updated map UI selectors, export and personally inspect every final screenshot; fill `docs/m3-verification.md`, review staged source/tests/docs/images, commit and tag M3. Then begin M4.
- M4 contract notes preserved: receipts must precede revision/rating validation, serialize duplicate operation UUIDs, reject changed payload, and include remove/delete operations. Ranking and Bookmark need a shared lock/recheck to prevent concurrent Want insertion after first rating. Existing fixture hashValue is not a cross-process intent hash. Log/Add visit/activities/media remain later-milestone dependencies, not completed discovery evidence.

### M3 checkpoint boundary

- Final affected run `m3-final-fixes-sol-20261013.xcresult`: **11 Swift tests passed, 3 UI tests passed, 0 skipped, 0 failed**; database after integrations **124/124**. This completes all seven discovery journeys with passing compact evidence across the previous run and affected reruns; full M8 suite will run the combined final source.
- All25 tracked M3 captures directly reviewed; updated12/21 show visible selected Kyoto,22/23 show selected pin/card/list and distinguish same-name addresses; no blocking layout defect found.
- `git diff --check` and `scripts/check-secrets.sh` pass (tracked source/built Debug app), no reference captures/config/pins modified.
- No active worker file owner; lead integrating commit. Next milestone M4: freeze service and receipt contracts, dispatch backend / ratingUI / engine lanes. Forward action/editor/social dependencies listed in `docs/m3-verification.md` remain required, not silently accepted as finished app features.
