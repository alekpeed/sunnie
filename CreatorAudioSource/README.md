# Creator Audio Source

Working files for music and ambience composed outside the app — DAW projects,
MIDI, and raw stems.

**Nothing in this directory ships.** Source MIDI is creator-side only and never
appears in the app bundle or in any user-facing interface (ADR-006). Vanessa sees
finished music and audio controls; she never sees a MIDI import screen, a file
picker, or a track manager.

## Workflow

1. Compose here, in whatever DAW you prefer.
2. Render to AAC (`.m4a`) or CAF for exact playback.
3. Place the rendered file in the app's asset catalog, named for its content ID.
4. Register the cue in the audio manifest (Phase 10).

`AudioService` resolves a `ContentID` to a bundled asset and no-ops when the asset
is absent, so cues can be wired into features now and gain sound later without any
code change.

## Naming

Rendered assets take the content ID as their filename:

```
sunnie.audio.ambience.{theme}.{phase}      e.g. sunnie.audio.ambience.jungle.night
sunnie.audio.cue.{event}                   e.g. sunnie.audio.cue.careCompleted
sunnie.audio.music.{track}
```

## Runtime rules

- Rendered audio is preferred. Runtime MIDI is used only where adaptive
  sequencing gives a specific benefit, and needs its own ADR.
- The audio session is `.ambient`, so Sunnie never interrupts the user's music or
  podcast and respects the ring/silent switch.
- Quiet hours suppress ambience entirely.
- Audio never previews without an explicit tap — opening the Themes screen stays
  silent.

## Not tracked by git

`.gitignore` excludes `.mid`, `.midi`, `.logicx`, `.wav`, and `.aiff` from this
directory. Keep source material in your own backup; commit only manifests and
notes.
