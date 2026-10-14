# M3 discovery verification

Continuation from `621ec90` on `codex/sol-max-handoff`, October 13, 2026.
The original checkpoint/tag and reference capture files are unchanged.

## Acceptance coverage

| M3 acceptance | Implementation / evidence |
| --- | --- |
| Query/destination, identity, latest response wins | Search cancels and invalidates before debounce, checks cancellation after enrichment, retains acknowledged state on refresh failure. Four historical race/identity tests plus 14 deterministic search failure/paging tests pass. Real MapKit POI/locality checks pass. Literal member-query migration tests actual 30+30+5 SQL and 30+5 public-RPC pages, cursor replay and visibility. Unidentified localities cannot merge into POIs; client enrichment IDs distinguish the types and canonical same-name localities. |
| Explore manual map/list, categories, selection, viewport, permission recovery | Denied-location Kyoto map and clean Lisbon map have distinct captures. Show on map selects the corresponding native annotation/card; list retains the selected trait. Actual map pan/Search this area replaces results and clears incompatible selection. Real callback bridge tests timeout, authorization timeout, cancellation, concurrent taps and approximate accuracy; model tests failed viewport/retry, older area and cancelled initial load. Native map tests selection close/reopen and cluster-controller zoom. |
| Detail factual/missing metadata | Rated/saved detail captures show available address/website/phone/directions, own/following scores, unavailable score labels and existing memories. Real detail test verifies missing phone and retained unranked Visit. No fabricated stock metadata or deferred dish/reservation module. External utility handoff, expanded media/editing and activity routes receive final journey checks in their owning M5/M7/M8 milestones. |
| Bookmark persistence, retry and no effects | Desired-state unique bookmarks have real fresh-client persistence and no Visit/ranking/geography effect; SQL rejects rated saves and proves privacy. Unit tests cover duplicate taps, ordinary failure/rollback/retry, account reset and late same-account snapshots after Save/Remove. Search/Explore guard the whole resolve+save action against duplicate taps. Add visit/Log flow integration belongs to M4 and is not claimed completed by these tests. |
| Own/other lists, category/unranked semantics | All mode has no combined rank, category scope preserves competition ranks, unranked memories are explicitly filtered. Other Want list has owner fields and viewer bookmark state. List model tests retain acknowledged rows, filters/sort/query/map/reference on failures and prevent old overlapping loads replacing newer rows. Viewer Log and rating actions are M4 integration dependencies. |
| Staged facets/sorts and recovery | Tests preserve Cancel/Apply/Clear, selected-state assertions before Apply, OR within facets/AND across facets, unknown-date ordering, stable ties, text matching and unavailable distance reference. Compact filter journey reaches Kyoto through the true List viewport, verifies both Kyoto rows, clears into populated unranked memories, and recovers filtered empty state. Accessibility-size footer/category controls are adaptive. |

## Execution evidence

All runs use iOS 26.2; the deployment target remains 18.0. Fixture UI and real backend results are distinct.

- Baseline database: **70 passed / 1 failed** of 71 (`m3-baseline-db-20261013-sol.log`), original literal-query collision.
- Baseline UI: **4 passed / 1 failed** of 5 (`m3-ui-baseline-sol-20261013.xcresult`), original Kyoto/Aster House assertion.
- Corrected complete Swift run, real backend enabled: **100 executed, 98 passed, 2 skipped, 0 failed** (`m3-logic-backend-sol-20261013.xcresult`). The two opt-in MapKit skips were subsequently run successfully.
- Focused list/map/provider/repeated-backend run: **16 passed, 0 skipped, 0 failed** (`m3-focused-live-repeat-sol-20261013.xcresult`); includes real MapKit 2/2, M3 backend 8/8 repeated on an already-used database.
- Subsequent compact logic regressions: **12/12 passed** (`m3-compact-final-sol-20261013.xcresult`); final-stage UI in that bundle is **6 passed / 1 failed**, with large-text overscroll retained as a failed check.
- Reviewed forward migrations `20261014000100`–`00300`: literal matching, helper ACL/default hardening, locality identity. Current database suite **124/124 passed** (`m3-db-identity-sol-20261013.log`). No reset or deletion of leftover accounts used to obtain a pass.
- Final affected selector run: **11/11 Swift identity/backend tests + 3/3 compact UI journeys passed, 0 skipped, 0 failed**, `m3-final-fixes-sol-20261013.xcresult`; post-integration pgTAP **124/124**, `m3-db-final-sol-20261013.log`. All seven M3 UI journeys have passing compact evidence, with affected selectors rerun after their fixes. Earlier failed bundles remain listed above.

Raw logs are in `build/evidence/`, result bundles in `build/results/`; both are intentionally ignored. Screenshot evidence is tracked in `screenshots/m3/`. Generate with `./scripts/generate.sh`; use the exact selectors/commands in `docs/build-status.md` to reproduce each run. Real backend flag: `TEST_RUNNER_ROAM_BACKEND_TESTS=1`; live MapKit flag: `TEST_RUNNER_ROAM_LIVE_MAPKIT=1`.

## Visual review and boundaries

Lead directly inspected all compact captures through three review sheets. Search/detail/list hierarchy, visible selected Kyoto, category rank, populated unranked memories, distinct denied/manual states, selected card/list and viewport clearing match the active S03–S06/S12/S13 reference hierarchy using original Roam styling. Screenshots 13–15 now exist. Available addresses were added to distinguish the two Morning Tide Bakery businesses; updated selection/list captures 22–23 were exported and directly reviewed. Screenshot 21 now shows Kyoto's selected checkbox fully visible between the toolbar and footer.

MapKit may aspect-fit the requested manual region and offer Search this area immediately; screenshot 17 proves manual browsing, not a user pan. Screenshots 24–25 and the gesture journey establish panning/replacement. Native controller cluster zoom is tested; this is distinct from a manually tapped cluster capture. Keyboard-present empty states are scrollable, with the destination control still reachable; M8 performs the broader keyboard/accessibility walkthrough.

Log/Add visit/comparison, media editors/gallery, activity/comments, feed/social, travel/lifecycle and sharing routes still belong to M4–M7. These discovery checks do not claim those features complete. Real Apple authorization/revocation and separately deferred iOS 18 runtime validation remain external checks.
