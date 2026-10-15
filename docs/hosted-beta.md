# Hosted beta

Setup completed October 14, 2026 for the user's first internal phone test with Apple sign-in.

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

Hosted media-cleanup/account-deletion scheduling and Apple token revocation remain outstanding; the
existing Python workers still intentionally reject non-loopback URLs. Real Apple sign-in and photo
upload must be verified on the phone. Support/privacy/terms destinations and moderation ownership
remain setup for a wider beta/public release. Do not represent account-deletion revocation as complete.

Signed archive/IPA verification is recorded in `apple-deployment-setup.md`. Next: upload the exported
IPA to App Store Connect, wait for processing, and add the user to internal TestFlight testing after
the user authorizes that step.
