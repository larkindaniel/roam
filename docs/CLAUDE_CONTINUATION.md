# Claude continuation: Roam internal TestFlight beta

Snapshot: October 14, 2026, after the successful upload recorded in
`build/evidence/upload-20261014-225238.log`.

This handoff was written in a side conversation while deployment continued in the main chat.
Reconcile the current checkout, deployment docs, upload logs and App Store Connect before acting.
Some status below may already have advanced. Do not run two deployment agents concurrently.

## Status update (October 15, 2026)

- Build 1 (`af31e6a0-4853-4d59-8e8f-0b82daeb78ff`) processed as `VALID` and was added to the
  `Roam Internal` group (`522aa6f9-…`); internal state `IN_BETA_TESTING`. The group has 1 tester.
- Next: the user installs from TestFlight on their iPhone and runs the phone checks below.
  Nothing on the device has been verified yet.

## Objective

Finish getting Roam onto the user's own iPhone through internal TestFlight, verify real Apple
sign-in and core hosted-backend journeys, and leave an accurate continuation record.
The app's M1–M8 implementation is already locally complete. Do not restart implementation.

## Repository and reading order

- Local checkout: `/Users/daniellarkin/Desktop/projects/capstone`.
- GitHub: `https://github.com/larkindaniel/roam`.
- Branch: `codex/sol-max-handoff`.
- Last confirmed pushed commit at this snapshot: `e81f5fb`, following `b6db774`, `ea47646`,
  and `a1094ab`. Those four commits were pushed successfully in this side conversation.
- Deployment changes were subsequently present as modified/untracked files and were not yet
  included in that push. Recheck; the main agent may commit them after this snapshot.

Read these first:

1. `CLAUDE.md`, including its newer hosted-beta authorization section at the top.
2. This document, `docs/hosted-beta.md`, and `docs/apple-deployment-setup.md`.
3. `docs/build-status.md` and `docs/m8-verification.md` for implementation evidence.
4. `README.md` and `docs/local-backend.md` for local operation.
5. `SPEC.md`, `MILESTONES.md`, and `DECISIONS.md` before product or behavior changes.

`SOL_MAX_HANDOFF.md` is superseded historical material. Do not follow its old milestone plan as
unfinished work. Older local-only restrictions describe the original build run; the newer scoped
authorization in `CLAUDE.md` describes the subsequent deployment work.

## Deployment state already achieved

### Hosted Supabase

- Project: `roam-beta`, reference `xnjzuotytfzyppubjcfi`.
- Organization: Roam; Free plan; East US / North Virginia (`us-east-1`).
- Dashboard: `https://supabase.com/dashboard/project/xnjzuotytfzyppubjcfi`.
- API: `https://xnjzuotytfzyppubjcfi.supabase.co`.
- All **15** repository migrations applied, without local seed or fixture accounts.
- Private `avatars` and `visit-media` buckets exist with 3 MiB limits.
- Health RPC and rejection of anonymous profile reads were checked.
- `prepare-media` deployed; unsigned/forged sessions rejected with HTTP 401.
- Apple provider enabled for native audience `com.daniellarkin.roam`.
- Redirects: `roam://auth-callback` and `roam://auth-callback/recovery`.
- Password minimum 12; email OTP length 6 and expiry 3,600 seconds; confirmations enabled.
- Successful authenticated photo upload and real Apple sign-in still need phone verification.

Do not recreate the project, reapply existing migrations, run hosted fixture setup, or reset data.

### Apple and signing

- Team: Somang Larkin, **`H5V24G3F3D`**. Never substitute `6KKPN7P748`.
- Bundle: **`com.daniellarkin.roam`**; Sign in with Apple capability enabled.
- App name: **Roam: Places & Memories**.
- App Store Connect ID: **`6822982847`**.
- App: `https://appstoreconnect.apple.com/apps/6822982847/distribution`.
- Xcode is signed into the team; development and distribution identities were created with user
  approval. `Roam TestFlight` App Store profile was installed.
- Debug uses automatic signing. Current Release config uses **manual Apple Distribution signing**.
  Older generic automatic-signing instructions do not describe the current Release setup.
