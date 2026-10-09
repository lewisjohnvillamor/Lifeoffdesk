#!/usr/bin/env python3
"""Build the bundled Makati starter catalog, road context and region manifest.

Reads the output of prepare_makati.py (local-data/makati/) and writes small,
app-ready resources. Selection is a deterministic rule, not a human review:
every place keeps verificationStatus 'source-only-unreviewed'. Source hours and
access tags are carried as *source claims* only; the verified fact fields stay
null until a person reviews them.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
# Ayala Triangle Gardens area; used only to order places for the curated subset.
ANCHOR = (14.5566, 121.0244)
RESTRICTED_ACCESS = {'private', 'no', 'customers', 'permit', 'residents'}
MAX_CAFES = 3
MAX_PER_CHAIN = 1
MAX_RADIUS_M = 2500

def haversine_m(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))

def select_places(places):
    """Non-café categories within the radius plus a few nearest distinct cafés."""
    chosen, cafes, seen_names = [], [], {}
    for place in sorted(places, key=lambda p: (haversine_m(ANCHOR, (p['latitude'], p['longitude'])), p['id'])):
        tags = place.get('sourceTags', {})
        if tags.get('access') in RESTRICTED_ACCESS:
            continue
        if haversine_m(ANCHOR, (place['latitude'], place['longitude'])) > MAX_RADIUS_M:
            continue
        if place['category'] == 'cafe':
            key = place['name'].casefold()
            if seen_names.get(key, 0) >= MAX_PER_CHAIN or len(cafes) >= MAX_CAFES:
                continue
            seen_names[key] = seen_names.get(key, 0) + 1
            cafes.append(place)
        else:
            chosen.append(place)
    return sorted(chosen + cafes, key=lambda p: p['id'])

def app_place(place):
    tags = place.get('sourceTags', {})
    return {
        'id': place['id'],
        'name': place['name'],
        'latitude': round(place['latitude'], 6),
        'longitude': round(place['longitude'], 6),
        'category': place['category'],
        'tags': [],
        'sourceURL': place['sourceURL'],
        'retrievedAt': place['retrievedAt'],
        'verificationStatus': place['verificationStatus'],
        'positionMethod': place.get('positionMethod', 'node'),
        'budgetPHP': None,
        'quietness': None,
        'openingHours': None,
        'sourceOpeningHours': tags.get('opening_hours'),
        'sourceAccess': tags.get('access'),
        'sourceFee': tags.get('fee'),
        'sourceLevel': tags.get('level'),
    }

def compact_roads(roads):
    out = []
    for feature in roads['features']:
        props = feature['properties']
        flat = []
        for lon, lat in feature['geometry']['coordinates']:
            flat += [round(lon, 6), round(lat, 6)]
        restricted = props.get('access') in RESTRICTED_ACCESS or props.get('foot') in ('no', 'private')
        out.append({'h': props['highway'], 'r': restricted, 'c': flat})
    return out

def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT/'local-data/makati')
    parser.add_argument('--output', type=Path, default=ROOT/'LifeOffDesk/Resources/StarterData')
    args = parser.parse_args()
    source_manifest = json.loads((args.input/'manifest.json').read_text())
    places = json.loads((args.input/'places-source.json').read_text())
    roads = json.loads((args.input/'roads.geojson').read_text())
    region = source_manifest['region']
    selected = [app_place(p) for p in select_places(places)]
    if not selected:
        raise ValueError('No places selected')
    common = {'schemaVersion': 1, 'regionID': region['id'],
              'attribution': source_manifest['attribution'], 'licenseURL': source_manifest['licenseURL'],
              'retrievedAt': source_manifest['retrievedAt'], 'sourceTimestamp': source_manifest.get('sourceTimestamp')}
    args.output.mkdir(parents=True, exist_ok=True)
    write_json(args.output/'places.json', {**common,
        'selectionRule': f'Rule-based subset: named OSM parks/museums/libraries/viewpoints within {MAX_RADIUS_M} m of '
                         f'{ANCHOR} plus the {MAX_CAFES} nearest distinctly named cafes; source access tags '
                         f'{sorted(RESTRICTED_ACCESS)} excluded. Not a human review.',
        'places': selected})
    write_json(args.output/'roads.json', {**common,
        'note': 'Visual context only; not a routing graph. Restricted flag reflects source tags only.',
        'roads': compact_roads(roads)})
    files = []
    for name in ('places.json', 'roads.json'):
        data = (args.output/name).read_bytes()
        files.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    bbox = region['bbox']
    write_json(args.output/'region.json', {
        'schemaVersion': 1, 'id': region['id'], 'version': 1, 'name': region['name'],
        'coverageStatus': region['coverageStatus'],
        'bounds': bbox, 'center': {'latitude': ANCHOR[0], 'longitude': ANCHOR[1]},
        'source': region['source'], 'attribution': source_manifest['attribution'],
        'licenseURL': source_manifest['licenseURL'],
        'builtAt': datetime.now(timezone.utc).isoformat(), 'files': files})
    counts = {}
    for p in selected:
        counts[p['category']] = counts.get(p['category'], 0) + 1
    print('Bundled', len(selected), 'places', counts, 'and', len(roads['features']), 'road lines.')
    print('All places remain source-only-unreviewed. Review before calling any fact verified.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print('Catalog build failed:', error, file=sys.stderr)
        sys.exit(1)
