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
        "required": COMMON + ["CFBundleShortVersionString", "CFBundleVersion"],
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


def main() -> int:
    failures = 0

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
        print(f"\n{failures} bundle(s) would be rejected at install time.")
        return 1

    print("\nEvery bundle declares what its type requires.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
