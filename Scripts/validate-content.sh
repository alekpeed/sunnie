#!/usr/bin/env bash
#
# Validates the shipped content packs (task E0-07).
#
# This is a fast structural gate that runs without a Swift toolchain, so a
# malformed pack is caught before anything is compiled. The authoritative check
# is `ContentValidationTests` in the shared package, which additionally enforces
# the tone rules; this script exists to fail early and to be runnable from a
# pre-commit hook.
#
# Usage: ./Scripts/validate-content.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENT_DIR="$ROOT/Packages/SunnieShared/Sources/SunnieShared/Resources/Content"

if [[ ! -d "$CONTENT_DIR" ]]; then
    echo "error: content directory not found at $CONTENT_DIR" >&2
    exit 1
fi

python3 - "$CONTENT_DIR" <<'PY'
import json
import pathlib
import re
import sys

content_dir = pathlib.Path(sys.argv[1])
issues = []

ID_PATTERN = re.compile(r'^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+$')
HEX_PATTERN = re.compile(r'^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
SUPPORTED_SCHEMA_VERSION = 1

# Kept in step with ContentValidator.swift. If you add a rule there, add it here.
PROHIBITED_PHRASES = [
    "you failed", "you broke your streak", "broke your streak",
    "sunnie is disappointed", "i'm disappointed", "im disappointed",
    "you ignored", "no excuses", "you must do this now",
    "you should have", "why didn't you", "dying because you",
    "don't lose your",
]
PROHIBITED_LABELS = {"lazy", "careless", "irresponsible", "unhealthy", "sloppy", "pathetic"}
PROHIBITED_DAY_CYCLE_NAMES = ["sunnie mornings", "sunnie evenings"]
PROHIBITED_CLAIMS = [
    "proves you", "you are depressed", "you are anxious", "you have anxiety",
    "you must be feeling", "is a symptom of", "diagnoses your",
    "medically proven", "clinically proven", "will cure", "cures your",
    "guaranteed to", "this will fix", "will make you happy", "will make you calm",
]

REQUIRED_CATEGORIES = {
    "greeting", "celebration", "casualAffirmation", "postcard", "homeScene",
    "careCompleted", "gentleReminder", "permissionRequest", "error",
    "privacyNotice", "healthExplanation", "travelDocumentAlert",
}
NICKNAME_INELIGIBLE = {
    "gentleReminder", "permissionRequest", "error", "privacyNotice",
    "healthExplanation", "travelDocumentAlert",
}


def check_claims(text, content_id):
    lowered = text.lower()
    for claim in PROHIBITED_CLAIMS:
        if claim in lowered:
            issues.append(f'{content_id}: medical or outcome claim "{claim}"')


def check_tone(text, content_id):
    lowered = text.lower()
    for phrase in PROHIBITED_PHRASES:
        if phrase in lowered:
            issues.append(f'{content_id}: prohibited language "{phrase}"')
    for name in PROHIBITED_DAY_CYCLE_NAMES:
        if name in lowered:
            issues.append(f'{content_id}: forbidden day-cycle name "{name}"')
    words = set(re.split(r"[^a-z']+", lowered))
    for label in PROHIBITED_LABELS & words:
        issues.append(f'{content_id}: negative label "{label}"')


def check_manifest(pack, filename):
    manifest = pack.get("manifest")
    if not isinstance(manifest, dict):
        issues.append(f"{filename}: missing manifest")
        return
    version = manifest.get("schemaVersion")
    if version != SUPPORTED_SCHEMA_VERSION:
        issues.append(
            f"{filename}: schema version {version} is not the supported "
            f"version {SUPPORTED_SCHEMA_VERSION}"
        )
    pack_id = manifest.get("packID", "")
    if not ID_PATTERN.match(pack_id):
        issues.append(f"{filename}: malformed pack ID {pack_id!r}")


def validate_messages(path):
    pack = json.loads(path.read_text())
    check_manifest(pack, path.name)

    seen = set()
    categories = set()
    for message in pack.get("messages", []):
        content_id = message.get("id", "<missing id>")
        if not ID_PATTERN.match(content_id):
            issues.append(f"{path.name}: malformed content ID {content_id!r}")
        if content_id in seen:
            issues.append(f"{path.name}: duplicate content ID {content_id}")
        seen.add(content_id)

        for field in ("category", "template", "localizationKey", "expression", "pose"):
            if not message.get(field):
                issues.append(f"{content_id}: missing required field {field!r}")

        if "phases" not in message:
            issues.append(f"{content_id}: missing required field 'phases'")

        category = message.get("category", "")
        categories.add(category)

        template = message.get("template", "")
        check_tone(template, content_id)

        if "{name}" in template and category in NICKNAME_INELIGIBLE:
            issues.append(
                f"{content_id}: category {category!r} may never use the nickname, "
                "but the text contains {name}"
            )

    for missing in sorted(REQUIRED_CATEGORIES - categories):
        issues.append(f"{path.name}: no messages for category {missing!r}")


def validate_themes(path):
    pack = json.loads(path.read_text())
    check_manifest(pack, path.name)

    seen = set()
    for theme in pack.get("themes", []):
        theme_id = theme.get("id", "<missing id>")
        if not ID_PATTERN.match(theme_id):
            issues.append(f"{path.name}: malformed theme ID {theme_id!r}")
        if theme_id in seen:
            issues.append(f"{path.name}: duplicate theme ID {theme_id}")
        seen.add(theme_id)

        for field in ("version", "displayNameKey", "basePalette",
                      "cardCornerRadius", "isUnlockedByDefault",
                      "minimumAppVersion", "phaseVariants"):
            if field not in theme:
                issues.append(f"{theme_id}: missing required field {field!r}")

        palettes = [theme.get("basePalette") or {}]
        if theme.get("highContrastPalette"):
            palettes.append(theme["highContrastPalette"])
        for palette in palettes:
            for role, value in palette.items():
                if not HEX_PATTERN.match(str(value)):
                    issues.append(f"{theme_id}: unreadable colour {role}={value!r}")

        for variant in theme.get("phaseVariants", []):
            if not variant.get("phase"):
                issues.append(f"{theme_id}: a phase variant has no phase")
            for role in ("canvas", "surface", "textPrimary", "textSecondary"):
                value = variant.get(role)
                if value is not None and not HEX_PATTERN.match(str(value)):
                    issues.append(f"{theme_id}: unreadable colour {role}={value!r}")


def validate_wellness(path):
    pack = json.loads(path.read_text())
    check_manifest(pack, path.name)

    seen = set()

    def check_id(content_id, label):
        if not ID_PATTERN.match(content_id):
            issues.append(f"{path.name}: malformed {label} ID {content_id!r}")
        if content_id in seen:
            issues.append(f"{path.name}: duplicate content ID {content_id}")
        seen.add(content_id)

    affirmations = pack.get("affirmations", [])
    for affirmation in affirmations:
        content_id = affirmation.get("id", "<missing id>")
        check_id(content_id, "affirmation")
        for field in ("text", "localizationKey", "tags", "phases", "suitsSensitiveMoments"):
            if field not in affirmation:
                issues.append(f"{content_id}: missing required field {field!r}")
        text = affirmation.get("text", "")
        if not text.strip():
            issues.append(f"{content_id}: empty text")
        check_tone(text, content_id)
        check_claims(text, content_id)

    # A harder moment filters the library down; if nothing survives, the
    # affirmation card is blank exactly when it matters most.
    gentle = [a for a in affirmations if a.get("suitsSensitiveMoments")]
    if not gentle:
        issues.append(f"{path.name}: no affirmations suitable for a harder moment")

    patterns = pack.get("breathingPatterns", [])
    for pattern in patterns:
        content_id = pattern.get("id", "<missing id>")
        check_id(content_id, "breathing pattern")
        inhale = pattern.get("inhaleSeconds", 0)
        exhale = pattern.get("exhaleSeconds", 0)
        cycles = pattern.get("defaultCycles", 0)
        if inhale <= 0 or exhale <= 0 or cycles <= 0:
            issues.append(f"{content_id}: pattern would never advance")
        for hold in ("holdAfterInhaleSeconds", "holdAfterExhaleSeconds"):
            if pattern.get(hold, 0) < 0:
                issues.append(f"{content_id}: negative {hold}")

    if patterns and all(p.get("isAdvanced") for p in patterns):
        issues.append(f"{path.name}: no breathing pattern is suitable as a default suggestion")

    for meditation in pack.get("meditations", []):
        content_id = meditation.get("id", "<missing id>")
        check_id(content_id, "meditation")
        if meditation.get("defaultDuration", 0) <= 0:
            issues.append(f"{content_id}: non-positive default duration")

    for sound in pack.get("calmSounds", []):
        check_id(sound.get("id", "<missing id>"), "calm sound")


found = False
for path in sorted(content_dir.glob("*.json")):
    found = True
    try:
        if "messages" in path.name:
            validate_messages(path)
        elif "themes" in path.name:
            validate_themes(path)
        elif "wellness" in path.name:
            validate_wellness(path)
        else:
            json.loads(path.read_text())
    except json.JSONDecodeError as error:
        issues.append(f"{path.name}: not valid JSON ({error})")

if not found:
    issues.append(f"no content packs found in {content_dir}")

if issues:
    print("Content validation failed:\n")
    for issue in issues:
        print(f"  - {issue}")
    sys.exit(1)

print(f"Content validation passed ({content_dir}).")
PY
