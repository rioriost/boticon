# Public source repository

This repository contains source code only, under the MIT license.

- Do not commit artwork, generated images, screenshots containing artwork, real member rosters, source observations, production records, credentials, provisioning profiles, or signed binaries.
- Keep `iOS/Boticon/Resources/catalog.json` empty in published commits. Real catalog entries and wallpaper files belong in a private working copy.
- Use invented identifiers and names in tests. Do not copy real people or organization records into test fixtures.
- Keep developer signing settings out of `project.yml`. Developers choose their own team locally.
- Generate the Xcode project with `xcodegen generate`; do not commit generated projects or build results.
- Run `swift test`, `python3 -m unittest discover -s Tests -p 'test_*.py' -v`, and `python3 tools/check_public_source.py` before publishing. The last command checks the Git index as well as tracked working files; stage intended changes first.
- Changes to the repository do not grant rights to separately supplied images, names, characters, logos, or datasets.
