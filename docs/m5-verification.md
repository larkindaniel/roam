# M5 memories and media verification

Status: local M5 acceptance verified, October 14, 2026. M4 is preserved at `97da54e` and `checkpoint/m4-verified-2026-10-14`. App-wide acceptance continues through M6–M8.

## Implementation boundary

Public note, photos and an optional date are edited on the S11 details step before comparisons, and later from detail through a Visit memory editor. Editors work on account-scoped local drafts. Done sends one immutable request with an operation UUID, an uncertain response retries that exact request, and Cancel discards the draft. The owner-only private note is a separate row and editor. It is stored only in `private_notes` and never serialized into detail, memory, Visit or activity projections.

Photos come from the system `PhotosPicker` (out of process, no Photos permission). `ImageProcessor` applies orientation, strips EXIF/GPS/XMP/IPTC/comments, bounds the longest side to 2,048 px and the encoding to 3 MB, and rechecks kept bytes before upload. `PhotoDraftModel` keeps a protected per-account manifest and JPEG bytes. Each photo has its own state (processing, uploading, ready, failed) and an immutable upload attempt. A failed photo blocks saving until it is retried or removed, so a save can never claim it succeeded. An expired or server-rejected stage needs a fresh attempt, and Cancel restores the editor checkpoint.

Server: the app uploads to `<member>/<attempt>.jpg`. The `prepare-media` Edge function inspects the real bytes and registers them through service-role-only `finalize_media_inspection`, bound to the exact Storage object id and eTag. Only inspected, unexpired, owned staged photos (or photos already attached to that Visit) attach. Storage reads follow Visit visibility and blocks. Staged uploads are owner-only and expire after 24 hours. A sweep and leased worker delete orphaned and removed objects with durable retry; a cleanup row is a tombstone that prevents revival. `update_visit` edits a Visit in place, so its post's projection changes without a new `publishedAt`. `public_memories` keeps Visit-backed memories after ranking removal. `delete_activity` removes only the post.

## Acceptance evidence

| Requirement | Evidence / status |
| --- | --- |
| Details editable before comparisons and later from detail; Cancel/Done; editing never publishes | S11 photo editor journey (`m5-05`–`07`); memory editor journey (`m5-01`–`03`); `M5MemoryEditorTests` (no service call until Done); pgTAP "editing a memory publishes no new activity" |
| Interrupted drafts survive restart, owner-scoped; discard/expiry/sign-out clear them | Relaunch journey (`m5-13`); photo-draft restart, 30-day expiry and other-account tests; editor and private-note restart tests; `M5SessionCacheTests` (expiry keeps, sign-out removes) |
| Note/date limits; unknown dates; no future visits; time zone never shifts the date | pgTAP (5,000/10,000 limits, future date, unknown, Kiritimati); integration edit test; local validation tests |
| PrivateNote separate from public serialization | pgTAP (other member, direct table, detail/memories/visit text search); integration (RLS table read, `experience_detail`/`public_memories` bodies); fixture parity |
| System picker cancel, up to six, metadata stripping, 2,048 px / 3 MB | Real picker cancel and selection journey (`m5-05a`); six-photo limit test; `M5ImageProcessorTests`; live inspector rejects EXIF, truncated, non-JPEG, 2,049 px and over-3 MB uploads |
| Per-photo retry/removal; failed photo cannot be reported as saved | Fixture fault journey (`m5-05`, `m5-06`); `M5PhotoDraftTests` (failure, interrupted, expiry, server expiry, cancel checkpoint) |
| Only completed owned uploads attach; staged private; publication grants reads | pgTAP attachment and Storage read sections (foreign, uninspected, replaced, expired, blocked); integration private-until-published test |
| Orphan cleanup after 24 hours; durable retry | pgTAP cleanup section (sweep, tombstone, lease, wrong worker, backoff, completion, registered never claimed); `test_media_cleanup.py` unit tests and the live deletion test |
| Activity snapshot, completion disclosure, edits keep `publishedAt`, snapshot labelled | M4 snapshots unchanged; disclosure on details and result (`m5-07`); pgTAP/integration/fixture `publishedAt` checks; snapshot badge now reads "Score when posted" (shown with feed cards in M6) |
| Ranking removal retains memory and access; Visit deletion removes memory/media; post removal keeps Rating/Visit | pgTAP memories and post sections; integration retention and post tests; UI `m5-12` |
| Gallery/viewer loading, error, empty; reports never claim review | `m5-14a` loading, `m5-14` error/retry, `m5-10` empty after owner removal, `m5-11` receipt text |

## Executed checks and failures retained

