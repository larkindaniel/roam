# Roam completion plan for Sol Max

Continue the existing native iOS app from Claude's M3 checkpoint, finish M3 through M8, and leave a reproducible, tested local application. Use parallel agents within each milestone, with one lead integrating and verifying their work. The product requirements are already decided; the remaining work is implementation and verification.

Prepared October 13, 2026. This handoff is repository documentation and is intended to travel with its source checkpoint.

## Prompt to give Sol Max

```text
Work in /Users/daniellarkin/Desktop/projects/capstone on the existing
codex/sol-max-handoff branch. Read SOL_MAX_HANDOFF.md, then execute its plan.
Read SPEC.md, MILESTONES.md, DECISIONS.md and CLAUDE.md before implementation.
Use Sol with maximum reasoning for the lead; have subagents inherit the
configured model and effort. Use up to three worker agents alongside the lead,
with explicit file ownership and the resource rules in the handoff.

Finish M3, then M4 through M8 in order. Preserve Claude's implementation and
the checkpoint tag. Resolve routine implementation decisions yourself, record
them, and keep working through testing, fixes, screenshots and milestone
commits without asking me to approve each step. Do not stop after writing a
plan, delegating work, or getting a successful build. Verify each milestone's
acceptance criteria. Commit coherent, reviewed work as you go.

Keep the progress ledger current so another session can resume precisely.
If Apple credentials or device access blocks a check, finish independent
local work and report the exact remaining external check. Keep the iOS 18
deployment target, test on installed iOS 26.2, and do not install iOS 18.
No hosted deployment, remote schema change or App Store submission is part
of this request. Finish with an honest M1–M8 status, test/evidence references,
startup commands, rollback references and any unresolved external checks.
```

## Requirements and starting state

Read these in order: [SPEC.md](SPEC.md), [MILESTONES.md](MILESTONES.md), [DECISIONS.md](DECISIONS.md), [CLAUDE.md](CLAUDE.md), then this plan's task details. Use [docs/roam-reference-map.md](docs/roam-reference-map.md) for visual comparisons and [docs/local-backend.md](docs/local-backend.md) for local services. `PLAN.md` contains historical background. Its old milestone list and the documentation-era “no build started” headers do not describe current implementation status.

The latest user instruction governs; SPEC is the product contract, DECISIONS supplies effective defaults, and MILESTONES defines acceptance. This handoff assigns execution and records audit findings; it does not remove any acceptance criterion. Preserve milestone order while parallelizing independent tasks inside the current milestone.

| Area | Verified handoff state |
| --- | --- |
| Source checkpoint | `621ec90643c7b9203e5cb7845955b3d2ebcbbf75`; clean working tree before this handoff |
| Named checkpoint | Annotated tag `checkpoint/claude-handoff-2026-10-13` points to that commit |
| Working branch | `codex/sol-max-handoff`; created from the checkpoint; the handoff itself is committed here |
| M1 | Foundation committed as `b7de0d8`; preserve its feasibility evidence |
| M2 | Authentication/schema/access committed as `be0c4e1`; real Apple authorization remains unverified |
| M3 | Implementation `953b313`, decisions/screenshots `621ec90`; explicitly in progress |
| M4–M7 | Some reusable models, protocols and fixture code exist; many real backend methods and routes remain stubs |
| Ranking | `Roam/Ranking/RankingEngine.swift` already implements a substantial pure engine; `Score.swift` supplies exact score math. Existing smoke tests do not establish full M4 correctness |
| Environment | Xcode 26.3, iPhone 17 Pro simulator on iOS 26.2, local Supabase project `roam`; recheck readiness before use |

Historical test evidence is a starting point, not a current pass:

