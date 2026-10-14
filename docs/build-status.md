# Roam continuation ledger

Updated October 14, 2026. Continuation of `1b338ee` on `codex/sol-max-handoff`.
Baseline remains `checkpoint/claude-handoff-2026-10-13` (`621ec90`).

## Milestone status

| Milestone | Status | Evidence / remaining work |
| --- | --- | --- |
| M1 | Existing checkpoint; preserve evidence | `b7de0d8`; iOS 18 runtime separately deferred |
| M2 | Existing checkpoint; Apple integration outstanding | `be0c4e1`; real Apple authorization remains unverified |
| M3 | Discovery baseline verified; rating/media/social actions continue in owning milestones | Final identity/backend11/11 + affected compactUI3/3; all seven discovery journeys have passing compact evidence; pgTAP124/124; 25 captures directly reviewed. Full app acceptance remains pending M4–M8. |
| M4 | Local acceptance verified; checkpoint being committed | Swift175 pass/2 opt-in skips; pgTAP254/254; all8 compact UI journeys have passing full+affected evidence;24 captures reviewed |
| M5 | Ready to begin after M4 checkpoint | Notes/media/persistence acceptance incomplete; read-only contracts prepared |
| M6 | Pending M5 | Social/feed/notification acceptance incomplete |
| M7 | Pending M6 | Travel/settings/lifecycle acceptance incomplete |
| M8 | Pending M1–M7 | Combined verification and reproducibility pending |

## Active ownership and resource rules

| Owner | Exact paths / responsibility |
| --- | --- |
| Lead | Shared domain/services/app/fixture/backend infrastructure; documentation; Git index/commits/tags; generation/build/simulator/screenshots/migrations/test execution |
| discovery_ui (A) | M4 rating recovery source/tests frozen to lead; idle available for compile/UI repairs |
| member_search (B) | `supabase/migrations/20261014000500_m4_ranking_runtime.sql`, `SupabaseBackend+Ranking.swift`, `03_m4_ranking_test.sql`, `M4RankingIntegrationTests.swift`; forward runtime fix and server-enforced last-Visit confirmation |
| acceptance_audit (C) | New `RoamTests/M4ProjectionRefreshTests.swift`; read-only flow/detail audit |

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

Commit/tag M4 after staged review/secrets check, then freeze M5 content/upload contracts and dispatch backend, editors/gallery, persistence/images lanes. Lead owns shared models/routes/fixtures/auth/session infrastructure and all resources. Continue M5–M8 in order.

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

## M4 active contracts / owners

- M3 commit `f081e2e`; checkpoint `checkpoint/m3-verified-2026-10-13`. Baseline original tag unchanged.
- Backend B/member_search owns new `supabase/migrations/20261014000400_m4_ranking.sql`, `Roam/Backend/Supabase/SupabaseBackend+Ranking.swift`, `supabase/tests/03_m4_ranking_test.sql`, `RoamTests/Integration/M4RankingIntegrationTests.swift`.
- UI A/discovery_ui owns new `Roam/Features/Rating/`, `RoamTests/M4RatingFlowTests.swift`, `RoamUITests/M4RatingUITests.swift`.
- Engine C/acceptance_audit explicitly owns `Roam/Ranking/RankingEngine.swift`, `Roam/Domain/Score.swift`, smoke/full engine tests and `docs/data/m4-ranking-golden.json`. Lead adds JSON as test-only resource in project.yml.
- Lead owns shared domain/protocols/app/fixture/pending conformance and ExperienceDetailView plus all resource operations/index/docs/commits. No recursive worker spawning.
- Existing RatingCommitRequest/AddVisitRequest signatures unchanged, now Codable for durable drafts/stable fixture fingerprints. RPC category_ranking(p_category), commit_rating(p_request), add_visit(p_request), remove_rating(p_experience_id,p_operation_id), delete_visit(p_visit_id,p_operation_id). Requests camelCase except ComparisonAnswer compared_rating_id. Server derives actor and SHA256 digest; rejects actor/score/order input, authoritative replay/scoring only.
- Lock order operation advisory -> experience row -> actor category revision. Bookmark shares experience lock and rechecks rating under it. Receipt read before revision/current-state checks; same successful UUID returns original result, changed intent fails. Remove/delete also have durable receipts.
- LogRequest.Mode Codable; new default `categoryLocked=false` and `existingVisit=nil`. Nonnil summary category alone is a suggestion, not a lock; lead fetches detail before row routing. UI entry RatingFlowView(request:onSaved:), RatingFlowCompletion rating(result)/visit(result), acknowledgement callback fires once. Lead invalidates library/details then result Done returns invoker.
- Rerank visit=nil preserves latest retained anchor. Supplied optional details update that existing Visit atomically without new Visit; preserve existing owned attached media or attach completed owned uploads, cleanup removed assets. Root passes anchor for UI draft prefill. Add visit creates Visit/activity without reorder.
- Next lead work: stable fixture receipt digests/removal+delete idempotency, firstLog/rerank/addVisit actions and acknowledged detail removal/last-Visit confirmation; integrate workers then test SQL/Swift parity and full M4 journeys.

### M4 lead integration progress

