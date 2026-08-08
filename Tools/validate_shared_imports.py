#!/usr/bin/env python3
"""Find app-target files that use a SunnieShared type without importing it.

Swift resolves names per file, not per target: a file that says only
`import Foundation` cannot see `DeepLinkScheme` even though every other file
around it can. The result is a single error —

    error: cannot find 'DeepLinkScheme' in scope

— which is trivial to fix and expensive to find, because a build reports it only
after compiling everything ahead of it, and the next missing import is not
reported until that one is fixed. Found serially, each costs a full CI round
trip on a macOS runner. Found here, they all arrive at once, on Linux, in a
second.

The check is deliberately conservative. It flags a file only when the symbol is
public in SunnieShared, the file does not import SunnieShared, and no file
compiled into the same target declares that name itself. Anything less certain
is left alone: a validator that cries wolf gets switched off, and this one is
meant to survive.

Usage:  python3 Tools/validate_shared_imports.py
Exit 0 when every use of a shared type is backed by an import.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "Packages" / "SunnieShared" / "Sources" / "SunnieShared"

# Each app target compiles one folder (Xcode synchronized groups), so a name
# declared anywhere in the folder is visible to every file in it.
TARGETS = {
    "SunnieDays": ROOT / "Apps" / "iOS",
    "SunnieDaysWatch": ROOT / "Apps" / "Watch",
    "SunnieWidgets": ROOT / "Apps" / "Widgets",
}

DECLARATION = re.compile(
    r"^\s*(?:public\s+|internal\s+|final\s+|@\w+\s+)*"
    r"(?:struct|enum|class|actor|protocol|extension|typealias)\s+([A-Z]\w*)",
    re.M,
)
PUBLIC_DECLARATION = re.compile(
    r"^\s*(?:@\w+\s+)*public\s+(?:final\s+)?"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Z]\w*)",
    re.M,
)


def strip_noise(source: str) -> str:
    """Remove comments and string literals so a name mentioned in prose or in a
    localization key is not mistaken for a use of the type."""
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', source)
    return source


def public_symbols() -> set[str]:
    names: set[str] = set()
    for path in SHARED.rglob("*.swift"):
        names.update(PUBLIC_DECLARATION.findall(strip_noise(path.read_text())))
    return names


def declared_in(folder: Path) -> set[str]:
    names: set[str] = set()
    for path in folder.rglob("*.swift"):
        names.update(DECLARATION.findall(strip_noise(path.read_text())))
    return names


def main() -> int:
    if not SHARED.is_dir():
        print(f"Shared sources not found at {SHARED}")
        return 2

    shared = public_symbols()
    if not shared:
        print("No public symbols found in SunnieShared — has the layout changed?")
        return 2

    findings: dict[Path, set[str]] = defaultdict(set)
    for target, folder in TARGETS.items():
        if not folder.is_dir():
            print(f"FAIL {target}: folder not found at {folder}")
            return 2

        # A target may legitimately declare its own type with a shared name;
        # that shadows rather than requires the import.
        local = declared_in(folder)
        candidates = shared - local

        for path in sorted(folder.rglob("*.swift")):
            source = path.read_text()
            if re.search(r"^\s*import\s+SunnieShared\b", source, re.M):
                continue
            body = strip_noise(source)
            used = {
                name
                for name in candidates
                if re.search(rf"\b{re.escape(name)}\b", body)
            }
            if used:
                findings[path.relative_to(ROOT)] = used

    if not findings:
        print(f"All uses of the {len(shared)} public SunnieShared types are imported.")
        return 0

    for path, used in sorted(findings.items()):
        print(f"FAIL {path}")
        print(f"       uses {', '.join(sorted(used))} without `import SunnieShared`")

    print(f"\n{len(findings)} file(s) need `import SunnieShared`.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
