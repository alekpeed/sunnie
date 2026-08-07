# Creator audio source

Source material for Sunnie Days' music and ambience. **Nothing in this folder
ships.** It is excluded from every build target, and no file here is copied into
the app bundle.

This is the creator's side of the wall described in
`Documentation/04_Features/AUDIO_MIDI_AND_SOUNDSCAPES.md` §1:

> Vanessa does not import, browse, assign, or manage MIDI files. The creator adds
> music behind the scenes. The user-facing app exposes only normal playback and
> preference controls.

There is no MIDI import screen, no file picker, no "manage tracks" list, and no
setting that reveals a filename. If a change to the app would put any of those in
front of Vanessa, the change is wrong.

## Layout

```
CreatorAudioSource/
  README.md              this file
  audio.manifest.json    the creator's manifest — empty until a track is added
  MIDI/                  source MIDI, never shipped
  Sessions/              DAW projects, never shipped
  Renders/               exported audio, staged before it goes to the bundle
```

Only `Renders/` produces anything the app sees, and only by being copied into
`Apps/iOS/Resources/` as a bundled asset.

## Workflow

The seven steps from §2, with what each one means here.

1. **Compose externally.** Piano, MIDI keyboard, DAW, notation software —
   whatever produces the piece. Nothing about the app constrains this.
2. **Export source MIDI and/or rendered audio.** Source into `MIDI/` and
   `Sessions/`, the export into `Renders/`.
3. **Store the source here.** Excluded from the shipping target. Runtime MIDI is
   not used (ADR-029), so no source file is ever needed at run time.
4. **Produce a tested runtime asset.** AAC/M4A or CAF. Test the loop *before*
   registering it — see "Testing a loop" below.
5. **Register it in the manifest.** Add an entry to `audio.manifest.json` and run
   the validator.
6. **Assign semantic contexts.** Which screens, cycles, or moments the track
   belongs to. The app asks for a context, never for a file.
7. **Validate loop, volume, interruption, and licensing.** The validator covers
   the manifest; the loop and the level need ears.

## Registering a track

Copy the rendered file into `Apps/iOS/Resources/`, then add an entry:

```json
{
  "id": "sunnie.music.theme.jungle.day",
  "version": 1,
  "titleKey": "audio.music.tropicalMorning",
  "runtimeAsset": "tropical_morning_v1.m4a",
  "sourceType": "renderedAudio",
  "loops": true,
  "layer": "music",
  "contexts": ["theme.jungle", "time.day", "screen.today"],
  "defaultGain": 0.55,
  "licence": "createdForThisApp"
}
```

Field by field:

| Field | Notes |
|---|---|
| `id` | Stable forever. Renaming one orphans anything that referenced it. |
| `version` | Bump when the audio changes but the id stays. |
| `titleKey` | A localization key, not display text. Add it to `Localizable.strings`. |
| `runtimeAsset` | The bundled filename, extension included. Omit for procedural tracks. |
| `sourceType` | `renderedAudio` or `procedural`. `runtimeMIDI` is rejected — see below. |
| `loops` | Beds loop; cues and bells do not. |
| `layer` | `music`, `ambience`, `effects`, `meditationBell`, `narration`. |
| `contexts` | §5's list, plus `destination.<code>` for a specific place. |
| `defaultGain` | 0–1, before the layer gain and the master gain. |
| `licence` | `createdForThisApp`. Anything else needs an ADR first. |

The seven music ids in `BuiltInAudioContent.musicTracks` are already declared
against the filenames above. **Dropping the file into the bundle is the whole
remaining step** — the manifest entry, the contexts, and the level are already
written, and the director starts selecting the track the moment the file exists.
Until then it is skipped, so the app is silent rather than selecting something
that cannot play.

## Runtime MIDI

Not used, and rejected by the validator (ADR-029). §3 is explicit that runtime
MIDI is for adaptive arrangement, tempo change, and layer activation — not for
"the source happened to be MIDI". If a future feature genuinely needs it, that
starts with an ADR, not with a manifest entry.

## Procedural tracks

Eight ambiences and two bells are synthesised rather than recorded, and their
entries live in Swift (`BuiltInAudioContent.swift`) because they reference code.
They need no file and cannot go out of sync with one. A rendered ambience can
replace a synthesised one later by taking the same id with a `runtimeAsset` —
that is a manifest edit and nothing else.

## Testing a loop

`§12` lists loop gap first for a reason: a bed with an audible seam is worse than
no bed, because the seam is the only thing anyone hears after they notice it.

1. Render at least three loop lengths back to back and listen through both joins.
2. Check the first and last samples are near zero. A non-zero boundary is a click.
3. Check reverb tails wrap rather than being cut. A tail that stops at the loop
   point is the commonest cause of a seam that is not a click.
4. Listen on a phone speaker, not just headphones. The low end that carries a
   swell on headphones is inaudible on a speaker, and a bed that is all low end
   sounds like nothing at all there.

## Validating

```
python3 Tools/validate_audio_manifest.py CreatorAudioSource/audio.manifest.json
```

It mirrors `AudioManifestValidator` in `SunnieShared`, so a manifest that passes
here passes in the app. It also checks the one thing the Swift validator cannot:
that every `runtimeAsset` actually exists in `Apps/iOS/Resources/` or
`CreatorAudioSource/Renders/`.

The manifest ships empty — the ten synthesised tracks and the seven declared
music entries live in `BuiltInAudioContent.swift`. This file is where a *new*
rendered track goes.

To make the app read it, copy it to
`Packages/SunnieShared/Sources/SunnieShared/Resources/Content/audio.v1.json`.
Note that it **replaces** the built-in manifest rather than adding to it — the
same rule the game and collection packs follow — so a copied file must list the
synthesised tracks too, or they stop being selectable.

Lines beginning `Note:` are informational. A context with no track registered
against it is a legitimate choice — silence suits some screens — so notes are
printed but do not fail the run.
