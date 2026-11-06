# Roam v1 implementation specification

> The app has moved on from parts of this original v1 contract. README's "How the app works" describes it as it is,
> and the "Current product" section of `DECISIONS.md` lists what changed.

**Ready for the separate build run. Updated October 13, 2026. No implementation has started in this documentation task.** This is the app to build, with eight milestones in [MILESTONES.md](MILESTONES.md) and execution instructions in [CLAUDE.md](CLAUDE.md).

## Authority, scope and reference boundary

The latest confirmed decisions in [PLAN.md](PLAN.md) §2/§6 and the user's subsequent instructions govern scope. This document replaces the earlier broad draft. All v1 requirements below are binding build requirements. [DECISIONS.md](DECISIONS.md) distinguishes user-confirmed choices from implementation defaults selected under the user's authorization; defaults are effective now and reviewable, not a pending approval gate. Record subsequent small implementation decisions there and continue. Do not reopen confirmed decisions or add deferred features.

Reference evidence is the original Beli 01–322 screenshots and new-account nc001–nc053 in `reference/beli/`, with `flows.md`, [new-account addendum](docs/beli-live-capture-addendum.md), and [reference map](docs/roam-reference-map.md). Retain original S/R IDs for traceability. The old inventory, screen map and capture-gap documents describe evidence and the previous wider scope; they do not override this specification. References remain read-only; do not operate iPhone Mirroring.

**Observed versus designed:** onboarding, sentiment → optional visit details → Okay → pairwise comparison, Undo/Too tough/Skip controls, rank-only results and delete-rating confirmation were reviewed. Beli numeric reveal, long comparison chains, Skip/Undo effects, successful photo uploads and follower-side posting remain unobserved. Roam's immediate numeric result, tie rules, atomic save and automatic publication are explicit product/default decisions, not claims about Beli internals. Missing competitor captures no longer block this build.

### Confirmed foundation

- Native SwiftUI, minimum iOS 18, MapKit place search/maps, XcodeGen `project.yml` as project source of truth. Never hand-edit `.pbxproj`.
- Supabase locally via Docker: PostgreSQL, Auth and Storage, with migrations and server-enforced access rules. Use `supabase-swift` via Swift Package Manager; record the resolved version. Deploying hosted services is separate from the local build run.
- Sign in with Apple and email; no phone sign-in. Bundle `com.daniellarkin.roam`; signing team **H5V24G3F3D**, Somang Larkin. Never substitute personal team `6KKPN7P748`.
- Each experience resolves to exactly one MapKit place. A Day Trip is one destination/locality, never a multi-pin rated trip.
- Exactly seven independent rankings: **Food & Drink, Outdoors, Day Trips, Culture, Nightlife, Activities, Stays**.
- Scores from the first rating, displayed on a 0–10 scale with one decimal. Each completed rating automatically creates activity for followers. There is no ten-item gate, manual numeric scoring, stealth toggle or separate publish step.
- One-way follows, public profiles; own and other profiles have experience pins, shaded visited countries and unique city/country counts. Feed is reverse chronological.

### v1 boundary

| Build now | Treatment |
|---|---|
| Search and manual destination browsing | Experiences and members; nearby/manual-city map with category filters |
| Experience detail, remembering, ranking | Your score and Following score; visits, public/private notes, photos, rerank, removal |
| Been and Want to Go | Per-category rankings, All view, list/map, basic search/filter/sort |
| Social | Follow graph, public profiles, automatic rating/revisit activity, likes, flat comments, mute/block/report |
| Travel profile and globe | Categories/cities/countries as counts; pins and country shading; new experiences this year |
| Shared Want to Go | Read-only intersection with one other member; list/map |
| Account and utilities | Apple/email auth, edit profile, in-app notifications, settings, sign out/delete account |
| Limited native sharing | Experience/profile text summaries; experience includes Apple Maps URL; no hosted share pages |

**Deferred past v1:** all custom/generated/collaborative guides, curated challenges, list sharing and selected-list cards, leaderboard, imports (including paste), curated/featured/trending discovery, predicted Rec Score, taste matching, city insights and all personal/global city scores, remote push delivery, public web/universal links, contact syncing, companion tags and mentions, calendar/history views, configurable goals/streak rewards and automatic camera-roll extraction. No routes, tabs, database features or disabled placeholders for these in v1. Native text sharing is not list sharing.

