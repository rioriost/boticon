import json
import unittest

from tools.check_public_source import CATALOG, EMPTY_CATALOG, validate


class PublicSourceTests(unittest.TestCase):
    def test_only_empty_catalog_is_publishable(self):
        validate(CATALOG, json.dumps(EMPTY_CATALOG).encode())
        for changed in [dict(EMPTY_CATALOG, members=[{"id": "private-record"}]),
                        dict(EMPTY_CATALOG, source="private-source")]:
            with self.assertRaises(ValueError):
                validate(CATALOG, json.dumps(changed).encode())

    def test_images_records_and_signed_resources_are_rejected(self):
        for path in ["assets/source.png", "data/master.json", "docs/screenshot.png",
                     "iOS/Boticon/Resources/Wallpapers/sample.png",
                     "iOS/Boticon/Resources/Wallpapers/sample.json",
                     "iOS/Boticon/Resources/Shortcuts/template.shortcut"]:
            with self.assertRaises(ValueError):
                validate(path, b"excluded")

    def test_binary_content_and_signing_settings_are_rejected(self):
        with self.assertRaises(ValueError):
            validate("Sources/BoticonCore/Unexpected.swift", b"text\x00binary")
        with self.assertRaises(ValueError):
            validate("project.yml", b"DEVELOPMENT_TEAM: local-team")
        with self.assertRaises(ValueError):
            validate("iOS/Boticon/Resources/Wallpapers/.gitkeep", b"not empty")