- `build/results/tests-20261013-230214.xcresult`: M3 fixture UI journeys, **4 passed / 1 failed**. Failure: `M3DiscoveryUITests.testListsCategoryOrderFiltersAndUnrankedMemories`, missing `experience-row-Aster House` after applying Kyoto.
- `build/evidence/tests-20261013-225225.log`: **68 tests executed, 14 skipped, 0 failures**. The skipped real-backend cases must not be counted as verified integrations.
- `build/evidence/tests-20261013-225312.log`: **18 real-backend integration tests passed**, including 6 M3 cases.
- Fresh database audit after those runs: **70/71 assertions passed**. M3 assertion 24 expected 4 member-search matches and received 5.
- `screenshots/m3/13–15` were not produced by the failed journey. `16-explore-location-denied.png` and `17-explore-map-lisbon.png` are byte-identical. Investigate the screen state and capture timing; passing element assertions do not establish correct map visuals.
- Build logs/result bundles are ignored local artifacts and may be absent in another checkout. Recreate evidence where necessary.

## Checkpoints and recovery

Claude's current code and screenshots were already committed. The named tag preserves that exact source state; do not move or delete it. `main` was left at `621ec90` when the handoff branch was created. Stay on the continuation branch unless the user chooses another.

Before editing, inspect `git status`, the current branch and recent commits. If another agent/session is actively changing this checkout, establish exclusive ownership before overlapping writes. A lingering Claude process alone does not prove ongoing work; check repository changes and project-specific build activity. Do not terminate unrelated processes.

Only the lead stages and commits. Review `git diff`, `git diff --check`, explicit staged paths and `git diff --cached` before committing. Keep commits coherent and named for the milestone. Intermediate checkpoints are allowed, but label incomplete work accurately. At each verified milestone, commit its code/tests/docs/screenshots and create a fresh `checkpoint/mN-verified-<date>` tag; if that name exists, use a new suffix. Never rewrite earlier checkpoints. Do not push unless asked.

For source recovery, preserve current changes first. Create a new recovery branch from the baseline tag to inspect or rebuild the earlier app:

```sh
git switch -c codex/recover-claude-baseline checkpoint/claude-handoff-2026-10-13
```

Use `git revert <specific-commit>` to undo a reviewed change while retaining history. Do not use blanket hard resets or clean commands. Git checkpoints do **not** restore the local database, Storage objects, ignored configuration or simulator state. Before migrations/cleanup that could remove meaningful local data, preserve a local database and Storage snapshot, record its location and restore procedure outside tracked files, and keep secrets out of output. Apply forward migrations normally. Reset only this project's confirmed disposable fixture database; never reset merely to make a test pass.

## Parallel execution rules

Use the multi-agent tools in the same task, not separate user-owned chats. Maximum four active agents: **lead + three workers**. Reuse idle workers for the next milestone. Do not let workers recursively spawn more agents. If fewer slots are available, reduce concurrency without reducing scope.

Default to the shared checkout with disjoint file ownership. All workers see each other's edits. Each assignment must name exact owned paths, interfaces, acceptance criteria and tests. A worker requests ownership transfer before editing another lane's files. The lead keeps a file-ownership table in `docs/build-status.md`; transfer ownership explicitly and wait for the previous owner to stop writing.

The lead owns these shared files unless it explicitly transfers one for a bounded task:

- `Roam/Services/ServiceProtocols.swift`, shared `Roam/Domain/` models and `Roam/App/` wiring/routing/state.
- `Roam/Backend/Supabase/SupabaseBackend+Pending.swift`, `RPCParams.swift`, `RoamJSON.swift` and shared backend setup.
- Existing shared fixture backend/state/seed files, `project.yml`, package pins, global configuration and test harnesses.
- `ExperienceDetailView.swift` when several features need to add actions; explicitly assign it to one worker when appropriate.
- Requirements/decision/status documentation, Git index, commits and checkpoint tags.

Workers may add feature-specific backend extensions and request removal of the corresponding pending conformance. The lead removes/replaces each stub as part of integration before compiling; never leave duplicate protocol methods. Prefer feature-local request/response types over concurrent edits to shared RPC parameter files. Settle any necessary shared contract changes before parallel implementation starts.

Only the lead runs XcodeGen, builds into the shared `build/DerivedData`, installs/launches/drives the simulator, exports shared screenshots, applies migrations, seeds fixtures, or runs tests against the shared database. A worker can author tests and request a run. Independent static analysis is parallel-safe; independent compiled tests need a separately assigned build directory and no shared simulator/backend state. Do not run two UI suites on the same simulator or overlap fixture-mutating integration tests with pgTAP.

