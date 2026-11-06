# Roam v1 — eight build milestones

**Ready for the separate build run; no build performed by this documentation update.** [SPEC.md](SPEC.md) is the binding product contract; [DECISIONS.md](DECISIONS.md) records confirmed choices and effective defaults; [CLAUDE.md](CLAUDE.md) defines build/test/simulator commands. The former M0–M12 plan is superseded.

Work in order. Keep every milestone buildable, run meaningful logic/service tests and simulator walkthroughs, repair failures, save evidence under `screenshots/mN/` and `build/evidence/`, and commit only task-owned files. No routine approval stop between milestones. A missing credential/device can block the corresponding integration check without blocking unrelated work; report it and never label that integration passed. Capture evidence is read-only.

## M1 — Project, design system, local services and MapKit feasibility

Scope: R00/R01 foundation, confirmed stack; empty S02/S03/S05/S12/S18 roots. Depends on nothing beyond the build-run instruction.

Acceptance:

- `project.yml` generates `Roam.xcodeproj`, shared `Roam` scheme, `Roam`, `RoamTests`, `RoamUITests` targets; iOS deployment target 18.0, bundle `com.daniellarkin.roam`, team `H5V24G3F3D`. No hand-edited generated project.
- SwiftUI navigation has Feed, Your Lists, Search, Explore, Profile with independent stacks. Test back/modal routing and state restoration inside a tab. Deferred guide/city-insight/import/leaderboard routes are absent.
- Feature service protocols, fixture injection and account-scoped configuration exist. Pin and record SPM dependencies. Client contains no privileged Supabase/Apple secret; ignored local config and checked-in example are clearly separate.
- Local Docker/Supabase project `roam` starts, applies migration scaffolding and exposes a health/status check. Seed/reset scripts target this local project only. No remote deployment or database reset occurs.
- Resolve a real MapKit POI and a locality; document ID availability, fallback dedup, fields/storage/attribution constraints and category resolution. Fictional UI fixtures cannot enter production provider results.
- Demonstrate zoomed-out globe, pins and visited-country polygon shading with licensed sample geometry on the installed simulator. Test antimeridian geometry and pin selection. Use an MKMapView wrapper if needed; report a true renderer limitation rather than silently substituting a flat illustration.
- Rows/cards/score badges/sheets/empty/skeleton/retry states support Dynamic Type and accessible labels; image/map missing-data fallbacks are usable.

Evidence: generated-project build log, service start/health result, navigation and globe screenshots, feasibility note listing tested runtime and geometry source. Do not call iOS 18 runtime behavior verified merely because deployment target is 18.

## M2 — Schema, authentication, public profiles and authorization

Scope: R02, data model/RLS, S01 and account foundations in S26. Depends on M1.

Acceptance:

- Migrations implement v1 entities/constraints and access rules without deferred-feature tables. Local seed creates at least three fictional accounts, seven categories, public and private memories and graph relationships through a reproducible test-only setup.
- Email sign-up/verification/sign-in/recovery/cancel/error and session restore work against local Supabase. Recovery callback targets the app and expires safely. Handle uniqueness/validation survives races; a duplicate does not lose entered profile data.
- Native Sign in with Apple uses nonce validation and Supabase token exchange; cancellation and missing first-login name handled. Verify a real supported account/provider configuration, or record exact external blocker while completing fixture tests. Never remove the method or report a mock as a successful Apple login.
- Progressive name/handle/optional avatar/home city setup resumes after interruption, permits skips, introduces public visibility and lands in Your Lists with one-time Log education. No implicit follows or permission-pressure flow. Home city does not count as visited.
- Database/API tests prove another signed-in unblocked member can read public profile data but not auth contacts, settings, drafts or PrivateNote; anonymous read and foreign writes fail. Storage ownership and attachment validation are enforced server-side.
- Tokens use secure storage; sign-out/expired session cannot submit pending writes as another user. Service-role/private keys absent from built client and tracked files.

Evidence: auth UI walkthrough, real-vs-fixture provider status, migration/pgTAP and unrelated-account authorization results. Record external SMTP/provider configuration requirements for release separately from local test results.

## M3 — Search, experience detail, Explore and Want to Go

Scope: R03/R04/R06, S03–S07/S12/S13 baseline. Depends on M2.

Acceptance:

- Search by query/destination resolves one-place experiences, disambiguates localities, cancels stale queries and prevents a slow old response overwriting new results. MapKit identifier/fallback dedup behaves according to SPEC, including same-name distinct businesses.
- Explore/manual-city map/list, category filters, selected pin/card, clusters, Search this area and known-place maps work without location permission. Current-location denial/timeout/approximate results keep manual browsing available.
- Detail displays factual available metadata with missing/closed/unavailable states; website/phone/Maps utilities work where applicable. Score/media placeholders say unavailable, never invented data. No dish/reservation/hours-edit module.
- Save/unsave from search/detail/list uses one persisted Bookmark with retry-safe desired state; no visit/activity/pin/count effect. Duplicate taps and relaunch preserve correctness. Already-rated records show Add visit rather than creating a Want bookmark.
- Been/Want and public other-member lists distinguish own editing from viewer Save/Log. All mode has category badges and no combined ordinal; single-category order and memories-without-rating filter have test fixtures.
- Staged filters Apply/Cancel/Clear obey specified OR/AND logic; stable sorts and no-results recovery work. Missing distance sorts last; list/detail/back preserves context. Empty states have no deferred import/guide/share CTA.

Evidence: search-race and place-identity tests, bookmark persistence/privacy checks, permission-denied and map/list simulator captures.

## M4 — Ranking engine and complete rating transaction

Scope: R05, S08–S11/S10/S12 ranking; M3 details may use text-only visits until M5 media. Depends on M3.

Acceptance:

- Flow matches captured category/sentiment → optional details → Okay → comparison ordering. First item/empty sentiment partition terminates without a comparison. Cards retain place/category/sentiment, Undo/Too tough/Skip with accessible fallbacks; no manual score, ten-item lock, separate confirmation or publish step.
- Implement `roam-category-v1` exactly: three sentiment partitions, binary insertion over groups, Too tough joins group, Skip inserts at remaining midpoint without tie, Undo restores draft history. Test bounds/termination for empty, 1, 2, 3 and large groups and all seven categories.
- Golden fixtures: one liked/fine/disliked = 8.4/5.0/1.7; two distinct liked = 10.0/6.7; three = 10.0/8.4/6.7; two tied liked alone = 8.4 each. Competition ranks 1,1,3; deterministic Decimal half-up rounding and equal tie scores. Ranking Outdoors cannot change Food & Drink scores.
- Authoritative RPC locks category revision and replays valid intent; client cannot forge score/actor/order. First log atomically creates Visit/Rating/activity and removes Want. Retry/duplicate timeout returns same mutation receipt. Simulated failure commits none of these effects.
- Stale revision retains details but requests refreshed comparisons. Close before commit preserves/discards only local draft. Score result appears only after acknowledgement, shows correct rank/score from first rating, and returns to the invoking context.
- Add visit creates one Visit/activity under existing Rating without changing order. Rank again changes current Rating and creates rerank activity without a duplicate Visit. Canonical category remains locked after first ranking.
- Remove ranking reflows only its category, removes rating-linked activity and retains memories/Visits/private notes; no bookmark restoration. Delete last Visit removes Rating only after an explicit explanatory confirmation. Failure/cancel leaves prior durable state.

Evidence: Swift engine and server golden-fixture parity, property/concurrency/idempotency tests, first/tied/subsequent/rerank/revisit/removal simulator journey. Activity records are already created atomically here even though feed UI arrives in M6.

## M5 — Notes, photos, visit history and activity content

Scope: R04/R10 persistence and media; S06/S07/S11/S23 content. Depends on M4.

Acceptance:

- Public note/photos/optional date are editable before comparisons and later from detail. Cancel/Done updates local draft correctly; changing editor content does not publish independently. Interrupted drafts survive restart scoped to their owner; explicit discard/expiry/sign-out clears them.
- Notes/date validation matches limits; unknown dates remain unknown, future completed visits rejected, destination/device timezone doesn't shift a stored date. PrivateNote remains separate from public activity/detail/share serialization.
- System Photos picker handles cancellation/limited availability, up to six images, normalization/metadata stripping, ≤2,048 px and ≤3 MB limits. Per-asset retry/removal is accurate; save cannot claim a failed image succeeded.
- Only completed owned uploads attach. Staged media inaccessible to others; publication makes authorized signed reads available through parent visibility. Orphan cleanup after 24 hours is implemented and testable; deleted media and account cleanup have durable retry.
- Every committed rating/revisit/rerank has the specified automatic activity snapshot; completion clearly discloses public output. Later note/photo edits update its projection without moving feed publication time. Old score snapshot is labeled separately from current rating.
- Removing ranking retains actual populated note/photo memories and public access through permitted detail; deleting Visit removes that Visit's memory/activity/media, and final-Visit deletion updates Rating. Standalone activity deletion leaves Rating/Visit intact.
- Gallery/viewer loading/error/empty states and content-report submission work; report receipt never claims human review.

Evidence: populated-memory retention tests, storage authorization/cleanup/idempotency tests, interrupted-upload/draft walkthrough and private-data serialization checks.

## M6 — People, chronological feed, interactions and notifications

Scope: R09/R10, S02/S18 identity/S21–S23/S25. Depends on M5.

Acceptance:

- One-way follow/unfollow and counts persist; no self/duplicate follow. Member search/follower/following empty, filtered, loading and pagination states work. No default follow from setup.
- With unrelated fixture accounts, following exposes eligible earlier and newly completed rating activity; feed sorts by server `(publishedAt,id)` descending with stable cursors. Backdated visit is ordered by publication time. Refresh/paging deduplicates and preserves content on failure.
- Following score averages one latest Rating per eligible followed member; revisits do not increase sample count; rerank/unfollow/removal recompute; zero raters shows no score.
- Like desired state is unique, flat comment posting retains failed text and prevents duplicates, owner comment/activity delete updates counts. No replies/mentions/request/guide UI.
- Mute affects feed only; block removes both follow edges and enforces server-side mutual visibility/interaction exclusion, including lists/media/shared wants. Unblock does not restore follows. Test service queries, not just UI filters.
- Shared Want to Go is the exact two-user Experience-ID intersection with list/map and an honest empty state. Updates to either bookmark list refresh it; no collaboration/list sharing or permanent group entity.
- In-app follow/like/comment events deduplicate, skip self events, honor recipient preferences, persist read state and route safely. Removed targets/events don't leak content. No nonfunctional APNs prompt/toggle.

Evidence: multi-account graph/RLS, cursor pagination, notification and score aggregation tests; feed/comment/shared-wants and blocked-state screenshots.

## M7 — Profile globe, travel counts, settings and account lifecycle

Scope: R08/R11/R13, S17–S19/S26/S28. Depends on M6 and M1 map feasibility.

Acceptance:

- Own/other profiles expose the same public globe/list/activity/travel data with correct owner controls. Mini/expanded globe has pins, shaded countries and unique X countries · Y cities counts, selectable pin/cluster and equivalent list; works with device location denied.
- Geography fixtures include same-name cities, destination locality, remote/no-city place, missing country geometry and repeated visits. Counts derive from persisted Visits only; bookmarks/home city don't count. Removing only a Rating retains travel counts; last Visit removal updates them.
- Travel Profile category/city/country rows filter visited experiences and show counts only. No city scores/confidence/guide/leaderboard placeholders. New experiences this year counts first known visit per Experience; date edits/revisits/unknown dates/deletions exercise the specified rule.
- Profile edit validates name/handle/bio/avatar/home city, persists across restart, retains failed edits and discards cancel. Units/haptics/in-app event settings apply consistently and roll back on failed save; only provider-supported account actions appear.
- Experience/profile native text shares contain the specified public values and real Apple Maps URL where applicable. Cancel has no write; no fabricated profile link, private data or list-sharing surface.
- Block/mute lists, help explaining actual scoring/ties/publication, stored reports and account sign-out function. Local operator inspection of reports and cleanup is documented.
- Account deletion uses reauthentication, clear confirmation, immediate visibility/write restriction and server-owned durable relational/media/session cleanup; Apple revocation integration is verified or explicitly listed as a release blocker. Test only disposable local fixtures. Stale tokens cannot recreate deleted user data.

Evidence: geography/year fixtures, globe comparison screenshots, settings persistence, share serialization and account-deletion authorization/cleanup tests.

## M8 — Complete journeys, compatibility and build handoff

Scope: every active screen/requirement. Depends on M1–M7; no deferred feature work.

Acceptance:

- Two accounts walk search → detail → Want → sentiment/details → compare/tie → immediate score → automatic follower feed → comment → repeat visit/rerank → globe/counts → shared wants → removal with retained memories. Cover all seven categories and empty/no-follow conditions.
- Exercise offline draft, expired session, failed save/upload, stale ranking revision, slow old search response, denied location, missing geography/media and deleted/blocked targets. No fallback fabricates success/data or removes a confirmed feature.
- Meaningful unit, engine/server parity, pgTAP/RLS, local integration and UI tests pass; rerun only checks affected by later fixes plus final end-to-end suite. Save logs, `.xcresult`, simulator screenshots and concise visual comparison against the reference map.
- Build with iOS 18 deployment target; run on installed iOS 26.2 and an iOS 18 simulator/device when available. Record missing iOS 18 runtime/device as compatibility validation outstanding; do not claim it passed on a newer simulator.
- Check Dynamic Type/VoiceOver/Reduce Motion, small-screen layout, long names, large tie groups, clustered globe pins and accessibility of map alternatives. No real capture-account names/contacts/media in seed or shipped assets.
- Verify real Apple sign-in separately from fixture auth, local startup/reset instructions and clean checkout generation. Record exact SDK/library/tool versions. No committed secrets, generated Xcode project, stale draft requirements or deferred-feature routes.
- Final report names complete milestones/screens, test evidence, effective defaults, any specific external configuration/validation blockers, and remaining release setup (hosting/SMTP, legal/support destinations, moderation, revocation). No App Store upload or production migration during this run.

Exit: reproducible local Roam app with all v1 requirements verified to the extent stated. “Build succeeds” alone is not completion; unresolved provider/runtime checks remain visible, and no partially tested feature is called production-ready.