- Before migrating: database dump `build/backups/m5-pre006-db-20261014-094945.dump` (58 tables) and Storage copy `build/backups/m5-pre006-storage-20261014-094945/`. The stack was restarted with `supabase stop`/`start` (data kept) so the edge runtime serves `prepare-media`: `build/evidence/m5-stack-restart-claude-20261014-101810.log`.
- The 006 migration was revised before it was applied: storage object id/eTag binding, a delete policy for registered objects, `delete_activity`, and `activityID` on memories. It was dry-run in a rolled-back transaction, then applied: `m5-migration-claude-20261014-101840.log`. 007 (`visit` report target) was applied with `m5-migration-007-claude-20261014-102044.log`.
- The first compile of the uncommitted Codex work failed with 7 errors in the memory editors (immutable `error` shadowing, a Section footer signature): `m5-compile-first-claude-20261014-094717.log`. After the fixes, plus splitting one view the type checker timed out on, the build was clean with no project warnings.
- First real upload smoke test: 2 failures, `m5-media-smoke-claude-20261014-102414.log`. The live inspector correctly rejected the older tests' raw `UIImage.jpegData` (EXIF APP1). Those two M2/M4 tests now upload through the app's real `ImageProcessor` preparation and pass: `m5-media-smoke-claude-20261014-102516.log`.
- pgTAP: the M2 `register_media` expectation changed to "clients cannot call it" (42501), and the M4 media fixture rows are now inspected uploads. Baseline 254/254: `m5-db-baseline-claude-20261014-102600.log`. The first M5 database run stopped after 74 passing assertions on a test-only SQL limit (a nested data-modifying CTE): `m5-db-first-claude-20261014-103244.log`. Corrected: **347/347**, including 93 M5 assertions (`m5-db-claude-20261014-103257.log`); final rerun **347/347** (`m5-db-final-claude-20261014-111926.log`).
- Swift unit plus real backend (`TEST_RUNNER_ROAM_BACKEND_TESTS=1 … -only-testing:RoamTests`): **224 executed, 222 passed, 2 skipped (opt-in live MapKit), 0 failed** (`build/results/m5-logic-backend-claude-20261014-104410.xcresult`). The 47 new M5 cases include 8 live integration tests through Storage, the Edge inspector and RLS.
- Cleanup worker: `python3 -I scripts/tests/test_media_cleanup.py` 4/4 unit tests. `ROAM_LIVE_CLEANUP=1` really deleted an aged orphan from local Storage and acknowledged its job: `m5-cleanup-live-claude-20261014-104400.log`.
- First M5 UI run: **5 passed, 3 failed** (`m5-ui-first-claude-20261014-104819.xcresult`). The gallery error/empty states rendered correctly, but the screen identifier overrode their identifiers; the system picker's remote-view cells report "not hittable". Fixes: state identifiers moved to inner containers, coordinate taps in the picker, photo-row containers, and the Done button queried directly. A premature "Finish uploading…" message during in-progress uploads was also removed. Affected reruns passed (`m5-ui-affected-claude-20261014-105250/105516/105617`).
- Full UI regression on the final source minus late layout fixes: **M1–M5 33/33 passed** in 1,035 s (`m5-ui-full-claude-20261014-105717.xcresult`).
- Final combined run after the large-text, photo-editor and gallery-caption fixes: **RoamTests 222 passed, 2 skipped, 0 failed; M5 UI 8/8** on iPhone 17 Pro (`m5-final-claude-20261014-111503.xcresult`).
- Compact iPhone 16e M5 UI run: **8/8 passed** (`m5-ui-compact-claude-20261014-111926.xcresult`).
- After the final full-width About card fix, the large-text journey was rerun on iPhone 17 Pro: **1/1 passed**; captures `15`–`17` re-exported (`m5-ui-largetext-claude-20261014-112411.xcresult`).

## Visual review

All 19 `screenshots/m5/` captures were reviewed directly. The review found and fixed three issues before the final run:

- At Accessibility L text the detail column was wider than the screen and clipped on both sides. The About section's fixed-size pills could not shrink; this predates M5 but surfaced here. The pills and the From travellers header now stack when they don't fit, and the About card spans the full width.
- "Retry upload" appeared on photos that were already ready.
- Per-photo failures were repeated in a bottom error box.

The final captures show the memory editor and private-note editor (`02`, `04`), the real system picker with ordered selection (`05a`), a per-photo failure blocking Done (`05`), retry to ready (`06`), the published result (`07`), and the gallery with its visit caption, loading, error, empty and viewer states (`08`–`10`, `14`, `14a`). They also show the honest report receipt (`11`), the retained memory after ranking removal with Unranked memory, Log and Want to Go (`12`), the restored interrupted draft (`13`) and large-text layouts (`15`–`17`). The picker says "Locations Included"; Roam's stripping happens before keeping or uploading bytes (`M5ImageProcessorTests`, live inspector). No Beli branding or real identities; all photos are fictional fixture art or the simulator's sample library.

## Remaining milestone boundary

M6 adds feed cards (which display "Score when posted"), the S23 post screen with the Remove post action that uses `delete_activity`, likes, comments, notifications and the follow graph. M7 adds profile/travel/settings/account deletion; that deletion reuses the durable media cleanup queue. Real Apple authorization/revocation and iOS 18 runtime validation remain outstanding external checks.