**Dropped:** popular/favorite dishes and dish search, reservation/order/payment/Gmail integrations, hours editing, invite-to-unlock credits, subscriptions/paid guides and stealth mode. Do not translate these into disguised v1 features.

City-score principles remain preserved for later: derive from experience ratings, show seven-category breakdowns, balance reviewers/categories, and let more independent contributors improve confidence rather than award popularity points. The exact formula is deferred; v1 city/country rows show counts only. Keeping a city ID is geography support, not permission to build city scoring.

## R00 — Design system, state and persistence

Roam uses native navigation, sheets, SF Symbols and original travel copy/artwork. Use system typography, an accessible teal accent and sentiment green/amber/red supplemented by icons/text. Reference screen geometry and interaction hierarchy; never copy Beli's branding or real captured identities. Fictional fixtures: Maya Chen (@mayaroams), Harbor Lantern Café, Cedar Ridge Trail, Willow Bay destination, North Quay Gallery, Moonline Jazz Room, Blue Kite Workshop and Aster House, one per category. Fixture places use a test-only provider; production places must be MapKit results.

Reusable components: `RootTabBar`, `ExperienceRow`, `ScoreBadge`, `MemberRow`, `ActivityCard`, `FilterSheet`, `MapListToggle`, `SelectedPlaceCard`, `PhotoGrid/Viewer`, `EmptyState`, skeletons, inline retry and destructive confirmation. An experience row displays name, category, city/country, relevant score/source, optional rank, and distinct Save/Log actions; tapping an action never opens the row accidentally. Score labels are **You** and **Following**; a missing score is “Not rated”/“No following ratings”, not 0. Public profile lists label the owner's score explicitly.

Every collection distinguishes loading, populated, genuinely empty, filtered empty, recoverable error and pagination failure. Preserve current content on refresh failure; retry does not clear filters/scroll. Search uses 300 ms debounce, cancellation and latest-query/destination-wins results. Remote pages use 30 rows and a stable cursor; do not fetch an entire social feed to sort on device. Maps may use a bounded viewport query and cluster pins, while counts remain server-derived totals.

Bookmarks/follows/likes can update optimistically with rollback. Rating completion, notes, profile edits and destructive actions require acknowledgement before success. Every mutation has an idempotency key or a unique desired-state operation. Network loss retains drafts and explains that saving requires connectivity; no silent offline publication queue. Authenticated caches/drafts are scoped per account and cleared on sign out/deletion. Interrupted local visit drafts survive restart for up to 30 days; keep/discard on cancellation of a nonempty draft. Credentials/tokens never enter draft files or logs; secure session storage uses Keychain.

Use Dynamic Type, VoiceOver labels/focus, minimum 44-point interactive targets, contrast, Reduce Motion and accessible equivalents for map-only information. Large text may stack the comparison cards. Keyboard and sheet safe areas must leave actions reachable. Localize displayed dates; distinguish visit date from publication time. Unknown metadata is omitted or labeled, never fabricated. Score rounding is identical in client/server fixtures.

## R01 — Navigation and active screen registry

Five tabs: **Feed, Your Lists, Search, Explore, Profile**. Each has its own navigation stack and retains query/filter/scroll state during the session. Search has Experiences/Members segments. First completed onboarding enters Your Lists; subsequent authenticated launches enter Feed. Modal back/close returns to the invoker. Routes carry stable Roam entity IDs, never a display name. Auth callback uses `roam://auth-callback`; external content deep links are deferred.

| ID | Screen | Main routes |
|---|---|---|
| S01 | Welcome, auth, setup and recovery | Signed-out root → profile setup → Your Lists; cancel/error returns safely |
| S02 | Feed | Root → experience, public profile, activity detail, notifications |
| S03 | Search Experiences/Members | Root/context search → detail/profile; S04 destination |
| S04 | Destination picker | Query city/locality with region/country → returns destination |
| S05 | Explore map/list | Manual destination or location → experience detail |
| S06 | Experience detail | Search/list/feed/pin → log, revisit, rerank, notes, photos, utilities |
| S07 | Visit-photo gallery/viewer | Detail/activity → full image, owner remove or report; back |
| S08 | Log/category/sentiment | Detail/row → optional S11 details → S09 or first-item save |
| S09 | Compare | Two choices, Undo/Too tough/Skip → next comparison or completion |
| S10 | Numeric result | Saved category rank/score → Done returns to caller |
| S11 | Visit details and memory editors | After sentiment, before comparison; later edit from detail |
| S12 | Own/other Been and Want to Go | Category, filters/sort and list/map → detail |
| S13 | Filter/search/sort/category | Draft filter sheet → Apply/Cancel back to list |
| S17 | Native text share | Experience/profile action → system share; cancel returns |
| S18 | Own/other profile | Follow, lists, globe, travel breakdown, Activity, edit |
| S19 | Globe and travel breakdown | Expanded map/list; category/city/country rows filter experiences |
| S21 | Followers/following/find people | Search and follow → public profile |
| S22 | Shared Want to Go | Other profile → two-person intersection list/map |
| S23 | Activity and comments | Feed/profile/detail → author/experience, like/comment/report |
| S25 | In-app notifications | Bell → profile/activity; unavailable target handled |
| S26 | Settings/account/help | Identity, units, haptics, notifications, moderation, sign out/delete |
| S28 | New experiences this year | Profile card → this-year first-visited experiences |

