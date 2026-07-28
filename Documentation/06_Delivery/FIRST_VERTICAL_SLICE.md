# First Vertical Slice

## Purpose

Validate the complete architecture with one useful flow before expanding the app.

## User story

As Vanessa, I can see a plant task on Today, open the plant, mark it watered, and immediately see the app update while the action is saved, rewarded appropriately, and synchronized to Watch/iCloud when available.

## Required flow

1. Today loads a local `PlantTodaySummary`.
2. Card shows one due plant.
3. Tap routes to Jungle due list.
4. Tap opens Plant detail.
5. Tap Water.
6. Quick log allows timestamp and optional note.
7. `LogPlantCare` use case validates and creates stable action key.
8. Repository stores `PlantCareEvent` locally.
9. Schedule recalculates next due date.
10. Domain event emits.
11. Progression engine evaluates once.
12. Today summary invalidates and refreshes.
13. Sunnie message service returns a short positive reaction.
14. Watch application context updates.
15. Cloud sync occurs when available.

## Minimum models

- UserProfile
- UserPreferences
- Plant
- PlantCareSchedule
- PlantCareEvent
- ProgressionProfile
- ProgressionEvent
- RewardGrant
- ThemeSelection
- PendingWatchAction

## Minimum screens

- Today shell
- Jungle due list
- Plant detail
- Quick care sheet
- Basic Settings/theme preview
- Minimal Watch Today/Plants

## Required tests

### Unit

- Next-due calculation
- Stable action key
- Reward idempotency
- Sunnie message eligibility
- Time/theme resolution

### Repository

- Save/fetch care event
- Transaction failure leaves no partial state
- In-memory store

### Integration

- Use case updates summary
- Duplicate Watch action creates one care event
- Offline local completion

### UI

- Navigate and complete watering
- Today card updates
- Dynamic Type
- VoiceOver labels

## Explicit non-slice work

Do not add:

- Full plant editor
- Travel
- Meals
- Full wellness
- Full games
- 3D
- Voice
- Android
- Custom backend

## Exit criteria

- App and Watch compile.
- Flow works on Simulator and physical iPhone.
- Queued Watch transfer is tested on physical paired devices before relying on it for release.
- No direct SwiftData access from feature views.
- No duplicate rewards/actions.
- Local data survives relaunch.
- Theme and all three branded day presentations render coherently.
