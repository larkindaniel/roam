# Roam continuation ledger

Updated October 14, 2026. Branch `codex/sol-max-handoff`. One lead (Claude) owns every file; the earlier Codex worker lanes no longer exist. Per-milestone detail lives in `docs/m3-verification.md` to `docs/m6-verification.md`. This ledger keeps only the current state and the exact next action.

## Milestone status

| Milestone | Status | Evidence / remaining work |
| --- | --- | --- |
| M1 | Verified checkpoint | `b7de0d8`; iOS 18 runtime validation deferred by the user |
| M2 | Verified checkpoint; real Apple authorization outstanding | `be0c4e1`; needs real Apple credentials/device |
| M3 | Verified | `f081e2e`, `checkpoint/m3-verified-2026-10-13` |
| M4 | Verified | `97da54e`, `checkpoint/m4-verified-2026-10-14` |
| M5 | Verified | `966a0d9`, `checkpoint/m5-verified-2026-10-14` |
| M6 | Verified; committing | See `docs/m6-verification.md`; tag `checkpoint/m6-verified-2026-10-14` |
| M7 | In progress | Drafts in `build/m7-drafts/` (git-ignored): migration `20261014000900_m7_travel_settings_account.sql`, pgTAP `06_m7_travel_settings_account_test.sql` |
| M8 | Pending M7 | Combined journeys, compatibility and handoff |

## Local environment (checked October 14, 2026)

- Xcode 26.3 (17C529), XcodeGen 2.46.0, Supabase CLI 2.120.0, Docker running. Simulators: iPhone 17 Pro `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`, iPhone 16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` (iOS 26.2).
- Local stack `*_roam`. Migrations applied through `20261014000800` (M6). Applied migrations are immutable; fix forward.
- Backup before M5 migrations: `build/backups/m5-pre006-db-20261014-094945.dump` and `build/backups/m5-pre006-storage-20261014-094945/`.
- Deno is not installed; `inspector_test.ts` cases run against the live function through the Swift integration suite instead.
- Disk: the Mac's APFS container was down to about 0.5 GB free on October 14 (Preboot/OS-update snapshots and VM swap use most of it, outside this project). Unreferenced, superseded result bundles (M1/M2-era `tests-20261013-*` and probe reruns) were removed; their text logs stay in `build/evidence/`. Check `df -h /` before long runs.

## M6 final evidence

pgTAP **444/444** (`m6-db-final-claude-20261014-145558.log`). Full run on the 17 Pro: RoamTests 241 executed, 239 passed, 2 opt-in skips; RoamUITests M1–M6 **44/44** (`m6-final-full-claude-20261014-143409`). M6 UI on the 16e 11/11, and 11/11 again after the large-text card fix (`m6-ui-compact-final-claude-20261014-150055`).

## M7 plan (being implemented)

- Server (migration 009): `travel_profile(user, year)` from Visits only (pins with first known visit date, canonical city/country rows, `placesWithoutCity`, New this year with `unknownDateCount`); `my_settings`/`update_settings` (desired state); `create_profile` refuses removed or deactivated accounts; account deletion: `request_account_deletion` (needs an `amr` sign-in within 10 minutes, deactivates at once, revokes sessions and refresh tokens), `account_deletion_status`, and service-role `claim_account_deletions`/`process_account_deletion`/`refresh_account_deletion`/`fail_account_deletion` (leases, backoff, Storage cleanup via the M5 queue, Apple revocation recorded `not_configured` without credentials).
- Worker: `scripts/account-deletion.py` (claim, process, one media-cleanup pass, refresh), plus unit tests and a live test against a disposable local user.
- App: real Settings/Travel/Account services; `SettingsStore` (units, haptics, notification toggles, rollback with retry); Settings screens (Profile, Account, Preferences, Notifications, Safety with Blocked/Muted/Report history, About & help, Delete account with reauthentication); Edit profile with a restorable draft; profile Activity/Travel Profile tabs, category/city/country rows with sort and filtering, New this year (S28) and its list; expanded globe filters and the pin card; native text sharing for experiences and profiles.

## Next executable action

1. If the M6 commit/tag is missing: fill `COMPACT_FINAL` in `docs/m6-verification.md` from `build/evidence/.last-m6-compact`, run `git diff --check` and `scripts/check-secrets.sh`, stage the M6 files explicitly, commit "M6: …" and tag `checkpoint/m6-verified-2026-10-14`.
2. M7: back up the local DB (`docker exec supabase_db_roam pg_dump -U postgres -Fc postgres > build/backups/m7-pre009-db-<time>.dump`), dry-run the 009 draft and its pgTAP inside one rolled-back transaction, then move both into `supabase/` and apply with `supabase migration up --local`.

## External checks (not local verification)

Real Apple capability/provider/token exchange and revocation need the user's credentials and a device. iOS 18 runtime validation is deferred by the user. Hosted Supabase/SMTP, the hosted cleanup schedule, public legal/support pages and operational moderation are release setup.
