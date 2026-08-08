#!/usr/bin/env python3
"""Reject interpolation in a localization *key*.

`String(localized:defaultValue:comment:)` types its key argument as
`StaticString`, because the key is what the tooling extracts into a String
Catalog at build time. Writing

    String(
        localized: "today.plants.seeAll \\(count)",   // <- key
        defaultValue: "See all \\(count)",            // <- fine, and correct
        comment: "..."
    )

fails with `cannot convert value of type 'String' to expected argument type
'StaticString'`. The interpolation belongs in `defaultValue`, which is a
`String.LocalizationValue` and is designed to carry arguments; the key must
stay constant, since a key that varies per value could never be looked up.

Sixteen call sites had this shape and it survived every static review, because
nothing short of an Apple type checker distinguishes the key position from the
default-value position. This makes the distinction checkable anywhere.

Usage:  python3 Tools/validate_localization_keys.py
Exit 0 when every localization key is a constant.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH = [ROOT / "Apps", ROOT / "Tests"]

# The key argument, up to the closing quote of its literal. Escapes are honoured
# so a quote inside the literal does not end the match early.
KEY = re.compile(r'localized:\s*"((?:[^"\\]|\\.)*)"')


def main() -> int:
    failures: list[tuple[str, int, str]] = []
    scanned = 0

    for root in SEARCH:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            scanned += 1
            for number, line in enumerate(path.read_text().split("\n"), start=1):
                match = KEY.search(line)
                if match and "\\(" in match.group(1):
                    failures.append(
                        (str(path.relative_to(ROOT)), number, match.group(1))
                    )

    if failures:
        for file, number, key in failures:
            print(f"FAIL {file}:{number}")
            print(f'       key "{key}" interpolates a runtime value')
        print(
            f"\n{len(failures)} localization key(s) are not constant.\n"
            "Move the interpolation into defaultValue and leave the key static."
        )
        return 1

    print(f"Every localization key across {scanned} files is a constant.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
