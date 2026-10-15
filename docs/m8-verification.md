# M8 complete journeys, compatibility and build handoff verification

Status: local M8 acceptance verified, October 14, 2026. M7 is preserved at `ea47646` and `checkpoint/m7-verified-2026-10-14`. This file is also the final build handoff. Real Sign in with Apple and an iOS 18 runtime/device pass remain outstanding external checks (see the end).

## What M8 added

- **End-to-end journeys.** In the fixture app, two members start from empty lists and no follows (`M8JourneyUITests`):
  - search → detail → Want → sentiment and details → compare and tie → immediate score;
  - automatic follower feed → comment → notifications;
  - repeat visit → Rank again → travel counts and New this year → Shared Want to Go;
  - ranking removal with the memory and travel kept.

  A second journey ranks one place in each of the seven categories in one session and checks Been and Travel Profile. `M8JourneyIntegrationTests` runs the same two-member chain through the real local backend.
- **Accessibility.**
  - Xcode's automated audit runs on 21 screens (`M8AccessibilityAuditTests`). Its findings were fixed rather than waived:
    - a darker secondary text color (about 6.3:1 on white, versus 3.5:1 for the system gray);
    - darker light-mode sentiment colors (at least 5.4:1 on their fills);
    - theme-red in-page destructive buttons (system red is 3.6:1);
    - a wordmark and avatar initials that scale with Dynamic Type;
    - wrapping destination chips, feed area lines and short notes;
    - a stacking S19 header and a fixed-size map/list toggle.
  - Reduce Motion: `M8MotionUITests` reads the setting the app received, and the only app-defined motion (skeleton pulse and map camera moves) is gated on it.
  - Layout stress (`stress` fixture, `M8LayoutStressUITests`): a 49-character name, a 104-character place and a 13-place tie group.
- **Hygiene.**
  - Removed the unused `AppRoute.findPeople` and the "Not available" route fallback, so every route has a screen.
  - Added `README.md` (quick start) and marked `SOL_MAX_HANDOFF.md` as superseded history.

## Acceptance evidence

| M8 requirement | Evidence / status |
| --- | --- |
| Two accounts walk the whole product, all seven categories, empty and no-follow conditions | UI `testTwoMembersFromEmptyListsThroughFeedCommentRevisitTravelSharedWantsAndRetainedMemory` (`m8-01`–`m8-08`), `testAllSevenCategoriesRankIndependentlyInOneSession` (`m8-09`, `m8-10`); real backend `testTwoMembersWalkTheWholeJourneyAgainstTheRealBackend`; M4 integration `testFirstLogsAcrossAllSevenCategoriesAreAtomicAndIdempotent` |
| Offline draft, expired session, failed save/upload, stale revision, slow old search, denied location, missing geography/media, deleted/blocked targets; nothing fabricates success | See the failure-condition matrix below (existing tests from M2–M7, all in the final run) |
| Unit, engine/server parity, pgTAP/RLS, integration and UI tests pass; logs, `.xcresult`, screenshots and a visual comparison | Final runs below; `screenshots/m1`–`screenshots/m8`; per-milestone visual reviews in `docs/m3-verification.md`–`docs/m8-verification.md` |
| Builds with the iOS 18 deployment target; tested on iOS 26.2; iOS 18 recorded as outstanding | `IPHONEOS_DEPLOYMENT_TARGET = 18.0` (project.yml). Runs on iOS 26.2 (iPhone 17 Pro, iPhone 16e) plus a Release and a device-SDK build below. **No iOS 18 runtime or device run: outstanding (deferred by the user)** |
| Dynamic Type, VoiceOver, Reduce Motion, small screen, long names, large ties, clustered pins, map alternatives, fictional data | Audit (21 screens), large-text journeys M3–M8, `M8MotionUITests` with Reduce Motion on (16e), compact 16e runs, `M8LayoutStressUITests`, flat-map clusters (`m7-07`), List alternatives for every map; fixtures are fictional (see Hygiene) |
| Real Apple sign-in separate from fixture auth; startup/reset instructions; clean checkout; versions; no secrets, generated project, stale requirements or deferred routes | Apple: **outstanding** (needs credentials and a device). `README.md` + `docs/local-backend.md`; clean-checkout build below; versions below; `scripts/check-secrets.sh`; `.gitignore` excludes `*.xcodeproj`; deferred features have no routes (`M1NavigationUITests.testDeferredFeaturesHaveNoEntryPoints`) |
| Final report | This file and `docs/build-status.md` |

