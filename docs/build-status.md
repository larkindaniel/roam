# Roam continuation ledger

Updated October 14, 2026. Branch `codex/sol-max-handoff`. One lead (Claude) now owns every file; the earlier Codex worker lanes no longer exist. Per-milestone detail lives in `docs/m3-verification.md`, `docs/m4-verification.md` and `docs/m5-verification.md`; this ledger keeps only the current state and the exact next action.

## Milestone status

| Milestone | Status | Evidence / remaining work |
| --- | --- | --- |
| M1 | Verified checkpoint | `b7de0d8`; iOS 18 runtime validation deferred by the user |
| M2 | Verified checkpoint; real Apple authorization outstanding | `be0c4e1`; needs real Apple credentials/device |
| M3 | Verified | `f081e2e`, `checkpoint/m3-verified-2026-10-13` |
| M4 | Verified | `97da54e`, `checkpoint/m4-verified-2026-10-14` |
| M5 | Verified; committing | See `docs/m5-verification.md` |
| M6 | Drafted, not started in the tree | Drafts in `build/m6-drafts/` (git-ignored): migration `20261014000800_m6_social.sql`, pgTAP `05`, Swift services/models/views/tests |
| M7 | Pending M6 | Profile/travel/settings/account lifecycle |
| M8 | Pending M1–M7 | Combined journeys, compatibility and handoff |

## Local environment (checked October 14, 2026)

- Xcode 26.3 (17C529), XcodeGen 2.46.0, Supabase CLI 2.120.0, Docker running. Simulators: iPhone 17 Pro `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`, iPhone 16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` (iOS 26.2).
- Local stack `*_roam` restarted with `supabase stop`/`supabase start` (data kept) so the edge runtime serves `prepare-media`. Migrations applied through `20261014000700`.
- Backup before M5 migrations: `build/backups/m5-pre006-db-20261014-094945.dump` and `build/backups/m5-pre006-storage-20261014-094945/`.
- Deno is not installed; `inspector_test.ts` cases run against the live function through the Swift integration suite instead.

## M5 state

- Migrations `20261014000600_m5_memories_media.sql` (revised before applying: storage object id/eTag binding, delete policy for registered objects, `delete_activity`, `activityID` on memories) and `20261014000700_m5_visit_reports.sql` are applied and immutable.
- pgTAP **347/347** (93 new M5 assertions). Swift unit/real-backend **224 executed, 222 passed, 2 opt-in MapKit skips**. Cleanup worker unit tests 4/4 and the live deletion test pass. Full UI regression M1–M5 **33/33** (`build/results/m5-ui-full-claude-*`).
- Final: RoamTests 222 passed / 2 opt-in skips and M5 UI 8/8 on 17 Pro (`m5-final-claude-20261014-111503`), M5 UI 8/8 on the 16e (`m5-ui-compact-claude-20261014-111926`), pgTAP 347/347 (`m5-db-final-claude-20261014-111926.log`).

## Next executable action

1. If the M5 commit/tag is missing, run `git diff --check` and `scripts/check-secrets.sh`, stage the M5 files explicitly, commit "M5: …" and tag `checkpoint/m5-verified-2026-10-14`.
2. M6: move `build/m6-drafts/` into the tree, dry-run then apply the M6 migration, add fixture `comment-uncertain` and comment-conflict parity, register the new routes and `ActivityChangeStore`, then build, test, capture, review and commit as for M5.

## External checks (not local verification)

Real Apple capability/provider/token exchange and revocation need the user's credentials and a device. iOS 18 runtime validation is deferred by the user. Hosted Supabase/SMTP, the hosted cleanup schedule, public legal/support pages and operational moderation are release setup.
