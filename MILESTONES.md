# Roam ordered implementation milestones — draft

**No build has begun.** This is the proposed future sequence for [SPEC.md](SPEC.md). Approval of documentation is not a claim that pending captures or product decisions are resolved. Screen IDs S01–S28 and requirements R00–R13 resolve to SPEC; B IDs and filenames resolve through [Roam reference map](docs/roam-reference-map.md). Evidence includes original 01–322 and [53 visually reviewed new-account captures](docs/beli-live-capture-addendum.md); reconcile later captures before finalization.

Each milestone must leave a buildable app once implementation is authorized. Screenshots and fixtures use Roam branding and fictional travelers/experiences. Source references remain read-only. Build-time validation should include unit/service tests for meaningful logic, integration tests for authorization and persistence, and simulator walkthroughs for UI; do not create tests that only restate view constants.

## M0 — Finish decisions and reconcile references (pre-build gate)

Dependencies: none. Scope: all R/S/B IDs; G01–G12 and D01–D12.

Acceptance:

- Capture completion status established; every new distinct layout/state visually reviewed with filename/provenance, repeated content explicitly sampled. Reconcile SPEC, milestones and the reference map; coordinate later updates to capture-owned inventory/gap documents without overwriting the running capture work. The new-account ledger is the current boundary for NC001–053.
- Approve ranking interaction/math, ten-per-category threshold vs earlier provisional scores, deletion/relock and city-contribution eligibility, category-assignment/revisit policy, All-view order, posting policy, auth/backend/minimum iOS and proposed release deferrals. Uncaptured behavior can be an explicitly accepted Roam design; cannot be called verified Beli behavior.
- Exact city formula remains deferred to M7, with confirmed balancing/confidence constraints retained; no numeric placeholder treated as production score.
- Media/share/guide privacy and moderation scope have an owner and recorded decisions. Release phase chosen for challenges, generated/collaborative guides, goals/history/streak and member leaderboard.
- Screen registry and scope matrix agree; no feature disappears solely because reference is inconvenient or gated.

Exit evidence: approved decision register and reconciled draft. Only then request/start the separate implementation phase.

## M1 — Project foundation, navigation and place/globe feasibility

Depends on M0 technical choices. Scope: R00/R01, C platform and globe requirements; S02–S06/S18–S19 shells; B01/B13/B23/B05.

Acceptance:

- `project.yml` generates project using XcodeGen; selected minimum iOS builds and launches. No manual `.pbxproj` edits.
- Five tabs route correctly; present/dismiss/back preserve invoking tab. Fake provider fixture separates development data from production MapKit results.
- MapKit spike resolves one POI and a locality for a Day Trip; stable identity/re-resolution strategy documented with actual API capabilities.
- Globe spike demonstrates pins, country polygon shading and camera behavior on selected device/OS; measure an agreed representative dataset. If feasibility fails, obtain a product decision before substituting a flat map.
- Reusable rows, cards, sheets, score labels, skeleton/empty/error states accommodate long travel titles, large text and accessible labels. No copied Beli artwork/content.

Evidence: build log, simulator routes and globe/MapKit feasibility note. No backend framework chosen implicitly.

## M2 — Identity, persistence and authorization

Depends on M1 and approved providers. Scope: R02/R13, logical model, S01/S26; B32/B34/B38/B41, remaining G01 variants.

Acceptance:

- New account, session restoration, provider cancel/error and sign out work for chosen auth methods. Duplicate handle prevents save with retained form values. The observed progressive setup informs Roam's optional photo, home city, import and permission prompts; each optional step can be skipped and returning users do not repeat first-use education.
- Optional avatar/home destination/import/member suggestions skip cleanly, with manual browsing/search after permission denial. Home city does not count as visited. No implicit inviter or default-selected follow; explicit selection persists directional edges with partial-failure feedback.
- Authenticated setup resumes its saved checkpoint after relaunch; credentials are never stored in drafts. First-use card/Log coachmark dismiss once, creates no ranking, and leads to the category list. Returning users do not replay completed setup.
- Persist profiles and canonical places/experiences with one-place constraint and seven categories; duplicate place reconciliation follows approved policy.
- Public profile read works for a different account, while credentials/private notes/settings are inaccessible through service/database tests, not only hidden in UI.
- Owner-only writes and public read subsets enforced; client cannot impersonate another user or forge notification/aggregate ownership.
- Profile editing persists after relaunch, cancel does not save, network failure retains edits. Tests include new and expired sessions.