S14–S16 (guides), S20 (city insights), S24 (requests) and S27 (imports) have no v1 route. Their references remain historical. S17/S28 retain only the narrowed behavior above.

## Journey A — sign in, discover and save

### R02 — Auth and setup (S01, S26)

Welcome presents Roam's travel proposition, Sign in with Apple, Continue with email and existing-account sign-in. Email uses password auth: sign-up, verify email, sign-in, forgot password, recovery callback, set new password. Minimum password length 12; maximum 128; no arbitrary composition rules. Align Auth server settings with validation. Failed login uses a generic message without exposing whether an account exists. Retry preserves email, not passwords across app restarts. Local verification/recovery emails go to the local mail viewer reported by Supabase; production SMTP is deployment configuration.

Native Apple sign-in uses AuthenticationServices, a fresh nonce and Supabase ID-token exchange. Cancel leaves the user signed out without an error alarm; invalid nonce/token fails closed. Capture Apple name on first authorization when provided; missing name goes through normal profile setup. Do not infer identity by matching public email or merge separate accounts client-side. Existing accounts restore their profile; a new account completes display name, unique handle, optional avatar and optional home destination. No phone, inviter, contacts import, reservation sync or forced follow. Display name 1–50 characters, lowercase handle 3–20 ASCII letters/digits/underscore, bio 0–160 characters. Server uniqueness/validation mirrors client rules; checking availability does not reserve the handle.

Explain that profiles, ratings and public visit notes/photos are visible to other signed-in members; private notes remain private. Optional setup can be skipped and revisited in settings. Avatar/home city never count as a visit. Persist setup checkpoint after profile creation, then show one-time Been teaching card and Log coachmark. No preselected follows. Member suggestions come from a deterministic service query, excluding self/blocked members, or show Find people when empty; never auto-follow.

Session restore uses bounded loading; failure offers retry/sign-in. Expired sessions preserve nonsensitive route intent and owner draft, but do not submit until reauthenticated. Sign-out clears local account data. Real Apple sign-in remains required even when local email fixtures are used for most tests; a mock-provider walkthrough is not provider verification.

### R06 — Search, destination and Explore (S03–S05)

Search experiences by name/query in the selected MapKit region. Default destination is last selected, then home city, then manual city choice; never pretend device location was granted. “Use current location” requests permission only on action. Denial, restricted access, timeout and approximate location retain manual destination search. Do not request background location.

Rows show name, area, known category/subtype, and separate Save/Log buttons. Existing Roam experiences include You/Following score if available. Search hits absent from Roam are resolved/upserted into Place/Experience on the first save/log action; browsing alone need not persist them. Member search matches handle/display name case-insensitively and paginates stable results with Follow state. Clear/query/no-results states remain distinct from errors.

Destination picker resolves a MapKit locality and displays region/country to disambiguate names. It changes search context only, not home city or visited counts. Explore offers manual destination/current location, category, list/map toggle, recenter when authorized, and explicit Search this area after panning. New viewport results replace rather than silently merge incompatible regions; selected pin highlights the same experience in its card/list. Known-coordinate maps and the profile globe work without location authorization. No featured guides, trending module or recommendation-request entry.

Canonical identity: one Place and one Experience per resolved MapKit place. Store available stable MapKit identifier plus Roam UUID and name/address/coordinate/geography snapshot with provenance. Verify identifier availability with the selected SDK. If an identifier is absent, reuse only an exact normalized name + full address + coordinate match (coordinates rounded to six decimals); otherwise create a distinct unresolved-for-merge record rather than merging nearby different businesses. Keep provider adapters so future reconciliation can alias duplicates transactionally. Never use name alone; no arbitrary map-pin creation. Provider metadata is optional, and storage/attribution rules must be checked during M1.

