# Hosted beta

Setup completed October 14, 2026 for the user's first internal phone test with Apple sign-in.

## November 6, 2026 update

Build 5, combining Kieran's product overhaul with the beta configuration and fixes, was signed,
uploaded, processed as valid, and added to the existing `Roam Internal` TestFlight group. Its build
ID is `f108055e-e52f-48d3-a957-b61a0177e3e4`. Existing internal testers can update in TestFlight.

The overhaul's 34 migrations (`20261101000100` through `20261106000100`) were applied to this
project. The remote now has 50 migration history entries; `plan` reports none pending and `check`
passes. `google-place` was deployed and is active alongside `prepare-media`. The new
`friends_feed()` RPC is present. Existing one-way follows became pending friend requests as designed:
the beta has six mutual follow edges and three pending requests after migration.

No `GOOGLE_PLACES_KEY` is set on the hosted function. It safely returns a fallback, so Google photos
and ratings are unavailable until a server-side Places API (New) key is configured. Do not put that
key in the iOS app. The refreshed project-scoped deployment token is in the ignored `.env.beta` and
expires according to its Supabase token settings.

## Target and access

- Organization: Roam, Free plan (`hhcmlcedfqllxefntitp`).
- Project: `roam-beta`, reference `xnjzuotytfzyppubjcfi`.
- Region: East US (North Virginia), `us-east-1`, selected during project creation.
- Dashboard: https://supabase.com/dashboard/project/xnjzuotytfzyppubjcfi
- Public API: https://xnjzuotytfzyppubjcfi.supabase.co
- The user generated/saved the database password and submitted project creation themselves.
- Deployment token: `Roam beta deployment`, restricted to this project, expires after 7 days
  (October 21, 2026). Stored in Git-ignored `.env.beta` with owner-only file permissions.
- Token permissions: read project settings and API keys/secrets; read-write Database, Migrations,
  Auth Config and Edge Functions. No account-wide project access was granted.

Do not log or commit `.env.beta` or private keys. The project's public client settings live in ignored
`Config/Beta.xcconfig`, required by `Config/Release.xcconfig`. Debug keeps its local configuration.

## Deployed and verified

All 15 repository migrations were applied without fixture/seed data. Migration SQL and original
version/name/statements history entries committed together via the Management SQL API. The private
history structure remains compatible with CLI migration history. Future deployments refuse unknown
remote versions rather than reapplying or resetting them.

Both `avatars` and `visit-media` are private, with 3 MiB limits. The public health RPC responds.
Anonymous profile reads are rejected. `prepare-media` is deployed, and unsigned/forged sessions
receive HTTP 401. A successful authenticated photo upload still needs device/integration verification.

Auth settings saved through the dashboard:

- Site URL: `roam://auth-callback`.
- Exact redirects: `roam://auth-callback`, `roam://auth-callback/recovery`.
- Native Apple provider enabled for `com.daniellarkin.roam`; no web OAuth secret configured.
- Minimum password length 12; email OTP length 6; expiry 3,600 seconds.
- Email confirmation enabled; anonymous sign-in and manual identity linking disabled.

The Management Auth PATCH endpoint unexpectedly also requires `project_admin_write`; the scoped token
was deliberately not expanded. Perform future Auth configuration changes in the dashboard unless the
user approves a token with that additional permission. Read-back verification works with this token.

## Repeatable commands

```sh
python3 -I scripts/deploy-beta.py plan
python3 -I scripts/deploy-beta.py migrate
python3 -I scripts/deploy-beta.py check
set -a
source .env.beta
set +a
supabase functions deploy prepare-media --project-ref "$SUPABASE_PROJECT_REF" --use-api
node scripts/provision-beta.mjs
./scripts/archive-beta.sh
```

The migration helper checks the exact named project. Do not add seed/reset operations. The archive
script exports locally without uploading. Increase the build number for subsequent uploads.

## Explicitly deferred / remaining

The user chose Apple sign-in for the first phone test and deferred SMTP. Supabase's free sender is
restricted to organization team addresses, and custom email templates require custom SMTP or a paid
upgrade. Confirmation/recovery templates in `supabase/templates/` have therefore not been applied to
the hosted email service. Do not invite email testers until delivery and templates are configured.

Apple token revocation was deployed on November 12 (`delete-account` function, its migration and the
Sign in with Apple key secrets) and ships in build 7; a real-device deletion test is still pending.
Hosted media-cleanup/account-deletion scheduling runs from `.github/workflows/roam-maintenance.yml`
once it is on `main` with the `ROAM_BETA_SERVICE_ROLE_KEY` secret. Support, privacy and terms are
published at https://larkindaniel.github.io/roam-site/ (source in `site/`).

Signed archive/IPA verification is recorded in `apple-deployment-setup.md`. Build 5 is available to
the existing internal TestFlight tester. Additional testers require their own App Store Connect access
and invitations; real-device behavior is still to be verified.
