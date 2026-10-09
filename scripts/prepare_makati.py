#!/usr/bin/env python3
"""One-time OSM source-data preparation for a configured region (config/regions.json).

Despite the historical file name this handles every starter region (Makati, Muntinlupa,
Metro Manila context). Review places before bundling."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ENDPOINT = 'https://overpass-api.de/api/interpreter'

FULL_DETAIL_HIGHWAYS = ['footway', 'path', 'pedestrian', 'residential', 'living_street', 'service',
                        'tertiary', 'secondary', 'primary']

def load_region(region_id):
    config = json.loads((ROOT/'config/regions.json').read_text())
    for region in config['regions']:
        if region['id'] == region_id:
            return region
    raise ValueError(f"Unknown region {region_id}; see config/regions.json")

# Named things people can walk to. Street furniture and parking are left out (noise, not outings).
EXCLUDED_AMENITIES = {'parking', 'parking_space', 'parking_entrance', 'bicycle_parking', 'motorcycle_parking',
                      'bench', 'waste_basket', 'waste_disposal', 'recycling', 'toilets', 'atm', 'vending_machine',
                      'shelter', 'drinking_water', 'telephone', 'post_box', 'charging_station', 'fuel',
                      'loading_dock', 'fire_hydrant', 'clock', 'grit_bin', 'letter_box', 'water_point'}
EXCLUDED_SHOPS = {'vacant', 'no', 'yes'}
SPORTS_LEISURE = {'pitch', 'sports_centre', 'golf_course', 'fitness_centre', 'stadium', 'swimming_pool',
                  'track', 'sports_hall', 'fitness_station', 'miniature_golf', 'ice_rink', 'bowling_alley'}
PARK_LEISURE = {'park', 'garden', 'playground', 'nature_reserve', 'dog_park', 'common'}
FOOD_AMENITIES = {'restaurant', 'fast_food', 'food_court', 'bar', 'pub', 'biergarten', 'ice_cream'}
FOOD_SHOPS = {'bakery', 'pastry', 'confectionery', 'deli'}
LANDMARK_AMENITIES = {'place_of_worship', 'townhall', 'fountain', 'monastery'}
LANDMARK_TOURISM = {'attraction', 'artwork', 'monument', 'memorial'}
SPORT_LABELS = {'tennis': 'Tennis court', 'pickleball': 'Pickleball court', 'basketball': 'Basketball court',
                'badminton': 'Badminton court', 'volleyball': 'Volleyball court', 'soccer': 'Football field',
                'golf': 'Golf course', 'swimming': 'Swimming pool', 'running': 'Running track',
                'skateboard': 'Skate park', 'fitness': 'Fitness area', 'multi': 'Sports court'}

def query_for(bbox, highways=None, include_places=True):
    b = ','.join(str(bbox[k]) for k in ('south', 'west', 'north', 'east'))
    classes = '|'.join(highways or FULL_DETAIL_HIGHWAYS)
    roads = f'way["highway"~"^({classes})$"]({b});' if highways is not False else ''
    places = f'''nwr["amenity"]["name"]({b});
nwr["shop"]["name"]({b});
nwr["leisure"]["name"]({b});
nwr["tourism"]["name"]({b});
nwr["historic"]["name"]({b});
nwr["leisure"~"^({'|'.join(sorted(SPORTS_LEISURE))})$"]({b});
''' if include_places else ''
    out = 'out tags center geom;' if roads else 'out tags center;'  # geometry only needed for roads
    return f'''[out:json][timeout:180];(
{places}{roads}
);{out}'''

def classify(tags):
    """(category, kind, label) from OSM tags, or None when it is not somewhere to go.
    Unnamed places are kept only for sports facilities, labelled from their own tags."""
    amenity, shop, leisure = tags.get('amenity'), tags.get('shop'), tags.get('leisure')
    tourism, historic = tags.get('tourism'), tags.get('historic')
    sport = (tags.get('sport') or '').split(';')[0].strip()
    name = tags.get('name')
    if amenity in EXCLUDED_AMENITIES or shop in EXCLUDED_SHOPS:
        return None
    if leisure in SPORTS_LEISURE or (sport and not amenity and not shop):
        kind = sport or leisure
        label = name or SPORT_LABELS.get(sport) or (leisure or 'sports').replace('_', ' ').capitalize()
        return 'sports', kind, label
    if not name:
        return None
    if amenity == 'cafe':
        return 'cafe', 'cafe', name
    if amenity == 'library':
        return 'library', 'library', name
    if amenity in FOOD_AMENITIES or shop in FOOD_SHOPS:
        return 'food', amenity or shop, name
    if leisure in PARK_LEISURE:
        return 'park', leisure, name
    if tourism in ('museum', 'gallery') or amenity == 'arts_centre':
        return 'museum', tourism or amenity, name
    if tourism == 'viewpoint':
        return 'scenic', 'viewpoint', name
    if amenity in LANDMARK_AMENITIES or tourism in LANDMARK_TOURISM or historic:
        return 'landmark', amenity or tourism or historic, name
    if shop or amenity == 'marketplace':
        return 'shopping', shop or 'marketplace', name
    if amenity or leisure or tourism:
        return 'other', amenity or leisure or tourism, name
    return None

METRO_MANILA_SEARCH_BOX = '14.30,120.90,14.80,121.20'

def boundary_query(name):
    return f'''[out:json][timeout:60];
relation["boundary"="administrative"]["name"="{name}"]({METRO_MANILA_SEARCH_BOX});
out bb tags;'''

def bbox_from_boundary(raw, name):
    """Bounding box of the administrative boundary called `name` (city level preferred)."""
    candidates = [e for e in raw.get('elements', []) if e.get('type') == 'relation' and e.get('bounds')
                  and e.get('tags', {}).get('name') == name]
    if not candidates:
        raise ValueError(f'No OSM administrative boundary named {name!r} found')
    level = lambda e: abs(int(e['tags'].get('admin_level', '99') or 99) - 6)
    best = min(candidates, key=lambda e: (level(e), e['id']))
    b = best['bounds']
    return ({'south': b['minlat'], 'west': b['minlon'], 'north': b['maxlat'], 'east': b['maxlon']},
            f"https://www.openstreetmap.org/relation/{best['id']}")

def overpass(query, endpoint):
    body = urllib.parse.urlencode({'data':query}).encode()
    request = urllib.request.Request(endpoint, data=body,
                headers={'User-Agent':'LifeOffDesk-hackathon-starter/1.0 (one-time preparation)',
                         'Content-Type':'application/x-www-form-urlencoded'})
    with urllib.request.urlopen(request, timeout=300) as response:
        return json.load(response)

def resolve_bbox(region, endpoint):
    """Fill a missing bbox from the OSM boundary and record it in config/regions.json."""
    if region.get('bbox'):
        return region
    bbox, source = bbox_from_boundary(overpass(boundary_query(region['boundaryName']), endpoint), region['boundaryName'])
    config_path = ROOT/'config/regions.json'
    config = json.loads(config_path.read_text())
    for entry in config['regions']:
        if entry['id'] == region['id']:
            entry['bbox'] = bbox
            entry['boundarySource'] = f'{source} (bounding box of the administrative boundary, includes water)'
    config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + '\n')
    print(f"{region['id']}: bbox from {source}: {bbox}")
    return {**region, 'bbox': bbox}

def representative_point(element):
    """Node position, Overpass center, or bounds midpoint (`out geom` returns bounds, not center)."""
    if element['type'] == 'node' and 'lat' in element and 'lon' in element:
        return {'lat':element['lat'], 'lon':element['lon']}, 'node'
    center = element.get('center', {})
    if 'lat' in center and 'lon' in center:
        return center, 'overpass-center'
    bounds = element.get('bounds', {})
    if all(k in bounds for k in ('minlat', 'minlon', 'maxlat', 'maxlon')):
        return {'lat':(bounds['minlat']+bounds['maxlat'])/2,
                'lon':(bounds['minlon']+bounds['maxlon'])/2}, 'bounds-midpoint'
    return None, None

def convert(raw, retrieved_at, require_places=True, require_roads=True):
    if raw.get('remark'):
        raise ValueError('Overpass reported a partial/error response: ' + raw['remark'])
    if not isinstance(raw.get('elements'), list):
        raise ValueError('Expected OSM elements list')
    places, roads = [], []
    for element in raw['elements']:
        tags = element.get('tags', {})
        classified = classify(tags) if tags and not tags.get('highway') else None
        if classified:
            category, kind, label = classified
            position, method = representative_point(element)
            if position:
                places.append({'id':f"osm:{element['type']}:{element['id']}",
                               'name':label, 'latitude':position['lat'],
                               'longitude':position['lon'], 'category':category, 'kind':kind,
                               'nameFromTags': not tags.get('name'),
                               'tags':[], 'sourceURL':f"https://www.openstreetmap.org/{element['type']}/{element['id']}",
                               'retrievedAt':retrieved_at, 'verificationStatus':'source-only-unreviewed',
                               'positionMethod':method,
                               'budgetPHP':None, 'quietness':None, 'openingHours':None,
                               'sourceTags':tags})
        geometry = element.get('geometry', [])
        if element['type'] == 'way' and tags.get('highway') and len(geometry) >= 2:
            if not all('lat' in point and 'lon' in point for point in geometry):
                continue
            roads.append({'type':'Feature', 'id':f"osm:way:{element['id']}",
                          'properties':{'name':tags.get('name'), 'highway':tags['highway'],
                                        'access':tags.get('access'), 'foot':tags.get('foot'),
                                        'sourceURL':f"https://www.openstreetmap.org/way/{element['id']}"},
                          'geometry':{'type':'LineString','coordinates':[[point['lon'],point['lat']] for point in geometry]}})
    if (require_places and not places) or (require_roads and not roads):
        raise ValueError('No usable places or roads; review the region/source response')
    return sorted(places, key=lambda p:p['id']), {'type':'FeatureCollection','features':roads}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, help='Use an existing Overpass JSON response without network access')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--region', default='makati-cbd-starter', help='Region id from config/regions.json')
    parser.add_argument('--output', type=Path, help='Defaults to local-data/<region dir>')
    parser.add_argument('--places-only', action='store_true',
                        help='Refresh places but keep the existing roads.geojson (street matching unchanged)')
    parser.add_argument('--endpoint', default=ENDPOINT, help='Overpass endpoint (mirrors allowed)')
    args = parser.parse_args()
    region = load_region(args.region)
    if not region.get('bbox'):
        if args.input or args.dry_run:
            raise ValueError(f"{region['id']} has no bbox yet; run once online to resolve it from OSM")
        region = resolve_bbox(region, args.endpoint)
    args.output = args.output or ROOT/'local-data'/region['localDir']
    include_places = region.get('places', True)
    query = query_for(region['bbox'], False if args.places_only else region.get('highways'), include_places)
    if args.dry_run:
        print(query)
        return
    if args.input:
        raw = json.loads(args.input.read_text())
    else:
        raw = overpass(query, args.endpoint)
    retrieved = datetime.now(timezone.utc).isoformat()
    if args.places_only:
        existing = json.loads((args.output/'roads.geojson').read_text())
        places, _ = convert(raw, retrieved, require_places=True, require_roads=False)
        roads = existing
        outputs = {'source-osm-places.json':raw, 'places-source.json':places}
    else:
        places, roads = convert(raw, retrieved, require_places=include_places)
        outputs = {'source-osm.json':raw, 'places-source.json':places, 'roads.geojson':roads}
    args.output.mkdir(parents=True, exist_ok=True)
    for name, data in outputs.items():
        (args.output/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    manifest = {'region':region,'retrievedAt':retrieved,'sourceTimestamp':raw.get('osm3s',{}).get('timestamp_osm_base'),
                'attribution':'© OpenStreetMap contributors','licenseURL':'https://www.openstreetmap.org/copyright',
                'status':'source-backed, unreviewed; choose/review 15–30 places before bundling',
                'placeCount':len(places),'roadCount':len(roads['features']),
                'files':[{ 'name':name,'bytes':(args.output/name).stat().st_size,
                           'sha256':hashlib.sha256((args.output/name).read_bytes()).hexdigest()}
                         for name in (list(outputs) + (['roads.geojson'] if args.places_only else []))]}
    if args.places_only:
        previous = json.loads((args.output/'manifest.json').read_text()) if (args.output/'manifest.json').exists() else {}
        manifest['roadsRetrievedAt'] = previous.get('roadsRetrievedAt') or previous.get('retrievedAt')
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared',len(places),'source places and',len(roads['features']),'road geometries.')
    print('Review access and provenance before bundling. No quietness, budget or live hours were inferred.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError,OSError) as error:
        print('Preparation failed:',error,file=sys.stderr)
        sys.exit(1)