Assign unique monotonically ordered migration filenames centrally. Add corrective migrations after `20261013000600_m3_experiences_lists.sql`; do not edit an already-applied migration and assume the running database changed. One backend worker owns new migration SQL in each wave. The lead applies it and verifies the resulting schema. No worker resets Docker, changes simulator settings, updates dependencies or installs runtimes independently.

Every worker returns: implemented behavior, exact files changed, checks actually run, checks awaiting the lead, known gaps, shared edits requested, and acceptance IDs covered. “Done” from a worker is input to integration, not milestone acceptance. The lead reviews the diff and tests the combined result.

Create and maintain `docs/build-status.md` with milestone status, requirement/screen coverage, active owners, contracts, recent commits, exact test commands/results, evidence paths, external blockers and the next executable action. Update it at integration boundaries and before context compaction or stopping. Include failed/skipped tests and distinguish fixture UI from real-backend evidence.

## First wave Complete M3

First reproduce the known failures with the existing tests. Delegate the following bounded investigations in parallel; the lead coordinates actual test runs.

| Worker | Ownership and work | Acceptance |
| --- | --- | --- |
| A Discovery UI | `RoamUITests/M3DiscoveryUITests.swift`; `Roam/Features/Lists/FilterSheet.swift`; relevant list/Explore view files after explicit assignment | Diagnose the offscreen Kyoto interaction; select a visible/hittable control through its real scroll container and verify selected state before Apply. Preserve assertions for Cancel, Apply, Clear, unranked memories and empty-state recovery. Fix application behavior if the real UI is faulty; do not weaken the test |
| B Member search | New M3 corrective SQL migration; `supabase/tests/02_m3_places_lists_test.sql`; relevant M3 integration tests | Diagnose literal matching and fixture isolation. Verify visibility and stable pagination with enough records to cross a page boundary. Test repeated execution against an already-used fixture database |
| C Acceptance audit | Read-only code/spec/screenshot review, reported to lead | Map every M3 acceptance item to evidence; inspect Search, destination disambiguation, detail, lists, map/list, selected pin and Search this area. Identify missing/error-state coverage and any reachable unfinished route belonging to a later milestone |

Member-search diagnosis already established: the SQL escapes `_` in the handle predicate but leaves it as a wildcard in the display-name predicate; `%` is stripped and backslash behavior also needs review. Query `m3_` matched a persisted integration member with handle `bm3c58b42c` and display name containing that handle. That result explains the extra row. Fix literal user-search semantics consistently for handle and display name, and make test expectations independent of unrelated leftover members. Add a deliberate collision fixture so this cannot regress. Do not merely change expected count from 4 to 5 or delete the leftover account to hide the issue.

The filter screenshot captured after the attempted city tap has disabled Clear all and plain Apply, suggesting no facet was selected. Confirm the cause with the UI hierarchy and actual rendering. Check compact and large-text reachability of controls. Also investigate why the two Explore captures are identical and recapture actual denied/manual-destination/map states.

The lead integrates, runs affected Swift tests, M3 real-backend tests, pgTAP and all five M3 UI journeys, then inspects every new screenshot against the active reference map. Audit the full M3 acceptance list, including retry/race/bookmark/privacy behavior; green existing tests alone are insufficient. Write the M3 evidence summary, commit and checkpoint before M4.

## Second wave M4 Ranking and atomic save

Start with SPEC R05 and the existing `RankingService`, `RatingCommitRequest`, `VisitPayload`, `ComparisonAnswer`, engine and schema. The lead freezes the request/response/error contract: actor from JWT, operation UUID, intent hash, base revision, canonical category, ordered answers, enrichment, acknowledged result and stale-revision recovery. Preserve operation UUID across uncertain retries. Establish shared golden inputs and expected outcomes for Swift and SQL.

