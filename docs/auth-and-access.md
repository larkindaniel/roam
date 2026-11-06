# Authentication and access control (M2)

## Providers

| Path | Status in this build run |
|---|---|
| Email + password (sign-up, 6-digit email code or link, sign-in, forgot password, recovery code or link, set new password) | **Verified against local Supabase** (`RoamTests/Integration/M2AuthIntegrationTests`, codes read from the local Mailpit viewer) and in fixture UI journeys (`RoamUITests/M2AuthUITests`). |
| Native Sign in with Apple (AuthenticationServices, SHA-256 nonce, Supabase `signInWithIdToken`) | **Implemented, not verified with a real Apple account.** Local Auth has the Apple provider enabled with `com.daniellarkin.roam` as the allowed audience. An invalid identity token fails closed (tested). Cancelling leaves the member signed out with no alarm; a first-authorization name pre-fills setup; a missing name falls back to normal setup. |

### Apple sign-in: exact remaining external steps (needs the account holder)

1. In the Apple Developer account for team **H5V24G3F3D**, enable the *Sign in with Apple* capability on App ID
   `com.daniellarkin.roam` (the app's entitlements already request it).
2. Build and run a **signed** build (automatic signing, team H5V24G3F3D) on a device or simulator that is signed in
   to an Apple ID. Unsigned simulator builds (`CODE_SIGNING_ALLOWED=NO`) cannot complete Apple authorization.
3. For a physical device, point the app at a reachable development API (the device cannot use the Mac's loopback).
4. For account-deletion token revocation and any web OAuth flow, create a Sign in with Apple key and configure the
   provider secret server-side (`[auth.external.apple].secret` via environment, never committed or shipped).

No mock or fixture path is reported as an Apple sign-in success; fixture mode explicitly refuses Apple sign-in.

## Email details

- Password length 12–128 (server `minimum_password_length = 12`; client checks the same bounds). No composition rules.
- Failed sign-in shows one generic message whether or not the account exists (tested). Reset requests never reveal
  whether an address has an account.
- The last typed email is remembered on the device; passwords never are.
- Recovery links target `roam://auth-callback/recovery`; codes/links expire after one hour; replayed or forged codes
  fail without creating a session (tested).
- Local email goes to the Supabase mail viewer (`MAILPIT_URL` from `supabase status`). Production SMTP is deployment
  configuration and is required before release.

## Sessions

- Sessions are stored in the Keychain by the Supabase client (`KeychainLocalStorage`, service `com.daniellarkin.roam.auth`).
- Restore is bounded (12 s) and falls back to Retry / Sign in again.
- Expired session: drafts stay on disk scoped to that account; nothing submits until sign-in; a different member never
  sees them. Explicit sign-out deletes the account's local drafts and caches.

## Database access model

- Every public table has RLS. `anon` has **no** table privileges; `authenticated` has **SELECT only** (TRUNCATE/TRIGGER/
  REFERENCES revoked). All writes go through `security definer` RPCs that derive the actor from the JWT, fix
  `search_path`, validate input and check ownership/blocks.
- Visibility helper `app_private.can_see_member` hides deactivated members and blocked pairs (either direction) from
  every public read: profiles, visits, ratings, bookmarks, activities, follows, likes, comments.
- Owner-only: private notes, settings, notifications, category revisions, blocks/mutes, own reports. Profiles expose
  only public columns through column grants; setup/deactivation fields are owner-only via `my_profile()`.
- Storage buckets `visit-media` and `avatars` are private (JPEG, ≤3 MB). Uploads only into the caller's own folder;
  reads follow the parent (attached visit media or current avatar of a visible member); blocked members and
  deactivated accounts cannot read. Media must be registered after upload (`register_media` checks the stored object
  exists, is JPEG, ≤3 MB and owned) before it can be attached.
- Tests: `supabase/tests/01_m2_access_test.sql` (41 assertions: anonymous, owner, follower, unrelated, blocked) and
  REST-level checks in `M2AuthIntegrationTests`.

## Fixture accounts (local only)

`scripts/fixtures/setup.py` creates six fictional members (maya, theo, priya, jonas, lena, sam `@roam.test`, password in
the script) through the local Auth admin API using the service key from the ignored `scripts/.fixture-env`, then builds
profiles and follows through the same RPCs the app uses and loads fictional places/memories with SQL. It refuses to run
against a non-loopback API.
