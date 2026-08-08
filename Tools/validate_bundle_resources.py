#!/usr/bin/env python3
"""Catch resource filenames that would collide inside a built app bundle.

The project uses Xcode 16 synchronized folder groups: a folder is added to a
target once, and every file inside it is a member from then on, with no per-file
entry in the project. That is a good arrangement for a codebase with 129 source
files, and it has one sharp edge.

Copying a resource flattens it. `Features/Meals/README.md` and
`Features/Travel/README.md` both land at `SunnieDays.app/README.md`, and the
build system refuses:

    error: Multiple commands produce '.../SunnieDays.app/README.md'

This is not a compile error. It happens before a single line of Swift is
compiled, so it fails the whole build in about twenty seconds and tells you
nothing about your code. It cost this project its first real build attempt, and
it recurs the moment anyone adds a README to a new feature folder — which is a
thing this repository actively encourages.

The check: for every synchronized folder group, find files that would be copied
as resources, drop the ones the project explicitly excepts, and assert no two
share a basename.

Usage:  python3 Tools/validate_bundle_resources.py
Exit 0 when no collision is possible.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "SunnieDays.xcodeproj" / "project.pbxproj"

# Compiled, not copied — these never reach the bundle as files.
COMPILED_SUFFIXES = {".swift", ".m", ".mm", ".c", ".h", ".metal"}

# Bundled as a single unit by their own compiler, so the files inside them are
# not individually copied and their internal names cannot collide.
OPAQUE_DIR_SUFFIXES = (".xcassets", ".xcdatamodeld", ".lproj", ".bundle", ".docc")

# Consumed by the build settings rather than copied.
IGNORED_NAMES = {".DS_Store", "Info.plist"}


def parse_exception_sets(text: str) -> dict[str, list[str]]:
    """Map each exception-set id to the paths it excludes from its target."""
    sets: dict[str, list[str]] = {}
    section = re.search(
        r"/\* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section \*/(.*?)"
        r"/\* End PBXFileSystemSynchronizedBuildFileExceptionSet section \*/",
        text,
        re.S,
    )
    if not section:
        return sets

    for block in re.finditer(
        r"([0-9A-F]{24})\s*/\*.*?\*/\s*=\s*\{(.*?)\n\t\t\};", section.group(1), re.S
    ):
        identifier, body = block.group(1), block.group(2)
        members = re.search(r"membershipExceptions\s*=\s*\((.*?)\);", body, re.S)
        if not members:
            sets[identifier] = []
            continue
        sets[identifier] = [
            entry.strip().strip('",')
            for entry in members.group(1).split("\n")
            if entry.strip().strip('",')
        ]
    return sets


def parse_group_paths(text: str) -> dict[str, str]:
    """Map each child group id to its parent group's path, so a root group's
    `path = iOS` can be resolved to the real `Apps/iOS` on disk."""
    parents: dict[str, str] = {}
    section = re.search(
        r"/\* Begin PBXGroup section \*/(.*?)/\* End PBXGroup section \*/", text, re.S
    )
    if not section:
        return parents

    for block in re.finditer(
        r"([0-9A-F]{24})\s*/\*.*?\*/\s*=\s*\{(.*?)\n\t\t\};", section.group(1), re.S
    ):
        body = block.group(2)
        path = re.search(r"\n\t\t\tpath\s*=\s*([^;]+);", body)
        children = re.search(r"children\s*=\s*\((.*?)\);", body, re.S)
        if not path or not children:
            continue
        parent_path = path.group(1).strip().strip('"')
        for child in re.finditer(r"([0-9A-F]{24})", children.group(1)):
            parents[child.group(1)] = parent_path
    return parents


def parse_root_groups(text: str) -> list[tuple[str, str, list[str]]]:
    """Return (id, folder name, exception-set ids) for each synchronized group."""
    groups: list[tuple[str, str, list[str]]] = []
    section = re.search(
        r"/\* Begin PBXFileSystemSynchronizedRootGroup section \*/(.*?)"
        r"/\* End PBXFileSystemSynchronizedRootGroup section \*/",
        text,
        re.S,
    )
    if not section:
        return groups

    for block in re.finditer(
        r"([0-9A-F]{24})\s*/\*.*?\*/\s*=\s*\{(.*?)\n\t\t\};", section.group(1), re.S
    ):
        identifier, body = block.group(1), block.group(2)
        path = re.search(r"\n\t\t\tpath\s*=\s*([^;]+);", body)
        if not path:
            continue
        exception_ids = re.findall(r"([0-9A-F]{24})\s*/\* Exceptions", body)
        groups.append((identifier, path.group(1).strip().strip('"'), exception_ids))
    return groups


def copied_resources(folder: Path, excepted: set[str]) -> list[Path]:
    """Files under `folder` that the build system would copy into the bundle."""
    found: list[Path] = []
    for path in sorted(folder.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(folder)
        if any(part.endswith(OPAQUE_DIR_SUFFIXES) for part in relative.parts[:-1]):
            continue
        if path.suffix in COMPILED_SUFFIXES:
            continue
        if path.name in IGNORED_NAMES or path.name.startswith("."):
            continue
        if str(relative) in excepted:
            continue
        found.append(relative)
    return found


def main() -> int:
    if not PROJECT.exists():
        print(f"Project file not found at {PROJECT}")
        return 2

    text = PROJECT.read_text()
    exception_sets = parse_exception_sets(text)
    parents = parse_group_paths(text)
    groups = parse_root_groups(text)

    if not groups:
        print("No synchronized folder groups found — has the project format changed?")
        return 2

    failures = 0
    for identifier, name, exception_ids in groups:
        parent = parents.get(identifier)
        folder = ROOT / parent / name if parent else ROOT / name
        if not folder.is_dir():
            print(f"FAIL {name}: folder not found at {folder}")
            failures += 1
            continue

        excepted: set[str] = set()
        for exception_id in exception_ids:
            excepted.update(exception_sets.get(exception_id, []))

        by_name: dict[str, list[Path]] = defaultdict(list)
        for relative in copied_resources(folder, excepted):
            by_name[relative.name].append(relative)

        collisions = {n: paths for n, paths in by_name.items() if len(paths) > 1}
        if not collisions:
            print(f"ok   {folder.relative_to(ROOT)}: no colliding resource names")
            continue

        failures += 1
        for basename, paths in sorted(collisions.items()):
            print(f"FAIL {folder.relative_to(ROOT)}: {len(paths)} files named {basename}")
            for path in paths:
                print(f"       {path}")
            print(
                "       All flatten to the same path in the bundle. Add all but one\n"
                "       to membershipExceptions for this folder, or rename them."
            )

    if failures:
        print(f"\n{failures} folder(s) would produce a bundle-resource collision.")
        return 1

    print("\nNo bundle-resource collisions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