## Failure-condition matrix (all tests in the final run)

| Condition | Tests |
| --- | --- |
| Offline draft | `M4RatingFlowTests.testRankingLoadFailureKeepsDetailsAndRetriesBeforeAnyCommit`, `testUncertainSaveSurvivesRestartAndRetriesExactOperationAndPayload`; `M3ListRefreshTests` (offline refresh keeps rows); `M5PhotoDraftTests` interrupted-upload restore; UI `testInterruptedMemoryEditSurvivesRelaunchUntilDiscarded`, `testEditProfileValidatesKeepsAnInterruptedDraftAndSaves` |
| Expired session | `M5SessionCacheTests.testExpiredSessionKeepsTheOwnersDraftsAndSignOutRemovesThem`, `testRouteIntentSurvivesExpiryOnlyForTheSameAccount`; `M4RatingFlowTests.testAccountChangeCannotSubmitOrReuseAnotherAccountsDraft`; `SessionStoreTests.testSignOutClearsAccountScopedData`; `AppInfrastructureTests.testAccountsAreIsolatedAndClearedIndependently` |
| Failed save/upload | `testFailedUploadBlocksSaveUntilRetryReusesTheSameAttempt`, `testFailedCommentKeepsTextAndRetriesTheSameOperation`, `testAFailedSaveRestoresThePreviousValueAndRetrySendsTheSameChange`, `testValidationBlocksSaveAndALostHandleKeepsEveryField`, `testAFailedRequestSaysTheAccountWasNotDeleted`; UI `testSystemPickerUploadFailureRetryRemovalAndPublishedPhoto`, `testCommentFailureKeepsTextAndRetryPostsOnce`, `testSettingsRollBackAFailedSaveAndApplyUnitsAfterAcknowledgement` |
| Stale ranking revision | `testStaleRevisionKeepsEnrichmentAndRequiresFreshComparisons`; integration `testConcurrentCategoryRevisionRejectsStaleWithoutPartialWrites`; pgTAP 03 |
| Slow old search response | `testSlowOlderResponseNeverOverwritesNewerResults`, `testChangedQueryInvalidatesOldResponseBeforeDebouncedRequestStarts`, `testNewDestinationWinsWhenOldProviderIgnoresCancellation` |
| Denied location | UI `testCurrentLocationDenialKeepsManualSearch`, `testExploreWorksWithLocationDeniedAndTogglesMapList`, `testExpandedGlobeShadesVisitedCountriesWithAnEquivalentList` (globe with location denied) |
| Missing geography/media | `testMissingSmallCountryGeometryReturnsNoShading`, `M7TravelProfileTests` (place without a city, Singapore without geometry); UI `testGalleryLoadingThenFailureOffersRetry` |
| Deleted/blocked targets | `testUnavailablePostShowsNoCachedText`, `testUnavailablePostLeavesTheFeedWhenLiking`, `testBlockIsMutualServerSideAndUnblockDoesNotRestoreFollows`; pgTAP 05/06 (blocked and deleted members everywhere); UI `testBlockRemovesTheMemberFromFeedAndSearch`, `testDeleteAccountNeedsReauthenticationAndSignsOut` |

## Executed checks and failures retained

- First M8 compile: clean, with no project warnings (`m8-compile-claude-20261014-200730.log`).
- First M8 run on the iPhone 17 Pro (`m8-first-claude-20261014-200749`):
  - The real-backend journey, the Reduce Motion (off) check and the long-names test passed first time.
  - Two journeys failed on test navigation: a profile was still pushed on the Search tab, and list rows sat under the translucent header.
  - All seven audit tests failed.

  The first audit pass found **19 contrast failures, 35 near-passes, 6 clipped texts and 27 Dynamic Type findings**. That led to the darker secondary text and sentiment colors, theme-red destructive buttons, a scaling wordmark and avatar initials, wrapping chips, area lines and short notes, and a stacking S19 header (see DECISIONS).