Experience category is canonical. Suggest from place metadata, let the first logger confirm one of seven before ranking; an unranked bookmark may remain Uncategorized. Once any rating exists, category is fixed in the client; “Report category issue” records a correction request rather than silently moving everyone's rankings. Day Trips resolve to the destination locality. Do not allow the same user to rank the same place under two categories.

### R04 — Experience detail and memories (S06–S07)

Hero: map/place name, category, city/country, Log or Add visit, Saved state, share and overflow. A compact header remains while scrolling. Body: You score + category position, Following score + distinct rater count, your visit history/memory actions, available factual metadata (address, website, phone and read-only hours when supported), then public visit/activity cards. Never manufacture price/hours/stock photos; no popular-dish or predicted/community-city scores.

Following score is the arithmetic mean of the latest current Rating per eligible followed user for this Experience, rounded to one decimal. Exclude self and blocked users; muting affects feed only, not score eligibility. Zero contributors shows no score. Do not weight repeat visits as extra votes. Detail score reflects current ranking; old activity score is explicitly “Score when posted”. Unfollow/rerank/removal invalidates cached following summary.

Native Maps directions, website and phone handoffs require available metadata and return unchanged on cancel. Share exports a Roam text summary with the experience's Apple Maps URL; no private notes or account contacts. Closed/missing provider listing retains historical memories and labels unavailable metadata; it must not reassign a rating to another place.

Your memory lists visits newest by visit date, unknown dates last, stable ID tie-break. Each exposes public note/photos and visit date editing; a separate **Private note** is owner-only per user/experience. Photo grid/viewer is visit media, not a dish catalogue. Other member content has report and author/activity navigation. Loading/error in media does not blank the whole detail. Report reasons: incorrect place/category, spam, inappropriate content, other, with optional text ≤1,000 characters; acknowledge a stored report, not an instant correction.

### R03 — Want to Go, Been and filters (S12–S13)

The saved list is named **Want to Go** everywhere. Bookmark is a unique user/experience pair. Save/unsave from any surface stays synchronized after acknowledgement/relaunch; it creates no visit, rating, activity or geography count. Already-rated experiences cannot be re-added to Want; show “Already been — add a visit” instead. Completing a first rating atomically removes its bookmark; cancellation/failure leaves it. Removing a rating does not recreate an old bookmark; the user can save it again once unrated.

Your Lists has Been and Want to Go only. Been defaults to All, sorted by most recent logged visit; category selection shows category rank order. All rows show category badges and scores but never a combined ordinal. Default Want order is saved date descending. Retained unranked memories are available through a **Memories without a rating** filter and labeled “Unranked”; they are excluded from ranked Been count, not discarded. Other-member lists use the same read-only controls; Save/Log acts on the viewer's own account.

Facets: category, city, country, and rated/unranked where appropriate. Text searches name and locality. Sort: category rank (single-category Been), most recent visit (Been), saved date (Want), name, distance. All-category score sorting is excluded because scores are category-relative. Missing distance sorts last; distance requests use current permission/manual reference point and state which. OR within a multi-select facet; AND across facets. Filters edit a sheet-local draft; Clear all clears draft, Apply applies, Cancel/X discards. Reset from no-results removes filters. Preserve selection/scroll on return from detail. Empty Been offers Log/Search; empty Want offers discovery, with no import CTA. Lists share no external link or card in v1.

## Journey B — log, compare, score and publish

### R05 — Ranking flow and deterministic engine (S08–S10)

Sequence: resolve experience/category → choose sentiment → optional S11 visit details → **Okay** → zero or more comparisons → atomic save → immediate numeric result → Done. First item in a sentiment partition requires no comparisons. Comparison choices retain place/category/sentiment context and show two cards with name/city. There is no separate Confirm or Publish screen. The result shows place, category, position and score, with explanation that scores change as the category list grows. Result is a Roam design because Beli's numeric reveal remains uncaptured.

One current Rating per user/Experience. Repeat visits are separate Visits under that relationship. A normal **Add visit** uses the existing score/order, allows optional details/date and atomically creates one Visit + activity without reranking. **Rank again** explicitly reruns sentiment/comparisons, excluding the current item from its old order while drafting; it updates the existing Rating, adds no new Visit and creates one rerank activity. All completed first rankings/reranks publish automatically. Repeat-visit publication is the adopted default; edits to existing notes/photos do not create new activity.

