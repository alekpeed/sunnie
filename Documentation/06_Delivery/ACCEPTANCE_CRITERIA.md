# Acceptance Criteria

## Product-level

- AC-001 App is fully native Swift/SwiftUI.
- AC-002 App title and user-facing naming follow the source of truth.
- AC-003 Canonical Sunnie art remains young and consistent.
- AC-004 Core features work offline.
- AC-005 No user-facing copy violates tone rules.
- AC-006 No ads, subscriptions, or third-party data monetization exist.

## Today

- AC-HOME-001 Local summaries render without waiting for cloud.
- AC-HOME-002 Travel, plant, wellness, meal, puzzle, and progression states are represented.
- AC-HOME-003 Completed actions update immediately.
- AC-HOME-004 Empty feature states remain useful.

## Jungle

- AC-PLANT-001 Collection remains responsive with 50+ plants.
- AC-PLANT-002 Care actions create historical events and next-due updates.
- AC-PLANT-003 Duplicate action keys do not create duplicate care.
- AC-PLANT-004 Search/filter/sort and bulk care work.
- AC-PLANT-005 Travel coverage and QR-ready IDs work.

## Travel

- AC-TRAVEL-001 User can plan and complete a work or personal trip.
- AC-TRAVEL-002 Packing, departure, return, time zones, weather, and plant handoff work.
- AC-TRAVEL-003 Past memories appear on map/list and collections.
- AC-TRAVEL-004 Offline trip records remain usable.

## Wellness/journal

- AC-WELL-001 User can record a check-in with optional fields.
- AC-WELL-002 App offers no more than one optional response action.
- AC-WELL-003 Meditation/breathing sessions survive interruption.
- AC-WELL-004 Journal drafts survive app interruption.
- AC-WELL-005 Health permission denial does not disable the feature.

## Meals

- AC-MEAL-001 Egg-containing suggestions are excluded by default.
- AC-MEAL-002 User can plan, shop, prep, and pack through linked workflows.
- AC-MEAL-003 Travel and pantry context changes suggestions deterministically.

## Games

- AC-GAME-001 Initial games have distinct documented mechanics.
- AC-GAME-002 Sessions save and resume.
- AC-GAME-003 Results explain solutions where applicable.
- AC-GAME-004 Rewards are granted once.
- AC-GAME-005 Games have accessibility alternatives.

## Progression/home

- AC-PROG-001 Earned items are never removed for inactivity.
- AC-PROG-002 Sunnie Home visibly reflects equipped content.
- AC-PROG-003 Missing content assets fail safely.

## Audio

- AC-AUDIO-001 No user-facing MIDI management exists.
- AC-AUDIO-002 Creator tracks are manifest-driven.
- AC-AUDIO-003 Audio handles interruptions/routes.
- AC-AUDIO-004 Playback never begins unexpectedly after first launch.

## Health/Watch

- AC-WATCH-001 Every permission is optional and explained.
- AC-WATCH-002 Watch actions queue offline and process idempotently.
- AC-WATCH-003 Health data is not used diagnostically.
- AC-WATCH-004 Physical paired-device transfer is tested.

## Accessibility/privacy

- AC-A11Y-001 Core flows work with VoiceOver.
- AC-A11Y-002 Core screens support large Dynamic Type.
- AC-A11Y-003 Reduce Motion produces a usable static experience.
- AC-PRIV-001 Private content is excluded from logs.
- AC-PRIV-002 Export and deletion work.

## Release exit

Release 1.0 is accepted only when all P0 and P1 requirements in `REQUIREMENTS_TRACEABILITY.md` are implemented, tested, or explicitly waived in a signed Architecture Decision Record.
