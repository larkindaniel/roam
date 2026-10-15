# M7 profile globe, travel counts, settings and account lifecycle verification

Status: local M7 acceptance verified, October 14, 2026. M6 is preserved at `a1094ab` and `checkpoint/m6-verified-2026-10-14`. M8 combines the journeys and checks compatibility. Real Apple authorization/revocation and iOS 18 runtime validation remain outstanding external checks.

## Implementation boundary

Server (`20261014000900_m7_travel_settings_account.sql`):

- `travel_profile(user, year)` builds travel from persisted Visits only. It returns one pin per Experience (with first known visit date and visit count), canonical city/country rows, `placesWithoutCity`, and New this year (earliest known visit per Experience in the device's year, with an unknown-date count).
- `my_settings`/`update_settings` store per-member desired state (km/mi, haptics, in-app follow/like/comment notifications) and reject unknown keys and types.
- `create_profile` refuses tokens for removed or deactivating accounts.
- Account deletion:
  - `request_account_deletion` needs an `amr` sign-in within 10 minutes. It hides the profile, stops writes and revokes every session and refresh token at once.
  - `account_deletion_status` reports the job's state.
  - Leased service-role steps (`claim_account_deletions`, `process_account_deletion`, `refresh_account_deletion`, `fail_account_deletion`) delete the profile cascade and the auth user, strip the member from place provenance and queue their Storage folders on the M5 cleanup queue. A job completes only when the folders are empty and records Apple revocation honestly.
- `scripts/account-deletion.py` runs those steps with the media cleanup pass.

Client:

- The real Settings, Travel and Account services replace the M1 stubs. `SettingsStore` applies acknowledged settings app-wide: list distances in the chosen unit, and haptics on like, follow, save, comparisons and a saved rating.
- S26 Settings: Profile, Account (password reset for email accounts only, Sign out, Delete account), Preferences, In-app notifications, Safety (Blocked, Muted, Your reports), and About & help (ranking, privacy, terms, support).
- Edit profile has a restorable draft.
- S18 has Activity and Travel Profile tabs, Share, and Edit profile (own) or Follow/overflow/Share (others).
- Travel Profile shows New this year (S28) and Categories/Cities/Countries rows that open the filtered S19.
- S19 has filters, all-time totals, the flat map with a pin card (owner context, View place), and an equivalent list.
- Globe pins are overlay dots.
- Native text sharing for experiences and profiles.
- Delete account flow: explanation, reauthentication, confirmation, honest status, sign-out.

## Acceptance evidence

| Requirement | Evidence / status |
| --- | --- |
| Own/other profiles expose the same public travel data with the right owner controls | pgTAP "another member sees the same public travel data"; integration `seen == travel`; UI `m7-01`, `m7-09` (Edit/Settings/Share own; Follow/overflow/Share other) |
| Globe/mini globe: pins, shaded countries, X countries · Y cities, selectable pin/cluster, equivalent list, works with location denied | UI `m7-06` (globe dots and shading, launched with location denied), `m7-07` (flat map clusters), `m7-08` (list); pin card on the flat map (`globe-selected-pin`); header totals pgTAP-checked against `public_profile` |
| Geography fixtures: same-name cities, destination locality, remote/no-city, missing geometry, repeated visits | pgTAP (two Portlands, Reykjavík locality, Greenland ice cave, revisits); fixture parity test (Portland ME/OR, Greenland, Singapore has no bundled boundary, Harbor two visits); UI `m7-02` |
| Visits only; bookmarks and home city don't count; rating removal keeps counts; last Visit removal updates them | pgTAP; `testTravelCountsComeFromRealVisitsAndFollowRatingAndVisitRemoval` (real RPCs) |
| Category/city/country rows are counts and filters only; no city scores or placeholders | UI `m7-01`–`m7-04`; `TravelRow` tests; no score, confidence, guide or leaderboard UI exists |
| New this year: first known visit; date edits, revisits, unknown dates and deletions | pgTAP (revisit, earliest-date edit, unknown-only, deletion); integration (`update_visit` date edit, revisit, unknown); UI `m7-05` |
| Profile edit validates, survives restart, keeps failed edits, Cancel discards | `M7EditProfileModelTests` (lost-handle race keeps every field); UI `m7-16`–`m7-18` |
| Units/haptics/notification settings apply and roll back on failure; only supported account actions | `M7SettingsStoreTests`; pgTAP (validation, owner-only, like notifications off); integration persistence; UI `m7-12`–`m7-15`; password reset only for email accounts |
| Native shares carry public values and a real Apple Maps URL; cancel writes nothing | `M7ShareTextTests`; UI `m7-10`, `m7-11` (system sheet, Close, counts unchanged) |
| Block/mute lists, help, stored reports, sign-out; operator inspection documented | UI `m7-19`–`m7-25`; `docs/local-backend.md` "Reports and account deletion (operators)"; M2 sign-out journey in the full run |
| Deletion: reauthentication, confirmation, immediate restriction, durable cleanup, Apple status, stale tokens | pgTAP deletion section; `M7DeleteAccountModelTests`; integration (hidden, writes stop, other device's refresh fails; refresh keeps `amr`, reauth renews it); `test_account_deletion.py` live test (auth user, profile, Storage object and sessions gone; stale token can't recreate); UI `m7-26`–`m7-29` |

## Executed checks and failures retained

- Before migrating: database dump `build/backups/m7-pre009-db-20261014-150541.dump`.
- The 009 migration and its pgTAP file were dry-run together in one rolled-back transaction. The first attempt stopped at test setup: the fixture cities reused city keys that already exist in the local database. The fixture now uses fictional regions. The second attempt ran 92 of a planned 96; after two before/after assertions were added, 94/94 passed. Applied: `build/evidence/m7-migration-claude-20261014-150633.log`. Database **538/538** (94 new): `m7-db-first-claude-20261014-150634.log`.
- First compile of the M7 app code: clean, with no project warnings (`m7-compile-claude-20261014-151629.log`).
- First Swift run: a test compile error (an optional key path) in `m7-logic-backend-claude-20261014-152048`. Then **262 executed, 1 failed** (`m7-logic-backend-claude-20261014-152104`). The share test's "no other score" check matched "9.1" inside the Apple Maps coordinate `-9.1366`; it now checks the score lines themselves.
- Deletion worker: 4/4 unit tests plus the live test. The live test deleted a disposable local member end to end (auth user, profile, stored photo and sessions gone; a stale token can't recreate the profile): `m7-deletion-worker-claude-20261014-152326.log`.
- First M7 UI run: **5/10** (`m7-ui-first-claude-20261014-152553`). Causes:
  - The test's scroll helper only scrolled down.
  - The toolbar Save was queried through its wrapper element.
  - The globe list row needed scrolling.
  - The member search kept the previous query.
  - The empty-state test waited for a system search field that Roam doesn't use.

  The helpers were fixed, and a container identifier on the Travel Profile was removed. Second run: **9/10** (`m7-ui-claude-20261014-153813`). Then **10/10** (`m7-ui-claude-20261014-154402`).
- Globe probes (`m7-globe-probe-claude-20261014-153328` to `-153724`): marker views on the imagery globe were misplaced, and MapKit's coordinate conversion matched a flat projection. Globe pins became overlay dots (sized after a second probe).
- Final full run on iPhone 17 Pro (`m7-final-full-claude-20261014-193157`):
  - RoamTests: **262 executed, 260 passed, 2 opt-in MapKit skips, 0 failed**.
  - RoamUITests M1–M7: **54 executed, 53 passed, 1 failed**. The failure was a new step in the edit-profile journey: it tapped the multi-line bio field's corner, which never took keyboard focus. The step was removed (bio trimming is unit-tested), and the journey then passed on its own (`m7-ui-editprofile-claude-20261014-200005`).
- Final database run: the first attempt passed **523/538, with 15 failures** (`m7-db-final-claude-20261014-200107`). A deletion job left pending by the real-backend integration test was claimed together with the test's own job, so the test processed the wrong one. The test now parks other runs' jobs and cleanup rows inside its rolled-back transaction. With a competing pending job deliberately present it passed **538/538** (`m7-db-final-claude-20261014-200154`), and the worker then completed that disposable job.
- Workers: cleanup 4/4 and deletion 4/4 unit tests; both live tests pass (`m7-workers-final-claude-20261014-200110.log`).
- iPhone 16e M7 UI: **10/10** (`m7-ui-compact-claude-20261014-200103`).

## Visual review

All 33 `screenshots/m7/` captures from the final M7 run were opened and checked against S17–S19, S26 and S28 in `docs/roam-reference-map.md`. Roam's globe, its counts-only travel rows and New this year are adaptations, so the Beli "taste" layouts serve only as references for row and sort patterns. The review of the first run's captures found and fixed these problems:

- **Globe pins were in the wrong places.** On the 3D globe a Tokyo cluster appeared beside Greenland, and Lisbon's marker sat off Portugal. Pins are now overlay dots that sit on their countries (`06`, mini globes in `18`, `30`). Clustering, selection and the pin card are on the flat map (`07`) and in the list.
- **List rows were tinted.** Place names in the S19 list and New this year rows took the button tint. Names are now primary text (`04`, `05`, `08`).
- **City filter shading.** Filtering to a city tinted the whole country's low-resolution outline over the city map. A city filter no longer shades (`03`).
- **Large text.** Travel rows squeezed the count ("7 categories" rendered one letter per line). Rows now stack and the sort control wraps under the count (`31`).
- **Delete account.** After the request, the tab bar still offered the rest of the app. It's hidden until Done signs out (`28`, `29`).
- **Bio whitespace.** The interrupted-draft journey typed at the start of the bio, which exposed an untrimmed leading space on the profile. Name and bio are now trimmed on save, and the test types at the end.

What the final captures show:

- Travel Profile with New this year and its unknown-date note, and counts-only category rows (`01`).
- Two Portlands plus the "City unavailable" note (`02`).
- A Portland filter on the flat map and in the list, with all-time totals (`03`, `04`).
- New in 2026, newest first (`05`).
- The globe, flat map and list with Greenland's "Location unavailable"-style area and the 2-visit Harbor row (`06`–`08`).
- Another member's travel (`09`).
- The system share sheets with the profile and experience text (`10`, `11`).
- Settings, a failed save with the previous value back and Retry, the saved Miles/Haptics off, and list distances in miles (`12`–`15`).
- Edit profile validation (required name, taken handle), the restored draft and the saved profile (`16`–`18`).
- Muted and blocked lists, the unblock confirmation and the empty blocked state (`19`–`22`).
- Report history "Received, not yet reviewed" (`23`), plus How Roam works and Privacy (`24`, `25`).
- Deletion: explanation, wrong password, pending status and the signed-out notice (`26`–`29`).
- Large-text travel and settings (`30`–`32`), and the own empty travel state (`33`).

In `27`, the password field and the lower half look blank because iOS leaves secure text entry and its keyboard out of screenshots; the M2 sign-in capture `m2-13` shows the same blank password field. No Beli branding or real identities appear; all people, places and photos are fictional fixtures. Country shading uses the bundled Natural Earth data noted in M1.

## External checks and boundary

Sign in with Apple reauthentication for deletion and Apple token revocation need real Apple credentials, a device and the Apple refresh-token exchange. Locally, Apple jobs record `not_configured`, and the app says revocation didn't happen automatically. This is a release blocker, not a pass. Device validation of globe rendering is part of the iOS 18/device pass. Public privacy, terms and support destinations and a moderation owner are release setup. M8 runs the combined journeys and compatibility checks.