Evidence: two-account authorization test results and simulator walkthrough compared to B41 where observed; Roam-specific providers, permission-granted variants and success paths remain labeled design choices.

## M3 — Discovery → detail → Want to Go

Depends on M2. Scope: R03/R04/R06, S03–S07/S12–S13; B07–B19/B22–B24/B26.

Acceptance:

- Query + selected destination finds fixture/MapKit experiences; newer query wins over delayed older results. Members tab may use fixture until M8 but must be labeled development-only.
- Place/guide/city result types route distinctly. Unmatched search offers query/location recovery; cannot create an invalid or multipin experience.
- Detail handles full/missing metadata, long title, personal/followed/community score absence, open/closed/unknown hours and media failure without fabricated facts.
- Save/unsave from search/detail/list share one persisted bookmark state after relaunch; retry cannot duplicate bookmark. It creates no visit/rating/city contribution/post.
- Want empty/populated/search/filter/map states work. Apply changes staged filters; Cancel discards; facet logic and sort meet approved D04 contract. A no-results filter has Reset.
- Manual-city map works after location denial; map marker/card/list identify the same experience. Permission failure leaves list usable.

Evidence: search race test, bookmark persistence test, list/map navigation and permission walkthrough.

## M4 — Category ranking design and engine

Depends on M0 approved ranking rules and M2 model; can precede final UI. Scope: R05; B20/B42–B43 low-count flow, pending G02 variants and G03 numeric reveal.

Acceptance:

- After reviewing missing variants, define the now-authorized, versioned Roam ranking algorithm: sentiment bounds, numeric-score unlock threshold, candidate selection, tie/skip behavior, rerank, removal and rounding. Preserve the observed Beli sequence; explicitly distinguish own math from observed behavior.
- Tests cover empty category, one item, multiple sentiments, exact/near ties, repeated comparisons, cancellation and all seven categories.
- Numeric availability is separate from ordinal rank. If a threshold is adopted, test below/at/above threshold per category, removal below threshold, progress copy and the approved treatment of hidden scores in community/city aggregates. Missing scores are never zero.
- Scores remain bounded/deterministic/monotonic with approved ties. Ranking one Outdoors experience does not change Food & Drink order or scores.
- Atomic commit and optimistic version conflict handled; failed/retried commit does not create partial order or duplicate visit.
- Revisit and rerank change one current contribution according to approved policy; removal recomputes expected affected scores.

Evidence: algorithm decision plus meaningful property/fixture/concurrency tests. No guessed city formula introduced here.

## M5 — Log visit, compare and ranking-result UI

Depends on M3/M4. Scope: S08–S10/S12, R03/R05; B20/B26/B42–B44; NC031–051; G02 partially resolved, G03 numeric reveal still pending.

Acceptance:

- From an experience show category/sentiment, then optional visit enrichment and Okay **before** comparison, restricted to the chosen Roam category. No manual numeric input, unsupported extra confirmation screen or mandatory travel-metadata detour. First item bypasses comparison.
- First category item reaches ordinal result without invalid comparison; numeric score presentation follows the approved unlock threshold. Repeated case exercises preference/Too tough/Skip/Undo/back/cancel contract. Display of missing photos and very long names remains usable.
- Result/completion ordering matches B42–B43 for low counts, displays the correct category rank and locked/unlocked score state, and reaches updated Been list/detail. Any new numeric reveal design is labeled Roam-owned until G03 is resolved. Never report a successful save before acknowledgement.
- Cancel changes no durable rank; failed save preserves draft and retry is idempotent. Concurrent rerank prompts approved recovery, not silent overwrite.
- Remove ranking from own detail shows confirmation and preserves visits/notes/photos under the approved retention policy. Cancel/failure leaves the prior order; successful removal recomputes affected scores and city aggregates. Test retained memories remain accessible and globe counts follow Visit eligibility, including removal of the final ranking. Rank-again preserves existing memory and does not duplicate a Visit unless explicitly chosen.
- Been selected category has correct ranks; All never presents a false combined category order. Visit/date/score history labels and Want removal/undo follow accepted policy.

Evidence: complete simulator journey and persistence assertions; screenshot comparison covers NC031–045 entry/details/comparison/rank results and NC049–051 removal. Uncaptured numeric reveal/failure states are labeled proposed Roam design.

## M6 — Remembering, media and optional activity publication

Depends on M5 and media/posting decisions. Scope: R04/R10, S07/S11/S23 draft paths; B17–B19/B21/B42; NC032–036; G04 partially resolved for editor layout only.

Acceptance:

- Add public note/photos/highlights through the reconciled completion/edit flow and retain a separate private-note entry. Automatic vs explicit activity creation must follow the accepted evidence-based policy; do not require a new Save/Share fork. Private notes cannot enter public output/share serialization.
- Notes/companions/labels/date editors use Cancel/Done against the same local visit draft before comparisons. Done in an editor creates no public event; cancel restores previous values; app interruption retains nonsensitive draft. Date is optional, highlights fit the category, and a failed mention lookup does not erase prose.
- Test the approved distribution choice at ranking completion and distinguish public profile/ranking visibility from feed distribution. Do not infer follower visibility from an empty own feed or claim locked stealth mode was exercised.
- Photo picker cancel/limited access/denial, per-asset upload failure and retry work. Approved media limits enforced with clear errors; draft survives interruption.
- Completion clearly communicates public output without an unsupported mandatory preview screen. The accepted completion event creates one Post, whether coupled to ranking or explicitly triggered; double tap/retry does not duplicate. Published score snapshot distinguished from current reranked score.
- Edit/delete memory/post obeys approved separation: deleting a post does not unexpectedly delete a rating or guide. B44's Delete rating warning says notes/photos survive in Beli; decide Roam retention explicitly. Failed edits preserve draft and public old version.
- Gallery grid/search/viewer has loading/no-photo/no-result/error states and functional reporting path if included.

Evidence: privacy/serialization tests, retry tests and posting walkthrough labeled proposed Roam design until capture reconciled.

## M7 — Geography, city scoring design and profile globe

Depends on M5, M1 feasibility and explicit scoring design approval. Scope: R07/R08, S18–S20; B05/B25, Roam additions.

Acceptance:

- Canonical geography policy handles same-name cities, locality Day Trip, remote experience, missing country/city and corrected place. Counts deduplicate; bookmarks never count as visits.
- Own and other profiles show pins/shaded countries/city-country counts; selecting pin opens correct experience; expanded globe/list alternative works without location permission. Private notes absent.
- Before numeric score implementation, approve formula/version, reviewer/category caps, baseline/sparse handling and confidence display. No direct city rating UI exists.
- Tests prove repeated visits do not increase independent visitors; one prolific user and one huge category cannot dominate outside approved caps. Zero data shows no score, missing category is not zero, independent evidence changes confidence appropriately without popularity bonus.
- Personal/global lenses and seven-category breakdown display source/sample/confidence. Rerank/removal/geography correction invalidates/recomputes affected aggregates; cache shows recalculating if asynchronous.
- Numeric golden fixtures and confidence invariance tests established only after formula approval. Population changes can support high or low score.

Evidence: geography fixture matrix, approved formula, aggregation tests and own/other globe walkthrough. If formula still deferred, milestone cannot claim shipped city scoring; nonnumeric UI prototype alone is partial.

## M8 — Follows, social feed and interactions

Depends on M2/M6; M7 for full profile context. Scope: R08–R10, S02/S18/S21/S23; B03/B04/B18/B21/B25/B30/B34.

Acceptance:

- A follows B without reciprocity; duplicate/self-follow prevented; counts persist. Follow/unfollow failures roll back and retry cleanly. Public profile/Been/Want work for unrelated users.
- Feed ordered by publish timestamp and stable tie-break with cursor paging; backdated visit does not change publication ordering. Empty/no-follow/refresh/paging/media-error states handled.
- Likes deduplicate; comments/replies retain failed text, respect ownership and route mentions under approved scope. Editing/deletion updates detail/feed/profile consistently.
- Mute excludes feed activity without deleting follows; Block/Report follow approved policy; two-account tests verify interactions and private-note protection.
- Following recommendations recompute from eligible unique followed raters; unfollow updates source eligibility. No proprietary predicted score placeholder.

Evidence: directional graph, feed pagination and authorization tests; walkthrough with fictional social fixtures.

## M9 — Guides, list sharing and shared wants

Depends on M3/M6/M8. Scope: R09/R11, S14–S17/S22/S24; B08/B23/B27–B29/B38. Core sharing cannot be deferred away.

Acceptance:

- Create/edit/delete free guide, add resolved experiences, reorder/remove and persist across restart. Guide operations do not mutate personal rank order.
- Directory/category/city filters route to accessible guide list/map; viewer progress accurately distinguishes saved vs visited. Generated/request/collaborative variations implemented only per approved scope, with every omitted variant recorded.
- Share experience/profile/full list/selected subset/activity via preview/native sheet; zero selections disabled; cancel creates no post or unintended write. Public payload excludes private notes/contact values.
- Live-link vs subset snapshot semantics tested; valid link routes to correct entity, deleted target shows unavailable; auth preserves target. Approved nonuser fallback tested if in scope.
- Shared-wants picker applies/cancels correctly; exact-place group intersection yields expected fixture set and empty recovery. No location permission required for known map points.
- Recommendation request/contribution and role tests prevent public viewers editing owner guides. Bulk save/challenge join, if accepted, do not create visits or duplicate existing bookmarks.

