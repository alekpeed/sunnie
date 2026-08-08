#!/usr/bin/env bash
#
# Choose an Xcode and export it as DEVELOPER_DIR for the rest of the job.
#
# This replaces a hardcoded `/Applications/Xcode_16.app/...` in the workflow.
# The pin was well-intentioned — PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §11
# asks for a known toolchain rather than whatever a runner happens to default to
# — but a literal path is pinned to the *runner image*, not to the toolchain.
# GitHub retires image versions on a schedule, and when that path stops existing
# every Xcode step in the job fails at once, with an error that names a missing
# directory rather than a missing Xcode.
#
# So: prefer a version that satisfies the project's floor, take the newest one
# installed, and say out loud which one was chosen. A build whose compiler
# version is printed in its own log is one you can reason about later; a build
# that silently used something else is not.
#
# Usage:  ./Tools/select_xcode.sh
# Writes DEVELOPER_DIR to $GITHUB_ENV when run under Actions, and prints the
# selection either way.

set -euo pipefail

# iOS 18 and watchOS 11 SDKs arrived in Xcode 16 (Config/Shared.xcconfig sets
# both deployment targets). Anything older cannot build this project at all.
MINIMUM_MAJOR=16

if [ ! -d /Applications ]; then
    echo "No /Applications directory — this script is for macOS runners."
    exit 1
fi

best=""
best_version=""
for app in /Applications/Xcode*.app; do
    [ -d "$app" ] || continue
    plist="$app/Contents/version.plist"
    [ -f "$plist" ] || continue

    version=$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null || true)
    [ -n "$version" ] || continue

    major=${version%%.*}
    case "$major" in
        ''|*[!0-9]*) continue ;;
    esac
    [ "$major" -ge "$MINIMUM_MAJOR" ] || continue

    # Newest wins. `sort -V` rather than a string compare, so 16.10 sorts above
    # 16.9 instead of below it.
    if [ -z "$best_version" ] || \
       [ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -1)" = "$version" ]; then
        best=$app
        best_version=$version
    fi
done

if [ -z "$best" ]; then
    echo "No Xcode ${MINIMUM_MAJOR} or newer found. Installed:"
    ls -d /Applications/Xcode*.app 2>/dev/null || echo "  (none)"
    exit 1
fi

developer_dir="$best/Contents/Developer"
echo "Selected Xcode $best_version at $best"
echo "  $(DEVELOPER_DIR="$developer_dir" xcodebuild -version | tr '\n' ' ')"

if [ -n "${GITHUB_ENV:-}" ]; then
    echo "DEVELOPER_DIR=$developer_dir" >> "$GITHUB_ENV"
fi