- Release now uses `Config/Release.xcconfig` -> ignored `Config/Beta.xcconfig`.
- Required privacy manifest added at `Roam/Support/PrivacyInfo.xcprivacy`.
- Release prebuild validation requires the hosted HTTPS URL and public client key.

### Archive and upload: do not upload build 1 again without checking

- First signed archive/export: `build/archives/Roam-20261014-224208.xcarchive` and
  `build/exports/Roam-20261014-224208/Roam.ipa`.
- Initial upload was rejected for iPad multitasking/orientation validation. Evidence:
  `build/evidence/upload-build-1.log`.
- The app target now explicitly sets `TARGETED_DEVICE_FAMILY: "1"` in `project.yml`, in addition
  to the global setting. A newer archive/export followed.
- Latest exported IPA observed: **`build/exports/Roam-20261014-225109/Roam.ipa`**.
- **The subsequent upload succeeded:** `build/evidence/upload-20261014-225238.log` contains
  `UPLOAD SUCCEEDED with no errors` and `No errors uploading archive`.
- Intended upload: **version 1.0, build 1**. Confirm these values in App Store Connect.
- Successful transport does not establish that Apple processing finished or that TestFlight access
  is enabled. Those are the immediate remaining checks.
- At this snapshot, the two deployment setup docs still said upload was outstanding; that prose
  lagged behind the successful upload log. Reconcile and update it after checking live status.

## Authorization and credentials

The main checkout's `CLAUDE.md` records user authorization for hosted setup, signed archive/export,
uploading version 1.0 build 1, and enabling **the user's own internal TestFlight access**.
Read current user instructions and preserve that scope. External testing, public distribution,
invitations to other people, and unrelated environments were not included.

Credential locations, not secret contents:

- Ignored `.env.beta`: project-scoped Supabase deployment token and project reference. Owner-only
  permissions were configured. Token expires **October 21, 2026**; renew if expired.
- Ignored `Config/Beta.xcconfig`: public hosted URL/client key and provisioning profile UUID.
- App Store Connect key: `/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8`.
  Key/issuer IDs and signing details are in `docs/apple-deployment-setup.md`; scripts already default
  to them. Team key role is App Manager and applies across the team's apps, so keep operations
  restricted to Roam.
- Signing private keys reside in the Mac's Keychain. If macOS prompts, the user handles the prompt;
  never request their Keychain password in chat.

Do not print, commit or copy tokens, `.p8` contents, service-role keys, `.env.beta`, local fixture
credentials, or signing private keys into logs or app config. Do not harvest unrelated credentials.
On another machine, ignored config, downloaded keys and Keychain identities will need secure setup;
a Git clone alone will not reproduce signing access.

## Immediate next steps

1. **Reconcile current state first.** Run `git status --short --branch`, inspect latest docs and
   upload evidence, and confirm another agent is no longer deploying. Preserve all existing changes.
2. **Read TestFlight processing status.** `node scripts/testflight.mjs status` is the existing
   read-only helper. Confirm version 1.0/build 1 appears for app `6822982847` and reaches `VALID`.
   If processing fails, inspect Apple's actual error before rebuilding. If still processing, avoid
   duplicate upload and excessive polling.
3. **Finish internal access.** Check for an existing `Roam Internal` internal group and its build.
   The helper supports `create-internal` and `add-build <Apple-build-resource-id>`; the resource ID
   comes from status and is not the displayed build number. Check current group relationships before
   adding anything twice. The helper does not add the user as a tester; finish that in App Store
   Connect if still needed. Resolve any actual compliance/setup prompt accurately.
4. **User installs and tests.** Have the user open TestFlight on their iPhone, accept/access the
   internal beta and install Roam. Their phone must run iOS 18+. Device interaction requires the
   user or an explicitly available, authorized device-control mechanism; never invent device results.
5. **Verify the hosted journey.** Real Apple sign-in, first profile setup, search, Want, first ranking,
   visit/photo upload, relaunch/session restore, and sign-out/sign-in. A second account is needed for
   meaningful live follow/feed/comment checks and must stay within the user's authorized test scope.
   Check that real uploads reach the private hosted buckets and inspection succeeds.
6. **Record and preserve the result.** Update deployment docs and the continuation ledger with the
   processed build, internal access state, actual device results, failures and exact remaining work.
   Review deployment source changes for secrets before committing/pushing when authorized; the push
   performed earlier did not include these later changes. Keep generated projects, build artifacts,
   credentials and local runtime files ignored.