#### Ranking algorithm `roam-category-v1`

Ranking consists of three sentiment partitions in order: liked, fine, disliked. Each contains ordered tie groups. Comparisons only use this user, this category and the selected sentiment; other partitions have fixed relative order. No other person's score influences your rank.

For insertion among `g` groups ordered best to worst, begin with insertion slots `lo = 0`, `hi = g` inclusive. While `lo < hi`, compare with group `mid = floor((lo + hi) / 2)` using a deterministic representative (oldest rating in that group, UUID tie-break).

| Choice | Draft transition |
|---|---|
| Prefer new | Set `hi = mid`; continue or insert at `lo` when bounds meet |
| Prefer existing | Set `lo = mid + 1`; continue or insert at `lo` when bounds meet |
| Too tough | Join the shown tie group and finish; all group members share a score and rank |
| Skip | End comparisons and insert a new group at `floor((lo + hi) / 2)` within the remaining interval; does not mean tie. Explain “Place approximately; you can rank again.” |
| Undo | Restore previous draft bounds/decision; disabled before the first comparison decision. No committed write is undone. If completion already occurred, Rank again is the edit path. |
| Close | Keep draft or discard when nonempty; no ranking/visit/activity/bookmark write |

Normal binary insertion terminates as the interval shrinks. Skip and Too tough terminate immediately; there is no unbounded reasking. On rerank remove the old item from the draft first; remove an empty tie group; old server state remains intact until commit. Changing sentiment/category before commit rebuilds candidates and discards old comparison answers while retaining enrichment. Canonical category locking still applies.

Scores use each partition's number of **tie groups**, not member count. Sentiment bounds: liked `[6.7, 10.0]`, fine `[3.4, 6.6]`, disliked `[0.0, 3.3]`. For a partition with one group use its midpoint. For `g > 1`, group index `i` from best (0) has raw score `high - i * (high - low) / (g - 1)`. Store deterministic decimal values; display nearest tenth, halves rounded up (not binary floating-point banker's rounding). First liked = **8.4**, fine = **5.0**, disliked = **1.7**. Two distinct liked groups = **10.0 / 6.7**; three = **10.0 / 8.4 / 6.7**. Two tied liked items alone both = **8.4**. These intentionally chosen rules are not a reverse-engineering claim. A displayed 0.0 is a valid lowest disliked score; absence is null.

Rank uses competition ranking over all partitions: `1 + number of higher-ranked items`; ties yield `1, 1, 3`. Stable within-tie display order is first-rated timestamp then UUID. More members in the same tie group do not alter that group's score. Inserting/removing groups recomputes current category scores, never other categories. Existing activity snapshots remain historical. There is no minimum-count score lock and no direct numerical entry.

#### Save transaction and failure contract

The client drafts against a category revision and sends intent, ordered comparison answers, base revision, operation UUID, enrichment and uploaded asset references. A server RPC authenticates the actor, locks their category revision, validates/replays placement and computes authoritative scores. Do not trust client-provided final scores or actor IDs. First log atomically creates Visit + Rating, order/revision, activity and removal from Want. Rerank atomically replaces Rating order/scores + activity. Add visit atomically creates Visit + activity referencing the current rating. A unique `(actor, operationUUID)` returns the original success on retry. Transaction failure has no partial rank/post/bookmark effect.

Pending media uploads are outside the database transaction; only fully uploaded, owned asset references may be attached. Failed upload keeps draft editable; the user may explicitly remove failed media and retry. On stale category revision, preserve enrichment, reload current order and explain that comparisons must be refreshed; do not replay old choices against silently changed candidates. A slow request is “Saving”, not a successful score result. An uncertain response retries with the same operation UUID before offering a fresh attempt.

**Remove ranking:** own detail overflow → confirmation “Your visits, notes and photos will stay; your ranking and rating activity will be removed” → acknowledged transaction. Delete current Rating, recompute category, remove activity linked to that rating (including its reactions/comments/notifications), retain Visits/media/private notes and public memories reachable on detail/unranked filter. No automatic Want restoration. Failure/cancel leaves original state. Pins/year counts remain if retained Visits qualify. **Delete visit** is a separate confirmed action removing that Visit, its memory media and visit-linked activity. If it is the last Visit, also remove current Rating and its activity, explaining this before confirm. Delete-private-note affects only that note. Removing a post alone does not remove a Rating; the activity overflow labels this clearly.