- Second run (`m8-claude-20261014-201830`): the two-member journey passed; the tie test needed to tap the row's combined button.
  - Third run (`m8-claude-20261014-203204`): the tie test passed. The seven-category check showed that the scroll helper only searched one direction, so recycled rows never reappeared.
  - Fourth run (`m8-claude-20261014-204347`): **all seven audits passed** with the documented exceptions, and a fit-to-size toggle and result score fixed the last clipping candidates. The seven-category check moved to the list's own search; a mid-text cursor then left fragments behind (cleared with the field's clear button), and the keyboard covered the tab bar. It passed in `m8-seven-claude-20261014-205654`.
- iPhone 16e with **Reduce Motion on**:
  - The first attempt executed 0 tests: a stale test runner left on the simulator had no M8 classes (`m8-compact-reducemotion-claude-20261014-210024`). It was uninstalled.
  - The rerun passed **11/12** (`m8-compact-reducemotion-claude-20261014-210128`), including the motion check ("Reduce Motion: on") and both journeys. The feed audit flagged the area line squeezed to a 51 pt column on the narrower screen. The category line now fits on one line or stacks.
  - The feed checks then passed **4/4** with Reduce Motion still on (`m8-compact-reducemotion-feed-claude-20261014-211114`). Reduce Motion was switched back off afterwards.
- Review of the 16e captures found "1 categories" (and "1 cities", "1 countries") in Travel Profile, plus "1 places"/"1 countries" in map and globe VoiceOver labels. All are now pluralized.
- **Final full regression on the iPhone 17 Pro** (`m8-final-full-claude-20261014-211218`):
  - RoamTests: **263 executed, 261 passed, 2 opt-in MapKit skips, 0 failed**. This includes the real-backend journey and every M2–M8 integration suite.
  - RoamUITests: **66/66 passed** (all M1–M8 journeys, 2,106 s).
- **Final database run: 538/538** (`m8-db-final-claude-20261014-211327.log`). **Workers:** cleanup 4/4 and deletion 4/4 unit tests; both live tests deleted real local objects and a disposable account (`m8-workers-final-claude-20261014-211329.log`).
- **Affected checks after the last label fixes** (`m8-affected-claude-20261014-214833`): **14/15 passed**:
  - both M8 journeys, five M7 travel/globe journeys, the Shared Want to Go journey, and 6 of 7 audits.
  - The Explore audit stopped with "Audit failed to complete in time", a tooling timeout on the live map with no findings. It passed when rerun alone (`m8-explore-audit-claude-20261014-220053`).
- **Compact iPhone 16e on the final code with Reduce Motion on** (`m8-compact-final-claude-20261014-220136`): **5/5** (both journeys, both stress tests, and the motion check reporting "on"). Reduce Motion was switched back off afterwards.
- **Final audit state** (all 21 screens, `docs/evidence/m8-accessibility-audit/`): **0 failing findings**. Recorded under documented exceptions:
  - 43 advisory "partially supported" Dynamic Type and 8 advisory "nearly passed" contrast;
  - 8 contrast samples in scroll-edge zones;
  - 3 disabled controls, 3 system-keyboard items, 2 single-line fields, 1 system navigation title and 1 MapKit cluster glyph;
  - **19 findings with no element reference** (18 contrast, 1 Dynamic Type). These are text inside rows combined into one VoiceOver element (Been 6, globe list 4, settings 4, Want 2, edit profile 2, notifications 1). The audit can't say which text it measured. Every text color used in those rows measures 5.25:1 or more (most 6:1 or higher), so they are reported here as an open follow-up, not as a pass.

## Compatibility, reproducibility and hygiene

- **Deployment target:** iOS 18.0 (`project.yml`; Info.plist `MinimumOSVersion` 18.0).
- **Release build for the simulator:** succeeds with no project warnings (`m8-release-build-claude-20261014-220926.log`).
  - The Release binary has **no fixture code** (0 `FixtureBackend`/`ComponentCatalog` symbols, 0 fixture launch-argument strings) and **no local-network ATS exception**.
  - No `sb_secret_` key or the local service-role key is present. The only `sb_secret_` text is a bare 10-character prefix constant inside the Supabase SDK.
