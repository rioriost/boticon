#!/usr/bin/env python3
"""Verify a downloadable-catalog app bundle contains no bundled wallpaper catalog or artwork."""
import argparse
import json
import plistlib
from pathlib import Path


def verify(app, require_shortcut=False):
    assert not (app / 'Wallpapers').exists(), 'Wallpaper assets must not be bundled'
    catalog = app / 'catalog.json'
    if catalog.exists():
        assert not json.loads(catalog.read_text())['members'], 'Bundled roster is forbidden'
    assert not list(app.rglob('*.bwp.zip')), 'Wallpaper archives must not be bundled'
    assert (app / 'Metadata.appintents').is_dir(), 'App Intent metadata missing'
    shortcut = app / 'Shortcuts/Boticon壁紙を変更.shortcut'
    if require_shortcut or shortcut.exists():
        assert shortcut.is_file(), 'Shortcut template missing'
        assert shortcut.read_bytes()[:4] == b'AEA1', 'Expected signed Shortcut container'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['NSPhotoLibraryAddUsageDescription'], 'Missing photo permission text'
    assert info['UIDeviceFamily'] == [1], 'Expected iPhone target'
    assert any('boticon' in item.get('CFBundleURLSchemes', [])
               for item in info.get('CFBundleURLTypes', [])), 'Shortcut callback URL scheme missing'
    assert info.get('ITSAppUsesNonExemptEncryption') is False, 'Expected standard encryption declaration'
    privacy = plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes())
    assert privacy['NSPrivacyTracking'] is False and privacy['NSPrivacyCollectedDataTypes'] == []
    print('Verified: no bundled wallpapers/roster/packs; App Intents, privacy manifest, permissions and callback scheme present')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--require-shortcut', action='store_true')
    args = parser.parse_args()
    verify(args.app, args.require_shortcut)
