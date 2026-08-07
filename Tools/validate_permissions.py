#!/usr/bin/env python3
"""Check that every permission the code asks for has a purpose string.

    python3 Tools/validate_permissions.py

iOS terminates an app that requests a protected resource without the matching
`Info.plist` purpose string. It is not a warning and not a denied prompt — the
process is killed. That makes this the single nastiest class of bug to hit for
the first time on a device: it looks like a crash in whatever code happened to be
running, and the real cause is a missing line in a plist.

It also cannot be caught by the compiler, by the Simulator in most cases, or by
any test that does not run on hardware. So it is caught here instead, by matching
the frameworks the source actually touches against the keys the plists actually
declare.

Exit code 0 means every requested permission is declared. Non-zero lists what is
missing, and which file asked for it.
"""

from __future__ import annotations

import pathlib
import plistlib
import re
import sys

# A permission-gated API, the plist keys it requires, and a human name.
#
# `patterns` are matched against source text. They are deliberately the call that
# triggers the prompt rather than the `import`, because importing HealthKit to
# check availability is fine and common — it is `requestAuthorization` that gets
# the app killed.
RULES = [
    {
        "name": "HealthKit (read)",
        "patterns": [r"requestAuthorization\s*\(\s*toShare:", r"\.execute\(\s*HKSampleQuery"],
        "keys": ["NSHealthShareUsageDescription"],
    },
    {
        "name": "HealthKit (write)",
        "patterns": [r"requestAuthorization\s*\(\s*toShare:", r"store\.save\("],
        "keys": ["NSHealthUpdateUsageDescription"],
    },
    {
        "name": "Calendar",
        # iOS 17+ splits calendar access; `requestFullAccessToEvents` needs the
        # FullAccess key specifically, not the older NSCalendarsUsageDescription.
        "patterns": [r"requestFullAccessToEvents", r"requestWriteOnlyAccessToEvents"],
        "keys": ["NSCalendarsFullAccessUsageDescription"],
    },
    {
        "name": "Microphone",
        "patterns": [r"requestRecordPermission", r"AVAudioRecorder\("],
        "keys": ["NSMicrophoneUsageDescription"],
    },
    {
        "name": "Camera",
        "patterns": [r"AVCaptureDevice", r"AVCaptureSession"],
        "keys": ["NSCameraUsageDescription"],
    },
    {
        "name": "Photo library (direct access)",
        # `PhotosPicker` runs out of process and needs no purpose string; only
        # direct `PHPhotoLibrary` access does. Listing both would demand a key
        # the app does not actually need.
        "patterns": [r"PHPhotoLibrary", r"PHAsset\b"],
        "keys": ["NSPhotoLibraryUsageDescription"],
    },
    {
        "name": "Location",
        "patterns": [r"requestWhenInUseAuthorization", r"requestAlwaysAuthorization"],
        "keys": ["NSLocationWhenInUseUsageDescription"],
    },
    {
        "name": "Contacts",
        "patterns": [r"CNContactStore"],
        "keys": ["NSContactsUsageDescription"],
    },
    {
        "name": "Speech recognition",
        "patterns": [r"SFSpeechRecognizer"],
        "keys": ["NSSpeechRecognitionUsageDescription"],
    },
    {
        "name": "Local network",
        "patterns": [r"NWBrowser", r"NetServiceBrowser"],
        "keys": ["NSLocalNetworkUsageDescription"],
    },
]

# Each target: where its Swift lives, and where its Info.plist is.
TARGETS = [
    ("iPhone app", "Apps/iOS", "Apps/iOS/Resources/Info.plist"),
    ("Watch app", "Apps/Watch", "Apps/Watch/Resources/Info.plist"),
    ("Widgets", "Apps/Widgets", "Apps/Widgets/Resources/Info.plist"),
]


def strip_comments(source: str) -> str:
    """Remove comments so a mention in prose does not count as a use.

    Every one of these files documents its own permission handling at length, so
    without this the doc comment explaining why HealthKit is optional would
    itself trigger the HealthKit rule.
    """
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def audit() -> list[str]:
    problems: list[str] = []

    for label, source_dir, plist_path in TARGETS:
        root = pathlib.Path(source_dir)
        if not root.exists():
            continue

        plist_file = pathlib.Path(plist_path)
        if not plist_file.exists():
            problems.append(f"{label}: no Info.plist at {plist_path}")
            continue
        declared = set(plistlib.load(plist_file.open("rb")).keys())

        # Which rule each file triggers, so a failure names the culprit.
        triggered: dict[str, list[str]] = {}
        for swift in root.rglob("*.swift"):
            text = strip_comments(swift.read_text())
            for rule in RULES:
                if any(re.search(p, text) for p in rule["patterns"]):
                    triggered.setdefault(rule["name"], []).append(str(swift))

        for rule in RULES:
            files = triggered.get(rule["name"])
            if not files:
                continue
            for key in rule["keys"]:
                if key not in declared:
                    problems.append(
                        f"{label}: {rule['name']} is requested but {key} is not in "
                        f"{plist_path}.\n    asked for in: " + ", ".join(sorted(files))
                    )

        # The reverse direction is worth a note but never a failure: an unused
        # purpose string is harmless at run time, though App Review does ask why
        # it is there.
        used_keys = {k for r in RULES if r["name"] in triggered for k in r["keys"]}
        for key in sorted(declared):
            if key.endswith("UsageDescription") and key not in used_keys:
                problems.append(
                    f"Note: {label} declares {key} but nothing appears to use it."
                )

    return problems


def main() -> int:
    problems = audit()
    failures = [p for p in problems if not p.startswith("Note:")]

    for problem in problems:
        print(problem)

    if failures:
        print(f"\n{len(failures)} missing purpose string(s). "
              "The app will be terminated by iOS on a device.")
        return 1

    print("Every requested permission has a purpose string.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