- **Unsigned device build:** `generic/platform=iOS`, Release, arm64, succeeds (`m8-device-build-claude-20261014-221038.log`). It wasn't signed and didn't run on a device.
- **Runtimes:** everything ran on the iOS 26.2 simulator, on the iPhone 17 Pro and the compact iPhone 16e. **There was no iOS 18 runtime or device run.** You deferred it, and it stays outstanding.
- **Tool and library versions:**
  - Tools: Xcode 26.3 (17C529), Swift 6.2.4, XcodeGen 2.46.0, Supabase CLI 2.120.0 (2.121.0 is available; not installed, by rule), Docker 29.7.2, Python 3.9.6.
  - Local stack: Postgres 17.11 (`supabase/postgres:17.11.0.004`), GoTrue v2.197.0, PostgREST v16.4, Storage v1.79.36, Edge Runtime v1.77.4 (`npm:jpeg-js@0.4.4` in `prepare-media`), Mailpit v1.31.3.
  - SwiftPM (`Config/Package.resolved`): supabase-swift 2.55.3, swift-crypto 4.5.2, swift-asn1 1.7.3, swift-http-types 1.8.0, swift-clocks 1.1.1, swift-concurrency-extras 1.4.2, xctest-dynamic-overlay 1.13.1. Country geometry: Natural Earth 1:110m v5.1.2 (public domain).
- **Clean checkout** of commit `b6db774` into scratch space (`build/evidence/m8-clean-checkout-claude-20261014-221319.log`):
  - The clone has no generated project. `./scripts/generate.sh` created it from `project.yml`, and `./scripts/configure-local.sh` wrote only the public URL and publishable key.
  - Packages resolved at the pinned versions (supabase-swift 2.55.3).
  - It built with no project warnings. RoamTests in fixture mode: **263 executed, 209 passed, 54 skipped, 0 failed**. The 54 skips are the 52 real-backend integration tests, which need `TEST_RUNNER_ROAM_BACKEND_TESTS=1` and ran in the main checkout, plus 2 opt-in MapKit tests.
  - The clone, with its ignored server environment, was deleted afterwards.
- **Hygiene:**
  - `scripts/check-secrets.sh` passes (tracked files and the built Debug app).
  - `.gitignore` excludes the generated `*.xcodeproj`, DerivedData, `.xcresult`, `Config/Local.xcconfig`, `scripts/.fixture-env` and `.env` files; the only tracked config is the keyless `Config/Local.xcconfig.example`.
  - No deferred-feature routes exist (the M1 journey checks Guides, Leaderboard, Import, Trending, Challenges and City score), and the route switch is exhaustive.
  - Shipped assets are the original app icon, colors and Natural Earth geometry. All fixture people, places and photos are fictional; photo fixtures are generated colors.

## Visual review

The M8 captures were opened and checked against S01–S03, S06, S09–S12, S18, S19, S22, S23, S25 and S28 in `docs/roam-reference-map.md`. They are in `screenshots/m8/` (iPhone 17 Pro, final full run plus the affected rerun) and `screenshots/m8/iphone-16e/` (final code, Reduce Motion on).

- **Journey (`01`–`08`):**
  - the quiet feed with Find people for a member with no follows;
  - the immediate 8.4 first score, then a Too tough tie: "Position 1 of 2 … Tied with 1 other experience";
  - the follower's view of the automatic post with the new comment, and Shared Want to Go with exactly the one shared place;
  - Maya's two unread notifications;
  - travel counts after a repeat visit and Rank again ("1 country · 1 city", New this year 2, "1 category");
  - the ranking removed with "Unranked memory", both visits and the note kept.
- **Seven categories (`09`, `10`):** every place first in its own category at 8.4, and seven one-place category rows (6 countries · 7 cities).
- **Stress (`11`–`15`):**
  - the 49-character name and 104-character place wrap while the score stays top-right and the actions stay reachable;
  - the system navigation title truncates the name, which is shown in full on the page;
  - the 13-place tie shows "1." on every row at 10.0 and "#1 of 16 … Tied with 12 others" on detail.
