# Future Animation, Voice, and 3D Extension Plan

## Current release boundary

The current implementation is a polished 2D SwiftUI application. It may use layered character images, simple loops, transitions, haptics, and audio. It does not require a character skeleton, lip synchronization, voice personality model, or 3D environment.

## Architectural requirement

Character presentation should use an abstraction such as:

```swift
protocol SunnieRenderer {
    func render(_ state: SunnieVisualState) -> AnyView
}
```

The exact Swift design may differ, but feature code should request a semantic state rather than directly selecting image file names.

A semantic visual state may include:

- Pose
- Expression
- Outfit
- Prop
- Theme
- Destination
- Time phase
- Motion preference

## Future 2D animation

Possible later approaches:

- Frame animation
- Layered SwiftUI animation
- Rive or another approved runtime
- Sprite-based rig
- Pre-rendered video with transparency where supported

No third-party runtime should be added without an Architecture Decision Record.

## Future voice

Potential components:

- Recorded Sunnie lines
- Recorded meditations
- System text-to-speech for accessibility or prototypes
- Custom synthesized voice after explicit approval
- Localized voice packs

Required future controls:

- Voice on/off
- Separate voice volume
- Never speak sensitive text on a lock screen
- Respect silent mode and audio route
- No surprise speech
- Caption every spoken line

## Future 3D

A future 3D renderer may use the then-current Apple-native 3D stack. It must preserve the canonical young character design.

Potential 3D uses:

- Sunnie Home
- Garden scene
- Destination scenes
- Outfit preview
- Gentle interactive objects

Do not make 3D a dependency of core records, navigation, progression, or feature logic. The 2D app must remain functional if a 3D module is absent.

## Data boundaries

Future renderer-independent state should include:

- Equipped outfit ID
- Decor placement
- Pose request
- Expression request
- Destination context
- Theme context
- Audio cue

Do not store engine-specific node paths or animation names in core domain models. Map semantic IDs inside the renderer/content pack.

## Deferred work list

Do not implement now:

- 3D model import
- skeletal rigging
- facial blend shapes
- real-time lip sync
- voice cloning
- generative dialogue
- character physics
- networked 3D spaces
