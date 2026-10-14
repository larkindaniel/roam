# M6 people, feed, interactions and notifications verification

Status: local M6 acceptance verified, October 14, 2026. M5 is preserved at `966a0d9` and `checkpoint/m5-verified-2026-10-14`. App-wide acceptance continues through M7–M8.

## Implementation boundary

Server (`20261014000800_m6_social.sql`): `feed`, `profile_activity`, `activity`, `set_like`, `comments`, `post_comment`, `delete_comment`, `followers`/`following`, `set_mute`, `set_block`, `blocked_members`, `muted_members`, `shared_wants`, `notifications`, `unread_notification_count`, `mark_notification_read` and `mark_all_notifications_read`. Every function derives the actor from the JWT. Pages are 30 rows with opaque keyset cursors. Blocks are checked inside each query; posts by blocked or deactivated authors are unavailable, not hidden by the client. Notifications are created server-side by the existing `notify()` helper (self, block, preference and event-key rules). Comment and like removal delete their notifications, and post removal cascades likes, comments and notifications.

Client: the real Supabase services replace the M1 "unavailable" stubs. The feed (S02) has cards showing author, action, place, category, area, visit date and posting time, note, photos, "Score when posted", likes, comments and the viewer's own Save/Log. S23 shows the full post, Open place, likes, a chronological comment list, a composer pinned above the keyboard, report/delete menus and the author's Remove post. Also new: S25 notifications (Unread/Earlier, Mark all read, read-on-open, safe routing); S21 followers/following (segment, literal search, paging, follow/follow-back); S18 profile identity (follow, follower/following links, Shared Want to Go, mute/block/report, member posts); and S22 Shared Want to Go (both identities, count, list/map, honest empty state). The fixture backend gained comment-conflict parity and a `comment-uncertain` lost-response scenario.

## Acceptance evidence

| Requirement | Evidence / status |
| --- | --- |
| One-way follow/unfollow, counts, no self/duplicate follow, no default follows | pgTAP follow section; integration `testFollowingExposesHistoryAndNewPostsByPublicationTime`; M2 setup has no preselected follows |
| Follower/following search, empty, filtered, loading, paging | pgTAP follow pages and literal filter; integration 30+1 pages; `FollowListModel` tests; UI `m6-07`, `m6-08`, `m6-20` |
| Following exposes earlier and new posts; `(publishedAt, id)` order; backdated by publication time; refresh/paging dedupe and keep content | pgTAP feed section (backdated, 30+7 pages, invalid cursor); integration; `FeedModel` tests; UI `m6-01` |
| Following score: one latest rating per followed member; revisits add nothing; rerank/unfollow/removal recompute; none for zero | pgTAP following-score section |
| Like desired state; flat comments keep failed text, no duplicates; deletes update counts; no replies/mentions | pgTAP likes/comments; integration; model tests (same operation retried, edited text gets a new operation); UI `m6-02`–`m6-04` |
| Mute is feed-only; block removes both edges and excludes everywhere server-side; unblock doesn't restore follows | pgTAP mute/block (profile, post, like, comment, lists, shared wants, follow, search, notifications, counts); integration block/mute; UI `m6-09`–`m6-12` |
| Shared Want to Go is the exact intersection, refreshes on changes, list/map, honest empty state | pgTAP; integration; UI `m6-13`–`m6-15` |
| In-app notifications dedupe, skip self, follow preferences, persist read state, route safely, removed targets don't leak; no push prompt | pgTAP notifications (preferences, self-like, removed like/comment, blocked actor); integration; model tests; UI `m6-05`, `m6-06`; no APNs code or prompt exists |
| Standalone post removal keeps Rating/Visit (M5 RPC, M6 UI) | UI `m6-16` then detail still shows the 10.0 ranking |
| Large text keeps actions and composer reachable | UI `m6-18`, `m6-19` (full snapshot label and area at Accessibility L) |

## Executed checks and failures retained