- **Reduce Motion (`iphone-16e/16`):** the debug catalogue shows "Reduce Motion: on" with the darker sentiment colors.

Problems found and fixed during this review:

- On the 16e, the post's area line was squeezed into a 51 pt column beside the category. It now stacks (`iphone-16e/04`).
- "1 categories" (and the same in VoiceOver map and globe labels) is now pluralized (`07`).

In the 16e captures, visit dates read Oct 15 because each date is "today" in the place's own time zone (D15; the run was in the evening of Oct 14 in North America). No Beli branding or real identities appear anywhere.

## Final handoff

### Milestones

| Milestone | Status | Commit / tag | Evidence |
| --- | --- | --- | --- |
| M1 Project, design system, local services, MapKit feasibility | Verified (iOS 18 runtime deferred) | `b7de0d8` | `docs/m1-feasibility.md`, `screenshots/m1` |
| M2 Schema, authentication, profiles, authorization | Verified locally; **real Apple sign-in outstanding** | `be0c4e1` | `docs/auth-and-access.md`, `screenshots/m2` |
| M3 Discovery, search, lists | Verified | `f081e2e`, `checkpoint/m3-verified-2026-10-13` | `docs/m3-verification.md` |
| M4 Ranking engine, atomic saves, drafts | Verified | `97da54e`, `checkpoint/m4-verified-2026-10-14` | `docs/m4-verification.md` |
| M5 Memories, photos, private notes | Verified | `966a0d9`, `checkpoint/m5-verified-2026-10-14` | `docs/m5-verification.md` |
| M6 Feed, posts, comments, follows, notifications | Verified | `a1094ab`, `checkpoint/m6-verified-2026-10-14` | `docs/m6-verification.md` |
| M7 Travel profile, globe, settings, sharing, account deletion | Verified; **Apple revocation outstanding** | `ea47646`, `checkpoint/m7-verified-2026-10-14` | `docs/m7-verification.md` |
| M8 Journeys, compatibility, handoff | Verified locally; **iOS 18 and Apple outstanding** | `b6db774` plus this evidence commit, `checkpoint/m8-verified-2026-10-14` | this file |

### Commands

See `README.md` (quick start) and `docs/local-backend.md` (runbook, fixtures, workers, operator queries). The final evidence was produced with:

```sh
supabase start && ./scripts/configure-local.sh && ./scripts/backend-health.sh
./scripts/generate.sh
supabase test db --local
TEST_RUNNER_ROAM_BACKEND_TESTS=1 xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=3C864AD4-9C80-44BF-8B1C-EB57732C2C9C" -derivedDataPath build/DerivedData \
  -resultBundlePath build/results/<run>.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
python3 -I scripts/tests/test_media_cleanup.py && python3 -I scripts/tests/test_account_deletion.py
ROAM_LIVE_CLEANUP=1 python3 -I scripts/tests/test_media_cleanup.py LiveCleanupTest
ROAM_LIVE_DELETION=1 python3 -I scripts/tests/test_account_deletion.py LiveAccountDeletionTest
```

### Defaults and decisions changed during the build

No confirmed product decision or default was changed. Every small judgment is logged in the `DECISIONS.md` table (M3–M8 rows). The ones a reviewer is most likely to notice:

- Globe pins are overlay dots on the 3D globe; selection is on the flat map and in the list.
- Account deletion requires an `amr` sign-in within 10 minutes; Apple revocation is recorded as `not_configured` locally.
- Settings are server-acknowledged desired state with rollback.
- Secondary text is darker than the system gray (accessibility).

### Still blocked and needs you

1. **Sign in with Apple:** the real capability, provider and token exchange, reauthentication before deletion, and token revocation on deletion. These need your Apple Developer credentials (team `H5V24G3F3D`), the Supabase Apple provider secret and a device. The local Apple paths fail closed and are never reported as passed.
2. **iOS 18 runtime or device validation:** deferred by you. Everything ran on iOS 26.2 simulators; the deployment target stays 18.0.
3. **Release setup, not v1 product work:**
   - hosted Supabase and SMTP;
   - scheduled cleanup and deletion workers (with the hosted service key in a secret store);
   - public privacy, terms and support destinations;
   - a moderation owner for reports.