### R10 — Details, public activity and comments (S11, S02, S23, S25)

S11 follows sentiment, before comparison: optional public note, photos and visit date, then Okay. Remove companions, guide/label editors, dishes and stealth mode from this v1 surface. Public note maximum 5,000 characters. Date defaults to today in the destination time zone when known (device zone otherwise); allow clear to Unknown and any past date, reject future completed visits. Store date-only plus source time zone/precision, not a midnight timestamp that changes date when travelling. Edits use Cancel/Done against a local visit draft. Done in a subeditor does not publish. Private note is a separate detail action, max 10,000 characters.

Use the system Photos picker; no whole-library scanning or unnecessary blanket permission. Up to six images per visit, reordering and removal before save; no video/captions in v1. Normalize orientation, strip location metadata, resize longest side to 2,048 pixels, compress JPEG to ≤3 MB per image. If constraints cannot be met, explain per asset and retain draft. Progress/retry/cancel are per asset; no media is public until attached to a committed Visit. Use owner-scoped private storage with authorized signed reads for published public media; do not put permanent public URLs in drafts. Expire unattached staged uploads after 24 hours via a documented local/hosted cleanup job; private-note content is never in media metadata.

The completion sheet states **“Your rating, public note and photos will appear on your profile and in your followers' feeds.”** Automatic publication is confirmed, not optional. Revisit/rerank activity uses an explicit type and server publication time. Notes/photos can be added or edited later; update the corresponding Visit view/activity projection without bumping `publishedAt`. Rerank activity references the most recent retained Visit (unknown-date ordering by created time) plus its rating snapshot. Removed referenced Visits delete their associated activity. Public score snapshots distinguish historical from current values.

Feed shows own and currently followed actors' activity ordered by `(publishedAt DESC, id DESC)`, excluding blocked and muted actors. Following someone includes their eligible prior history; unfollow removes it immediately. No trending, featured-guide or request cards are injected. Refresh and cursor pagination deduplicate cards; backdated visits still appear by publication time. Empty feed offers Find people/Search; populated cards show actor, action, place/category, score at posting, visit date, optional media/note, like/comment counts and Save/Log. Note expansion is inline; opening card opens S23.

S23: full note/photos, author, experience and score snapshot, counts, Like and flat comment list. One like per actor/activity; desired-state retries are safe. Comment maximum 2,000 characters, whitespace-only disabled, pinned composer above keyboard. Failed send preserves text and operation UUID. Owner can delete comment; no reply trees, tagging or comment editing in v1. Paginate chronologically with stable IDs. Other-member content can be reported. Removed/blocked target shows unavailable without leaking cached text. Author can remove activity with confirmation; Rating/Visit stays unless a separately named delete action is used. Automatic publication on new completion remains mandatory even if an earlier event was deleted.

In-app notifications: new follow, like and comment on your activity. No self-notifications or notification per follower for a routine rating; the feed carries ratings. Generate server-side from committed events with unique event keys. Unread/Earlier groups, Mark all read, read-on-open; notification tap marks one read and routes to profile/activity. Deleted source removes its notification; blocked source is hidden. Preferences govern new notifications, not deletion of earlier history. Remote push/APNs is deferred by documented default; no push-permission prompt or nonfunctional push toggle in v1.

## Journey C — people, shared wants and remembering travel

### R09 — Follow graph and shared Want to Go (S21–S22)

Follow is a directional unique pair; reject self-follow. Public profile/list read requires sign-in, not reciprocity. Counts persist; pending/error states prevent duplicate actions. Followers/following support search, no-results, empty Find people and stable pagination. Follow/unfollow does not create Visits or mutate bookmarks. Muting keeps the follow but hides feed activity; unmute restores eligible history. Block removes both follow edges, excludes either member from each other's app queries/interactions/shared wants and stops related new notifications. Unblock restores visibility, not follows. Enforce block rules server-side, not only by hiding buttons. Public here means visible to other signed-in, unblocked members; anonymous browsing is deferred.

S22 compares the viewer with exactly one public-profile owner. Display both identities and **Shared Want to Go**; intersect bookmark Experience IDs, not city or fuzzy names. Sort by most recently saved by the viewer, stable ID tie-break. Display count and list/map toggle. Empty explains that neither list is changed and offers return to their Want list. Remove/update bookmark refreshes intersection; in-flight failure keeps last results with retry. No group planning, new collaborative list, bulk save or shared link.

