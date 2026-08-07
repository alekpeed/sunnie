#!/usr/bin/env python3
"""Validate a creator audio manifest.

Mirrors `AudioManifestValidator` in `SunnieShared`, so a manifest that passes
here passes in the app. It also checks the one thing the Swift validator cannot:
that every `runtimeAsset` actually exists in the bundle resources.

    python3 Tools/validate_audio_manifest.py CreatorAudioSource/audio.manifest.json

Exit code 0 means the manifest is shippable. Anything else is a list of problems,
one per line, ordered by track.

Why a second implementation rather than reusing the Swift one: the creator runs
this before the app is built, often before the asset is in the repository at all.
A check that needs a working build cannot run at the moment it is most useful.
"""

from __future__ import annotations

import json
import pathlib
import sys

LAYERS = {"music", "ambience", "effects", "meditationBell", "narration"}
SOURCE_TYPES = {"renderedAudio", "procedural", "runtimeMIDI"}
LICENCES = {"createdForThisApp"}

# The contexts §5 lists. `destination.<code>` is also legal and is checked by
# prefix rather than by membership, because destinations are content.
SPECIFIED_CONTEXTS = {
    "time.day",
    "time.afternoon",
    "time.night",
    "theme.jungle",
    "screen.travelScrapbook",
    "screen.today",
    "screen.plantCare",
    "screen.wellness",
    "screen.sunnieHome",
    "practice.meditation",
    "practice.breathing",
    "screen.game",
    "moment.reward",
}

RESOURCE_DIRECTORIES = [
    pathlib.Path("Apps/iOS/Resources"),
    pathlib.Path("CreatorAudioSource/Renders"),
]


def asset_exists(name: str) -> bool:
    return any((directory / name).exists() for directory in RESOURCE_DIRECTORIES)


def validate(manifest: dict) -> list[str]:
    problems: list[str] = []

    if not isinstance(manifest.get("version"), int):
        problems.append("The manifest needs an integer `version`.")

    tracks = manifest.get("tracks")
    if not isinstance(tracks, list):
        return problems + ["The manifest needs a `tracks` array."]

    seen: set[str] = set()
    music_by_contexts: dict[frozenset[str], list[str]] = {}
    declared: set[str] = set()

    for index, track in enumerate(tracks):
        label = track.get("id") or f"track #{index}"

        for field in ("id", "titleKey", "sourceType", "layer", "defaultGain"):
            if field not in track:
                problems.append(f"{label}: missing `{field}`.")

        track_id = track.get("id")
        if track_id:
            if track_id in seen:
                problems.append(f"{label}: duplicate id.")
            seen.add(track_id)

        layer = track.get("layer")
        if layer is not None and layer not in LAYERS:
            problems.append(f"{label}: unknown layer `{layer}`.")

        source_type = track.get("sourceType")
        if source_type is not None and source_type not in SOURCE_TYPES:
            problems.append(f"{label}: unknown sourceType `{source_type}`.")

        licence = track.get("licence", "createdForThisApp")
        if licence not in LICENCES:
            problems.append(
                f"{label}: licence `{licence}` needs an ADR before it can ship."
            )

        gain = track.get("defaultGain")
        if isinstance(gain, (int, float)) and not 0 <= gain <= 1:
            problems.append(f"{label}: defaultGain {gain} is outside 0…1.")

        contexts = track.get("contexts") or []
        if not contexts:
            problems.append(f"{label}: no contexts, so nothing can ever ask for it.")
        for context in contexts:
            declared.add(context)
            if context not in SPECIFIED_CONTEXTS and not context.startswith(
                "destination."
            ):
                problems.append(
                    f"{label}: context `{context}` is not one the app knows. "
                    "A typo here means the track never plays."
                )

        asset = track.get("runtimeAsset")
        if source_type == "renderedAudio":
            if not asset:
                problems.append(f"{label}: rendered audio with no runtimeAsset.")
            elif not asset_exists(asset):
                problems.append(
                    f"{label}: runtimeAsset `{asset}` is not in the bundle "
                    "resources yet, so this track cannot play."
                )
        elif source_type == "procedural" and asset:
            problems.append(f"{label}: procedural track also names a runtimeAsset.")
        elif source_type == "runtimeMIDI":
            problems.append(
                f"{label}: runtime MIDI is not used and needs an ADR (ADR-029)."
            )

        if layer == "music" and track_id:
            music_by_contexts.setdefault(frozenset(contexts), []).append(track_id)

    for contexts, ids in music_by_contexts.items():
        if len(ids) > 1:
            joined = ", ".join(sorted(ids))
            problems.append(
                "More than one music track claims exactly "
                f"{sorted(contexts)}: {joined}. Nothing can prefer one."
            )

    for context in sorted(SPECIFIED_CONTEXTS - declared):
        problems.append(f"Note: no track is registered for `{context}`.")

    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2

    path = pathlib.Path(argv[1])
    try:
        manifest = json.loads(path.read_text())
    except FileNotFoundError:
        print(f"No manifest at {path}")
        return 2
    except json.JSONDecodeError as error:
        print(f"{path} is not valid JSON: {error}")
        return 2

    problems = validate(manifest)
    if not problems:
        print(f"{path}: {len(manifest.get('tracks', []))} tracks, no problems.")
        return 0

    # Notes are informational — a context with no track is a legitimate choice,
    # so they are listed but do not fail the run.
    failures = [p for p in problems if not p.startswith("Note:")]
    for problem in problems:
        print(problem)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
