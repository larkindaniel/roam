#!/bin/zsh
# Verifies no service-role/secret key appears in tracked files or the built app. Prints no secrets.
set -euo pipefail
cd "${0:A:h}/.."
[[ -f scripts/.fixture-env ]] || ./scripts/configure-local.sh >/dev/null
source scripts/.fixture-env
result=0
if git grep -q -F "$ROAM_SERVICE_ROLE_KEY" -- . 2>/dev/null; then echo "FAIL: service-role key found in tracked files"; result=1; else echo "ok: service-role key absent from tracked files"; fi
if git grep -q -E "sb_secret_[A-Za-z0-9_-]{10,}" -- . 2>/dev/null; then echo "FAIL: secret-format key in tracked files"; result=1; else echo "ok: no sb_secret_ keys in tracked files"; fi
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Roam.app
if [[ -d $APP ]]; then
  if grep -r -q -F "$ROAM_SERVICE_ROLE_KEY" "$APP"; then echo "FAIL: service-role key inside built app"; result=1; else echo "ok: service-role key absent from built app"; fi
  if grep -r -a -q -E "sb_secret_[A-Za-z0-9_-]{10,}" "$APP"; then echo "FAIL: secret-format key inside built app"; result=1; else echo "ok: no sb_secret_ keys in built app"; fi
fi
exit $result
