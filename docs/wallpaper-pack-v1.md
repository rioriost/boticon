# Boticon Wallpaper Pack v1 (BWP)

Status: version 1, 2026-10-29. This specification and its implementation are published under the repository's MIT license. Image rights are independent. BWP is an application format, not an industry standard.

## Choice of format

We did not find a cross-platform static-wallpaper distribution standard that specifies a JSON catalog, attribution and per-image integrity checks together. Wallpaper Engine uses an application-specific [`project.json`](https://docs.wallpaperengine.io/en/web/first/gettingstarted.html), including executable web wallpapers. [BagIt (RFC 8493)](https://www.rfc-editor.org/rfc/rfc8493.html) provides general payload/checksum packaging, but does not define wallpaper catalog metadata or a JSON manifest. BWP therefore defines a small wallpaper-specific profile of standard ZIP plus UTF-8 JSON. It does not claim compatibility with those formats.

## Container

Recommended extension: `.bwp.zip`; HTTP Content-Type: `application/zip` (not mandatory). One pack contains 1–500 static images and a root `manifest.json`. Every manifest image MUST exist and every ZIP entry MUST be listed (except `manifest.json`). No directory entries, previews, scripts, hidden files, thumbnails, executables or remote image references.

```
manifest.json
wallpapers/star.png
wallpapers/moon.jpg
```

ZIP profile (normative):

- Single-disk, classic ZIP; method **0 (stored)** only. PNG/JPEG data is already compressed. Deflate, ZIP64, encryption and data descriptors are rejected.
- Names are ASCII, exact case. General purpose flags may be 0 or `0x0800` (UTF-8). Version needed <=20. No extra fields, entry/archive comments, split volumes, prepended/trailing data or gaps.
- Local entries and central-directory entries have the same order; local headers and central records agree on path, flags, method, CRC-32 and sizes. Every payload CRC-32 is checked. Records must be contiguous and non-overlapping.
- Entries are regular files: Unix type 0 or regular-file type; no symlinks, directories or devices. DOS directory flag is disallowed. Permissions are never applied to disk.
- The only paths permitted are `manifest.json` and `wallpapers/<id>.png` / `wallpapers/<id>.jpg`. No backslashes, absolute paths, traversal, duplicate entries or nested paths. Extraction uses app-generated names, never archive paths.
- Compressed and uncompressed sizes are equal. Archive <=268,435,456 bytes (256MiB); manifest <=1,048,576 bytes; each image <=20,971,520 bytes. Maximum 501 entries.

Use `tools/build_wallpaper_pack.py` to produce this strict profile. Arbitrary ZIP utilities may add unsupported compression, metadata or directories. A pack larger than 256MiB must be split into independently identified packs. The app accepts at most 100 packs, 2GiB of image bytes and a 16MiB installed catalog.

## Manifest

See the machine-readable [JSON Schema](wallpaper-pack-v1.schema.json). JSON is an object, encoded as UTF-8 without a BOM. Unknown keys are reserved for compatible extensions and ignored by v1 readers; extensions cannot change validation requirements. Producers must use unique object keys. A schema or format change that alters semantics requires a new version; v1 readers reject unsupported schema versions.

An illustrative manifest (the checksum must be replaced with the actual image's digest):

```json
{
  "format": "boticon-wallpaper-pack",
  "schemaVersion": 1,
  "id": "example-stars",
  "revision": 1,
  "name": "Example Stars",
  "author": "Example creator",
  "license": "CC0-1.0; original artwork by Example creator",
  "homepage": "https://example.com/wallpapers",
  "wallpapers": [
    {
      "id": "star",
      "name": "Star",
      "file": "wallpapers/star.png",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "bytes": 1000,
      "width": 1320,
      "height": 2868,
      "mediaType": "image/png",
      "anchor": "lowerLeft",
      "organization": "Example group",
      "aliases": ["Example Star"],
      "debutDate": "2020-01-01",
      "attribution": "Original fictional character; copyright Example creator",
      "aiGenerated": false
    }
  ]
}
```

Required top-level fields:

| Field | Meaning |
| --- | --- |
| `format`, `schemaVersion` | Exactly `boticon-wallpaper-pack` and integer `1` |
| `id` | Stable pack ID; 1–64 lowercase ASCII letters/digits/hyphens; starts and ends with letter/digit |
| `revision` | Positive integer, increases for every update; no floating-point values |
| `name`, `author` | Nonempty human-readable strings, <=200 characters |
| `license` | Nonempty use/distribution terms, <=4,000 characters; optionally an SPDX identifier plus explanatory terms. The app does not infer rights from it |
| `wallpapers` | 1–500 image records; unique `id` and `file` within the pack |

`homepage` is optional; if present it must be HTTPS, without credentials or fragments, and port 443/default. It is opened only by an explicit user action.

Required image fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable image/subject ID with the same syntax as pack `id`; preserve the source ID rather than deriving a replacement from the display name |
| `name` | Nonempty display name, <=200 characters |
| `file` | Exactly `wallpapers/<id>.png` or `.jpg`, matching `mediaType` |
| `sha256` | 64 lowercase hex characters; SHA-256 of the exact archived image bytes |
| `bytes` | Positive integer; exact image byte count |
| `width`, `height` | Positive integer pixel dimensions; each <=8,192; product <=24,000,000 |
| `mediaType` | `image/png` or `image/jpeg`; checked against ImageIO's decoded type |
| `anchor` | `lowerLeft` or `lowerRight`, used by existing wallpaper layout |
| `attribution` | Nonempty source/creator/rights notice, <=4,000 characters |
| `aiGenerated` | Boolean, publisher's declaration; displayed with attribution in the app |

Optional: `organization` (nonempty <=200 characters), `aliases` (<=20 nonempty strings each <=200), `debutDate` (a real calendar date `YYYY-MM-DD`; omit if unknown). Null is not a substitute for a required value. Text must not contain control characters except newline. PNG/JPEG must decode completely as one image frame, not SVG, HTML, GIF, HEIC, animation or executable content. The manifest dimensions must equal the decoded dimensions. The app validates pixels before installation and does not run embedded content.

## Acquisition, installation and updates

1. User enters a publicly reachable HTTPS URL and optionally an independently obtained archive SHA-256. HTTP, credentials, fragments, non-default ports, localhost/`.local` hosts and IP literals are rejected.
2. Ephemeral URLSession makes a GET; no shared cookies, stored credentials, analytics or background polling. Normal system TLS certificate checks apply. Authentication challenges other than TLS are refused. Up to five redirects, each subject to the same HTTPS URL checks. The original URL is the recorded distribution source, even when a CDN redirect is used.
3. Only HTTP 200 is accepted. Declared response size and received bytes are bounded. Data streams to a temporary file; timeout and cancellation clean up partial data.
4. Verify optional archive SHA-256, ZIP structure/CRC, manifest, image SHA-256/byte lengths, raster type, frames, dimensions and decode. No file enters the live catalog during this stage.
5. Show source host, author, license, count, revision, AI declaration and archive SHA-256. User confirms addition.
6. Write into a new app-generated UUID directory; atomically replace the catalog index only when all writes succeed. Failed downloads, validation or commits retain the previous installed pack. Abandoned staging directories are cleaned at next launch. Storage is in Application Support, available after first device unlock; system backup may include it.
7. The same pack ID updates only from the same original HTTPS host and only at a greater revision. All entries in the pack are replaced together. The user fetches and confirms each update; there is no automatic update or publisher code execution. Source changes require explicit deletion and re-addition.
8. App-internal selection IDs are `p-<SHA256(UTF8(pack id))>-<image id>`, preventing cross-pack collisions. Original manifest IDs are retained unchanged; they are not replaced in producer master data. Selection and placement persist for retained IDs; removed IDs leave the selection pool. Deletion removes that pack's local images, catalog and selection, not system wallpaper, Photos copies or Shortcuts.

## Security and trust boundaries

SHA-256 and CRC establish **integrity**, not publisher identity, copyright permission or absence of malicious intent. Someone controlling the archive can replace both image and manifest hashes. An optional whole-archive digest helps only if obtained through an independently trusted channel. BWP v1 is not digitally signed, has no key registry or publisher verification, and does not claim protection against a compromised distribution host. Same-host update restrictions reduce accidental substitution; an untrusted initial pack can still claim an arbitrary ID/name/author.

HTTPS URL checks are not a network isolation firewall: a public-looking domain may resolve or redirect at DNS level to a private address. The app sends an explicit unauthenticated GET only; users should fetch URLs from trusted publishers. It does not send existing wallpaper files, selection state or credentials to that host. The host sees normal connection information including IP address, requested path/query and timing. Private/tokenized URLs may remain in the on-device installed index; do not paste secrets into URLs. Redirects may reveal the request to additional hosts. No URL/hash is sent to the developer's own service.

No checksum can establish legal rights. Distributing the artwork separately from the app does not itself confer redistribution rights. Producers must obtain any required permissions, preserve provenance and state accurate license/AI notices. MIT covers this specification and code, not separately supplied images or characters.

## Producer tool

Create a recipe with the same manifest fields; `sha256`, `bytes`, `width`, `height`, `mediaType` can be omitted because the tool derives/replaces them from the image bytes. Place images under `input/wallpapers/` using the recipe paths.

```sh
python3 tools/build_wallpaper_pack.py recipe.json input output.bwp.zip
```

The tool uses Python's standard library, writes stored ZIP regular-file entries and prints the archive SHA-256. It refuses to overwrite an existing output. Its header inspection is not a full decoder; the app performs additional complete-image verification. Do not commit generated archives/images/real-person manifests to the source-only repository. Test cases generate invented fixtures locally.
