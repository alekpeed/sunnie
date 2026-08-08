#!/usr/bin/env python3
"""Check each bundle's Info.plist carries the keys its type requires.

This exists because of a failure that is invisible to every earlier check in
this repository. The widget extension's Info.plist had no `CFBundleExecutable`.
It parsed, it validated, the extension compiled, linked, and was embedded, and
the whole app built clean — then `installd` refused to install it:

    SunnieDays.app/PlugIns/SunnieWidgets.appex has missing or invalid
    CFBundleExecutable in its Info.plist

An app embedding an executable-less extension is rejected as a unit, so a
missing key in the smallest target took the phone app down with it. Every test
in the run failed, none of them for its own reason, and the message named
installd rather than anything in the project.

A green build says nothing about this. It costs a full macOS run to discover and
about a second to check.

Usage:  python3 Tools/validate_info_plists.py
Exit 0 when every bundle declares what its type requires.
"""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Keys every CFBundle needs to be installable, whatever its type.
COMMON = ["CFBundleExecutable", "CFBundleIdentifier", "CFBundlePackageType"]

BUNDLES = {
    "Apps/iOS/Resources/Info.plist": {
        "kind": "application",
        "package_type": "APPL",
        # ITSAppUsesNonExemptEncryption is not needed to build or install. It is
        # needed to *distribute*: without it every TestFlight upload lands as
        # "Missing Compliance" and sits undistributable until someone answers
        # the question by hand in a web form, once per build, forever.
        "required": COMMON
        + [
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "ITSAppUsesNonExemptEncryption",
        ],
    },
    "Apps/Watch/Resources/Info.plist": {
        "kind": "watch application",
        "package_type": "APPL",
        "required": COMMON + ["CFBundleShortVersionString", "CFBundleVersion"],
    },
    "Apps/Widgets/Resources/Info.plist": {
        "kind": "app extension",
        "package_type": "XPC!",
        "required": COMMON + ["NSExtension"],
    },
}


# An asset catalog entry naming no file produces a bundle with no icon, which
# builds and installs perfectly and is refused at upload. Both catalogs are
# checked because the Watch has its own.
APP_ICONS = [
    "Apps/iOS/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "Apps/Watch/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
]


def check_app_icons() -> int:
    """Every declared icon slot must name a file that exists."""
    failures = 0

    for relative in APP_ICONS:
        path = ROOT / relative
        if not path.is_file():
            print(f"FAIL {relative}: not found")
            failures += 1
            continue

        try:
            images = json.loads(path.read_text()).get("images", [])
        except json.JSONDecodeError as error:
            print(f"FAIL {relative}: not readable JSON — {error}")
            failures += 1
            continue

        if not images:
            print(f"FAIL {relative}: declares no icon")
            failures += 1
            continue

        # Counted per catalog, so a fault in the first does not suppress the
        # second's report — both are wanted in one run.
        faults = 0
        for image in images:
            filename = image.get("filename")
            if not filename:
                size = image.get("size", "?")
                print(f"FAIL {relative}: the {size} slot names no file")
                faults += 1
            elif not (path.parent / filename).is_file():
                print(f"FAIL {relative}: {filename} is named but missing")
                faults += 1

        failures += faults
        if not faults:
            print(f"ok   {relative} (app icon)")

    return failures


def main() -> int:
    failures = check_app_icons()

    for relative, spec in BUNDLES.items():
        path = ROOT / relative
        if not path.is_file():
            print(f"FAIL {relative}: not found")
            failures += 1
            continue

        try:
            plist = plistlib.loads(path.read_bytes())
        except Exception as error:  # malformed plist is itself the finding
            print(f"FAIL {relative}: not a readable plist — {error}")
            failures += 1
            continue

        missing = [key for key in spec["required"] if key not in plist]
        if missing:
            failures += 1
            print(f"FAIL {relative} ({spec['kind']})")
            for key in missing:
                print(f"       missing {key}")
            continue

        actual = plist.get("CFBundlePackageType")
        if actual != spec["package_type"]:
            failures += 1
            print(
                f"FAIL {relative} ({spec['kind']}): CFBundlePackageType is "
                f"{actual!r}, expected {spec['package_type']!r}"
            )
            continue

        # An extension that declares no extension point is loaded by nothing.
        if spec["kind"] == "app extension":
            point = plist.get("NSExtension", {}).get("NSExtensionPointIdentifier")
            if not point:
                failures += 1
                print(f"FAIL {relative}: NSExtension has no NSExtensionPointIdentifier")
                continue

        print(f"ok   {relative} ({spec['kind']})")

    if failures:
        print(f"\n{failures} problem(s) would be rejected at install or upload time.")
        return 1

    print("\nEvery bundle declares what its type requires, and every icon slot has a file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
