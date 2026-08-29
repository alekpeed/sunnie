#!/usr/bin/env python3
"""Every contract fixture file must be read by both clients.

The fixtures under `Backend/contract` are the only thing holding the Swift and
Kotlin implementations of the shared game rules together (ADR-035). That job has
a quiet failure mode: a fixture file read by one client and not the other looks
exactly like a working contract — green tests, a file full of intended
behaviour — while constraining nothing on the side that never opens it.

This is cheap to check and impossible to notice by reading. It also catches the
narrower version of the same mistake: a file nobody reads at all, left behind
after a rename.

Run from the repository root. Exits non-zero with a specific complaint.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "Backend" / "contract"

# Where each client's suites live. Kept explicit rather than globbed from the
# whole tree so that a fixture referenced from application code — which would be
# a different mistake — does not count as being tested.
SUITES = {
    "Swift": ROOT / "Packages" / "SunnieShared" / "Tests",
    "Kotlin": ROOT / "Apps" / "Android" / "wire" / "src" / "test",
}


def sources(root: pathlib.Path) -> list[str]:
    if not root.is_dir():
        return []
    return [
        path.read_text(encoding="utf-8", errors="replace")
        for path in root.rglob("*")
        if path.is_file() and path.suffix in {".swift", ".kt"}
    ]


def main() -> int:
    if not CONTRACT.is_dir():
        print(f"No contract directory at {CONTRACT}", file=sys.stderr)
        return 1

    fixtures = sorted(p.name for p in CONTRACT.glob("*.json"))
    if not fixtures:
        print(f"No fixture files in {CONTRACT}", file=sys.stderr)
        return 1

    corpora = {name: sources(path) for name, path in SUITES.items()}
    for name, texts in corpora.items():
        if not texts:
            print(f"Found no {name} test sources under {SUITES[name]}", file=sys.stderr)
            return 1

    problems: list[str] = []
    for fixture in fixtures:
        readers = [
            name for name, texts in corpora.items()
            if any(fixture in text for text in texts)
        ]
        missing = [name for name in SUITES if name not in readers]
        if missing:
            problems.append(
                f"{fixture} is not read by: {', '.join(sorted(missing))}"
            )

    if problems:
        print("Contract fixtures are not pinning both clients:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nA fixture read by one client constrains one client. It looks like\n"
            "a contract and behaves like a document.",
            file=sys.stderr,
        )
        return 1

    print(f"All {len(fixtures)} contract fixtures are read by both clients:")
    for fixture in fixtures:
        print(f"  {fixture}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
