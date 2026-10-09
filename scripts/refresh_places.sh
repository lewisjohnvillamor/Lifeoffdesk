#!/usr/bin/env bash
# Re-download every named place (shops, sports, landmarks, food, cafés, parks…) for the detailed
# regions from OpenStreetMap (new cities: Parañaque, Pasay, Taguig, with streets), rebuild the packs and demo walks,
# and run the tests. Needs internet once; the app itself stays offline.
# Usage: scripts/refresh_places.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENDPOINTS=(https://overpass-api.de/api/interpreter https://overpass.private.coffee/api/interpreter
           https://overpass.kumi.systems/api/interpreter https://maps.mail.ru/osm/tools/overpass/api/interpreter)
# Existing packs refresh places only (roads kept); new cities download streets + places once.
for region in makati-cbd-starter muntinlupa paranaque pasay taguig; do
  dir=$(python3 -c "import json;print([r['localDir'] for r in json.load(open('config/regions.json'))['regions'] if r['id']=='$region'][0])")
  mode=--places-only
  [ -f "local-data/$dir/roads.geojson" ] || mode=""
  ok=0
  for attempt in 1 2; do
    for endpoint in "${ENDPOINTS[@]}"; do
      echo "== $region via $endpoint (attempt $attempt) $mode"
      if python3 scripts/prepare_makati.py --region "$region" $mode --endpoint "$endpoint"; then ok=1; break 2; fi
      sleep 5
    done
  done
  [ "$ok" = 1 ] || { echo "Could not download $region from any Overpass endpoint; try again later." >&2; exit 1; }
done
python3 scripts/build_starter_catalog.py
python3 scripts/build_demo_walks.py
python3 -m unittest discover -s tests
swift test --package-path Packages/LifeOffDeskCore
echo "Done. Review: git diff --stat LifeOffDesk/Resources/StarterData ; then commit and rebuild the app."