- The M6 migration was dry-run, and its full pgTAP file was run against the unapplied migration inside one rolled-back transaction. One wrong test expectation (followers of the viewer naturally "follow the viewer") was corrected, then 97/97 passed before the migration became immutable. Applied: `build/evidence/m6-migration-claude-20261014-112638.log`. Database **444/444** (97 new): `m6-db-first-claude-20261014-112639.log`.
- The first build failed only in the new integration test, where XCTest autoclosures contained `await` (`m6-compile-claude-20261014-112646.log`); the results were bound to locals. Clean build with no project warnings: `m6-compile-claude-20261014-112716.log`.
- Swift unit plus real backend: **240 executed, 238 passed, 2 opt-in MapKit skips** (`m6-logic-backend-claude-20261014-112740.xcresult`). It includes 6 live multi-account M6 integration tests (owner, follower, blocked/unrelated, anonymous).
- First M6 UI run: **1/9** (`m6-ui-first-claude-20261014-112839`). The screen identifier overrode `feed-list` and `notifications-list`, and test bugs left a stale member query and pressed a non-existent search Cancel. After the fixes: 7/9 (`m6-ui-claude-20261014-113157`), affected 2/2 (`m6-ui-affected-claude-20261014-113547`; the keyboard covered the tab bar, and notifications needed row-based waits). Full suite with two added journeys: **11/11** (`m6-ui-claude-20261014-113828`).
- Visual review fixes: the feed category badge wrapping, the S23 comments card width, Shared Want to Go rows (now Save/Log like Want to Go) and the Shared Want to Go map. SwiftUI `Map`, then the UIKit map, opened on empty ocean for Iceland plus New Zealand; the shared region helper now frames the densest group (`m6-ui-sharedmap-claude-20261014-143316`, plus a unit test).
- Final full run on iPhone 17 Pro: **RoamTests 241 executed, 239 passed, 2 opt-in MapKit skips, 0 failed; RoamUITests (M1–M6) 44/44 passed** (`build/results/m6-final-full-claude-20261014-143409.xcresult`, 1,230 s of UI journeys). Final database run **444/444** (`build/evidence/m6-db-final-claude-20261014-145558.log`).
- iPhone 16e M6 UI: **11/11** (`m6-ui-compact-claude-20261014-145605`). The final screenshot review then found the large-text card issue below. After the fix, the large-text journey passed on the 17 Pro (`m6-ui-largetext-claude-20261014-150016`, captures `18`–`19` re-exported) and the M6 suite passed on the 16e again, **11/11** (`m6-ui-compact-final-claude-20261014-150055`).

## Visual review

All 20 `screenshots/m6/` captures from the final run were opened and checked against S02, S18, S21–S23 and S25 in `docs/roam-reference-map.md`. Earlier reviews fixed the feed category badge wrapping, the S23 comments card width, Shared Want to Go rows, and the Shared Want to Go map opening on empty ocean. The final review found one more issue. At Accessibility L text, a feed or post card cut the snapshot label to "Score when po…" and squeezed out the place's area line. The label now wraps to three lines, and at accessibility sizes the area sits under the category (`18`, `19`).

What the final captures show:

- Feed cards with author, action, place, category, area, visit and posting time, note, photos, "Score when posted" and the viewer's own action (`01`); the optimistic like (`02`).
- A failed comment that keeps its text and says Send retries it (`03`), then the comment posted once (`04`).
- Notifications grouped Unread/Earlier, then all read (`05`, `06`); followers with Follow back/Following and literal search (`07`, `08`).
- Mute keeping profile activity while the feed drops that member (`09`, `10`); the block confirmation that names both consequences, and the feed after the block (`11`, `12`).
- Shared Want to Go as a list, a map framing the densest group, and an honest empty state (`13`–`15`).
- The Remove post confirmation that keeps the ranking (`16`); the quiet feed with Find people (`17`); large-text feed and post (`18`, `19`); the followers empty state (`20`).

The mini globe in `09` still uses the M1 whole-earth camera (a known M1 limitation), and M7 reworks the profile globe. No Beli branding or real identities appear; all people, places and photos are fictional fixtures.

## Remaining milestone boundary

M7 adds the settings API and screens (units, haptics, notification preferences), Blocked/Muted management with unblock, edit profile, sharing, the profile Activity/Travel Profile tabs, the globe and travel counts, New this year, report history and account deletion. Real Apple authorization/revocation and iOS 18 runtime validation remain outstanding external checks.
