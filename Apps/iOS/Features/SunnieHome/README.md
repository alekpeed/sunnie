# Sunnie Home

Built in Phase 8 (`Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md`).

```
SunnieHome/
├── Screens/
│   └── SunnieHomeScreen.swift   S-22 — zones, slots, outfit, sound, nook, stories
└── UseCases/
    └── ManageHome.swift          arranging, with an ownership check on every write
```

The domain lives in `SunnieShared/Domain/SunnieHome.swift`.

## Named slots, no dragging (ADR-025)

Every placement is a `DecorSlot`: a named, content-defined position that holds
one thing and declares which categories it accepts. Choosing what goes in one is
a list and a tap.

There is **no** drag path — not "a drag path plus an accessible alternative".
One path, which works with VoiceOver, Switch Control, and an unsteady hand
because a list does. Adding dragging later would mean maintaining two ways to
decorate, one of which would be second-class by construction.

The validator can prove every placeable reward has a slot that accepts it. A
freeform canvas has no equivalent check.

## What the scene responds to

`HomeSceneResolver` takes the theme, the time phase, an active trip's
destination, a recent unlock, and the season. Every one of those is something
the app already knows for a stated reason.

It takes **nothing** that could express "the user has not done enough", which is
why there is no version of this screen where Sunnie looks disappointed. That is
structural rather than a matter of picking kind artwork — the inputs do not
exist.

A destination outfit overrides the equipped one *only while a trip is on*, and
only if it is owned. Outside a trip the user's choice stands; a home that
silently overrides what someone chose is not theirs.

## Reduced motion

The static fallback S-22 asks for is `animationIntensity == 0`, not a slower
animation. Pinned in the resolver, so nothing downstream has to remember.
