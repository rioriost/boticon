#!/usr/bin/env python3
"""Build the wallpaper Shortcut; --sign validates it with Apple's signing service."""
import argparse
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "shortcuts/BoticonWallpaper.template.json"
RESOURCE = ROOT / "iOS/Boticon/Resources/Shortcuts/Boticon壁紙を変更.shortcut"


def validate(workflow):
    actions = workflow["WFWorkflowActions"]
    if [action["WFWorkflowActionIdentifier"] for action in actions] != [
        "com.example.boticon.NextWallpaperIntent", "is.workflow.actions.wallpaper.set"
    ]:
        raise ValueError("Expected only image retrieval and wallpaper setting")
    source = actions[0]["WFWorkflowActionParameters"]
    target = actions[1]["WFWorkflowActionParameters"]
    descriptor = source["AppIntentDescriptor"]
    if descriptor["BundleIdentifier"] != "com.example.boticon" or descriptor["AppIntentIdentifier"] != "NextWallpaperIntent":
        raise ValueError("Unexpected app intent")
    token = target["WFInput"]
    if token["WFSerializationType"] != "WFTextTokenAttachment" or token["Value"]["Type"] != "ActionOutput" or token["Value"]["OutputUUID"] != source["UUID"]:
        raise ValueError("Wallpaper input must refer to the app's image output")
    # Keep device-specific wallpaper identifiers and file paths out of the template.
    options = {"WFWallpaperShowPreview", "WFWallpaperSmartCrop", "WFWallpaperLegibilityBlur"}
    if set(source) != {"AppIntentDescriptor", "UUID"} or set(target) != {"WFInput", "UUID"} | options:
        raise ValueError("Unexpected action parameters; review before distributing")
    if any(target[key] is not False for key in options):
        raise ValueError("Preview, smart cropping and blur must be disabled")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign", action="store_true", help="Send only this workflow to Apple's standard signing service")
    parser.add_argument("--output", type=Path, default=RESOURCE)
    args = parser.parse_args()
    workflow = json.loads(TEMPLATE.read_text())
    validate(workflow)
    unsigned = ROOT / "build/shortcuts/BoticonWallpaper.unsigned.shortcut"
    unsigned.parent.mkdir(parents=True, exist_ok=True)
    unsigned.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
    print(f"Prepared unsigned workflow: {unsigned}")
    if args.sign:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".shortcut-sign-", dir=args.output.parent) as work:
            signed = Path(work) / args.output.name
            subprocess.run(["/usr/bin/shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)], check=True)
            if signed.read_bytes()[:4] != b"AEA1":
                raise ValueError("Signing did not produce the expected signed container")
            signed.chmod(0o644)
            signed.replace(args.output)
        print(f"Signed workflow: {args.output}")
    else:
        print("Not signed. Re-run with --sign to update the importable app resource.")


if __name__ == "__main__":
    main()
