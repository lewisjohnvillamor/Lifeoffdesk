import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'scripts'/f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

downloads = load('download_materials')
makati = load('prepare_makati')
catalog = load('build_starter_catalog')
demo = load('build_demo_walks')

class DownloadTests(unittest.TestCase):
    def artifact(self, content):
        return {'name':'fixture.gguf','relativePath':'model/fixture.gguf',
                'url':'https://example.invalid/fixture','sha256':hashlib.sha256(content).hexdigest()}

    def test_verified_cache_never_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);target=root/'model/fixture.gguf'
            target.parent.mkdir();target.write_bytes(b'correct')
            with patch.object(downloads.subprocess,'run') as run:
                downloads.download(self.artifact(b'correct'), root)
                run.assert_not_called()

    def test_corrupt_download_cannot_replace_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);target=root/'model/fixture.gguf'
            target.parent.mkdir();target.write_bytes(b'old')
            def write_bad(command, **kwargs):
                Path(command[command.index('--output')+1]).write_bytes(b'corrupt')
            with patch.object(downloads.subprocess,'run',side_effect=write_bad):
                with self.assertRaisesRegex(ValueError,'Checksum mismatch'):
                    downloads.download(self.artifact(b'correct'), root)
            self.assertEqual(target.read_bytes(),b'old')
            self.assertFalse(target.with_name(target.name+'.partial').exists())

    def test_verified_download_is_committed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            def write_good(command, **kwargs):
                Path(command[command.index('--output')+1]).write_bytes(b'correct')
            with patch.object(downloads.subprocess,'run',side_effect=write_good):
                downloads.download(self.artifact(b'correct'), root)
            self.assertEqual((root/'model/fixture.gguf').read_bytes(),b'correct')

class MakatiTests(unittest.TestCase):
    def fixture(self):
        return {'elements':[
            {'type':'node','id':1,'lat':14.55,'lon':121.02,
             'tags':{'name':'Synthetic fixture cafe','amenity':'cafe','opening_hours':'24/7'}},
            {'type':'way','id':2,'tags':{'highway':'footway','access':'private'},
             'geometry':[{'lat':14.55,'lon':121.02},{'lat':14.551,'lon':121.021}]},
            {'type':'way','id':3,'center':{'lat':14.56,'lon':121.03},
             'tags':{'name':'Synthetic fixture park','leisure':'park'}},
            {'type':'way','id':4,'bounds':{'minlat':14.54,'minlon':121.01,'maxlat':14.542,'maxlon':121.012},
             'geometry':[{'lat':14.54,'lon':121.01},{'lat':14.542,'lon':121.012}],
             'tags':{'name':'Synthetic geom-only park','leisure':'park'}}]}

    def test_sources_remain_unreviewed_and_unknown_facts_stay_unknown(self):
        places,roads=makati.convert(self.fixture(),'fixture-time')
        self.assertEqual(len(places),3)
        self.assertEqual(places[0]['verificationStatus'],'source-only-unreviewed')
        self.assertIsNone(places[0]['openingHours'])
        self.assertIsNone(places[0]['quietness'])
        self.assertEqual(places[0]['sourceTags']['opening_hours'],'24/7')
        self.assertEqual(roads['features'][0]['properties']['access'],'private')
        self.assertEqual(roads['features'][0]['geometry']['coordinates'][0],[121.02,14.55])

    def test_geom_output_without_center_uses_bounds_midpoint(self):
        places,_=makati.convert(self.fixture(),'fixture-time')
        park=next(p for p in places if p['id']=='osm:way:4')
        self.assertAlmostEqual(park['latitude'],14.541)
        self.assertAlmostEqual(park['longitude'],121.011)
        self.assertEqual(park['positionMethod'],'bounds-midpoint')

    def test_partial_response_fails_instead_of_silently_bundling(self):
        fixture=self.fixture();fixture['remark']='runtime timeout'
        with self.assertRaisesRegex(ValueError,'partial/error'):
            makati.convert(fixture,'fixture-time')

    def test_missing_data_fails(self):
        with self.assertRaises(ValueError):makati.convert({'elements':[]},'fixture-time')

