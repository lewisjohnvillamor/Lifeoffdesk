#!/usr/bin/env python3
"""Generate SYNTHETIC demo walks along bundled OSM street geometry.

These are presentation fixtures so an audience can see what a well-explored map looks
like. They are not real GPS and never enter a user's personal data: the app shows them
only in its labelled Demo mode. Output is deterministic for a given seed.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import random
import uuid

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'LifeOffDesk/Resources/StarterData'
LABEL = 'SYNTHETIC DEMO DATA: generated along OpenStreetMap streets; not real GPS or a real person\'s walks.'
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
# Fixed reference so the file does not change between runs.
BASE_DATE = datetime(2026, 10, 8, tzinfo=timezone.utc)
WALK_SPEED = 1.3        # m/s
SAMPLE_SPACING = 10.0   # metres between generated fixes
ACCURACY = 5.0          # reported accuracy for every synthetic fix
# Region id -> (number of walks, min metres, max metres)
PLAN = {'makati-cbd-starter': (24, 1200, 3200), 'muntinlupa': (10, 1200, 3000)}

def metres(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))

def bearing(a, b):
    y = math.sin(math.radians(b[1]-a[1])) * math.cos(math.radians(b[0]))
    x = math.cos(math.radians(a[0]))*math.sin(math.radians(b[0])) - \
        math.sin(math.radians(a[0]))*math.cos(math.radians(b[0]))*math.cos(math.radians(b[1]-a[1]))
    return math.degrees(math.atan2(y, x))

def build_graph(roads):
    graph = {}
    for road in roads:
        if road['r'] or road['h'] in ('motorway', 'trunk'):
            continue
        c = road['c']
        points = [(round(c[i+1], 6), round(c[i], 6)) for i in range(0, len(c)-1, 2)]
        for a, b in zip(points, points[1:]):
            if a == b:
                continue
            graph.setdefault(a, set()).add(b)
            graph.setdefault(b, set()).add(a)
    return graph

def random_walk(graph, start, target, rng):
    path, prev, length = [start], None, 0.0
    while length < target:
        here = path[-1]
        options = [n for n in graph[here] if n != prev] or list(graph[here])
        if not options:
            break
        if prev is not None and len(options) > 1:
            heading = bearing(prev, here)
            # Prefer carrying on roughly straight, like a person strolling; still allow turns.
            weights = [1.0 + 3.0 * math.cos(math.radians(bearing(here, n) - heading)) ** 2
                       if abs(((bearing(here, n) - heading) + 180) % 360 - 180) < 100 else 0.4 for n in options]
            nxt = rng.choices(options, weights)[0]
        else:
            nxt = rng.choice(options)
        length += metres(here, nxt)
        prev = here
        path.append(nxt)
    return path, length

def densify(path):
    points = [path[0]]
    for a, b in zip(path, path[1:]):
        d = metres(a, b)
        steps = max(1, int(d // SAMPLE_SPACING))
        for i in range(1, steps + 1):
            t = i / steps
            points.append((a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t))
    return points

def walk_session(points, started, rng):
    t = (started - APPLE_EPOCH).total_seconds()
    samples, last = [], None
    for p in points:
        if last is not None:
            t += metres(last, p) / WALK_SPEED
        samples.append({'latitude': round(p[0], 6), 'longitude': round(p[1], 6), 'timestamp': round(t, 1),
                        'horizontalAccuracy': ACCURACY, 'speed': WALK_SPEED})
        last = p
    start_ts = samples[0]['timestamp']
    end_ts = samples[-1]['timestamp']
    return {'id': str(uuid.UUID(int=rng.getrandbits(128), version=4)).upper(), 'schemaVersion': 1,
            'state': 'finished', 'startedAt': start_ts, 'endedAt': end_ts,
            'bankedActiveDuration': round(end_ts - start_ts, 1), 'lastCheckpointAt': end_ts,
            'segments': [samples], 'wasRecovered': False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, default=20261009)
    parser.add_argument('--output', type=Path, default=DATA/'demo/sample-walks.json')
    args = parser.parse_args()
    rng = random.Random(args.seed)
    walks, summary = [], {}
    for region_id, (count, low, high) in PLAN.items():
        region = json.loads((DATA/region_id/'region.json').read_text())
        roads = json.loads((DATA/region_id/'roads.json').read_text())['roads']
        graph = build_graph(roads)
        center = (region['center']['latitude'], region['center']['longitude'])
        # Start near the region's reference point so the explored area forms a believable neighbourhood.
        starts = sorted((n for n in graph if len(graph[n]) >= 3), key=lambda n: metres(n, center))[:400]
        total = 0.0
        for _ in range(count):
            path, length = random_walk(graph, rng.choice(starts), rng.uniform(low, high), rng)
            if length < 300:
                continue
            # Spread over the previous six weeks at typical break times (Manila time = UTC+8).
            manila_hour = rng.choice([7, 8, 12, 13, 17, 18])
            started = BASE_DATE - timedelta(days=rng.randint(1, 45)) + \
                timedelta(hours=manila_hour - 8, minutes=rng.randint(0, 59))
            walks.append(walk_session(densify(path), started, rng))
            total += length
        summary[region_id] = {'walks': count, 'metres': round(total)}
    walks.sort(key=lambda w: w['startedAt'], reverse=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'schemaVersion': 1, 'label': LABEL,
        'generator': f'scripts/build_demo_walks.py seed={args.seed}; random walks on bundled OSM street graph, '
                     f'{SAMPLE_SPACING:g} m fix spacing at {WALK_SPEED} m/s, no GPS noise',
        'walks': walks}, separators=(',', ':')) + '\n')
    print('Generated', len(walks), 'synthetic walks', summary, '->', args.output)

if __name__ == '__main__':
    main()
