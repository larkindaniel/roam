# Roam continuation ledger

Updated October 14, 2026. Branch `codex/sol-max-handoff`. One lead (Claude) owned every file through M8. **All eight milestones are locally verified.** The final handoff is `docs/m8-verification.md`, and the human quick start is `README.md`. This ledger keeps only the current state and what is still blocked.

## Milestone status

| Milestone | Status | Commit / tag |
| --- | --- | --- |
| M1 | Verified (iOS 18 runtime deferred by the user) | `b7de0d8` |
| M2 | Verified locally; **real Apple sign-in outstanding** | `be0c4e1` |
| M3 | Verified | `f081e2e`, `checkpoint/m3-verified-2026-10-13` |
| M4 | Verified | `97da54e`, `checkpoint/m4-verified-2026-10-14` |
| M5 | Verified | `966a0d9`, `checkpoint/m5-verified-2026-10-14` |
| M6 | Verified | `a1094ab`, `checkpoint/m6-verified-2026-10-14` |
| M7 | Verified; **Apple revocation outstanding** | `ea47646`, `checkpoint/m7-verified-2026-10-14` |
| M8 | Verified locally; **iOS 18 and Apple outstanding** | `b6db774` + evidence commit, `checkpoint/m8-verified-2026-10-14` |

## Final evidence (October 14, 2026)

- pgTAP **538/538** (`build/evidence/m8-db-final-claude-20261014-211327.log`).
- Full regression on the iPhone 17 Pro (`m8-final-full-claude-20261014-211218`): RoamTests **263 executed, 261 passed, 2 opt-in MapKit skips**; RoamUITests **66/66**.
- Affected reruns after the last fixes passed (`m8-affected-claude-20261014-214833`, `m8-explore-audit-claude-20261014-220053`).
- Compact iPhone 16e with Reduce Motion on: **5/5** (`m8-compact-final-claude-20261014-220136`).
- Workers (unit and live) pass. The Release and device-SDK builds succeed, with no fixture code or secrets in Release. A clean checkout of `b6db774` generates, builds and passes RoamTests in fixture mode (`m8-clean-checkout-claude-20261014-221319`).
- 21-screen accessibility audit: 0 failing findings. 19 findings with no element reference are reported as a follow-up (`docs/m8-verification.md`).

## Local environment

- Xcode 26.3 (17C529), Swift 6.2.4, XcodeGen 2.46.0, Supabase CLI 2.120.0, Docker 29.7.2, Python 3.9.6. Simulators: iPhone 17 Pro `3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`, iPhone 16e `FF96AB35-BC3B-420C-88FF-CF509F0DCEF6` (iOS 26.2; Reduce Motion left off).
- Local stack `*_roam`, with migrations applied through `20261014000900`. Applied migrations are immutable; fix forward.
- Backups: `build/backups/m5-pre006-*`, `build/backups/m7-pre009-db-20261014-150541.dump`.
- Deno is not installed; the inspector cases run against the live function through the Swift integration suite.
- Disk ran low once (about 0.5 GB free); superseded result bundles were removed. Check `df -h /` before long runs.

## If a new session resumes here

Nothing in M1–M8 is pending locally. Useful next steps, all needing the user:

1. Configure real Sign in with Apple (team `H5V24G3F3D`, bundle `com.daniellarkin.roam`): the Supabase Apple provider secret, a device build, then verify token exchange, reauthentication before deletion and token revocation (`scripts/account-deletion.py` records `not_configured` until then).
2. Run the suites on an iOS 18 runtime or device (deferred by the user).
3. Release setup: hosted Supabase/SMTP, scheduled cleanup and deletion workers, public privacy/terms/support pages, and a moderation owner.

Optional local follow-up: work out the 19 findings with no element reference in the audit (combined rows) by splitting a row's accessibility temporarily.