- UI entry actions wired Search/Explore/own+other lists/selected cards/detail via authoritative detail into LogRequest; category suggestions remain editable until globally locked. Sheet now hosts RatingFlowView and invalidates library only after acknowledged callback. Detail has Rank again, Remove ranking, per-Visit deletion and distinct last-Visit confirmation; uncertain deletion keeps an account-scoped exact operation locally for retry.
- Fixture receipts now use sorted-key SHA256 digests instead of process hashValue, include removal/Visit deletion receipts, preserve original last-Visit result, support atomic rerank anchor enrichment and enforce revisit date/photo limits. Authenticated fixture calls capture actor before simulated latency and reject account switch. New fixture parity cases authored.
- SDK source review revealed SupabaseClient.adaptRequest overwrites Authorization with current token at transport time. Shared RPC helper now snapshots session, guards account across refresh, uses SDK PostgrestClient with immutable per-request JWT/transport. New real backend held-transport/account-switch test proves pending mutation cannot transfer to another member; not run yet.
- Engine C returned frozen code +18 tests +shared29goldens. UI A returned frozen2source/14modeltests/7UIjourneys. Backend B migration/adapter mostly frozen; requested post-category-lock revisit snapshot reread before apply; SQL/integration tests still being completed.
- Next: static review/apply004, run pgTAP, generate, run engine/model/fixture/realbackend tests; fix compile/runtime errors; run M4UI then inspect captures. No M4 verification/build result yet.

### M4 first integration results and current ownership

- Applied004 locally successfully; raw `build/evidence/m4-migration-sol-20261013.log`. Applied migration remains immutable; backend B owns ONLY corrective `20261014000500_m4_ranking_runtime.sql` for runtime qualification error.
- First pgTAP aborted after31 passing M4 assertions due missing ARRAY in authored test FOREACH. Test syntax corrected; second run aborted at same boundary because applied commit_rating qualified local variables with an unavailable implicit function label. M2/M3 still124/124. Failed logs: `m4-db-first-sol-20261014.log`, `m4-db-corrected-sol-20261014.log`; no M4 backend pass claimed.
- Initial combined build-for-testing passed, `build/evidence/m4-compile-first-sol-20261014.log`. Later recovery/fixture changes require rebuilding. Lead removed deprecated SDK initializer use and preexisting avatar actor warning.
- Common JSON/storage Date codec now preserves PostgreSQL microseconds, avoiding same-millisecond inverse-UUID tie representative drift. Focused precision tests authored; actual draft replay precision test requested from A.
- A owns ONLY RatingFlowModel.swift/M4RatingFlowTests.swift for cancelled comparison-load recovery, canonical-category changes while a draft was closed, and precise tie draft restoration. Other UI source/tests frozen to lead. C read-only audits M4 acceptance/recovery; no source ownership. B corrective005 only; all other backend/tests frozen.
- Lead fixture review now rejects fresh invalid answers as validation, invalid time zone identifiers, and unknown Experience removal consistently with server; adds focused regressions. Root owns fixture/domain/app/shared infrastructure plus new account-scope test. No accepted M4 Swift/backend/UI result yet.
- Review found two ordinary Visit deletions based on stale two-Visit snapshots could delete the last Visit/Rating without explanatory consent. Contract now requires explicit allowRatingRemoval; server locks/rechecks and rejects unconfirmed last-Visit removal with confirm_last_visit. UI retains durable state and opens the distinct confirmation with a new operation after this definite rejection. Successful receipt includes consent in intent digest; same UUID retry preserves original result. B adds005/adapter/tests; root fixture/UI/error/protocol changes complete, tests pending.
- Result Close now dismisses acknowledged completion directly. Skip explains approximate placement/rank-again. Lead added invoking-search score refresh and last-Visit cancel/confirm UI journey; detail loads reject stale generations.
- Applied005 immutable; corrected pgTAP **254/254** before and after real integrations (`m4-db-final-sol-20261014.log`, `m4-db-after-integration-sol-20261014.log`). All130M4 assertions pass. Two last goldens had accidentally queried two independent categories; isolated Outdoors with exact original expectations retained.
- Combined Swift/real backend `build/results/m4-logic-backend-sol-20261014.xcresult`: **177 executed,175 passed,2 skipped,0 failed**. Engine18/model18/projection8/fixture8/precision2 plus M4 public integration11 and held-transport account scope1 all pass. Two liveMapKit opt-ins skipped in this run; they passed separately under M3.
- C authored8 projection regressions. Root fixed projection refreshes superseding pending Search/Explore destinations: independent Search projection generation, queued refresh during foreground loads, latest requested viewport for Explore. All8 pass.
- Read-only A review caught absent sentiment colors and editor Done errors hidden behind modal. Lead now adds green/amber/red icons/text/fills and editor-local error labels. Compact all8UI journeys running `build/results/m4-ui-compact-sol-20261014.xcresult`; final build/visual checks pending. All workers frozen/idle, no active file ownership outside lead.
- Compact full M4UI **6 pass/2 fail** (404s): incorrect broad Date switch tap and actual Search keyboard covering Okay on row Log. Lead fixed focus; A strengthened real switch value/Cancel/Done assertions. Affected recovery **2/2 pass** (96s), `build/results/m4-ui-recovery-sol-20261014.xcresult`. All8 journeys have passing evidence across full+affected runs.
- All24 captures personally reviewed, including new23 sentiment colors/24 unknown date and20–22 query-preserving acknowledged score + last-Visit confirmation/deletion. Reference nc031/032/040 directly compared; no blocking visual defect, no reference edits. `docs/m4-verification.md` maps complete M4 evidence and later dependencies.
- After user reset/continue, branch/baseline/dirty source preserved; local services healthy; compact simulator shut down and was booted by focused rerun. No backend reset performed by lead. Workers previously reported usage-limit errors; their completed source is frozen, and they will be reused for M5 if available.