### R08 — Profile, globe and travel profile (S18–S19, S28)

Profile header: avatar/name/handle/bio, optional home city, follower/following counts; own Edit/Settings/Share or other Follow/overflow/Share. Show ranked Been count, Want count, mini globe and **X countries · Y cities**. Activity and Travel Profile are the two tabs. Activity reuses eligible cards; unranked memories are reachable through lists/detail. No Guides/Recs locks or leaderboard rank.

Visited means at least one persisted Visit, whether currently rated or not. Bookmarks/home destination never count. Deduplicate one globe pin per Experience and unique canonical city/country IDs; repeat visits and ties do not inflate counts. Removing the last qualifying Visit removes the pin and may decrement geographic counts. Deleting only a Rating does not erase travel history.

Use MapKit for native map interaction, zoomed-out globe, experience pins and visited-country polygon shading. Bundle a licensed low-resolution country geometry source with attribution and ISO mapping; record source/version. Mini view expands to S19; tapping a cluster zooms, pin opens experience with profile-owner context; list alternative exposes identical filtered data. Selecting category/city/country changes displayed pins/list, while header totals are labeled all-time. Do not tie globe access to current-location permission. Verify rendering in M1 before investing in profile layout; if country shading cannot render using SwiftUI Map alone, use an `MKMapView` wrapper while preserving SwiftUI app structure. Do not silently replace the globe requirement with a static illustration.

City/country assignment uses normalized provider geography with source/version. Canonical city key includes country code, administrative region and locality identifier/name so same-name cities remain distinct. For remote places with no city, include valid country and pin, omit city count with “City unavailable”. Unrecognized country boundary renders the pin without arbitrary shading. Exact provider boundary/territory mapping must be recorded; no invented city scores. Travel Profile tabs list Categories, Cities and Countries with distinct visited-experience counts, sortable count descending or name; tapping filters the owner's experiences. Zero-data states invite own Log or describe the other's empty history.

**New experiences this year** is a count, not a configurable target or streak. Count each Experience once when its earliest known Visit date falls in the device's current calendar year. Unknown dates do not count; later revisits do not count again. Show year explicitly and explain excluded unknown dates. Editing/deleting earliest Visit recomputes this metric; tapping opens that year's qualifying experiences. No achievements, leaderboard or reward notifications.

### R11 — Native text sharing (S17)

Use system share sheet from experience/profile only. Experience: Roam name, category, place/locality and Apple Maps URL; include the sharer's score only when it is their own current score and label it. Profile: display name/handle and public city/country counts as plain text. No nonexistent profile URL, hosted card, selected list, city-score share or activity-post creation. Native share cancel has no database effect. Public serialization excludes private notes, auth email, settings, report/block data and draft assets.

### R13 — Settings and account lifecycle (S26)

Settings groups: Profile (avatar/name/handle/bio/home city), Account (email/provider info, email password reset, Sign out, Delete account), Preferences (kilometres/miles; haptics), Notifications (follow/likes/comments in-app), Safety (muted/blocked members, report history receipt/support information), About/help (how ranking/ties/automatic posts work, privacy and terms information). No phone/password controls for Apple-only accounts, payment/subscription/referral rows, city-score explanation or push toggle. Profile edit validates retained fields and reports save/uniqueness/media errors; cancel does not save.

Defaults: kilometres, haptics on, all supported in-app event types on. Settings persist per user across sessions. UI-only settings apply after acknowledged save; failed write restores the previous value with retry. Blocked/muted lists have populated, empty, loading, retry and removal actions. Support/report UI stores actionable reports with operator-only access; seed/admin inspection is documented locally, but public release requires a real support/privacy/terms destination and moderation owner. Do not pretend a local report has been human-reviewed.

Sign out clears sensitive caches after session termination. Delete account requires recent reauthentication and confirmation of loss of ratings, visits, photos, follows and activity. Server-owned deletion job immediately disables new writes/visibility, revokes available sessions, deletes user-owned relational data and queues storage cleanup with durable retry; UI reports pending vs completed honestly. Apple account deletion includes the supported Apple-token revocation path, with server credentials outside the app. Published shared text cannot be recalled. Reference-account actions and real-user deletion are never part of fixture tests.

## Data model, service boundaries and authorization

Use UUID primary keys, server timestamps, foreign keys, category enum and uniqueness constraints. Migrations are authoritative; no client-only integrity rules. Do not create tables for deferred features.

