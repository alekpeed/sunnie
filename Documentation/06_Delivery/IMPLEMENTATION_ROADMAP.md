# Implementation Roadmap

The roadmap controls dependency order. It does not reduce the complete 2D release scope.

## Phase 0 — Repository and project foundation

Deliver:

- Repository conventions
- Xcode project
- iPhone, Watch, unit-test, and UI-test targets
- Shared local Swift package
- CI skeleton
- Entitlement placeholders
- Documentation copied into repository
- Architecture decision log

Exit:

- iPhone and Watch schemes compile.
- Tests run.
- No feature code violates planned boundaries.

## Phase 1 — Shared engines and shell

Deliver:

- App shell and five-tab navigation
- Typed router
- Design tokens/components
- Theme engine
- Universal time engine
- Sunnie semantic state/message shell
- Dependency composition
- SwiftData schema V1
- Repository/service protocols
- Content registry
- Local notification shell
- Progression shell
- Audio shell

Exit:

- Theme/day presentation previews work.
- Preferences persist.
- Sample content validates.

## Phase 2 — First vertical slice

Implement the plant-care path in `FIRST_VERTICAL_SLICE.md`.

Exit:

- End-to-end path works offline.
- Watch duplicate actions are safe.
- Tests pass.

## Phase 3 — Today, wellness, and journal

Deliver:

- Today summaries
- Check-in
- Affirmations
- Gratitude
- Journal text/voice/photo
- Breathing
- Meditation timer
- Calm sounds
- Reminder foundation
- Wellness history

## Phase 4 — Full Jungle

Deliver:

- Plant editor
- 50+ collection management
- All schedules/events
- Health observations
- Growth photos
- Bulk care
- Travel coverage
- QR generation/scanning in main app
- Export

## Phase 5 — Travel

Deliver:

- Trips and segments
- Packing/templates
- Departure/return
- Time zones
- Calendar
- Weather
- Map and places
- Work travel mode
- Sleep/hydration/meal helpers
- Memories/stamps/postcards
- Plant handoff

## Phase 6 — Meals

Deliver:

- Planner
- Recipes
- Egg-free filtering
- Grocery
- Pantry
- Prep
- Packed food
- Travel integration
- Timers/reminders

## Phase 7 — Games

Deliver:

- Shared host
- Daily puzzle
- Initial game set
- Save/resume
- Explanations
- Accessibility
- Progression events
- Content packs

## Phase 8 — Collections and Sunnie Home

Deliver:

- Rewards
- Ownership
- Outfits
- Decor
- Music/soundscapes
- Postcards/stamps/souvenirs
- Home scene
- Destination and day-cycle variants

## Phase 9 — HealthKit, Watch, widgets, intents

Deliver:

- Granular Health permissions
- Selected reads/writes
- Complete Watch flows
- Widgets
- App Intents
- Physical-device Watch testing

Some Watch foundations appear earlier for the vertical slice; this phase completes the product integration.

## Phase 10 — Creator audio completion

Deliver:

- Manifest-based audio
- Rendered soundtrack
- Optional approved adaptive MIDI
- Crossfades
- Theme/destination/game/meditation cues
- Interruption/route tests

## Phase 11 — Accessibility, sync, export, and release polish

Deliver:

- CloudKit production validation
- Media sync/backup policy
- Migration suite
- Full accessibility pass
- Performance
- Onboarding
- Settings
- Privacy
- Export/delete
- Beta
- Release candidate

## Phase gate rule

Do not proceed because screens “look done.” A phase exits only when:

- Required behavior works
- Tests pass
- Offline and errors are handled
- Accessibility is checked
- Data migration implications are recorded
- Documentation is updated
