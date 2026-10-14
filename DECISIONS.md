# Roam decisions

Updated October 13, 2026. This is the decision register for the v1 build. **Confirmed** means chosen by the user/PLAN; **Default** means selected under the user's instruction to settle smaller rules sensibly. Defaults are effective implementation requirements, listed here for review, and do not require another approval checkpoint. If a build discovery requires changing a default, record the reason and update SPEC/tests together. Preserve confirmed scope; do not silently substitute a feature or backend.

## Confirmed product and technical decisions

| ID | Decision | Authority / implication |
|---|---|---|
| C01 | Roam, native SwiftUI, MapKit, XcodeGen, minimum iOS 18 | PLAN §2; no generated `.pbxproj` edits or iOS 26-only UI dependency |
| C02 | Supabase local Docker for PostgreSQL/Auth/Storage | PLAN §2; public-profile and owner-private-data access rules; hosted deployment later |
| C03 | Apple + email sign-in; no phone | PLAN §2; Apple provider remains required, not replaced by email-only implementation |
| C04 | Bundle `com.daniellarkin.roam`, team `H5V24G3F3D` | User account verification and PLAN §9; never use personal team `6KKPN7P748` |
| C05 | One MapKit place per Experience; seven independent categories | PLAN §2; Day Trip is its destination/locality |
| C06 | Immediate 0–10 score from first category rating | PLAN D01; explicit difference from captured Beli ten-item lock |
| C07 | Completed ratings automatically publish notes/photos to followers | PLAN D03; no mandatory separate post composer or stealth option |
| C08 | One-way follows, public profiles; reverse-chronological feed | PLAN §1/§2 |
| C09 | Profile globe: experience pins, shaded countries, unique cities/countries | PLAN §2; other profiles show equivalent public view |
| C10 | v1 = Keep + Adapt; guides/list sharing/leaderboard/imports/curated-trending/city scores deferred | PLAN D07/§6; detailed exclusions in SPEC; eight milestones replace thirteen |
| C11 | Too tough is a tie; one rating per place with repeat Visits; rated place leaves Want | Current user instruction; no repeated-reviewer inflation or duplicate category rating |
| C12 | City-score principles preserved for later, exact math deferred | PLAN §2 with later v1 scope trim; do not implement city scoring in this run |

## Effective implementation defaults

| ID | Default | Reason / consequence |
|---|---|---|
| D01 | Three sentiment partitions; binary insertion of ordered tie groups | Preserves reviewed flow while giving deterministic Roam-owned math. Only same-category/same-sentiment comparisons; full algorithm in SPEC R05 |
| D02 | Too tough joins shown group; equal score and competition rank | Ties transitive within a group, stable oldest-first display; ranks 1,1,3. No inference about Beli's private tie engine |
| D03 | Skip ends comparisons at midpoint of remaining insertion interval, without tie | Gives a finite uncertain-choice path distinct from Too tough; user can rerank. Undo restores last uncommitted decision, disabled initially; after save use Rank again |
| D04 | Liked 6.7–10, fine 3.4–6.6, disliked 0–3.3; evenly space tie groups, singleton midpoint; Decimal half-up to one decimal | First scores 8.4/5.0/1.7; tied liked singleton group stays 8.4. Formula version `roam-category-v1`; current scores reflow, historical activity snapshots do not |
| D05 | Canonical category, confirmed by first logger and fixed after first ranking | Avoids per-user duplicate interpretations of one place; unranked bookmarks can be Uncategorized; later category problems become reports, not client mass migrations |
| D06 | Add visit keeps current score and posts visit activity; Rank again adds no Visit and posts rerank activity | One Rating per place, multiple memories; a rerank event attaches to most recent retained Visit. Editing notes/photos changes existing content without new feed timestamp |
| D07 | Remove ranking retains Visits/notes/photos/private note, removes rating-linked activity/reactions/comments; no Want restoration | Matches the reference retention wording with explicit Roam data lifecycle. Last-Visit deletion also removes Rating after distinct confirmation. Standalone activity removal leaves Rating/Visit |
| D08 | Want to Go name; cannot save currently rated item; All Been by latest visit, category Been by rank | Avoids false cross-category ordering. Unranked retained memories have a separate filter. Want defaults saved-date newest |
| D09 | Following score = equal mean of one current Rating per followed eligible user | Simple transparent experience score; not city score, popularity bonus or predicted liking. Zero data = unavailable |
| D10 | Five tabs: Feed, Your Lists, Search, Explore, Profile | Retains reference navigation; removes deferred discovery/list segments. First setup goes to Your Lists; later launch to Feed |
| D11 | Email + password with verification/recovery; optional avatar/home city; no default follows | Uses chosen providers without new SMS cost; new-account reference's preselected follows/referrals are intentionally omitted. Password min 12/max 128; handle 3–20 lowercase ASCII alphanumerics/underscore |
| D12 | Public data for authenticated unblocked members; anonymous browsing deferred | Public does not require mutual follows. PrivateNote/credentials/settings remain owner-only; block enforced server-side, not just UI |
| D13 | Public note 5,000 chars, private note 10,000, comment 2,000; flat comments with owner delete, no replies/mentions | Clear bounded implementation. Likes and comments remain v1; companions/mentions/label editors deferred to keep scope narrow |
| D14 | Up to six JPEG images, longest side 2,048px, ≤3MB each; strip location metadata; no captions/video | Manageable media v1. Stage privately, attach after upload, clean unattached files after 24h. Limits apply to actual encoded assets |
| D15 | Visit date optional, default today; date-only with timezone source, no future completed visits | Unknown travels remain loggable without fabricated dates. Retained Visits drive globe; bookmarks/home city never count |
| D16 | New experiences this year counts first known Visit date per place; no target/streak/rewards | Travel-appropriate replacement approved as Adapt; unknown dates excluded with explanation. Device current year, stored date doesn't shift with timezone |
| D17 | City/country rows are counts and filters; canonical geography keyed with region/country | Preserves globe/travel profile without pulling deferred city scoring into v1. Missing city still permits country/pin |
| D18 | Shared Want to Go is a read-only two-member bookmark intersection | Preserves adapted social planning without collaborative guides, groups or list-sharing backend |
| D19 | In-app follow/like/comment notifications; remote push/APNs deferred | Notifications are functional locally without push service setup. Paid membership availability alone did not require remote push. No push-permission prompt or fake toggle |
| D20 | Native experience/profile text sharing only; no hosted URLs/cards/list shares | Uses native sheet with Apple Maps URL for experiences; profile shares public handle/counts as text. Keeps utility small without reintroducing list sharing |
| D21 | Per-account local drafts/caches, 30-day draft expiry, online-only durable writes | No full sync queue; retries idempotent. Clear data on sign out, never mix accounts or persist credentials in drafts |
| D22 | Follow/mute/block/report and account deletion with server-owned cleanup | Public social content needs working lifecycle/access controls. Block removes both follow edges; unblock does not restore them. Real-user release needs moderation/support and Apple revocation configuration |
| D23 | Kilometres/haptics/all in-app events on; stable 30-row pagination and 300ms search debounce | Concrete consistent defaults; users can change supported preferences |
| D24 | SDK place ID when available; fallback exact normalized name/address/six-decimal coordinate match | Avoids merging different nearby businesses by name alone. Production entry must be a MapKit result; migration/aliasing required for later dedup corrections |