## Existing scripts: inspect before using

| Script | Purpose / effect |
| --- | --- |
| `node scripts/testflight.mjs status` | Read groups and builds for this app. |
| `node scripts/testflight.mjs create-internal` | Create `Roam Internal` if absent. |
| `node scripts/testflight.mjs add-build <id>` | Attach a processed build to the internal group. |
| `python3 -I scripts/deploy-beta.py plan` | Read migration history; list pending local migrations. |
| `python3 -I scripts/deploy-beta.py check` | Run hosted checks; inspect implementation before use. |
| `python3 -I scripts/deploy-beta.py migrate` | Apply pending migrations to the exact beta project. |
| `node scripts/provision-beta.mjs` | Reuse/create and install the app profile using an existing identity; update ignored beta config. |
| `./scripts/archive-beta.sh` | Generate, sign, archive and export locally; does not upload. |
| `./scripts/upload-beta.sh <ipa-path>` | Upload the IPA; use only for the intended, authorized build. |

The current upload script checks log contents as well as exit status because `altool` can return
zero after a validation failure. Future uploads need a new build number after an accepted upload.
Do not execute deployment helpers merely to reproduce steps already completed.

## Known remaining work and deferred scope

- **Apple account deletion/revocation:** not complete. `scripts/account-deletion.py` records
  `not_configured` for Apple revocation. The App Store Connect upload key is a different credential
  from a Sign in with Apple server/revocation key. Complete the server token lifecycle, not just
  provider configuration, before claiming revocation works.
- **Hosted workers:** cleanup/deletion Python workers deliberately reject non-loopback URLs.
  Hosted scheduling, service credentials, retries and monitoring remain to be implemented. Preserve
  local fixture safeguards when adding explicit hosted support. Account hiding is not completed
  deletion; distinguish their observed states.
- **SMTP:** user deferred it for the first Apple-sign-in phone test. Before email testers, configure
  a sender/SMTP and the confirmation/recovery templates under `supabase/templates/`, then test
  delivery, six-digit codes and deep links. Do not treat local Mailpit success as hosted email proof.
- **Auth management permissions:** scoped token cannot PATCH Auth config without additional
  `project_admin_write`; existing settings were saved through the dashboard. Do not broaden token
  permissions automatically.
- **Wider release:** hosted privacy/terms/support destinations and moderation owner are outstanding.
- **Minimum OS:** deployment target is iOS 18, but runtime validation was performed on iOS 26.2.
  User explicitly deferred iOS 18 runtime installation/testing; do not download it unprompted.
- **Accessibility:** 19 audit findings lack element references and remain an optional follow-up.

## Verified implementation baseline

These are prior recorded results, not tests rerun by this handoff:

- pgTAP: **538/538**.
- Main full regression: RoamTests **263 executed, 261 passed, 2 opt-in MapKit skips**;
  RoamUITests **66/66**. Affected reruns and compact iPhone 16e checks passed as documented.
- Worker unit/live tests passed against the local backend.
- Release and unsigned device-SDK builds passed; a later signed archive/export was also verified.
- Clean-checkout fixture tests passed with explicitly documented integration/MapKit skips.
- Final accessibility audit reports 0 failing findings under its documented exception accounting;
  do not erase the unresolved 19 findings described above.

See `docs/m8-verification.md` for evidence and caveats. Do focused verification for new deployment
changes; broad reruns are warranted by behavior changes or unresolved failures, not merely resumption.

## Working conventions

- Edit `project.yml`; regenerate with `./scripts/generate.sh`. Never hand-edit `.pbxproj`.
- Applied migrations are immutable; fix forward. Fixture commands and resets remain local-only.
- Keep native Apple sign-in, seven separate category rankings, and the globe.
- No new guides, imports, leaderboard, city scores, curated discovery, list sharing or remote push.
- Preserve reference material, unrelated work and existing dependency pins.
- Local startup/build commands are in `README.md`. Recheck tool versions and available simulators.
- Check `df -h /` before large test/archive runs; disk space ran low during M8.
- Report exact observed progress and specific external blockers. Do not call a successful archive,
  uploaded binary, fixture auth path or simulator run a successful installation on the user's phone.
