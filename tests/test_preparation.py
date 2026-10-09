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

if __name__ == '__main__':
    unittest.main()