| Entity | Fields / relationships | Required constraint or lifecycle |
|---|---|---|
| Auth user / Profile | Auth UUID, unique handle, display name/avatar/bio/home city, setup checkpoint | Private provider/contact data stays in Auth; public Profile exposes only approved fields |
| Place | MapKit identifier when available, snapshot, coordinate, city/country refs, provenance | Roam UUID always; exact provider identity uniqueness/reconciliation |
| Experience | unique place ID, nullable category until first rank, category source | Exactly one Place; canonical category locked after first ranking |
| City / Country | canonical key, display name, country/region identity, source version | Geography only; no score aggregate |
| Visit | owner, experience, optional date/time-zone/precision, public note, created/updated time | Many per user/experience; owned writes; deleting last Visit removes Rating |
| Rating / TieGroup | owner, experience, category, sentiment, group/order, score, firstRatedAt | Unique owner/experience; groups isolated by owner/category/sentiment |
| CategoryRevision | owner, category, version, scoring version | Compare-and-swap/lock for ranking mutations |
| MutationReceipt | actor, operation UUID, intent hash and result IDs/version | Same UUID + different payload rejected; successful retry returns original receipt |
| Bookmark | owner, experience, savedAt | Unique pair; first rating removes in same transaction |
| PrivateNote | owner, experience, text, updatedAt | Owner-only; separate query/view/serialization from public notes |
| Media | owner, visit/avatar ref, object key, order, state, size/dimensions | Only owned completed uploads attach; signed reads enforce parent visibility |
| Activity | author, type, experience, visit and nullable rating refs, category/score/rank snapshot, publishedAt | Unique source mutation; no client-chosen author/time; remove per lifecycle rules |
| Follow / Like / Comment | directional edges; actor/activity; comment text/time | Pair uniqueness, block checks and owner delete |
| Notification / Settings | recipient/event/target/readAt; persisted user preferences | Recipient-only; server-created notifications and supported event preferences |
| Block / Mute / Report | actor/target; report reason/text/status | No public exposure; reports accessible only to reporter receipt and operator |
| AccountDeletionJob | user, state, cleanup/revocation progress | Server-only execution, idempotent retries |

Service protocols isolate Auth, places, ranking, memory/media, lists, people/feed, notifications and geography from SwiftUI. Use `@Observable` feature state with async services, cancellation and `@MainActor` UI updates. Dependency injection selects fixture providers only in tests/debug; Release never fabricates MapKit or auth results. Persist nonsensitive drafts/caches in an account-scoped local store; Supabase is the source of truth for durable data.

RLS: public app data readable by signed-in unblocked members; owner's draft/private data/settings only by owner; no anonymous reads in v1. Restrict base tables so broad API selects cannot bypass block/public projections. Ranking/order/score writes must use the validated RPC, not unrestricted direct table inserts. Functions derive actor from authenticated context; fix search path, validate ownership and restrict execution. Storage read authorization follows Visit/avatar ownership and block state; signed URLs are short-lived, and block/account-delete prevents issuing new URLs. Public data cannot contain credentials or private-note joins.

Tests must exercise unrelated users, a follower, a blocked pair and anonymous callers; assert denied writes/reads through service/database APIs, not merely missing SwiftUI controls. Secrets/service-role keys never ship in the app, fixtures, repository or logs. Client uses only local/public publishable configuration protected by RLS. Privileged provisioning, account deletion/revocation and cleanup run server-side.

Derived dependencies: rating mutation → that category's current order/scores + Following summaries; Visit mutation → history, pin/city-country counts and this-year count; bookmark → Want/shared intersection; follow/block/mute → feed and visibility; public-note/media edit → corresponding detail/activity projection without new publication. Invalidate caches by revision/event; retain prior acknowledged data on error. No v1 city scoring pipeline.

## Completion and external configuration

Implement M1–M8 in order, verify each and record evidence. Missing external credentials or runtimes must be reported precisely while independent work continues; they do not authorize dropping Apple sign-in or calling mocked integration complete. Local email/integration fixtures provide most testing. Real Apple provider configuration/token exchange, country geometry licensing/rendering and iOS 18 runtime/device validation require actual evidence before claiming complete compatibility/provider support.

A local build run is not App Store deployment. Hosted Supabase/SMTP, public privacy/terms/support destinations, operational moderation and Apple revocation credentials must be configured and verified before real-user release. These are release setup tasks, not unresolved v1 product rules. Build/test command conventions and currently verified environment are in CLAUDE.md; additional small judgments go in DECISIONS.md.
