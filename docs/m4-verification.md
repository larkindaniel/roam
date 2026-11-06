# M4 ranking verification

Status: local M4 acceptance verified, October 14, 2026. M3 is preserved at `f081e2e` and `checkpoint/m3-verified-2026-10-13`. App-wide acceptance continues through M5–M8.

## Implementation boundary

The rating flow uses sentiment, optional details, Okay, comparisons and an acknowledged result. Each category is independent. Durable account-scoped drafts retain exact uncertain operation UUIDs and payloads. A definitive stale revision keeps enrichment and asks for fresh comparisons. Category changes while a draft is closed refresh non-pending comparisons; immutable pending requests still resolve their original receipt.

The server derives the actor from JWT, validates strict request keys, locks the experience and category revision, replays comparisons, computes scores and commits Rating/Visit/activity/Want removal atomically. Repeated successful operations return the original receipt before current revision/state validation. Changed intent under an acknowledged UUID conflicts. Add visit retains order; rerank retains Rating identity and an existing Visit anchor. Removing ranking retains populated memories; deleting the last Visit requires explicit consent verified against locked current state.

Common JSON and local storage preserve server microseconds so the oldest tied member remains the representative after decoding and draft restoration. In-flight RPC transport snapshots its JWT to prevent account switching from transferring an original intent to a different actor.

## Acceptance evidence

| Requirement | Evidence / status |
| --- | --- |
| Engine bounds, termination, all categories, Undo/Skip/ties, exact half-up scoring | 18/18 engine cases; exhaustive insertion slots through1024 groups; shared scoring/replay/rejection goldens pass |
| Client/server golden parity | 29 shared SQL goldens plus Swift goldens and public-RPC score/tie/rerank assertions pass |
| Authoritative replay, category locking, duplicate/changed receipts, category isolation, canonical races | 130/130 M4 pgTAP and11/11 M4 real backend cases pass |
| Post-write transaction rollback and atomic Want removal | Injected late activity-insert failure leaves no partial rows/revision/receipt and retains Want; public concurrent Bookmark/log case passes |
| Draft restart, account boundary, stale revision, cancellation, category change | Model18/18, fixture8/8, transport1/1, precision2/2, projection8/8 pass |
| First/tied/subsequent/rerank/revisit/removal and last-Visit confirmation | All eight fixture UI journeys have passing compact evidence across full+affected reruns;24 captures directly reviewed |
| Actual uploaded JPEG retention | Actual local Storage JPEG/upload/attachment/rerank/retention assertions pass in public integration; cleanup runner remains M5 |

## Executed checks and failures retained

- Initial build-for-testing passed: `build/evidence/m4-compile-first-sol-20261014.log`. Subsequent source fixes require another build.
- Applied004, then corrective005 locally without reset. Logs: `build/evidence/m4-migration-sol-20261013.log`, `build/evidence/m4-runtime-migration-sol-20261014.log`.
- First database run aborted after31 M4 assertions because the authored test FOREACH lacked ARRAY. Second aborted because `commit_rating` qualified local variables with an unavailable function label. Both raw logs retained as `m4-db-first-sol-20261014.log` and `m4-db-corrected-sol-20261014.log`.
- Runtime correction executed all130 M4 assertions; two tie expectations incorrectly combined independent Outdoors and Food & Drink rankings. Queries now constrain the intended category without deleting fixtures or changing exact expectations. Failed log: `m4-db-runtime-sol-20261014.log`.
- Corrected database: **254/254 passed**, including130 M4 assertions; `build/evidence/m4-db-final-sol-20261014.log`.
- Combined command: `TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug -destination 'platform=iOS Simulator,id=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C' -derivedDataPath build/DerivedData -resultBundlePath build/results/m4-logic-backend-sol-20261014.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test -only-testing:RoamTests`, with pipefail/tee/xcbeautify. **177 executed,175 passed,2 skipped,0 failed**. The two opt-in live MapKit tests were not enabled; both passed separately in M3. M4 HTTP11+account-scope1 all pass.
- Database after these integrations: **254/254**, `build/evidence/m4-db-after-integration-sol-20261014.log`; no reset/purge used.
- Compact full UI command uses iPhone16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` and `-only-testing:RoamUITests/M4RatingUITests`: **6 passed,2 failed**, `build/results/m4-ui-compact-sol-20261014.xcresult`/matching raw log. Date switch center tap hit the broad accessibility frame instead of its visible control; the strengthened test taps the visible switch and checks its value and exact Cancel/Done state. Search-row Log retained the keyboard and obscured Okay; the application now explicitly clears Search focus without clearing the query.
- Affected rerun selectors `testOptionalEditorsCancelDoneUndoAndSkip` and `testResultCloseReturnsToUpdatedSearchAndLastVisitRequiresDistinctConfirmation`: **2/2 passed**, `build/results/m4-ui-recovery-sol-20261014.xcresult`/matching raw log. All eight journeys have passing compact evidence. Final M8 will execute combined final source.

## Visual review

Lead personally inspected all24 `screenshots/m4/` captures in five review sheets, plus both failed screen recordings. Compared active reference `nc031`, `nc032`, `nc040`: category/sentiment precedes optional details/Okay and two name/city comparison cards; green/amber/red always have text/icons; native compact/large-text layout keeps controls reachable by scrolling. Roam supplies immediate numeric results and publication disclosure under SPEC; excluded companions/labels/dishes/stealth remain absent. Captures20–22 prove the invoking query remains, keyboard is dismissed, current score updates, last-Visit consent explains cascading ranking deletion, and the acknowledged deletion removes the memory. No blocking layout defect found. Reference captures were not edited.

## Remaining milestone boundary

M5 completes picker/upload/gallery, public retained-memory projection, private editors and runnable storage cleanup; it also repairs image-cache/account-expiry handling and inspects actual server-side JPEG bytes. M6 completes activity/comment/feed/social surfaces. M7 completes profile/travel/settings/account lifecycle. These routes remain explicit dependencies, not completed M4 acceptance. Real Apple authorization/revocation and iOS18 runtime validation are outstanding external checks.
