#!/usr/bin/env bash
# Point the app at an App Services endpoint and turn on store-data sync.
#
#   ios/tools/point-at-endpoint.sh wss://<id>.apps.cloud.couchbase.com[:4984]/<endpoint> [--dry-run]
#
# The port is optional: Capella endpoints answer on 443, some also on 4984.
#
# Checks the URL's shape, checks the endpoint answers (an unauthenticated request gets 401, which
# proves it is there and online), then sets Info.plist AppServicesEndpointURL and
# TallyStoreDataSync = true. With --dry-run it checks and prints, and changes nothing.
# Only use an endpoint that links counts, catalog, locations, reviews, trucks, shipments and
# proposals (docs/deploy-store-data.md): with store-data sync on, the phone asks for all seven.
set -euo pipefail

url="${1:-}"
dry="${2:-}"
plist="$(cd "$(dirname "$0")/.." && pwd)/InventoryCount/Info.plist"

if [[ ! "$url" =~ ^wss://([A-Za-z0-9.-]+)(:[0-9]+)?/([A-Za-z0-9_-]+)/?$ ]]; then
  echo "Expected wss://<host>[:port]/<endpoint>, got: ${url:-nothing}" >&2
  exit 2
fi
host="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
endpoint="${BASH_REMATCH[3]}"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://${host}/${endpoint}/" || true)
case "$code" in
  401|200) echo "Endpoint answers (HTTP $code): https://${host}/${endpoint}/" ;;
  404)     echo "No endpoint '${endpoint}' at ${host} (HTTP 404). Check the name, and that it is online." >&2; exit 1 ;;
  503)     echo "The endpoint is offline (HTTP 503). Bring it online in Capella first." >&2; exit 1 ;;
  000)     echo "No answer from ${host}. Check the host and the network." >&2; exit 1 ;;
  *)       echo "Unexpected HTTP $code from the endpoint." >&2; exit 1 ;;
esac

current=$(/usr/libexec/PlistBuddy -c "Print :AppServicesEndpointURL" "$plist")
sync=$(/usr/libexec/PlistBuddy -c "Print :TallyStoreDataSync" "$plist" 2>/dev/null || echo "missing")
echo "Info.plist now:  AppServicesEndpointURL=$current  TallyStoreDataSync=$sync"
echo "Info.plist next: AppServicesEndpointURL=$url  TallyStoreDataSync=true"

if [[ "$dry" == "--dry-run" ]]; then
  echo "Dry run: nothing changed."
  exit 0
fi

plutil -replace AppServicesEndpointURL -string "$url" "$plist"
plutil -replace TallyStoreDataSync -bool YES "$plist"
echo "Done. Build, sign in as bob with crew store-001, and check Model & sync shows Up to date."
