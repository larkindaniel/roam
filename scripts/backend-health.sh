#!/bin/zsh
# Health check for this project's local Supabase stack. Prints no secrets.
set -euo pipefail
cd "${0:A:h}/.."
[[ -f scripts/.fixture-env ]] || ./scripts/configure-local.sh >/dev/null
source scripts/.fixture-env
echo "Containers:"
docker ps --format '  {{.Names}}\t{{.Status}}' | grep '_roam' || { echo "  none running"; exit 1; }
echo "Auth health:"
curl -fsS "$ROAM_API_URL/auth/v1/health" -H "apikey: $ROAM_PUBLISHABLE_KEY" | sed 's/^/  /'; echo
echo "Database health RPC:"
curl -fsS -X POST "$ROAM_API_URL/rest/v1/rpc/roam_health" -H "apikey: $ROAM_PUBLISHABLE_KEY" -H "Content-Type: application/json" -d '{}' | sed 's/^/  /'; echo
echo "Storage health:"
curl -fsS -o /dev/null -w "  HTTP %{http_code}\n" "$ROAM_API_URL/storage/v1/version" -H "apikey: $ROAM_PUBLISHABLE_KEY"