| Worker | Owned implementation |
| --- | --- |
| A Backend | New ranking RPC migration and feature-specific Supabase extension; ranking pgTAP and real-backend integration cases |
| B Rating UI | New `Roam/Features/Rating/` flow/model/views; feature-local draft UI; M4 UI/model tests |
| C Ranking engine | `Roam/Ranking/RankingEngine.swift`, `Roam/Domain/Score.swift` by explicit transfer; full engine/property/golden tests replacing the smoke-only evidence |

The lead owns fixture parity, route and LibraryStore invalidation, domain contract changes, and removal/revisit actions in detail unless assigned. Extend the existing engine after reviewing it; do not replace correct behavior just to make a new implementation.

Acceptance must include the specified sentiment → optional details → Okay → comparisons → acknowledged numeric result flow; first-item termination; all seven categories; Too tough, Skip and Undo; rerank excluding the old item; stale revision retaining enrichment; durable account-scoped draft identity; and cancellation without durable writes. M5 completes media/editor behavior, but M4's text/date payload and draft boundary must already support it.

Prove authoritative answer replay, per-category locking, concurrent first-log/category selection, duplicate operation receipts, rejection of changed payload under the same UUID, transaction rollback, atomic Want removal, and cross-category isolation. Verify singleton 8.4/5.0/1.7; two liked groups 10.0/6.7; three 10.0/8.4/6.7; a sole tied liked group 8.4 each; competition ranks 1,1,3. Add visit creates Visit/activity without reordering; rerank creates activity without another Visit. Remove ranking retains populated memories; last-Visit deletion has a distinct confirmation and correct cascades. Commit only after server/client parity and the full M4 journeys pass.

## Third wave M5 Notes media and visit content

Agree on staged/uploaded/attached media states, owned asset references, cleanup retries, and the relationship between the draft, Visit and activity projection before dispatch.

| Worker | Owned implementation |
| --- | --- |
| A Backend | Memory/media RPCs and Supabase adapter; authorization/attachment validation; durable orphan/deleted-media cleanup runner; SQL and integration tests |
| B Editors and gallery | New visit-details/private-note/gallery views and models; M4 editor connection by ownership transfer; M5 UI tests |
| C Persistence and images | `AccountStorage.swift`, `ImageProcessor.swift` by transfer; account-scoped 30-day drafts, asset processing and retry models; focused persistence/image tests |

The lead wires detail/activity content, fixture behavior, invalidation and route handling. Verify public 5,000-character and private 10,000-character note limits; optional date-only values and no future completed visits; six JPEGs maximum, longest side 2,048px and encoded size ≤3 MB; location metadata removal; picker cancellation and partial failure. A failed asset cannot be silently published. Only completed owned uploads attach, staged objects remain private, and unattached objects expire after 24 hours through a runnable server-owned mechanism.

Populate real local media for retention/deletion tests. Verify process restart, sign-out/account switch, explicit discard and expiry. Public content edits update projection without changing publication time; historical posted scores remain labelled. Keep private notes out of activity/detail/share payloads intended for other users. Finish the remaining M5 acceptance checks, UI evidence and checkpoint.

## Fourth wave M6 People feed and notifications

Freeze server cursor structure and `(publishedAt,id)` ordering, viewer relationship state, notification targets and mutation receipts. Assign one backend lane to prevent overlapping authorization changes.

| Worker | Owned implementation |
| --- | --- |
| A Backend | Social/feed/notification RPCs and adapters; shared-wants query; migrations and integration/authorization tests |
| B Feed and activity UI | `Roam/Features/Feed/`, new activity/comment views; ActivityCard by transfer; paging/retry models and corresponding UI tests |
| C People and notifications UI | New followers/following/shared-wants/notification screens and models; associated UI tests |

The lead wires routes, profile actions, relationship/cache invalidation, notification preferences and fixture projections. Use at least owner, follower, unrelated/blocked and anonymous actors. Prove follow uniqueness; following score uses one latest rating per followed eligible member; repeat Visits never inflate it. Mute affects feed only; block removes both follow edges and enforces mutual exclusion at service/storage level; unblock does not restore edges.

