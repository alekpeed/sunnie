# Audio

What makes sound, where each decision lives, and what is still owed a device.

## What actually plays

| Sound | How | Engine |
|---|---|---|
| White / pink / brown noise | synthesised | `NoiseEngine` (ADR-018) |
| Eight ambience beds | synthesised | `ProceduralAudioEngine` (ADR-029) |
| Opening and closing bells | synthesised | `ProceduralAudioEngine` |
| Seven music tracks | rendered files | `AudioService` — **files not delivered yet** |

The music entries are declared in `BuiltInAudioContent.musicTracks` against the
filenames the creator will render. Until a file is in the bundle, `isPlayable`
is false and the director skips the track, so the app is silent rather than
selecting something that cannot make a sound. Adding the file is the whole
remaining step — see `CreatorAudioSource/README.md`.

## Where each decision lives

Everything that can be got wrong quietly is a value type in `SunnieShared`, so it
can be tested with no device, no speaker, and no audio session:

| Question | Answered by |
|---|---|
| What should be playing? | `AudioDirector` |
| How loud? | `AudioPreferences.effectiveGain(for:trackGain:)` |
| Start, stop, crossfade, or just a level change? | `AudioTransition.between(current:next:)` |
| What shape is the fade? | `CrossfadePlan` — equal power |
| Which session category? | `AudioSessionPolicy` (ADR-030) |
| What to do about a phone call, a route change, backgrounding? | `AudioInterruptionMachine` (ADR-031) |
| What does a bed sound like? | `AmbienceVoice.recipe` |
| How loud is a bed before the user's controls? | `AmbienceCalibration` |

`AudioService` and `ProceduralAudioEngine` own the players and translate
`AVAudioSession` notifications into `AudioEvent`s. Neither decides anything.

## Session policy

One owner, one table (ADR-030). Nothing else may call `setCategory`.

| Use case | Category | Options | Survives lock |
|---|---|---|---|
| cue, ambience, music | ambient | — | no |
| generated noise | playback | mixWithOthers | yes |
| meditation | playback if background playback is on, else ambient | mixWithOthers | if on |
| voice note | playAndRecord (spoken audio) | duckOthers | no |

Background playback needs `UIBackgroundModes = audio` in `Info.plist`. Without
it, iOS suspends the app on leaving and playback stops — which looks exactly like
an audio bug and is not one.

## Defaults

Two settings are off out of the box, and both are deliberate:

- **Play sound automatically** — §6: nothing may make a noise on launch that the
  user did not ask for. With it off, sound happens only when something is tapped.
- **Keep playing when the screen locks** — it changes the session category, and
  with it whether the ring/silent switch still works. That is a choice to offer,
  not to assume.

## Still owed a device

The pure rules are covered by `AudioTests` — every scenario in §12 is a unit
test, including the sequences that are hardest to stage by hand. What a unit test
cannot check is that iOS posts the notification we think it does, and that the
render block keeps up under real load. These need hardware:

1. **Phone call during a bed.** Ring the phone while an ambience plays. Expect it
   to pause and resume when the call ends.
2. **Siri.** Same, but confirm playback resumes — Siri sets `shouldResume` where
   some interruptions do not.
3. **Headphones out.** Pull wired headphones mid-playback. Expect silence, not
   the speaker.
4. **Bluetooth away.** Walk out of range of a paired speaker. Expect the same.
5. **Headphones in.** Plug in with nothing playing. Expect nothing to start.
6. **Background and return.** Leave and come back with autoplay on. Expect the
   bed to pause and resume; with a practice running and background playback on,
   expect it *not* to pause.
7. **Simultaneous timer and audio.** Run a meditation to its end with the screen
   locked. Expect the closing bell, and the session recorded either way.
8. **Other audio.** Start a podcast over an ambience. Expect Sunnie's bed to step
   back and the podcast to be untouched.
9. **Loop gap.** Leave a bed running for twenty minutes and listen for a seam.
   The synthesised beds have no loop point at all, so this one is really a check
   on the *rendered* tracks once they arrive.
10. **Volume persistence.** Set a level, force-quit, reopen. Expect the level.
11. **Media services reset.** Rare and hard to force; if it happens, expect the
    bed to come back rather than the app going permanently silent.
12. **Render load.** Play a bed while scrolling a long list on the oldest
    supported device, and listen for breakup. The render block allocates nothing,
    but that is an argument, not a measurement.

None of these has been run — there is no device in this environment. They are
listed here rather than marked done.
