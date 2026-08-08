#!/usr/bin/env bash
#
# Parse every Swift file in the app targets.
#
# `swiftc -parse` runs the parser and nothing else: no imports resolved, no names
# looked up, no types checked. That makes it the only compiler-grade check that
# works on a machine with no Apple SDK — SwiftUI, SwiftData, UIKit and the rest
# are absent on Linux, so the app targets cannot be type-checked or built here at
# all (ADR-032 covers why the *shared package* is different).
#
# What this catches: genuine syntax errors — a malformed expression, a stray
# token, an unterminated string, a `guard` without `else`. Real defects that
# brace-balance counting cannot see.
#
# What it does NOT catch, and the distinction matters:
#
#   - whether any API used actually exists
#   - whether types line up
#   - whether protocol conformances are satisfied
#   - whether a SwiftUI body type-checks in reasonable time
#
# In other words: passing here means the files are well-formed Swift, not that
# they compile. `Documentation/COMPILE_RISK_REVIEW.md` §1 is the standing example
# — 34 call sites whose validity is a name-resolution question this check is
# blind to by construction.
#
# Usage:  ./Tools/parse_check.sh
# Exit 0 when every file parses.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Install a Swift toolchain, or run this on a Mac."
    exit 2
fi

mapfile -t files < <(find Apps Tests -name '*.swift' | sort)
echo "Parsing ${#files[@]} files with $(swiftc --version | head -1)"

failures=0
for file in "${files[@]}"; do
    output=$(swiftc -parse "$file" 2>&1)
    # A missing module is expected on every non-Apple machine and is not a
    # syntax problem; anything else is.
    real=$(echo "$output" | grep "error:" | grep -v "no such module")
    if [ -n "$real" ]; then
        failures=$((failures + 1))
        echo
        echo "── $file"
        echo "$real" | head -5
    fi
done

echo
if [ "$failures" -eq 0 ]; then
    echo "All ${#files[@]} files parse. (Syntax only — this is not a build.)"
    exit 0
fi

echo "$failures file(s) contain syntax errors."
exit 1