Evidence: link/privacy/role/intersection tests and guide/share journeys. Collaboration/challenges not “complete” if only display cards exist.

## M10 — Discovery depth, imports and approved breadth features

Depends on M7–M9. Scope: R06/R08/R11/R12, S05/S14–S16/S24/S27–S28; B06/B10/B23/B24/B27/B37.

Acceptance:

- Trending implements an approved transparent window/unique-user policy; sparse destinations show honest empty/fallback; no arbitrary “trending” seed order in production.
- Paste import resolves MapKit matches, stages ambiguous/unmatched rows, commits selected bookmarks only and reports partial failure/duplicates accurately. Retry adds no duplicates and creates no rating.
- Category/subtype/city/country/open-now filters return correct fixtures, with unsupported metadata omitted rather than fabricated.
- Each accepted optional feature (generated guides/challenges/goal/streak/history/member board) has its own confirmed policy and loading/empty/error/persistence criteria. Goal cancel saves nothing; repeated visit does not inflate distinct-experience goal or challenge progress.
- Every proposed deferral is explicitly accepted or scheduled; restaurant booking/payments, paid guides, referral gates and predictive recs cannot quietly become incomplete buttons.

Evidence: discovery/import fixtures and explicit scope-completion matrix.

## M11 — Notifications, settings and account lifecycle

Depends on M8/M9 and supported feature set. Scope: R13/R10/R02, S25–S26; B30–B36/B38–B40.

Acceptance:

- In-app events deduplicate, read state persists and navigation opens correct target or safe unavailable state. Push denied does not block in-app feed; push enabled tested on suitable device if included.
- Event preferences persist and govern actual supported events; backend failure is visible. Units/haptics apply across screens after relaunch.
- Account edit/auth recovery/sign out/deletion match actual provider capabilities; no unsupported phone/password/billing controls.
- Blocked/muted lists support empty/populated/recovery. Public profile explanation agrees with service authorization. FAQ answers reflect approved Roam rules.
- Deletion/retention and link/media/aggregate cleanup follow accepted policy; stale session cannot write after account removal. Support/report destination operational, not a decorative CTA.

Evidence: event/preferences/lifecycle tests and settings walkthrough.

## M12 — End-to-end acceptance and release readiness

Depends on all accepted milestones. Scope: all R/S IDs; reference-map coverage matrix.

Acceptance:

- Walk through discover → detail → Want → visit → compare → reveal → notes/photos → publish → follow/comment → guide/share → city/globe using at least two unrelated fictional accounts and all seven categories. Also walk the captured ordering of optional notes/photos before comparison, the first-item rank-only/score policy, and rating removal with retained memories.
- Validate chosen minimum and latest supported iOS/device sizes, accessibility, long text, missing geography/metadata, denied permissions, expired auth, offline draft, failed writes and media retries.
- Meaningful unit/service/authorization/integration tests pass; simulator evidence demonstrates states and navigation against mapped references with documented Roam adaptations.
- No pending capture is misrepresented as verified, no unapproved algorithm/omission, no private-data leak in public/API/share outputs, no real reference-account content in fixtures.
- Record build/run/test commands only after toolchain verification; save milestone screenshots to `screenshots/<milestone>/`, never into `reference/`. Review remaining risks and deployment/signing/push/link configuration before release.

Completion report must list implemented screens, approved deferrals, any unresolved blockers and evidence. Passing a UI build alone is not feature completion.


## Evidence update and remaining finalization work — 2026-10-13

New-account captures change acceptance targets in M2 (setup/first use), M4–M5 (comparison controls and score availability), M6 (pre-comparison memory editors) and M7/M8 (retained visits, score eligibility and publication). They do not authorize a backend, formula, stealth-mode policy or new release omission. SPEC's prioritized D01/D03/D02/D06/D07 list is the decision order; city math stays deferred to M7.

Documentation validation for this update: all NC001–053 visually reviewed, key controls inspected full size, per-file hashes recorded, three deliverables cross-checked for changed screen order and evidence status. Implementation tests above are future acceptance criteria, not tests already run. No app code, simulator run or live reference-account action is part of this update.
