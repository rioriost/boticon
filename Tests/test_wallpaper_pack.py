import copy
import hashlib
import json
import struct
import tempfile
import unittest
from unittest import mock
import zipfile
import zlib
from pathlib import Path
from tools import build_wallpaper_pack as pack


def png():
    def chunk(kind, content):
        return struct.pack('>I', len(content)) + kind + content + struct.pack('>I', zlib.crc32(kind + content))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 3, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\0\x20\x30\x40\x50\x60\x70' * 3)) + chunk(b'IEND', b'')


class WallpaperPackBuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'wallpapers').mkdir()
        (self.root / 'wallpapers/star.png').write_bytes(png())
        self.recipe = {'format': 'boticon-wallpaper-pack', 'schemaVersion': 1, 'id': 'example-stars',
                       'revision': 1, 'name': 'Example Stars', 'author': 'Example creator', 'license': 'CC0-1.0',
                       'wallpapers': [{'id': 'star', 'name': 'Star', 'file': 'wallpapers/star.png',
                                       'anchor': 'lowerLeft', 'attribution': 'Original example', 'aiGenerated': False}]}

    def tearDown(self):
        self.temp.cleanup()

    def test_build_standard_stored_zip_with_exact_hashes(self):
        recipe = self.root / 'recipe.json'
        recipe.write_text(json.dumps(self.recipe))
        output = self.root / 'example.bwp.zip'
        digest = pack.build(recipe, self.root, output)
        self.assertEqual(digest, hashlib.sha256(output.read_bytes()).hexdigest())
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ['manifest.json', 'wallpapers/star.png'])
            self.assertTrue(all(info.compress_type == zipfile.ZIP_STORED and not info.extra for info in archive.infolist()))
            record = json.loads(archive.read('manifest.json'))['wallpapers'][0]
            self.assertEqual(record['sha256'], hashlib.sha256(png()).hexdigest())
            self.assertEqual((record['width'], record['height']), (2, 3))
        before = output.read_bytes()
        with self.assertRaises(FileExistsError):
            pack.build(recipe, self.root, output)
        self.assertEqual(output.read_bytes(), before)

    def test_unsafe_paths_duplicate_ids_and_invalid_metadata_are_rejected(self):
        for change in [{'file': '../star.png'}, {'id': '../star'}, {'aiGenerated': 'false'},
                       {'debutDate': '2023-02-29'}, {'attribution': ''}, {'anchor': 'center'}]:
            recipe = copy.deepcopy(self.recipe)
            recipe['wallpapers'][0].update(change)
            with self.assertRaises((ValueError, FileNotFoundError)):
                pack.prepare(recipe, self.root)
        recipe = copy.deepcopy(self.recipe)
        recipe['wallpapers'] *= 2
        with self.assertRaises(ValueError):
            pack.prepare(recipe, self.root)

    def test_wrong_type_and_oversized_pixel_dimensions_are_rejected(self):
        (self.root / 'wallpapers/star.png').write_bytes(b'<svg></svg>')
        with self.assertRaises(ValueError):
            pack.prepare(self.recipe, self.root)
        image = bytearray(png())
        image[16:20] = struct.pack('>I', 999999)
        (self.root / 'wallpapers/star.png').write_bytes(image)
        with self.assertRaises(ValueError):
            pack.prepare(self.recipe, self.root)

    def test_total_size_is_rejected_before_loading_payload(self):
        with mock.patch.object(pack, 'MAX_ARCHIVE', len(png()) - 1):
            with mock.patch.object(Path, 'read_bytes', side_effect=AssertionError('must reject before reading')):
                with self.assertRaises(ValueError):
                    pack.prepare(self.recipe, self.root)

    def test_symlink_outside_input_cannot_be_packaged(self):
        image = self.root / 'wallpapers/star.png'
        image.unlink()
        image.symlink_to('/etc/hosts')
        with self.assertRaises(ValueError):
            pack.prepare(self.recipe, self.root)


if __name__ == '__main__':
    unittest.main()
