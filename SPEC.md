# Roam implementation specification — draft

**Status: design/specification only; not ready to build.** Original reference boundary remains 01–322. A separate, visually reviewed new-account session is documented in [the new-account review ledger](docs/roam-reference-map.md#new-account-captures-reviewed--2026-10-13). It establishes onboarding and the first three rating paths, while numeric score reveal and any later publication flow remain uncaptured. This describes the Roam app to build, with explicit proposals where decisions or reference flows are missing. No application implementation is part of this phase.

Primary journey: **discover an experience → view details → save to Want to Go → log a visit → compare within its category → receive a score → add notes/photos → share activity → explore people, lists, cities and the globe.** This is the product journey, not a rigid screen order: optional notes/photos are also available before comparison in the newly captured flow, and later editing remains available. A user can log a previously visited place directly without saving first. Numeric-score availability and activity publication still require the decisions below.

Evidence and traceability:

- [PLAN.md](PLAN.md): confirmed product decisions; precedence corrections below.
- [Roam reference map](docs/roam-reference-map.md): screen IDs → Beli references and adaptation/gap notes.
- [Beli inventory](docs/beli-inventory.md): visual observations, states, routes and exact screenshot review ledger.
- [Beli-to-Roam coverage map](docs/roam-screen-map.md): full feature translation and proposed omissions.
- [Capture gaps](docs/capture-gaps.md): G = missing reference, D = Roam decision.
- [Milestones](MILESTONES.md): ordered work and acceptance gates.

## Status vocabulary and precedence

**C — confirmed:** approved in PLAN or the user’s instructions. **P — proposed contract:** concrete default behavior for review, not silently approved. **TBD — unresolved:** no implementation may invent a final policy without an explicit decision. **Pending reference** means the Roam proposal may be specified, but Beli behavior is not verified.

All requirements under R00–R13 are **P unless explicitly marked C**. Beli screenshots support structure; they do not confer approval on Roam policy. Acceptance criteria validate the proposed contract after approval. Screens tagged optional/deferred do not vanish from scope without a recorded decision.

| Confirmed requirements | Consequence |
|---|---|
| C Native iOS, SwiftUI, MapKit, XcodeGen | Generate the project from `project.yml`; do not hand-edit `.pbxproj`. MapKit is the place/search/maps foundation. |
| C Exactly one MapKit place per experience | A day trip is its destination place/locality. No custom multipin rated trips. A guide may contain many separately rated experiences. |
| C Seven independent rankings | Food & Drink, Outdoors, Day Trips, Culture, Nightlife, Activities, Stays. No additional restaurant-only ranking categories. |
| C Tracking, discovery, saved experiences, social and list sharing all matter | No reduction to a search-and-bookmark utility. |
| C One-way follows and public profiles | A follows B without reciprocity. No private-profile feature or friends-only default authorization model. Private notes remain separate. |
| C Globe on own and other profiles | Experience pins, shaded visited countries, unique city/country counts. |
| C Personal/global city scores from experience ratings | No direct city-rating input; category breakdowns, balanced reviewer/category contributions; larger independent samples improve confidence, not popularity bonuses. Exact formula deferred. |
| C Reverse-chronological v1 social feed (PLAN §1) | Feed ordering does not use personalization/ranking. Discovery can have its own explicitly defined order. |
| C Own brand and travel content | Adapt interaction patterns, never copy Beli logos, artwork, text or private algorithms. |

**Superseded PLAN material:** §7 custom experiences with multiple pins is obsolete. §2 backend recommendation’s “friends-only access rules” conflicts with public profiles. §9’s alternative category/social/globe choices are already decided. §3’s claims about Beli binary search/equal spacing are historical research, not verified implementation rules. Supabase, iOS 18, `@Observable`, photo storage architecture and auth providers remain recommendations. Environment tool/version statements are historical and must be rechecked when building. The old “choose closest Beli behavior” build instruction does not finalize missing ranking/posting policies in this phase.

## Product scope and examples

Fictional UI fixtures: traveler **Maya Chen (@mayaroams)**; experiences **Harbor Lantern Café** (Food & Drink), **Cedar Ridge Trail** (Outdoors), **North Quay Gallery** (Culture), **Willow Bay** destination (Day Trips), **Moonline Jazz Room** (Nightlife), **Blue Kite Workshop** (Activities), **Aster House** (Stays). These are display/test fixtures, not asserted real MapKit listings. Production experiences must resolve to a real MapKit place; tests use a controlled place-provider fixture.

Draft core includes category rankings; visits and public/private memory; Want to Go; search, followed recommendations, trending and curated discovery; free custom guides/list sharing; public profiles/follows/shared wants; chronological activity/likes/comments; city insights/globe; notifications/settings. Challenges, goals/streak/calendar, generated guides and collaborative contributions are specified as proposed breadth features requiring release-phase decisions.

Proposed deferrals requiring approval: restaurant booking/order/payment/calendar/Gmail integrations; paid creator subscriptions; referral-gated access to basic scores; proprietary-style predicted liking/taste match; school/company member leaderboards; automatic camera-roll place extraction; provider-specific imports beyond paste-first. Reasons and all reference counterparts remain in the coverage map. Do not ship fake buttons for deferred services.

## R00 — Cross-cutting UI, state and persistence contracts

### Components

- `RootTabBar`: Feed, Your Lists, Search, Explore, Profile. Accessible names, active state and stable bottom safe-area placement.
- `ExperienceRow`: name, category/subtype, city/country; optional rank and correctly labeled score/count; optional hours/cost; rate/visit and save actions. Missing metadata is omitted or labeled unknown, never filled with invented values. Entire row opens detail; action buttons do not trigger row navigation.
- `ScoreBadge`: source label (You, Following, Community or City), one decimal if available, sample context and explanation affordance. No score uses “— / Not rated” rather than 0. Color is supplemental to text.
- `MemberRow/Card`: avatar fallback, display name, handle, follow state, optional reason for suggestion; profile navigation separate from Follow action.
- `ActivityCard`: author, action, experience, category, score, visit context, photos, public note, reactions/comments and timestamp. Compact and expanded variants share semantics.
- `GuideCard`: image or Roam gradient, title, owner, city/category context, item count, share action; progress reflects viewer’s visited items, not author’s rating.
- `FilterSheet`: staged draft values, single ranking category or All, queryable facets, Clear all/Apply/X; pinned footer and independently scrolling body. Dismissal discards unapplied changes.
- `MapListToggle`, `SelectedPlaceCard`, `EmptyState`, skeleton rows/media, inline retry, destructive confirmation and native share sheet.

### Universal states and behavior

Every remote collection must have initial loading, populated, genuinely empty, filtered-no-results, recoverable error and pagination-error variants. Existing content stays visible on refresh failure with retry. Empty follows invite finding people; empty Been invites logging; empty Want invites discovery. Permission denial is not an empty database.

Search cancels/supersedes stale requests: only the latest query/destination may populate results. Back and modal close return to the invoking context without losing committed state. Preserve list query/filter/scroll position within a tab session. Sheet/keyboard/composer must not cover the last row or action.

P Writes have explicit pending/success/failure states. Save/follow/like may update optimistically with rollback and a retry message; ranking commits and post publishing require server acknowledgement before success. Each logical write uses an idempotency key. Disable duplicate submission while pending. A retry must not duplicate visits/posts/comments/imports. Failed uploads preserve editable local drafts. Do not assume full offline synchronization: proposed v1 caches last-read content and permits local drafts, with network-required durable writes clearly labeled.

P Drafts for log/notes/post survive app interruption on the device; Cancel asks Keep draft/Discard when nonempty. No draft is public. Credential fields are never persisted as drafts. Full offline queues, multi-device draft sync and retention duration TBD.

P Dynamic Type, VoiceOver labels/order, minimum native touch targets, contrast, Reduce Motion, keyboard navigation where available and long-place-name wrapping are acceptance requirements. Loading announcements do not repeatedly interrupt accessibility focus. No essential state conveyed only by a map or color: provide matching list data. Dates use locale and explicit visit date vs posted time; remote opening hours use the place’s time zone if known. Score rounding must be consistent everywhere.

## R01 — Navigation and screen registry

P Each root tab owns a navigation stack. Search has a root screen and can also be presented from a search affordance; dismiss returns to the caller. Experience/person/guide/city routes can be reached from multiple tabs with stable IDs. Opening a deep link routes to its target; if auth is required, preserve the target through sign-in. Public-profile web preview and anonymous browsing are TBD, not guaranteed by public in-app profiles.

| Screen ID | Roam screen / destination | Entry and exit |
|---|---|---|
| S01 | Welcome/auth/account setup | Cold launch; new-account reference now available; proposed Roam completion enters Your Lists |
| S02 | Home Feed | Root; search, featured guides, activity detail, people, notifications, menu |
| S03 | Search Experiences/Members | Root or search action; detail/profile/city picker; close when presented |
| S04 | Destination picker | Search/filter/Explore; returns chosen canonical locality |
| S05 | Explore list/map | Root; manual destination or current location → detail |
| S06 | Experience detail | Search/list/feed/pin; back to origin; utilities/gallery/log/save |
| S07 | Gallery/photo viewer | Detail/review media; back to detail; report photo |
| S08 | Log visit and category/sentiment entry | Detail or rate action; cancel/draft; comparison |
| S09 | Comparison | Log/rerank; paired choices, Undo/Too tough/Skip observed; result/list |
| S10 | Ranking result / numeric-score reveal | First-rank education and locked-score list observed; numeric reveal pending |
| S11 | Visit details and memory editors | After sentiment, before comparison; later detail edits; upload/publication behavior pending |
| S12 | Your Lists / other member lists | Root/profile; Been/Want/Following Recs/Guides/Trending; list/map |
| S13 | List search/filter/sort/category | List controls; apply or cancel back |
| S14 | Guide directory | Lists/profile/featured discovery; guide detail/editor |
| S15 | Guide/challenge detail list/map | Directory/link/notification; share/save items/join if supported |
| S16 | Custom guide editor / contribution | New guide, owner edit, request contribution; pending reference |
| S17 | Share list/profile/experience/activity | Context action → options/selection/native sheet; cancellation returns |
| S18 | Own/other public profile | Root/avatar/search/link; globe/lists/follow graph/stats/activity/guides |
| S19 | Expanded globe and travel breakdown | Profile/stat rows; selected place/city; back |
| S20 | City detail and contributing experiences | Search/profile/globe/list city; personal/global/category views |
| S21 | Followers/following/member discovery | Profile counts or Find people; profile/follow |
| S22 | Shared Want to Go/member picker | Other profile; participants/list/map/share |
| S23 | Activity detail/comments | Feed/profile/place review; comment/reply/report; back |
| S24 | Ask for recommendations | Feed/guide; draft/create request; pending reference |
| S25 | Notifications | Bell/deep link; destination/back |
| S26 | Menu/settings and subpages | Profile/feed menu; account/privacy/preferences/help |
| S27 | Import and match review | Want/menu; confirm matches/import summary; pending downstream reference |
| S28 | Goal/streak/history/achievements | Profile/menu; proposed breadth feature; open release decision |

## Journey A — enter, discover and save

### R02 — Account setup (S01)

**Observed Beli sequence (B41):** welcome → phone submission → inviter acknowledgement → email → password → first/last name → available username → optional profile photo → default recommendation city → location request (skip confirmation) → optional list import → contacts request (skip confirmation) → suggested follows → bonus invites (give-up warning) → notifications request (skip confirmation) → reservation sync → first Been-list education card → starter suggestions. This was one path through a newly created account, not proof that every new member sees the same inviter, city options or defaults. The password-entry screenshot is blank. Contact values and real identities in reference images must not be transcribed into Roam fixtures. This review establishes displayed states; it does not independently verify backend authentication or every tap between images.

**P Roam flow:** branded welcome/value proposition → selected authentication method → display name/unique handle and optional avatar → optional home destination → optional import/follow suggestions → first experience list and Log entry. Preserve Beli's short full-screen setup steps, clear skip actions and first-list teaching moment. Adapt the restaurant-specific default city to a travel home/starting destination; whether Roam asks for a home city during setup is TBD. Explain public profiles before completion. Request location, contacts, notifications and photos in context; denial must leave manual destination browsing available. Do not copy Beli's invitation gate or Gmail reservation-sync requirement without an explicit product decision.

TBD providers: Sign in with Apple is available by team membership, but inclusion with email and/or phone remains a decision. Select providers before defining password/OTP/recovery screens. Supabase recommendation does not prove SMS availability.

P Profile creation and uniqueness checks must be retry-safe; duplicate handles show a field error without losing other input. Session restore shows a bounded loading state then app or auth; expired session preserves nonsensitive unfinished task intent. Auth cancellation returns to welcome; errors support retry. Account credentials remain inaccessible to other users.

#### Setup and first-use implementation details (P; S01 → S12)

Use a full-screen title, short explanation, one focused input or selection, Back, primary Continue and a visible Skip for optional steps. Roam copy introduces “Keep your travels in order” with original travel artwork. Do not reproduce the reference brand, invite pressure, or a fixed restaurant-city menu.

| Step | Display and actions | Persisted effect and edge states |
|---|---|---|
| Identity | Chosen auth provider, then display name and unique handle; inline availability check | Auth session and Profile; disabled submit for invalid fields, pending indicator, retry without duplicating account. Stale handle checks cannot overwrite the latest input. Auth/OTP/recovery variants remain provider-dependent. |
| Avatar / destination | Optional avatar picker; searchable MapKit city with region/country; Skip | Profile avatar/home-city reference only after successful save. Neither selection marks a city visited. Picker cancel retains prior avatar; unknown city stays unset. |
| Import / people | Optional import entry (R12), member search and selectable follow suggestions | Import saves bookmarks only after match confirmation. Propose no preselected follows and no implicit follow of an inviter; explicit Add selected action creates directional edges. Empty suggestions offer search or Skip. Partial failure identifies unsaved selections. |
| Permissions | Contextual explanation and native permission request on relevant action | Device authorization is separate from Roam settings. Skipping contacts leaves manual member search; denied notifications leave in-app events; denied location leaves manual destinations. No repeated warning to force optional consent. |
| First Been list | One-time educational card and coachmark pointing to Log; category selector and starter experiences | Persist education-dismissed/setup checkpoint separately from ratings. Dismissal creates no visit. Show original Roam examples in fixtures; production suggestions require valid places. Empty destination falls back to search. |

Propose resumable setup checkpoints after authenticated profile creation, with no passwords or OTPs in persisted drafts. Returning users resume the app instead of replaying first-use education. A checkpoint save failure offers retry and does not silently mark setup complete. Skipped setup remains accessible from settings/import/member search. Roam's final screen order and in-context permission timing are intentional adaptations for approval, not observations of Beli. Onboarding referral bonuses, reservation syncing and default-selected follows are proposed omissions/changes under D07/D10.

### R06 — Search and discovery (S03–S05)

P Experiences search combines place/name query with destination; defaults to chosen home/last destination, with an explicit Current Location option. Search results show name, location, category suggestion and independent Save/Log controls. Results can include Roam guides and city destinations as labeled types. A place result resolves to one canonical Place before mutation. Members search uses display name/handle, follow button, loading/empty/clear states and profile navigation.

P S04 displays current location action, recent destinations and locality matches with region/country disambiguation. Selecting a destination changes query scope and map viewport, not the user’s home city. No-results offers edit query/destination and provider-help; never fabricate a custom place to bypass MapKit.

P Explore supports list and map for a selected destination. Filter/category state is shared between views. Tapping a marker selects one place card; tapping card opens detail. Markers/clusters must remain readable; clustering technique TBD. Panning proposes a “Search this area” action rather than silently replacing the visible results. Recenter requests device location only on demand. Denied location offers manual city and Open Settings; approximate location still supports nearby discovery without promising exact distance. Map failure leaves the list usable.

P Discovery surfaces:

- **Following recommendations:** experiences rated by people the user follows; aggregate score and distinct followed-rater count; sort by following score, number of followed raters or distance. Propose one current rating per followed user/place; exact aggregate normalization TBD.
- **Trending:** explicit recent community activity, category/location filters and Most trending/Distance. Formula/window/unique-user cap TBD; never label arbitrary seed order as real popularity. Empty city/category suggests widening filters.
- **Curated/featured:** editorially ordered guides with author/description and real fixture/provenance distinction. Challenge variant in R11.
- **Related experiences:** same-category/location candidates labeled with their selection basis; no proprietary predicted score in draft initial scope.
- **Personalized recommendations:** proposed deferred until data/algorithm chosen. A future insufficient-data message must not obstruct following/curated discovery.

MapKit metadata/photo availability, stable identity facilities and storage/attribution constraints require a technical feasibility review. The spec does not assume MapKit supplies crowd photos, cost, subtype, hours or travel difficulty for every place.

### R04 — Experience detail and remembering (S06–S07)

C Experience identifies exactly one MapKit place. P Detail presents map hero and title/category/subtype/location; compact pinned header on scroll; Log visit, Want to Go and Share; tags and guide memberships; website/directions and phone only when supplied; personal current score, followed aggregate and community aggregate with explanation/sample context. Scores are distinct and cannot be substituted for each other. Category label accompanies all personal scores.

P Body order: score summary → highlights/photos → About (hours/cost/description if available) → Your memory/actions → followed-member reviews → related experiences. Restaurant reservations are a proposed omission, not a blank permanent module. Long travel titles wrap in hero and truncate accessibly only in compact header.

P Your memory contains visit history, public notes, photos, private notes, guide membership and personal highlight labels. Private notes are owner-only and never appear in feed, shared cards, public guide content, exported public previews or other-member requests. Public review labels and public highlights are separately visible. Food & Drink highlights may be dishes; other categories use flexible highlights, not mandatory meal fields.

P Gallery: search by available captions/highlights, horizontal popular/highlight rail where data exists, two-column media grid, full image/author/caption/date, report. Loading/media failure uses stable placeholders; zero photos invites owner upload rather than pretending a photo exists. Photo-viewer gestures remain design proposals; native zoom/swipe recommended.

P Utilities: native website/maps/call handoff and share; copy address when present. Cancel handoff returns unchanged. Correction form can report duplicate/wrong name/location/category/hours/closed/other into a proposed moderation queue; does not edit MapKit itself. Queue backend and review operator TBD. Missing/closed place preserves historical visits and labels unavailable metadata; cannot silently reassign old ratings to another place.

### R03 — Want to Go and ranked lists (S12–S13)

P Saving creates an idempotent Bookmark for user/experience; icon/count update on success or roll back on failure. It does not create a visit, rating, globe pin, city score or public post. Save appears from every experience row/detail/feed card; current state remains consistent. Unsave removes only the bookmark, not visits/rating/guide membership. Proposal: completing first visited/ranked log clears Want to Go with an undo-capable notice; exact behavior D02/D04 to approve.

P Been displays rated experiences with rank/score **within the selected category**. All shows grouped categories or latest-visited default (D04), never a false combined ordinal. Unranked visit memories are a separate visible state/filter, not assigned 0. Want is unranked, with optional followed/community context explicitly labeled. Other people’s lists use the same read components without owner editing controls.

P Header/category/tab/filter/sort controls stay pinned; body scrolls with floating Map toggle. More picker exposes all supported lists rather than hiding Following Recs/Trending/Guides. Starter Been shows suggestions and Log action; populated list replaces onboarding module. Empty Want offers discovery and import. Search and filter no-results offer clear/reset; loading/error never masquerade as an empty personal list.

P Filter facets: category, city, country/region, Good for tags, score source/range if available, followed-rater count, category subtype, cost if known, Open now if reliable, Not on my lists for discovery. Missing hours do not satisfy Open now. Filters unavailable for a category/data source are absent or explained; never simulate provider data. Proposed logic OR within a multi-select facet, AND across facets. Apply commits all changes atomically; X discards; Clear all resets the sheet draft until Apply. Sort score descending, date newest, distance nearest with unknown distances last. Stable ID breaks ties. Exact All-mode ordering requires approval before final tests.

P Owner controls expose visit edits, rerank and removal (R05); other-member controls allow saving/logging for the viewer, not editing the owner. List context stays explicit in headers and share payloads.

## Journey B — visit, compare, score and share

### R05 — Log visit and category ranking (S08–S10)

**C (user confirmation, 2026-10-13):** Roam must preserve Beli’s user-facing rating flow. We may define Roam’s own comparison-selection, tie and numeric-score rules after reviewing the missing captures. This authorizes designing the underlying rules, not replacing the interaction with manual stars, a score slider or a different ranking workflow. Seven category rankings remain separate.

**Observed Beli flow (B42–B43):** tap a plus on the starter Been list → place and category sheet → choose one of liked/fine/disliked → optional visit-details rows → **Okay** → if a prior restaurant exists, a **Which do you prefer?** pairwise sheet. The comparison visibly offers both place cards, **Undo**, **Too tough** and **Skip**. The first restaurant instead returns to Been with a celebration explaining that scores out of 10 start after **10 ranked spots within a category**. With a second restaurant, Too tough ended comparison and placed it at #2; this alone does not define general tie semantics. A third rating preferred over the shown prior place became #1 after one comparison. All three had ranks and locked numeric scores. No numeric-score reveal was reached because the user chose to stop at three. The test ratings were subsequently deleted. Preserve this observed ordering when adapting the flow.

P S08 shows place, category with inline selector, then sentiment selection. S11-style visit enrichment appears **before** comparison, as observed: companions, labels, notes, category-specific highlights, photos, date and visibility if supported. These remain optional so a rating without photo can proceed through Okay. The category must be selected before comparison; do not add a separate confirmation screen. Propose one canonical category per Experience; handling a place that spans categories and user correction is D02. A Day Trip locality remains one place, regardless of multiple activities performed there.

P Proposed internal ranking state machine (not a requirement for one screen/button per state):

| State | Action | Effects / persistence |
|---|---|---|
| Draft visit/category | Edit category / choose sentiment / close | Local draft only; no rank, score, public event or city change. |
| Sentiment chosen | Select sentiment; reveal optional visit details, then Okay | Build comparison candidates from this user’s current ranking in this category only. Candidate policy pending. |
| Comparing | Prefer new / prefer existing | Narrow candidate position; maintain reversible draft history. No live ranking writes per answer. |
| Comparing | Too tough / Skip / Undo | All three labels are now visually observed. Too tough ended the only comparison in the two-item case; broader placement/skip/undo semantics remain TBD. Do not assume a permanent tie or random placement. |
| No candidates | Okay | First-category-item path commits a rank without a displayed numeric score in the observed Beli state. Never compare across categories to fill the screen. |
| Ready to commit | Completion event matching captured flow | Atomic visit/rating/order update against category version; recalculate affected derived data. Do not add an extra Confirm screen without reference support; exact commit/reveal sequence pending. |
| Commit failed/conflicted | Retry/review refreshed comparisons | Preserve draft; no partial order/visit. Concurrent edits may require comparison refresh. |
| Score/result | Threshold/reveal controls matching later capture (TBD) | Beli explicitly gates numeric scores until 10 category ratings; Roam threshold and exact reveal remain a product decision. No reveal was captured. |
| Enrich visit | Optional notes/photos/date/companions before Okay | R10; user can finish with rating only. |

P Comparison screen follows the observed paired-card structure and the exact choice labels Undo, Too tough and Skip, adapted to experiences and city/region labels. The candidate pair was text-only in the observed captures, so media is optional. Missing-image fallback and long names must be usable. A Roam score reveal is pending reference; proposed content is place, sentiment, category position and score, with a link to the category list. Do not present it as Beli-verified. The Beli first-rank illustration was observed; Roam may use its own artwork.

**Ranking engine design is authorized; initial comparison captures are now reviewed, but exact rules remain TBD:** candidate design is an ordered category list with pairwise insertion and sentiment partitions. Explicit tie groups are only one candidate, not a settled interpretation of Too Tough. Define and document score function, bounds, first-item defaults, tie/skip handling, comparison selection, opposite-sentiment boundaries, rerank/deletion reflow and rounding while preserving the observed flow. PLAN’s proposed 6.7–10 / 3.4–6.6 / 0–3.3 ranges are not accepted here. Binary insertion is a candidate algorithm, not a verified private implementation.

P Required invariants regardless of algorithm:

1. Comparisons never cross user or category. Every rated experience belongs to the committed order exactly once for that user under the approved category policy.
2. Category order and displayed scores are deterministic for the same state/version; scores bounded 0–10 if the planned scale is approved; preferred ranks cannot receive a lower score than less-preferred ranks. Tie semantics explicit.
3. Zero ratings displays no score. One rating terminates without a comparison. The observed Beli threshold is 10 within a category; whether Roam uses the same threshold is TBD. Cancellation before the accepted commit event changes no durable rating; retrying that event creates one visit/rating. Dismissing after commit must not silently undo it; exact boundary pending captures.
4. Rerank preserves history and public memory while replacing current category position atomically. Deleting a rating removes its contribution and updates affected ranks/city summaries; confirmation identifies retained/deleted visit/posts separately.
5. Revisit adds a Visit to an existing user/experience relationship. Propose keeping one current personal rating; optional rerank. Repeated visits do not multiply one person’s influence on community/city scores.
6. Score formula/version is recorded; migration/recalculation is explicit. Existing posted score snapshot vs current score must be labeled (propose post stores historical snapshot while detail shows current score).

#### Public rating-flow research — checked 2026-10-13

This supplements the local evidence; it does not mark missing captures reviewed. Sources describe older app versions, so current captures take precedence for interaction details.

| Source and provenance | Supported finding | Limit |
|---|---|---|
| [Derek Ng, Food for thought](https://www.dereksfault.com/blog/food-for-thought), firsthand user account dated July 2024 in the article | Describes three sentiment choices, successive comparisons with previous places, then an automatically generated ten-point score displayed to one decimal. | Does not establish exact scoring formula, tie semantics, save timing or current composer sequence. |
| [Katie Im, Pratt iOS design critique](https://ixd.prattsi.org/2022/02/design-critique-beli-ios-app/), firsthand interface evaluation, February 4, 2022 | Describes choosing between the new and previously evaluated restaurant, with skip and Too Tough alternatives rather than direct numeric entry. | Old interface; does not explain how these responses affect ranking or prove they are separate controls today. |
| [Beli official website](https://beliapp.com/) | Confirms product emphasis on tracking, sharing and discovery. | The inspected page provides no ranking formula or detailed comparison walkthrough. |

No consulted primary source establishes binary-search implementation, equal score spacing, numerical sentiment bands, default first scores or permanent ties. Treat these as Roam design candidates. Competitor comparison pages and clone-app scoring rules were excluded as authorities for Beli internals. External embedded images could not be retrieved during this check, so no external screenshot was added to the visual-review ledger. Local new-account captures now establish an onboarding path and basic comparison layout; numeric reveal and publication remain pending.

### R10 — Memory composer, publishing and activity (S11, S02, S23–S25)

**Observed Beli first-three-ratings path (B42–B44):** the optional visit-details sheet appears immediately after sentiment and before comparisons; **Okay** advances to comparison or commits the first rank. No separate post composer or share action appeared in these three cases. The new account's feed remained in its follow-friends empty state after the three ratings. This does not prove whether followers saw activity, whether notes/photos alter the flow, or what happens after the tenth rating. Roam must match the captured sequence as closely as possible. Separate “Save memory / Share activity” buttons and a standalone preview are alternatives only, not required screens or accepted policy. Private-note edits must remain owner-only and must not leak into public activity regardless of that decision (D03).

P S11 supplies public notes, photos/captions/order, optional visit date and companion tags, highlights and guide additions after sentiment and before comparisons, matching the captured sequence; these may also be edited later from detail. Keep existing place-level editing entries analogous to 151. Personal Notes remains a separate, clearly private action as in 154 rather than being automatically inserted into a public composer. The completion surface must communicate what becomes public; this does not require a separate preview screen. Private notes never appear in public previews or output. Photo picker supports limited access and cancellation; permissions only on invocation. Count/size/compression limits TBD before upload implementation. Upload progress/retry/removal is per asset; publishing cannot claim missing media succeeded. Reordering changes display order, not upload identity.

P The accepted activity-producing completion event creates one Post referencing Visit, Experience and owner, with public note/media and rating snapshot. Whether this event is rating completion or a separate action remains TBD; do not add a mandatory Share step merely to create this entity. Store server `publishedAt`; visit date can be older/unknown. No required freeform note to publish a rating-only post. Publishing failure leaves editable local draft; successful retry yields one post. Editing/deleting own post updates feed/profile/detail and shared-link availability without deleting rating unless explicitly chosen. Full retention/audit policy TBD.

#### Visit-details subflows (P; S11)

Keep the place header, seven-category selector and selected sentiment above the optional detail rows. Use category-appropriate highlights: “Favorite dishes” for Food & Drink, “Highlights” for Cedar Ridge Trail or North Quay Gallery. These rows enrich the current visit draft; no field is mandatory merely to reach comparison.

| Surface | Navigation / displayed data | Proposed effect, persistence and states |
|---|---|---|
| Notes | Add notes → full-height editor; Cancel/Done, mention hint and text area | Done returns text to the visit draft; Cancel discards this editor's changes. Public-note label is explicit; private note stays a separate owner-only action. Blank text is allowed; pending mention lookup may fail without losing prose. |
| Companions | Member search and selectable rows; Cancel/Done | Stage stable member IDs, not copied names/contact data. Done changes draft only; no immediate notification or follow. Empty/search-no-result/loading/error states; companion notification and tag-removal policy D03/D10. |
| Guides and labels | Search, collapsible Your guides and Good for groups, multi-select labels | Stage labels and existing guide IDs; replace dining-only tags with category-relevant ones. Add new opens proposed guide authoring S16; its save semantics are separate from the visit. Commit checks guide edit rights and reports rejected membership without falsely claiming success. |
| Visit date | Calendar, previous/next month, selected-date chips, optional quick dates | Propose one optional date per Visit; Done stages it, Cancel restores prior draft. A separate revisit creates another Visit. The reference's chip layout does not establish multi-date semantics. Validate future dates for a completed visit and retain unknown-date support; date boundaries use destination time zone when known. |
| Photos | Photo action → picker → staged assets | Picker/upload/reordering states remain uncaptured; R10's retry/limited-access/limits contract is proposed. No successful upload or published media claimed from an action row. |
| Feed visibility | Reference shows a locked, off “Stealth mode” switch | Proposed Roam alternative: an ungated “Share to activity” choice in this sheet, applied on ranking completion; no extra composer. This is an option for D03, not an approved default. A public profile/ranking is distinct from distributing an event in the feed. Hiding a feed event must never be described as making a public rating private. |
| Okay | Returns to comparison, or completes the first-item path | Validate and stage inputs; use R05's atomic completion event for visit/ranking. Keep failed draft editable. Do not create a post merely by opening a subeditor or selecting Done. |

#### Rating deletion and retained memories (P; S06/S12)

The newly reviewed own-detail screen shows Rank again; overflow exposes Delete rating. Its confirmation says ranking removal retains notes/photos (NC049–051); NC052 shows Been returning to zero. Retention of actual media was not tested in these images.

Propose Roam “Remove ranking” → confirmation naming the experience and retained visits/notes/photos → server-acknowledged removal. Cancel changes nothing. Success removes the current Rating, reflows that category, invalidates city scores and returns to the originating list/detail; failure keeps the prior rank and offers retry. Retained memories remain reachable from experience detail and the unranked-memory filter. Public Post retention/removal is a separate D03/D10 decision and must be stated in the confirmation. Under the proposed persisted-visit globe rule, retaining a Visit retains its pin/city-country counts even when its numeric rating is removed; deleting the last Visit requires a distinct explicit action. Rerank entry is observed but its full workflow, media retention and network failure paths remain pending.

#### Rating/posting reconciliation checklist

| Evidence / current status | Still needed | Roam consequence |
|---|---|---|
| Sentiment → optional details is captured for three liked ratings | Fine/disliked branches, category changes, cancel/back | Follow observed ordering; alternative sentiment behavior is not verified. |
| Paired cards and Undo/Too tough/Skip captured; one Too tough outcome documented | Repeated pairings, Skip and Undo effects, larger lists and rerank | Own deterministic algorithm remains a design decision; no assumed permanent ties. |
| First-rank education states ten-per-category score threshold; ranks 1–3 have locked scores | Tenth-rating transition, actual numeric reveal, score reflow after removal | Decide Roam threshold explicitly; no invented observed reveal. |
| Notes, companions, labels and date editors captured before comparison | Saved text/media, picker/upload/cancel/error and post-completion editing | Stage details in draft; operational contracts remain proposals. |
| Own list/profile and empty feed captured after ratings | Follower-side feed, own Activity, visibility control, successful publication | Automatic vs explicit publication stays unresolved; empty feed is not proof of no public event. |
| Removal confirmation promises retained notes/photos | Populated-memory deletion, activity/link effects, offline/retry | Adopt retention only as Roam proposal; distinguish Rating, Visit and Post. |

A visible **Post** next to the comment field in 162/179 submits a comment; it is not evidence for an experience-post composer. Native share sheets are external sharing, also not evidence of ranking publication. Existing review cards establish the public output fields, not how users created them.

P Feed top: Roam header/search/discovery chips, featured guides, Ask for recommendations entry, followed activity. Cards: ranked/visited experience, recommendation request, approved milestone, optionally public save event (off in proposal until decided). Newest `publishedAt` first, stable ID tiebreak, cursor pagination; revisiting old travel dates does not insert a newly published memory invisibly deep in history. Own posts can appear alongside followed posts. Muted/blocked actors excluded by approved policy; no recommendation cards mixed into chronological order without clear separate section.

P S23 shows full post/media/expanded note, author/place, category score snapshot, visits/companions, reaction and comment counts, share/log/save. Likes are unique per user/post. Comments have text/author/time, reply context and owner delete/report controls. Composer pinned above keyboard, Post disabled for blank text. Submission errors retain text; duplicates deduplicated. Mentions/replies notify eligible recipients once. Comment length, nesting (propose one reply level), editing and moderation policy TBD. Do not promise tag UI from an untested placeholder alone.

P Empty feed offers Follow people/Discover experiences; skeletons and photo errors are independent; pagination error preserves cards. Empty comments has explicit friendly text (Roam improvement over blank reference). A deleted/private-internal/missing target resolves to unavailable content without leaking private data.

P S24 recommendation request: destination, optional categories, title, public prompt → preview/publish; it creates a request Post and linked guide for attributed recommendations. Contributions must resolve a MapKit experience, deduplicate within request, and show recommender identity; exact approval/ownership rules D08. Request can be closed by owner. This retains the Beli request-guide concept while defining a proposed Roam workflow.

P S25 notifications: grouped Unread/Earlier events (follow, like/comment/mention, request contribution, guide activity and featured content if enabled); avatar/icon, summary/time, contextual action. Read marker set when item is presented/read, idempotently; chosen exact policy to approve. Tapping routes to person/post/guide. Removed target has a safe unavailable state. Notification preferences govern delivery; denied push leaves in-app notifications functional. Push payload avoids private notes; delivery technology TBD.

## Journey C — people, lists, cities and globe

### R09 — People, follows and shared wants (S21–S22)

C Follow edges are directional and profiles public. P Follow/Following/Follow back actions update one edge and counts; no acceptance request. Self-follow disabled; duplicate edges impossible. A nonreciprocal follow still includes that person’s public posts in feed and ratings in Following recommendations. Unfollow removes future feed inclusion without deleting historical user-owned saved experiences.

P Follower/following lists have search, counts, skeleton/empty/no-results, Find people and pagination. Suggestions show a reason if known; contacts access optional and never silently uploaded. Cold start uses labeled editorial/synthetic test data only in development, not fake people in production.

P Profile overflow includes Mute, Block, Report, Unfollow. Proposed mute hides activity without unfollowing; block removes follow edges in both directions and prevents interaction/authorized in-app content access between the pair. Public web accessibility and exact block semantics TBD. Report requires reason/details, confirmation and retry; moderation recipient/workflow must exist before release. Empty and populated blocked/muted settings offer recovery.

P Shared Want to Go compares exact canonical experiences across selected members. Default two-member intersection; propose intersection of all selected people for groups, not union. Member picker stages changes with Cancel/Done, selected chips and query. Results use list/map, participant avatars and sharing. No overlap offers links to each participant’s public Want list; no location grant required for known-place maps. Sharing group membership/context needs approved D08 policy; do not expose a recipient’s private information (none implied by public bookmarks).

### R11 — Guides, lists and sharing (S14–S17)

P Guide directory preserves several discovery modes: your custom guides, city/category-generated guides, recommendation requests, featured challenges, recently updated and most experiences; each section has See all only when functional. City chips show available guide context, not an unbounded fake taxonomy. Custom free guides are core draft scope despite paid-guide deferral.

P Guide detail: hero/title/description/owner/city/categories, viewer progress, ordered experiences, List/Map, share; rows can include author’s public note/rating with clear attribution. Editorial order is independent of viewer’s category rank. Selected marker opens same row/card identity. Empty guide prompts owner to add and gives viewers an honest empty state; missing/deleted guide gives unavailable state.

P S16 creation/edit: title required, optional description/cover/destination, add resolved experiences, reorder/remove, save draft/publish. Owner can edit metadata/order/remove guide; removal does not delete experiences/ratings/bookmarks. Adding an unvisited experience can offer “Also save to Want to Go”; proposed explicit option rather than hidden coupling. A guide can mix categories without becoming one rated experience. Generated city/category guides are derived read-only views or explicit copies; exact generation limits/rank order TBD. Collaborative roles owner/editor/viewer and request contributors must be distinguished if collaboration is included; a public viewer cannot edit merely because the link is public.

P Challenge variation: curator-owned ordered guide, viewer visited count/total, optional Join/Leave. Joining creates membership, not bookmarks/visits. Bulk save requires preview/count and can be undone without deleting pre-existing bookmarks. Progress counts distinct visited guide experiences under approved “visited” policy; repeated visits do not advance twice. Enrollment/milestone notifications optional. Rules require scope approval.

P S17 share targets: experience, profile, full list/guide, selected experiences, activity, city/globe summary. Choice between live public link and generated summary must be clear. Propose full guide/list links stay live; selected-place share creates a fixed ordered subset snapshot with source attribution, no private notes. Selection screen offers checkbox rows, count, preview and Share disabled for zero selection; preserve draft selection on native-sheet cancel. System share success is not required to save user data; opening/canceling sharing never publishes a post or changes a ranking.

P Links use stable app routes and later an approved HTTPS domain/universal-link association (domain TBD). An in-app recipient sees public payload; deleted list/user/experience gives explicit unavailable state; auth preserves target. Web landing fallback and whether nonusers can read full guides are decisions. Generated images use Roam branding, fictional fixtures in tests, accessibility text and no Beli media. Private notes and account contact details are excluded at query and serialization layers, not just visually hidden.

### R08 — Profiles, globe and travel statistics (S18–S19, S28)

P Own profile header: identity/avatar/bio/home city if chosen, public-follow counts, Edit/Share, Been/Want counts, miniature globe with unique country/city counts. Other profile: Follow/Following, Share/overflow, same public globe/stats/lists/activity/guides plus Shared wants. No owner-only controls or private memory appear. Pin/badge/country count must derive from user data, not Beli rank locks.

C Globe shows experience pins, shaded visited countries and counts on own and other profiles. P “Visited” means a persisted visit or rating linked to a MapKit experience (not a bookmark); final rule D09. Collapse repeated visits into one experience pin; city/country counts deduplicate canonical geography. Unknown geography excluded from counts with visible explanation rather than assigned arbitrarily. Pin opens experience/user visit context; city statistic opens S20; expanded globe includes list alternative and category/destination filters. Shading follows visited countries, not current device location.

TBD feasibility: MapKit’s actual 3D globe behavior on selected iOS/device, camera controls, performant polygon rendering, country-boundary source/license and semantics for disputed/remote areas. Spike before promising a renderer. If required behavior fails, surface a decision; do not silently replace confirmed globe with a static flat map.

P Statistics tabs: Activity / Travel Profile / Guides. Travel Profile includes categories, cities and countries with visit/ranked counts; score shown only where approved aggregation exists. City rows show derived personal score and category coverage. Country score formula is not confirmed: propose counts initially, no fabricated average. Count and meaningful score sort only; empty categories show no score rather than zero. Last-30-days activity and history calendar are optional proposed screens, without competitive diner percentiles.

P S28 goals/streak/achievements: optional annual distinct-experience goal, presets plus valid positive integer, saved progress and cancel confirmation. Streak measured by approved travel-appropriate cadence (TBD; weekly restaurant cadence may encourage inappropriate incentives); share card generated from actual history. Competitive member leaderboard layout now observed in addendum B37; Roam policy and release decision remain open; city quality ranking is a different concept. No 30/50-place or invite lock inherited by default.

### R07 — City insights (S20)

C Two lenses: your derived score and community derived score. No direct “rate city” button. Show seven category rows with score if available, ranked experience count, distinct contributor count for community, category coverage, overall score/confidence context and links to underlying experiences. Personal view includes only your current eligible ratings; public profile city view shows that profile owner’s permitted data, clearly labeled.

P Layout: city/region/country heading and map context; Your score / Community selection; overall score or insufficient-data state; confidence/sample explanation; category breakdown; contributing experiences filtered to selected category; featured guides and followed activity below. Do not present unapproved numeric scores as production results. Sparse/missing categories are “No ratings yet,” not zero-valued evidence.

**Exact formula intentionally deferred.** Design later must specify per-user/category contribution bounds, reviewer/category balancing, treatment of missing categories, baseline/prior, shrinkage, minimum samples, confidence display, thresholds and rounding/versioning. More independent visitors should increase confidence in a quality estimate; high or low estimated quality may be supported. It must not award score merely for being popular. Whether stronger sample evidence changes a shrunk point estimate is distinct from a popularity bonus.

Required design acceptance before shipping numeric city scores:

- A prolific reviewer cannot dominate simply by logging many experiences or revisits; repeated visits do not add independent visitors.
- A high-volume category cannot drown out the seven-category breakdown or mechanically dominate overall quality.
- A sparse city remains appropriately uncertain; zero eligible ratings yields no score, not baseline presented as measured truth.
- More independent comparable evidence tightens confidence under the selected model; contradictory evidence is allowed to lower estimated quality.
- Same inputs/version reproduce outputs; reclassification/deletion/rerank invalidates dependent aggregates; missing geography is handled explicitly.
- Fixtures compare one prolific reviewer against many independent reviewers and restaurant-heavy against category-balanced cities. Expected numeric outputs are established only after formula approval.

Canonical city assignment is an open data decision: MapKit locality aliases, metro vs municipality, day-trip localities, remote trails, border-spanning places and place corrections. Each Experience still has one place and a single approved aggregation city or explicit unresolved geography; never count it in multiple cities silently.

## R12 — Import (S27)

P Initial proposal: paste one place per line with optional destination → parse → MapKit matches → review resolved/ambiguous/unmatched rows → confirm selected matches → add Want bookmarks → summary of added/already-saved/failed. Never auto-rate imported places. Ambiguous rows require user choice; unmatched rows remain unresolved, not custom coordinates. Cancel before confirm writes nothing; batch retry deduplicates. Partial network failure produces row-level retry and accurate counts. Import source text retained only per approved retention policy.

Google Maps public-list, Foursquare and Mapstr adapters are proposed deferred pending permitted data/source feasibility; do not reproduce Beli email submission instructions. Photo/Gmail reservation imports are separately deferred proposals.

## R13 — Settings, preferences and operational safety (S26)

P Settings groups: Account; Notifications; Public profile & privacy; App; Help. Menu may additionally link home city, goals, import and preferences when enabled. Account exposes Edit profile, auth-provider-appropriate identity/recovery controls, sign out, deactivate/delete. Edit profile uses name/handle/bio/avatar/optional home city with validation; cancel changes nothing, failed save preserves edits. Destructive actions require explicit confirmation and reauthentication where supported; deletion scope/retention policy must be approved before release.

P Privacy explains public profiles/follows/bookmarks/lists under approved publication policy and owner-only notes. Include blocked/muted users and report/help entry; no private-account toggle contradicting C. Cookies/analytics choices exist only for actual integrations; no inherited third-party toggles without a service.

P Notification preferences cover follows, reactions, comments/mentions, guide contributions/invites if supported, recommendation requests, featured guides and optional reminders. Saving a setting reports failure/reverts accurately; app-level choices cannot imply OS authorization. Offer Settings link if push denied. Device token/service/APNs configuration TBD.

P App includes miles/km and haptics toggle; distance labels update consistently and settings persist across restart. Help provides searchable Roam FAQ and contact/report path; FAQ explains approved category ranking, city confidence, private notes, public lists, deletion and sharing. Loading FAQ fails recoverably; support routing TBD. Superseded/omitted features have no dead menu rows.

## Data model and relationships — proposed logical contract

Backend/storage implementation TBD. This model states relations and privacy boundaries, not a committed SQL schema or framework.

| Entity | Minimum fields and relations | Integrity / lifecycle |
|---|---|---|
| Account | auth subject, private contact/provider metadata, session state | Never returned in public profile/list APIs. |
| Profile | user ID, unique handle, display name, avatar, bio, optional home city, created date | One per account; public subset only. |
| Place | Roam ID, MapKit reference when supported, name/address/coordinate snapshot, city/country refs, source timestamps | Exactly one physical/locality identity per Experience. Canonical reconciliation strategy TBD; name alone not a stable ID. |
| Experience | ID, place ID, category, optional subtype/tags/metadata provenance | C one place; P one canonical category. Category reassignment requires explicit migration/recalculation. |
| Visit | ID, owner, experience, date/precision, companions if enabled, created time | Many visits per user/experience; date can be unknown; draft separate from persisted visit. |
| Rating | owner, experience, category, sentiment, position/tie group, nullable derived score, score availability/reason, formula version, updated time | One current per approved user/experience/category policy; atomic within category order/version. No direct city rating. |
| RankingRevision | user/category, version, committed order/change provenance | Concurrent comparisons detect stale base; migration/replay strategy TBD. |
| Bookmark | user, experience, saved time | Unique pair; no ranking/visit implied. |
| PrivateNote | user, experience or visit, text, updated time | Owner-only read/write; separate from public serialization. |
| Post | author, type, visit/experience or request ref, public note, rating snapshot, published time | Draft not public; chronological feed; deleting post does not implicitly delete rating. |
| Media | owner, storage key, caption, ordered relation to visit/post/guide, upload state | Visibility derives from approved parent; pending/orphan assets cleaned by policy. Limits TBD. |
| Follow | follower, followed, created time | Directional unique edge; no self-edge. |
| Like / Comment | actor, post, text/parent comment where relevant, timestamps | Unique actor/post like; comment author permissions; deleted parent safe handling. |
| Guide / GuideItem | owner, type, title, description, cover, destination, ordered unique experience refs, attribution | Public read proposal; owner/editor permissions; guide order independent of category rank. |
| GuideMember / Contribution | guide, user, role or recommendation, status | Optional collaboration/request rules; deduplicated contributions. |
| ChallengeMembership | user, guide, joined time | Optional; progress derived from distinct visited items. |
| City / Country | canonical IDs, localized names, geography/source version | Assignment/provenance tracked; ambiguous mapping explicit. |
| CityAggregate | city, personal-user or global scope, version, category summaries, sample/confidence metadata | Derived cache; no manual writes by users; invalidate on relevant rating/geography changes. |
| Notification | recipient, type, actor/target refs, created/read time, dedupe key | Recipient-only; respects supported preferences; no private note payloads. |
| Settings / Goal | user, units/haptics/event prefs; optional year/target | Persist deliberately; schema versioned. |
| Moderation / Report | blocker/blocked or muter/muted; reporter/target/reason/status | Access-controlled; not public profile fields. |
| ShareArtifact / ImportJob | owner, target/subset IDs and visibility; input/match/result status | Stable routes, expiry/deletion policy TBD; no credentials/private notes. |

P Memory ownership is independent of an activity Post: Visit owns public-note content/highlights/companion references and ordered Media relations; PrivateNote remains separate. A Post references or snapshots only the approved public subset. Proposed visit draft stores the same editable fields locally plus category/base ranking version, pending asset IDs and optional distribution intent. Done in a subeditor never creates a public event. Retention of a Visit allows notes/photos to survive Rating removal without requiring an orphaned Post.

P Numeric-score eligibility must be modeled separately from rank. If Roam adopts a category threshold, persist/recompute the reason a score is unavailable and display explanatory progress rather than zero. Decide whether hidden/internal scores may contribute to community/city aggregates; the draft does not silently include them. Pins and travel counts use visited eligibility, not score-unlock status. ScoreBadge, list score filtering, activity snapshots and city breakdowns must all use the same approved availability contract. A deletion that crosses an unlock threshold requires an explicit relock/retain policy before M4/M7 implementation.

P Data dependencies: rating commit/rerank/delete → category order/scores → personal experience views → personal/global city summaries → profile statistics/globe if visited eligibility changes. Follow change → feed eligibility + followed score/recs; Bookmark change → Want + shared intersections; guide edits → live link/list map; Post change → feed/profile/review surface. Derived updates must be transactionally consistent or visibly marked recalculating; do not display a new category score beside a silently stale city score as if final.

P Authorization is enforced in service/database rules, not only SwiftUI. Users write only their own ratings/visits/notes/bookmarks/posts/settings, with narrowly scoped guide roles. Public reads expose only approved fields. Server-side notifications/aggregates cannot be client-forged. Test with two unrelated accounts and a blocked pair. Backend recommendation: local Supabase for relational queries/auth/storage, then hosted deployment; **not confirmed**. Firebase/CloudKit decisions and offline design must be evaluated without reintroducing friends-only access.

## Technical choices and pre-build gates

| Choice | Status | Needed before implementation |
|---|---|---|
| SwiftUI, MapKit, XcodeGen | C | Verify available APIs/toolchain, project generation and place/globe feasibility. |
| Minimum iOS | C — iOS 18 (decided 2026-10-13) | No iOS 26-only APIs such as Liquid Glass. |
| Backend/auth/storage | Supabase local Docker recommended, not confirmed | Provider choice, public access/private-note rules, identity, migrations, test fixtures. |
| Auth methods | TBD | Sign in with Apple/email/phone and recovery flow; real SMS service if needed. |
| App identity | Roam C; bundle/team IDs TBD | Signing configuration; do not invent a Team ID. |
| Observable state, service protocols, feature folders | P | Choose with minimum OS; keep ranking/city calculations independently testable. |
| Photo limits, upload/storage, moderation | TBD | Approved limits, retention, retries, abuse/support operator. |
| Country polygons / globe renderer | P approach, feasibility unknown | Source/license and native rendering spike preserving confirmed globe goal. |
| Link domain / push / analytics | TBD | Decide only for actual features; no fake integrations. |

## Finalization checklist

Reconcile late captures into all three requested deliverables plus the evidence inventory. Resolve D01–D04 (ranking, category/revisits, publishing, lists), D06 (stack/auth/iOS), D07–D08 (release breadth/guides) and media/geography decisions. Preserve exact city formula as explicitly deferred to the scoring-design milestone; no numeric scoring ships before that gate. Confirm every proposed omission. Only after the user accepts the scope and contracts should the build begin.

## Reference reconciliation note — 302–322

Late captures now support leaderboard loading/four metric tabs/member and city filters; profile edit/name/username/bio/home-city/photo-menu forms; profile native sharing; unlock-credit hub; reservation and subscription empty management. B37–B40 record their layouts and uncertainties. Roam account forms can use these references; validation/save/upload remain proposed. Do not adopt Beli’s 80-character bio limit, username-linked URL changes, referral credits or creator eligibility thresholds without approval. S28 member board remains optional: proposed metrics are distinct experiences, recommendations, public notes and photographed experiences, with eligibility and ranking rules TBD. This paragraph records the original 01–322 boundary. The separate NC001–053 update below supersedes its onboarding/comparison gaps; numeric score reveal and publication remain pending.


## New-flow reconciliation and prioritized decisions — 2026-10-13

Reviewed all 53 new-account screenshots (`reference/beli/nc001`–`nc053`), including full-size checks of visit details, first-rank threshold, comparison controls and deletion confirmation. See the [independent per-file review and hashes](docs/roam-reference-map.md#new-account-captures-reviewed--2026-10-13) and the capture chat’s [flow addendum](docs/beli-live-capture-addendum.md); original-reference hashes remain in [the reference snapshot](docs/beli-reference-snapshot.json). The original `reference/beli/flows.md` describes the earlier account/session; its zero-ratings and missing-onboarding statements are not claims about this new session. The original reference folder remains read-only.

The inventory and gap documents now link this local-capture addendum; original-boundary statements refer only to `reference/beli/`. All 28 screen destinations and the existing discovery/social/list/globe breadth are retained.

Decisions needed, in priority order:

1. **D01 — Numeric-score policy and ranking rules:** adopt Beli's ten-per-category threshold or show a provisional score earlier? A threshold is costly for occasional travelers in Stays/Day Trips. Confirm Too tough/Skip/Undo rules, sentiment bands, first eligible score and deletion/relock behavior after the remaining reveal reference or an explicit Roam design decision. No exact city formula is needed yet.
2. **D03/D10 — Activity and memory lifecycle:** automatic activity on rating completion, a sheet-level distribution choice, or explicit later sharing? Decide defaults, companion notifications, and what survives rating/post/visit deletion. Keep private notes separate and public-profile behavior clear.
3. **D02/D04/D09 — Category, revisit and lists:** approve canonical category vs user category assignment, one current rating with repeat visits, All-view ordering, Want removal on visit, and whether retained unranked visits count on the globe.
4. **D06 — Build foundations:** choose backend, auth providers and minimum iOS; SwiftUI/MapKit/XcodeGen remain confirmed. Approve optional setup ordering and permission timing rather than importing Beli's auth assumptions.
5. **D07/D08/D12 — Breadth and release phase:** accept or revise booking/payment/referral deferrals, free guides/import/share behavior, media limits and the phases for challenges, collaborations, goals/history and member boards. New proposed adaptations include no default-selected follows and no referral/permission-pressure screens.

Exact city-score weights/formula remain deferred to M7, constrained by confirmed reviewer/category balance and sample confidence. Numeric reveal, larger comparison/undo/skip paths, photo upload, actual activity distribution, rerank completion and mutation error states remain **pending reference**. This update authorizes no implementation or live-account actions.
