#!/usr/bin/env python3
"""Build a BWP v1 stored ZIP from a JSON recipe and PNG/JPEG files. Standard library only."""
import argparse
import datetime
import hashlib
import json
import re
import struct
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

MAX_ARCHIVE = 256 * 1024 * 1024
MAX_IMAGE = 20 * 1024 * 1024
MAX_MANIFEST = 1024 * 1024
ID = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\Z")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value, limit=200):
    return isinstance(value, str) and value.strip() and len(value) <= limit and all(ord(c) >= 32 or c == '\n' for c in value)


def image_info(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) >= 33 and data[8:16] == b'\0\0\0\rIHDR':
        return ('image/png', *struct.unpack('>II', data[16:24]))
    if data.startswith(b'\xff\xd8'):
        offset = 2
        while offset + 4 <= len(data):
            require(data[offset] == 255, 'Invalid JPEG marker')
            while offset < len(data) and data[offset] == 255:
                offset += 1
            require(offset < len(data), 'Truncated JPEG')
            marker = data[offset]
            offset += 1
            if marker in (0xd9, 0xda):
                break
            length = int.from_bytes(data[offset:offset+2], 'big')
            require(length >= 2 and offset + length <= len(data), 'Truncated JPEG segment')
            if marker in (0xc0, 0xc1, 0xc2):
                require(length >= 8, 'Invalid JPEG dimensions')
                height, width = struct.unpack('>HH', data[offset+3:offset+7])
                return ('image/jpeg', width, height)
            offset += length
    raise ValueError('Only PNG/JPEG are supported; full image decoding is additionally checked by the app')


def prepare(recipe, image_root):
    result = json.loads(json.dumps(recipe))
    require(result.get('format') == 'boticon-wallpaper-pack' and result.get('schemaVersion') == 1, 'Expected BWP v1')
    require(isinstance(result.get('id'), str) and ID.fullmatch(result['id']), 'Invalid pack id')
    require(type(result.get('revision')) is int and result['revision'] > 0, 'Invalid revision')
    for key in ('name', 'author', 'license'):
        require(text(result.get(key), 4000 if key == 'license' else 200), f'Invalid {key}')
    if 'homepage' in result:
        url = urlsplit(result['homepage'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.fragment
                and url.port in (None, 443), 'Invalid homepage')
    wallpapers = result.get('wallpapers')
    require(isinstance(wallpapers, list) and 1 <= len(wallpapers) <= 500, 'Expected 1..500 wallpapers')
    ids, files = set(), {}
    root = image_root.resolve()
    for item in wallpapers:
        identity = item.get('id')
        require(isinstance(identity, str) and ID.fullmatch(identity) and identity not in ids, 'Invalid/duplicate wallpaper id')
        ids.add(identity)
        require(item.get('file') in (f'wallpapers/{identity}.png', f'wallpapers/{identity}.jpg'), 'Invalid file path')
        path = root / item['file']
        require(not path.is_symlink() and path.resolve().is_relative_to(root), 'Image escapes input folder')
        require(0 < path.stat().st_size <= MAX_IMAGE, 'Image exceeds 20MiB')
        data = path.read_bytes()
        media_type, width, height = image_info(data)
        require((media_type == 'image/png') == path.name.endswith('.png'), 'Extension does not match image type')
        require(0 < width <= 8192 and 0 < height <= 8192 and width * height <= 24_000_000, 'Image dimensions exceed limits')
        require(text(item.get('name')) and text(item.get('attribution'), 4000), 'Missing name/attribution')
        require(type(item.get('aiGenerated')) is bool, 'aiGenerated must be a boolean')
        require(item.get('anchor') in ('lowerLeft', 'lowerRight'), 'Invalid anchor')
        if 'organization' in item:
            require(text(item['organization']), 'Invalid organization')
        if 'aliases' in item:
            require(isinstance(item['aliases'], list) and len(item['aliases']) <= 20 and all(text(a) for a in item['aliases']), 'Invalid aliases')
        if 'debutDate' in item:
            require(isinstance(item['debutDate'], str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', item['debutDate']), 'Invalid debut date')
            datetime.date.fromisoformat(item['debutDate'])
        item.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), width=width, height=height, mediaType=media_type)
        files[item['file']] = data
    manifest = (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    require(len(manifest) <= MAX_MANIFEST, 'Manifest exceeds 1MiB')
    require(sum(map(len, files.values())) + len(manifest) + 200 * (len(files) + 1) <= MAX_ARCHIVE, 'Archive exceeds 256MiB; split the pack')
    return {'manifest.json': manifest, **files}


def build(recipe_path, image_root, output):
    require(recipe_path.stat().st_size <= MAX_MANIFEST, 'Recipe exceeds 1MiB')
    files = prepare(json.loads(recipe_path.read_text(encoding='utf-8')), image_root)
    # Exclusive creation: never overwrite an older archive, source image or recipe.
    with output.open('xb') as handle:
        try:
            with zipfile.ZipFile(handle, 'w', compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
                for path, data in files.items():
                    info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, data)
            require(handle.tell() <= MAX_ARCHIVE, 'Archive exceeds 256MiB')
        except BaseException:
            output.unlink(missing_ok=True)
            raise
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recipe', type=Path)
    parser.add_argument('images', type=Path, help='Folder containing wallpapers/<id>.png or .jpg')
    parser.add_argument('output', type=Path, help='New .bwp.zip file')
    args = parser.parse_args()
    require(str(args.output).endswith('.bwp.zip'), 'Use the .bwp.zip extension')
    print(f'{build(args.recipe, args.images, args.output)}  {args.output.name}')


if __name__ == '__main__':
    main()