## Readiness and implementation-only verification

Documentation is ready for the build run. This session verified Xcode 26.3 (17C529), XcodeGen 2.46.0, xcbeautify 3.2.1, Supabase CLI 2.120.0 and the iOS 26.2 simulator. Docker CLI exists but its daemon was not running. No iOS 18 runtime is installed. These are local environment observations, not app build/test results.

Before claiming integrations complete, verify native Apple token exchange/provider configuration, the globe/polygon rendering and licensed geometry, account-deletion revocation, and an iOS 18 runtime/device. Missing configuration must be reported without replacing confirmed functionality. Hosted deployment/SMTP/legal/support/moderation remain separate release setup. No numeric city formula is needed for v1.

## Build-run decision log

Append entries here with date, affected requirement/milestone, chosen rule, reason, and test/evidence impact. Do not record secrets, reference-account contact data or routine progress as decisions. Changes to defaults must keep SPEC and acceptance tests synchronized.

| Date | Area | Decision | Reason | Evidence / tests |
|---|---|---|---|---|
| 2026-10-13 | M1 / R00 stack | `supabase-swift` pinned with `exactVersion: 2.55.3` (released 2026-09-29; 2.55.4 was released the same day as the build, so the prior patch was chosen). Transitive pins committed as `Config/Package.resolved` (copied into the generated project). | Reproducible SwiftPM resolution outside the ignored `.xcodeproj` | `Config/Package.resolved`; `docs/local-backend.md` |
| 2026-10-13 | M1 / R00 | Swift 5 language mode with minimal strict-concurrency checking; UI state uses `@Observable` + `@MainActor`, services use async/await. | Avoids Swift 6 Sendable friction with MapKit/Supabase types during the build run while keeping structured concurrency | Build log `build/evidence/build-*.log` |
| 2026-10-13 | M1 / C02 local stack | Realtime, Studio and analytics disabled in `supabase/config.toml`; data API tables are not auto-exposed (`auto_expose_new_tables = false`), so every grant is explicit in migrations. | Smaller local footprint; no implicit table exposure that could bypass block/public projections | `supabase/config.toml` |
| 2026-10-13 | M1 / R02 | Auth email templates include both the 6-digit code and the callback link; the app verifies either way. Recovery links use `roam://auth-callback/recovery`. | Codes work in the simulator without a browser hop; links still target the app | `supabase/templates/*.html` |
| 2026-10-13 | M1 / R06, D24 | MapKit returns no `MKMapItem.identifier` for localities. A locality (Day Trip destination) without an identifier is identified by its canonical city key `country|region|locality`; POIs keep D24 unchanged. | One Experience per destination locality; same-name localities in different regions stay distinct | `docs/m1-feasibility.md`; `LocalityIdentityTests` |
| 2026-10-13 | M1 / R08 globe | Globe uses an `MKMapView` wrapper with `MKImageryMapConfiguration(.realistic)` (the only configuration that renders the 3D globe), bright teal country fills, clustering, and **Flat map** + **List** alternatives in the expanded view. Initial camera fixed at 25°N 10°E because annotation views failed to render with other starting cameras on the iOS 26.2 simulator; revisit in M8. | Satisfies pins + shading + globe without a static substitute; limitation recorded honestly | `docs/m1-feasibility.md`; `screenshots/m1/05-profile-root.png`, `06-globe-expanded.png` |
| 2026-10-13 | M1 / R08 geometry | Natural Earth 1:110m Admin 0 Countries v5.1.2 (public domain), keyed by `ISO_A2_EH`; trimmed copy bundled. Small states without 1:110m polygons render pins without shading. | Licensed, low-resolution, ISO-mapped geometry | `docs/m1-feasibility.md`; `CountryGeometryTests` |
| 2026-10-13 | M1 / testing | UI journeys run in fixture mode via XCUITest (MobileBuildMCP UI automation is not enabled); screenshots are XCTest attachments exported with `scripts/export-screenshots.sh`. A Debug-only component catalogue (`-roam-component-catalog`) captures design-system states at default and accessibility text sizes. | Repeatable visual evidence without manual taps | `RoamUITests/`; `screenshots/m1/` |