class RegionTests(unittest.TestCase):
    def test_every_configured_region_builds_a_query(self):
        import json
        config = json.loads((ROOT/'config/regions.json').read_text())
        ids = [r['id'] for r in config['regions']]
        self.assertEqual(ids[0], 'makati-cbd-starter')
        self.assertIn('muntinlupa', ids)
        for region in config['regions']:
            if not region.get('bbox'):
                continue  # resolved from the OSM boundary at preparation time
            query = makati.query_for(region['bbox'], region.get('highways'), region.get('places', True))
            self.assertIn('way["highway"', query)
            self.assertEqual('leisure' in query, region.get('places', True))

    def test_roads_only_region_needs_no_places(self):
        raw = {'elements':[{'type':'way','id':9,'tags':{'highway':'primary'},
                            'geometry':[{'lat':14.4,'lon':121.0},{'lat':14.41,'lon':121.01}]}]}
        places, roads = makati.convert(raw, 'fixture-time', require_places=False)
        self.assertEqual(places, [])
        self.assertEqual(len(roads['features']), 1)

    def test_selection_keeps_every_named_place_and_skips_restricted_access(self):
        def place(i, category, access=None, name=None):
            return {'id':f'osm:node:{i}','name':name or f'P{i}','latitude':14.4+i*1e-4,'longitude':121.0,
                    'category':category,'sourceTags':{'access':access} if access else {}}
        places = [place(i, 'park') for i in range(40)] + [place(100, 'park', access='private')] + \
                 [place(200+i, 'cafe', name='Same Chain') for i in range(5)] + [place(300, 'cafe', name='Other')]
        chosen = catalog.select_places(places, (14.4, 121.0), None)
        ids = [p['id'] for p in chosen]
        self.assertEqual(sum(p['category']=='park' for p in chosen), 40, 'no city-wide cap')
        self.assertEqual(sum(p['category']=='cafe' for p in chosen), 6, 'chain branches are separate places')
        self.assertNotIn('osm:node:100', ids)
        near = catalog.select_places(places, (14.4, 121.0), 200)
        self.assertTrue(all(catalog.haversine_m((14.4, 121.0), (p['latitude'], p['longitude'])) <= 200 for p in near))

    def test_classifier_covers_businesses_sports_and_landmarks(self):
        c = makati.classify
        self.assertEqual(c({'leisure':'pitch','sport':'pickleball'}), ('sports', 'pickleball', 'Pickleball court'))
        self.assertEqual(c({'leisure':'golf_course','name':'Alabang Golf'})[0], 'sports')
        self.assertEqual(c({'shop':'mall','name':'Festival Mall'}), ('shopping', 'mall', 'Festival Mall'))
        self.assertEqual(c({'amenity':'place_of_worship','name':'St. Jerome'})[0], 'landmark')
        self.assertEqual(c({'amenity':'pharmacy','name':'Mercury Drug'}), ('other', 'pharmacy', 'Mercury Drug'))
        self.assertEqual(c({'amenity':'cafe','name':'Starbucks'})[0], 'cafe')
        self.assertIsNone(c({'amenity':'parking','name':'Lot A'}), 'parking is not an outing')
        self.assertIsNone(c({'amenity':'pharmacy'}), 'unnamed non-sports places are skipped')

    def test_bbox_comes_from_the_city_level_boundary(self):
        raw = {'elements': [
            {'type':'relation','id':2,'tags':{'name':'Pasay','admin_level':'10'},
             'bounds':{'minlat':14.52,'minlon':121.0,'maxlat':14.53,'maxlon':121.01}},
            {'type':'relation','id':1,'tags':{'name':'Pasay','admin_level':'6'},
             'bounds':{'minlat':14.49,'minlon':120.97,'maxlat':14.56,'maxlon':121.03}}]}
        bbox, source = makati.bbox_from_boundary(raw, 'Pasay')
        self.assertEqual(bbox, {'south':14.49,'west':120.97,'north':14.56,'east':121.03})
        self.assertTrue(source.endswith('/relation/1'))
        with self.assertRaises(ValueError):
            makati.bbox_from_boundary(raw, 'Atlantis')

class DemoWalkTests(unittest.TestCase):
    def test_generator_is_deterministic_and_labelled(self):
        import json, subprocess, sys
        with tempfile.TemporaryDirectory() as directory:
            outputs = []
            for name in ('a.json', 'b.json'):
                target = Path(directory)/name
                subprocess.run([sys.executable, str(ROOT/'scripts/build_demo_walks.py'), '--output', str(target)],
                               check=True, capture_output=True)
                outputs.append(target.read_bytes())
            self.assertEqual(outputs[0], outputs[1])
            data = json.loads(outputs[0])
            self.assertIn('SYNTHETIC', data['label'])
            self.assertEqual(outputs[0], (ROOT/'LifeOffDesk/Resources/StarterData/demo/sample-walks.json').read_bytes(),
                             'Bundled demo file must match the generator output')

if __name__ == '__main__':
    unittest.main()