Verify stable 30-row pagination with more than one page, equal timestamps, refresh and retries. Do not accept a test named “paginates” that never requests a second page. Comments retain failed text and deduplicate retries; likes use desired state; owner deletions update counts. Shared Want is the exact two-user Experience-ID intersection. Notification generation deduplicates, skips self-events, honors preferences and routes safely after deletion/block. Complete all M6 journeys and checkpoint.

## Fifth wave M7 Profiles travel and account lifecycle

Freeze Visit-derived geography/year aggregation and deletion-job states. Account deactivation must immediately restrict visibility and writes; asynchronous cleanup must be durable, retryable and privileged on the server.

| Worker | Owned implementation |
| --- | --- |
| A Backend and lifecycle | Travel/settings/account RPCs and adapters; relational/media/session cleanup worker and Apple revocation integration boundary; authorization/lifecycle tests |
| B Travel and profile UI | `Roam/Features/Profile/`, `Roam/Features/Globe/`, `Roam/Geography/` by transfer; travel breakdown/year screens and tests |
| C Settings and sharing UI | `Roam/Features/Settings/`, new profile-edit/help/sharing components; settings/deletion confirmation flows and tests |

The lead wires profile/detail shares, account reset/reauthentication, route handling and fixture parity. Counts come from persisted Visits, not home city, bookmarks or ratings alone. Cover duplicate visits, same-name cities, locality destinations, remote/no-city places, missing country polygons, the antimeridian and first-known-visit year changes. Keep globe pins, country shading, clusters and an accessible list equivalent; validate both own and other profiles.

Verify profile edits and settings across relaunch with rollback on failed saves; units and haptics must affect their consumers. Shares contain only allowed public text and real Apple Maps links. Help explains the actual scoring/tie/publication rules. Reports and cleanup have documented local operator commands. Account deletion needs fresh reauthentication, confirmation, immediate restriction and recoverable cleanup; stale tokens cannot recreate data. Test deletion only on disposable local accounts. Real Apple token exchange/revocation requires actual credentials; keep that integration explicitly outstanding if unavailable while completing all other M7 work.

## Sixth wave M8 Final verification and handoff

Parallelize review preparation; serialize execution against shared services:

| Worker | Review responsibility |
| --- | --- |
| A Security and lifecycle | Read-only review of authorization, private-data serialization, idempotency, storage and deletion across combined features; propose concrete reproductions |
| B Journeys and accessibility | Audit all active screens against SPEC/reference map; prepare two-account and failure journeys, compact layout, large Dynamic Type, VoiceOver semantics and Reduce Motion checks |
| C Reproducibility and compatibility | Audit clean-checkout generation/pins/config examples, iOS 18 API availability, Release fixture isolation, deferred-feature exclusions and runbooks |

Assign each finding to one owner for fixes. The lead runs final full Swift/UI/backend/pgTAP verification on the combined commit, with environment and skips recorded. Use a temporary clean checkout with separate build output for reproducibility; local ignored client config must be provisioned through the documented procedure. Do not reset the shared backend merely because the checkout is clean. Check Release configuration separately so Debug fixture success cannot hide a production provider stub.

Walk search → detail → Want → sentiment/details → compare/tie → immediate score → automatic follower feed → comment → revisit/rerank → globe/counts → shared wants → ranking removal retaining actual memories. Exercise all categories and the failure paths in M8: offline drafts, expired sessions, failed/uncertain writes, failed uploads, stale revisions, old search responses, denied location, missing geography/media and deleted/blocked targets.

Use iPhone 16e for compact layouts and accessibility variants, restoring any simulator settings changed during the run. Keep the deployment target at iOS 18; runtime coverage remains iOS 26.2 until the user separately authorizes the deferred compatibility pass. Use real MapKit feasibility checks where required and label fixture captures correctly.

Audit `SupabaseBackend+Pending.swift`, `UnavailableRouteView`, TODOs and every active route. Replace remaining required stubs; legitimate error states may remain. Do not delete a required action to make the audit green. Ensure every MILESTONES acceptance bullet has implementation and evidence or an explicit external blocker. Review images directly; screenshots existing on disk are not proof of a usable screen.

