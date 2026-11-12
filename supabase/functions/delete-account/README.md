# Apple account deletion endpoint

The iOS app receives a short-lived Sign in with Apple authorization code during
recent reauthentication and sends it over its authenticated Supabase connection
to `delete-account`. The function checks the caller's Apple identity, exchanges
the one-use code with Apple, starts Roam's durable account deletion job using the
caller's JWT, revokes Apple's refresh token, and records the outcome using a
service-role-only RPC. It never stores or logs the code, Apple tokens, or key.

Apple's [token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens)
and [revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens)
endpoints use a **Sign in with Apple** private key. The existing App Store Connect
API key is a different credential and cannot be substituted.

## Set up for hosted beta

1. Create a Sign in with Apple key for the primary Roam App ID in the Apple Developer portal.
2. Store the full private-key PEM and key ID as Supabase Edge Function secrets named
   `APPLE_SIGN_IN_PRIVATE_KEY` and `APPLE_SIGN_IN_KEY_ID`. Set `APPLE_TEAM_ID=H5V24G3F3D`.
   Keep the key out of Git, xcconfig, and the app bundle.
3. Apply `20261112000100_apple_revocation_result.sql` to the named `roam-beta` project using
   `scripts/deploy-beta.py`. Deploy this function to that same project, then release a new iOS build.
4. On a real iPhone, sign in with Apple, request account deletion, and confirm the Apple
   authorization is revoked. Check the deletion job reaches `completed`, media is removed,
   and the user cannot sign back into the deleted account without authorizing anew.

Until step 4 passes, this path is **implemented but not provider verified**. The
function returns 503 before starting deletion if the Apple key is absent or code
exchange fails. If Apple revocation fails after deletion starts, the job records
`failed` and the app reports that failure honestly.

Local protocol tests: `node --test supabase/functions/delete-account/apple.test.mjs`.
The database lease-race test is in `supabase/tests/06_m7_travel_settings_account_test.sql`.
