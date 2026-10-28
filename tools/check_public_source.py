#!/usr/bin/env python3
"""Reject non-source material in both the Git index and tracked working files."""
import json
import re
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
CATALOG = "iOS/Boticon/Resources/catalog.json"
EMPTY_CATALOG = {"schemaVersion": 1, "source": "", "capturedAt": "", "members": []}
TOP_FILES = {"LICENSE", "README.md", "AGENTS.md", "Package.swift", "project.yml", ".gitignore", ".gitattributes"}


def validate(path, content):
    item = PurePosixPath(path)
    allowed = path in TOP_FILES or path == CATALOG or path in {
        "iOS/Boticon/Resources/Wallpapers/.gitkeep", "iOS/Boticon/Resources/Shortcuts/.gitkeep",
        "iOS/Info.plist", "iOS/UITests/Info.plist", "shortcuts/BoticonWallpaper.template.json"
    } or any(path.startswith(prefix) and item.suffix == suffix for prefix, suffix in [
        ("Sources/BoticonCore/", ".swift"), ("iOS/Boticon/", ".swift"),
        ("iOS/UITests/", ".swift"), ("Tests/BoticonCoreTests/", ".swift"),
        ("Tests/", ".py"), ("tools/", ".py")
    ])
    if not allowed or ".." in item.parts:
        raise ValueError(f"File is outside the public source allowlist: {path}")
    if len(content) > 200_000:
        raise ValueError(f"Unexpectedly large source file: {path}")
    text = content.decode("utf-8")
    if "\x00" in text:
        raise ValueError(f"Binary content: {path}")
    if path == CATALOG and json.loads(text) != EMPTY_CATALOG:
        raise ValueError("The public catalog must contain no records or source metadata")
    if path.endswith(".gitkeep") and content:
        raise ValueError(f"Resource placeholder must be empty: {path}")
    if path == "project.yml" and "DEVELOPMENT_TEAM:" in text:
        raise ValueError("Developer signing team must stay local")
    for pattern in [r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----", r"\bgh[pousr]_[A-Za-z0-9]{20,}",
                    r"\bgithub_pat_[A-Za-z0-9_]{40,}", r"/Users/[^\s\"']+/"]:
        if re.search(pattern, text):
            raise ValueError(f"Possible credential or local user path: {path}")


def main():
    result = subprocess.run(["git", "ls-files", "--stage", "-z"], cwd=ROOT,
                            check=True, capture_output=True)
    entries = [entry for entry in result.stdout.split(b"\0") if entry]
    if not entries:
        raise ValueError("Stage the intended public source files before checking")
    paths = set()
    for entry in entries:
        metadata, raw_path = entry.split(b"\t", 1)
        mode, _, stage = metadata.split()
        path = raw_path.decode("utf-8")
        if mode not in {b"100644", b"100755"} or stage != b"0":
            raise ValueError(f"Symlink, submodule or conflicted entry: {path}")
        staged = subprocess.run(["git", "show", f":{path}"], cwd=ROOT,
                                check=True, capture_output=True).stdout
        validate(path, staged)
        work = ROOT / path
        if work.is_symlink() or not work.is_file():
            raise ValueError(f"Missing or symbolic working file: {path}")
        validate(path, work.read_bytes())
        paths.add(path)
    if not {"LICENSE", "README.md", CATALOG} <= paths:
        raise ValueError("Required public source files are missing")
    print(f"Verified {len(paths)} source files; empty catalog, no artwork or signed binaries")


if __name__ == "__main__":
    main()
