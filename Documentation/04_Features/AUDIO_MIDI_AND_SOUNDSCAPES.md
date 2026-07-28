# Feature Specification — Audio, MIDI, and Soundscapes

## 1. Core rule

Vanessa does not import, browse, assign, or manage MIDI files. The creator adds music behind the scenes. The user-facing app exposes only normal playback and preference controls.

## 2. Creator workflow

1. Compose music externally using piano, MIDI keyboard, DAW, or notation software.
2. Export source MIDI and/or rendered audio.
3. Store source files in `CreatorAudioSource/`, excluded from the shipping target unless runtime MIDI is required.
4. Produce a tested runtime asset.
5. Register the runtime track in a versioned audio manifest.
6. Assign semantic contexts such as theme, destination, game, meditation, or reward.
7. Validate loop, volume, interruption, and licensing metadata.

## 3. Runtime strategy

### Preferred: rendered audio

Use AAC/M4A or CAF for:

- Exact composition and instrumentation
- Seamless loops after testing
- Low-complexity playback
- Predictable sound across devices

### Optional: runtime MIDI

Use AVFAudio/Core MIDI only when the product benefits from:

- Adaptive arrangement
- Tempo changes
- Layer activation
- Interactive musical response
- Small generative variations based on approved deterministic rules

Do not use runtime MIDI merely because source music was composed as MIDI.

## 4. Audio layers

- Music
- Ambience
- Effects
- Meditation bells
- Future narration/voice

Each layer has independent gain and enable state.

## 5. Audio contexts

- Sunnie Days
- Sunnie Afternoonies
- Sunnie Nights
- Jungle
- Travel Scrapbook
- Destination
- Today
- Plant care
- Wellness
- Meditation
- Breathing
- Game
- Reward
- Sunnie Home

## 6. Playback behavior

The audio service handles:

- Start/stop
- Looping
- Crossfade
- Ducking
- Route changes
- Headphones/Bluetooth
- Interruption and resume policy
- App background behavior
- Silent/mute preferences
- Low-power considerations

Do not surprise the user with audible playback on app launch. Ambient/music auto-play must be opt-in and remember the user’s setting.

## 7. Audio session policy

Choose AVAudioSession categories by use case. Calm audio may mix with other audio if configured; meditation playback may require a more focused session. Centralize category changes in one service rather than feature code.

## 8. Manifest example

```json
{
  "id": "music.theme.jungle.day.001",
  "version": 1,
  "title": "Tropical Morning",
  "runtimeAsset": "tropical_morning_v1.m4a",
  "sourceType": "renderedAudio",
  "loop": true,
  "contexts": ["theme.jungle", "time.day"],
  "defaultGain": 0.55,
  "creator": "private"
}
```

## 9. User controls

- Master audio
- Music
- Ambience
- Effects
- Future narration
- Play previews only on tap
- Background playback setting
- Per-theme ambience setting

## 10. Meditation

- Start/end bell
- Optional background music
- Optional ambience
- Timer continues correctly through interruption
- Session completion is recorded separately from audio playback

## 11. Accessibility

- No essential information only in sound.
- Provide captions for future voice.
- Visual timer and haptic alternatives.
- Respect reduced sensory preferences.

## 12. Testing

- Phone call/interruption
- Siri
- Bluetooth disconnect
- Headphone insertion/removal
- Route change
- App background/foreground
- Simultaneous timer and audio
- Loop gap
- Volume persistence
- Other audio playing
