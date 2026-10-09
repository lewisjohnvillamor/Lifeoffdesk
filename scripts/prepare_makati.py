#!/usr/bin/env python3
"""One-time Makati OSM source-data preparation. Review before bundling."""
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

def query_for(bbox):
    b = ','.join(str(bbox[k]) for k in ('south', 'west', 'north', 'east'))
    return f'''[out:json][timeout:60];(
nwr["amenity"~"^(cafe|library)$"]["name"]({b});
nwr["leisure"="park"]["name"]({b});
nwr["tourism"~"^(museum|viewpoint)$"]["name"]({b});
way["highway"~"^(footway|path|pedestrian|residential|living_street|service|tertiary|secondary|primary)$"]({b});
);out tags center geom;'''

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

def convert(raw, retrieved_at):
    if raw.get('remark'):
        raise ValueError('Overpass reported a partial/error response: ' + raw['remark'])
    if not isinstance(raw.get('elements'), list):
        raise ValueError('Expected OSM elements list')
    places, roads = [], []
    for element in raw['elements']:
        tags = element.get('tags', {})
        category = None
        if tags.get('amenity') in ('cafe', 'library'):
            category = tags['amenity']
        elif tags.get('leisure') == 'park':
            category = 'park'
        elif tags.get('tourism') in ('museum', 'viewpoint'):
            category = 'museum' if tags['tourism'] == 'museum' else 'scenic'
        if category and tags.get('name'):
            position, method = representative_point(element)
            if position:
                places.append({'id':f"osm:{element['type']}:{element['id']}",
                               'name':tags['name'], 'latitude':position['lat'],
                               'longitude':position['lon'], 'category':category,
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
    if not places or not roads:
        raise ValueError('No usable places or roads; review the region/source response')
    return sorted(places, key=lambda p:p['id']), {'type':'FeatureCollection','features':roads}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, help='Use an existing Overpass JSON response without network access')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'local-data/makati')
    args = parser.parse_args()
    region = json.loads((ROOT/'config/starter-region.json').read_text())
    query = query_for(region['bbox'])
    if args.dry_run:
        print(query)
        return
    if args.input:
        raw = json.loads(args.input.read_text())
    else:
        body = urllib.parse.urlencode({'data':query}).encode()
        request = urllib.request.Request(ENDPOINT, data=body,
                    headers={'User-Agent':'LifeOffDesk-hackathon-starter/1.0 (one-time preparation)',
                             'Content-Type':'application/x-www-form-urlencoded'})
        with urllib.request.urlopen(request, timeout=90) as response:
            raw = json.load(response)
    retrieved = datetime.now(timezone.utc).isoformat()
    places, roads = convert(raw, retrieved)
    args.output.mkdir(parents=True, exist_ok=True)
    outputs = {'source-osm.json':raw, 'places-source.json':places, 'roads.geojson':roads}
    for name, data in outputs.items():
        (args.output/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    manifest = {'region':region,'retrievedAt':retrieved,'sourceTimestamp':raw.get('osm3s',{}).get('timestamp_osm_base'),
                'attribution':'© OpenStreetMap contributors','licenseURL':'https://www.openstreetmap.org/copyright',
                'status':'source-backed, unreviewed; choose/review 15–30 places before bundling',
                'placeCount':len(places),'roadCount':len(roads['features']),
                'files':[{ 'name':name,'bytes':(args.output/name).stat().st_size,
                           'sha256':hashlib.sha256((args.output/name).read_bytes()).hexdigest()} for name in outputs]}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Prepared',len(places),'source places and',len(roads['features']),'road geometries.')
    print('Review access and provenance before bundling. No quietness, budget or live hours were inferred.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError,OSError) as error:
        print('Preparation failed:',error,file=sys.stderr)
        sys.exit(1)
