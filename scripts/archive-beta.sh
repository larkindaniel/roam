#!/bin/zsh
# Archive and export a signed beta IPA. This script does not upload it.
set -euo pipefail
cd "${0:A:h}/.."
[[ -f Config/Beta.xcconfig ]] || { print -u2 'Configure Config/Beta.xcconfig first.'; exit 1; }
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
ROAM_ARCHIVE_PATH="build/archives/Roam-$ROAM_RUN_ID.xcarchive"
ROAM_EXPORT_PATH="build/exports/Roam-$ROAM_RUN_ID"
ROAM_ASC_KEY_PATH=${ROAM_ASC_KEY_PATH:-/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8}
ROAM_ASC_KEY_ID=${ROAM_ASC_KEY_ID:-2W7C5ZMNHA}
ROAM_ASC_ISSUER_ID=${ROAM_ASC_ISSUER_ID:-1b06d6de-7ee5-409f-9a2f-e21fbd621fee}
[[ -f "$ROAM_ASC_KEY_PATH" ]] || { print -u2 'Set ROAM_ASC_KEY_PATH to the App Store Connect private key file.'; exit 1; }
mkdir -p build/evidence build/archives build/exports
./scripts/generate.sh
ROAM_SIGNING_ARGS=(-allowProvisioningUpdates -authenticationKeyPath "$ROAM_ASC_KEY_PATH"
  -authenticationKeyID "$ROAM_ASC_KEY_ID" -authenticationKeyIssuerID "$ROAM_ASC_ISSUER_ID")
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  -archivePath "$ROAM_ARCHIVE_PATH" "${ROAM_SIGNING_ARGS[@]}" archive \
  >"build/evidence/archive-$ROAM_RUN_ID.log" 2>&1 || {
    print -u2 "Archive failed. See build/evidence/archive-$ROAM_RUN_ID.log"; exit 1;
  }
xcodebuild -exportArchive -archivePath "$ROAM_ARCHIVE_PATH" \
  -exportPath "$ROAM_EXPORT_PATH" -exportOptionsPlist Config/ExportOptions.plist \
  "${ROAM_SIGNING_ARGS[@]}" >"build/evidence/export-$ROAM_RUN_ID.log" 2>&1 || {
    print -u2 "Export failed. See build/evidence/export-$ROAM_RUN_ID.log"; exit 1;
  }
print "Archive: $ROAM_ARCHIVE_PATH"
print "Signed export: $ROAM_EXPORT_PATH"