Finish with a reviewed M8 commit, a status ledger, a concise local runbook, and a final report listing completed milestones/screens, exact passing/failing/skipped counts, evidence paths, model/default decisions changed, checkpoint commits, and external/release requirements. Never describe the app as fully verified or production-ready while required checks remain open.

## Build and test procedure

The lead owns these commands. First check `git status`, local processes, Docker health and simulator availability. Use the permission mechanism for sandbox access to Docker/CoreSimulator; a sandbox-denied connection is not proof those services failed. Do not print `supabase status -o env` or secrets-bearing files.

```sh
git status --short
xcodebuild -version
xcodegen --version
xcrun simctl list devices available
docker ps --format '{{.Names}} {{.Status}}'
```

Start only missing project services with `supabase start`; use `./scripts/configure-local.sh` when local configuration is absent. Preserve existing configuration. Apply only reviewed local migrations with `supabase migration up --local`. Use `python3 scripts/fixtures/setup.py` when fixture provisioning is needed, after checking for meaningful local changes. `./scripts/backend-health.sh` checks the project's service endpoints without printing keys.

For focused work, regenerate before building and choose the relevant test selectors. This example runs M3 UI; adjust the selector and evidence name for each milestone:

```sh
set -euo pipefail
ROAM_SIMULATOR_ID=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p build/evidence build/results
./scripts/generate.sh
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/results/m3-ui-$ROAM_RUN_ID.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  test -only-testing:RoamUITests/M3DiscoveryUITests \
  2>&1 | tee "build/evidence/m3-ui-$ROAM_RUN_ID.log" | xcbeautify
./scripts/export-screenshots.sh "build/results/m3-ui-$ROAM_RUN_ID.xcresult" m3
```

Run real-backend tests with `TEST_RUNNER_ROAM_BACKEND_TESTS=1` before `xcodebuild`; the current harness otherwise skips them. Keep normal fixture UI tests distinct from real-backend journey evidence. For final verification, run the database suite before and after the full app test suite to expose cross-suite fixture pollution:

```sh
set -euo pipefail
ROAM_SIMULATOR_ID=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p build/evidence build/results
./scripts/generate.sh
supabase test db --local 2>&1 | tee "build/evidence/final-db-before-$ROAM_RUN_ID.log"
TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild \
  -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "build/results/final-$ROAM_RUN_ID.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test \
  2>&1 | tee "build/evidence/final-$ROAM_RUN_ID.log" | xcbeautify
supabase test db --local 2>&1 | tee "build/evidence/final-db-after-$ROAM_RUN_ID.log"
./scripts/check-secrets.sh
git diff --check
```

A failed pipeline is a failed check; retain its raw log, diagnose it, then rerun the affected checks. Broaden reruns only for new changes, failures, unresolved concerns or the required final suite. Name all result bundles uniquely. Requery the simulator ID if necessary. No generated `.xcodeproj`, DerivedData, logs, secrets or local database volumes belong in commits. Keep `Config/Package.resolved` reproducible and edit `project.yml` rather than `.pbxproj`.

## Completion boundaries

Continue through ordinary implementation choices, failed tests and visual defects. Ask for user input only when a genuine external prerequisite or a change to confirmed scope requires it; complete independent work first. Do not fabricate a provider success, silently drop a feature, or add routine approval gates.

Preserve native Apple sign-in, bundle `com.daniellarkin.roam`, team `H5V24G3F3D`, automatic publication, seven separate category rankings and the real globe. Preserve the existing stack and dependency pins unless a verified problem requires a documented change. No city scores, guides, imports, list sharing, leaderboard, curated/trending discovery or remote push. Reference captures and real reference accounts remain untouched; no iPhone Mirroring or private Beli API use.

External checks remain visible: real Apple sign-in/capability and revocation configuration; separately deferred iOS 18 runtime validation; eventual hosted backend/SMTP, legal/support destinations and operational moderation. They do not block implementation of the remaining local app, and they must not be presented as completed release work.
