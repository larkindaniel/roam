# Apple deployment setup

Verified through Xcode and Apple's web portals on October 14, 2026.

## App and account

- Team: Somang Larkin, `H5V24G3F3D`.
- Apple Developer Program: individual membership; renewal September 27, 2027.
- Xcode is signed in with Admin access to this team and Certificates, Identifiers & Profiles access.
- Bundle ID: `com.daniellarkin.roam`, registered with Sign in with Apple enabled as a primary App ID.
- App Store name: **Roam: Places & Memories** (chosen by the user).
- App Store Connect app ID: `6822982847`.
- App record: https://appstoreconnect.apple.com/apps/6822982847/distribution
- Platform: iOS; primary language: English (Canada); SKU: `roam-ios`.

## Signing and upload credentials

The user explicitly approved creating Apple Development and Apple Distribution signing certificates
on this Mac. Both identities appeared in Xcode's Manage Certificates panel.

The user subsequently approved creation/installation of the `Roam TestFlight` App Store profile
for this bundle ID and team. UUID: `09c716cf-52d2-4bbc-bb19-98a8f9736ead`.
Release uses manual distribution signing; Debug retains automatic development signing.
`scripts/provision-beta.mjs` reuses a valid profile or creates one using a matching existing local
distribution identity. It does not create or revoke certificates.

Signed archive and IPA export were verified on October 14, 2026:

- Archive: `build/archives/Roam-20261014-224208.xcarchive`.
- IPA: `build/exports/Roam-20261014-224208/Roam.ipa`.
- Version 1.0, build 1; bundle and team match the app record.
- `codesign --verify --deep --strict` passed for the exported app.
- Signature authority: Apple Distribution: Somang Larkin (H5V24G3F3D).
- Hosted beta URL/public client key and required privacy manifest are bundled; Debug networking
  exceptions are absent.

On first command-line signing, macOS may ask the user for their login Keychain password to allow
`codesign` to use the private key. The user handled this prompt; do not request their password in chat.

The user approved Apple's API usage terms and generation/download of this dedicated team API key:

- Name: `Roam TestFlight Deploy`.
- Role: App Manager. This team key applies across all apps on the team and persists until revoked.
- Key ID: `2W7C5ZMNHA`.
- Issuer ID: `1b06d6de-7ee5-409f-9a2f-e21fbd621fee`.
- Private key download location on this Mac: `/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8`.
- Chrome showed the download as Done (257 bytes), and Finder confirmed the file location.

The private key's contents were not read or copied into the repository. Keep the `.p8` in secure local
storage and back it up securely: Apple permits only one download. This App Store Connect key is
separate from any Sign in with Apple server/revocation key. No such revocation key was created here.

## November 6, 2026 TestFlight update

Version 1.0 build 5 was archived from the merged product overhaul and beta source, exported as a
signed 9.9 MiB IPA, and passed `codesign --verify --deep --strict`. Apple accepted the upload, marked
the build `VALID`, and the build was attached to the `Roam Internal` group. Build ID:
`f108055e-e52f-48d3-a957-b61a0177e3e4`. The archive and export were generated in an isolated
temporary checkout; their locations were not committed. Real-device verification remains outstanding.

Hosted backend deployment status is recorded in `docs/hosted-beta.md`.

Do not substitute another Apple team. Keep private signing material out of xcconfig files, app bundles,
Git, screenshots and logs.
