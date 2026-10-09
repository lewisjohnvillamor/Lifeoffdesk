#!/usr/bin/env python3
"""Build the bundled starter region packs (catalog, road context, manifest) and index.

Reads the output of prepare_makati.py (local-data/<region>/) for every region in
config/regions.json that has been prepared, and writes small app-ready resources to
LifeOffDesk/Resources/StarterData/<region>/ plus StarterData/regions.json. Selection is a deterministic rule, not a human review:
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
RESTRICTED_ACCESS = {'private', 'no', 'customers', 'permit', 'residents'}
MAX_CAFES = 3
MAX_NON_CAFE = 27
MAX_FOOD = 60
PER_CUISINE = 4
MAX_PER_CHAIN = 1
MAX_RADIUS_M = 2500

def haversine_m(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))

def median_anchor(places):
    """Deterministic reference point when the region config names none: median place position."""
    lats = sorted(p['latitude'] for p in places)
    lons = sorted(p['longitude'] for p in places)
    return (round(lats[len(lats)//2], 6), round(lons[len(lons)//2], 6))

def select_food(places, anchor, max_radius_m):
    """Nearest named food places: up to PER_CUISINE nearest per cuisine (variety), then nearest overall."""
    pool = [p for p in sorted(places, key=lambda p: (haversine_m(anchor, (p['latitude'], p['longitude'])), p['id']))
            if p['category'] == 'food' and p.get('sourceTags', {}).get('access') not in RESTRICTED_ACCESS
            and (max_radius_m is None or haversine_m(anchor, (p['latitude'], p['longitude'])) <= max_radius_m)]
    chosen, names, per_cuisine = [], set(), {}
    for place in pool:  # variety pass
        cuisine = (place.get('sourceTags', {}).get('cuisine') or '').split(';')[0].strip()
        if cuisine and per_cuisine.get(cuisine, 0) < PER_CUISINE and place['name'].casefold() not in names \
                and len(chosen) < MAX_FOOD:
            chosen.append(place); names.add(place['name'].casefold())
            per_cuisine[cuisine] = per_cuisine.get(cuisine, 0) + 1
    for place in pool:  # fill nearest
        if len(chosen) >= MAX_FOOD:
            break
        if place['name'].casefold() not in names:
            chosen.append(place); names.add(place['name'].casefold())
    return chosen

def select_places(places, anchor, max_radius_m=MAX_RADIUS_M):
    """Nearest non-café categories within the radius plus a few nearest distinct cafés and food places."""
    chosen, cafes, seen_names = [], [], {}
    for place in sorted(places, key=lambda p: (haversine_m(anchor, (p['latitude'], p['longitude'])), p['id'])):
        tags = place.get('sourceTags', {})
        if tags.get('access') in RESTRICTED_ACCESS:
            continue
        if max_radius_m is not None and haversine_m(anchor, (place['latitude'], place['longitude'])) > max_radius_m:
            continue
        if place['category'] == 'food':
            continue
        if place['category'] == 'cafe':
            key = place['name'].casefold()
            if seen_names.get(key, 0) >= MAX_PER_CHAIN or len(cafes) >= MAX_CAFES:
                continue
            seen_names[key] = seen_names.get(key, 0) + 1
            cafes.append(place)
        elif len(chosen) < MAX_NON_CAFE:
            chosen.append(place)
    return sorted(chosen + cafes + select_food(places, anchor, max_radius_m), key=lambda p: p['id'])

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
        'sourceCuisine': tags.get('cuisine'),
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

def build_region(region, source_dir, output_dir):
    source_manifest = json.loads((source_dir/'manifest.json').read_text())
    roads = json.loads((source_dir/'roads.geojson').read_text())
    common = {'schemaVersion': 1, 'regionID': region['id'],
              'attribution': source_manifest['attribution'], 'licenseURL': source_manifest['licenseURL'],
              'retrievedAt': source_manifest['retrievedAt'], 'sourceTimestamp': source_manifest.get('sourceTimestamp')}
    output_dir.mkdir(parents=True, exist_ok=True)
    names = ['roads.json']
    selected = []
    anchor = tuple(region['anchor']) if region.get('anchor') else None
    if region.get('places', True):
        places = json.loads((source_dir/'places-source.json').read_text())
        anchor = anchor or median_anchor(places)
        # Full-city regions select from the whole administrative box; the CBD keeps its walking radius.
        radius = MAX_RADIUS_M if region.get('anchor') else None
        selected = [app_place(p) for p in select_places(places, anchor, radius)]
        if not selected:
            raise ValueError(f"No places selected for {region['id']}")
        rule_radius = f'within {MAX_RADIUS_M} m of {anchor}' if radius else f'inside the region box, nearest to {anchor}'
        write_json(output_dir/'places.json', {**common,
            'selectionRule': f'Rule-based subset: up to {MAX_NON_CAFE} named OSM parks/museums/libraries/viewpoints '
                             f'{rule_radius}, the {MAX_CAFES} nearest distinctly named cafes and up to {MAX_FOOD} food '
                             f'places (up to {PER_CUISINE} nearest per cuisine first); source access tags '
                             f'{sorted(RESTRICTED_ACCESS)} excluded. Not a human review.',
            'places': selected})
        names.insert(0, 'places.json')
    write_json(output_dir/'roads.json', {**common,
        'note': 'Visual context only; not a routing graph. Restricted flag reflects source tags only.',
        'roads': compact_roads(roads)})
    bbox = region['bbox']
    if anchor is None:
        anchor = ((bbox['south'] + bbox['north']) / 2, (bbox['west'] + bbox['east']) / 2)
    files = []
    for name in names:
        data = (output_dir/name).read_bytes()
        files.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    write_json(output_dir/'region.json', {
        'schemaVersion': 1, 'id': region['id'], 'version': 1, 'name': region['name'],
        'detail': region.get('detail', 'full'), 'coverageStatus': region['coverageStatus'],
        'bounds': bbox, 'center': {'latitude': anchor[0], 'longitude': anchor[1]},
        'source': region['source'], 'attribution': source_manifest['attribution'],
        'licenseURL': source_manifest['licenseURL'],
        'builtAt': datetime.now(timezone.utc).isoformat(), 'files': files})
    counts = {}
    for p in selected:
        counts[p['category']] = counts.get(p['category'], 0) + 1
    print(f"{region['id']}: {len(selected)} places {counts}, {len(roads['features'])} road lines.")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, default=ROOT/'local-data')
    parser.add_argument('--output', type=Path, default=ROOT/'LifeOffDesk/Resources/StarterData')
    args = parser.parse_args()
    config = json.loads((ROOT/'config/regions.json').read_text())
    index = []
    for region in config['regions']:
        source_dir = args.input_root/region['localDir']
        if not (source_dir/'manifest.json').exists():
            print(f"{region['id']}: not prepared (run prepare_makati.py --region {region['id']}); skipped")
            continue
        build_region(region, source_dir, args.output/region['id'])
        index.append({'id': region['id'], 'detail': region.get('detail', 'full')})
    if not index:
        raise ValueError('No prepared regions found')
    # The first region is the primary one: map origin and fallback distance origin.
    write_json(args.output/'regions.json', {'schemaVersion': 1, 'regions': index})
    print('All places remain source-only-unreviewed. Review before calling any fact verified.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print('Catalog build failed:', error, file=sys.stderr)
        sys.exit(1)
