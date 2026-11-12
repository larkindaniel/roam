#!/bin/zsh
# Upload an already verified IPA; obtain the user's deployment authorization first.
set -euo pipefail
cd "${0:A:h}/.."
[[ $# = 1 && -f "$1" ]] || { print -u2 'Usage: scripts/upload-beta.sh path/to/Roam.ipa'; exit 1; }
ROAM_IPA_PATH=$1
ROAM_ASC_KEY_PATH=${ROAM_ASC_KEY_PATH:-/Users/daniellarkin/Downloads/AuthKey_2W7C5ZMNHA.p8}
ROAM_ASC_KEY_ID=${ROAM_ASC_KEY_ID:-2W7C5ZMNHA}
ROAM_ASC_ISSUER_ID=${ROAM_ASC_ISSUER_ID:-1b06d6de-7ee5-409f-9a2f-e21fbd621fee}
ROAM_RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p build/evidence
ROAM_UPLOAD_LOG="build/evidence/upload-$ROAM_RUN_ID.log"
xcrun altool --upload-app -f "$ROAM_IPA_PATH" -t ios \
  --api-key "$ROAM_ASC_KEY_ID" --api-issuer "$ROAM_ASC_ISSUER_ID" \
  --p8-file-path "$ROAM_ASC_KEY_PATH" >"$ROAM_UPLOAD_LOG" 2>&1 || {
    print -u2 "Upload failed. See $ROAM_UPLOAD_LOG"; exit 1;
  }
# altool can return zero even when its server-side validation reports failure.
if grep -Eq 'UPLOAD FAILED|ERROR:' "$ROAM_UPLOAD_LOG"; then
  print -u2 "Apple rejected the upload. See $ROAM_UPLOAD_LOG"; exit 1
fi
if ! grep -Eq 'UPLOAD SUCCEEDED|No errors uploading|successfully uploaded' "$ROAM_UPLOAD_LOG"; then
  print -u2 "Upload outcome needs inspection. See $ROAM_UPLOAD_LOG"; exit 1
fi
print "Upload accepted. See $ROAM_UPLOAD_LOG and confirm processing in App Store Connect."
