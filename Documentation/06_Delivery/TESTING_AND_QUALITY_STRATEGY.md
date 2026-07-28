# Testing and Quality Strategy

## 1. Test layers

### Unit tests

Use Swift Testing or XCTest consistently for:

- Scheduling
- Time zones
- Theme/time resolution
- Sunnie message rules
- Nickname eligibility
- Meal filtering
- Game engines
- Reward rules
- Content validation
- Health summary mapping

### Repository tests

Use in-memory SwiftData configuration for:

- CRUD
- Relationships
- Queries
- Deletion
- Transactions
- Migrations

### Integration tests

- Use case + repository
- Domain event + progression
- Notification action + use case
- Watch payload + idempotent processing
- Content pack + registry

### UI tests

Critical flows:

- Onboarding
- Plant watering
- Wellness check-in
- Journal entry
- Trip packing
- Meal prep
- Daily puzzle
- Reward equip
- Theme change
- Permission denial

## 2. Visual quality matrix

Core screens tested with:

- Lush Tropical Jungle
- Travel Scrapbook
- Day-Cycle Theme
- Sunnie Days
- Sunnie Afternoonies
- Sunnie Nights
- Large Dynamic Type
- VoiceOver
- Reduce Motion
- High contrast

## 3. Data-volume fixtures

Provide fixtures for:

- No plants
- 1 plant
- 50 plants
- 100 plants
- 1,000 care events
- Multiple active/upcoming trips
- Large journal/media library
- Long game history

## 4. Time tests

- Daylight saving start/end
- Crossing International Date Line
- Home vs destination time
- Late-night boundary
- Trip starting/ending at midnight
- Reminder recurrence across time-zone change

## 5. Sync tests

- Offline create/update/delete
- Reconnect
- Duplicate Watch action
- Concurrent profile edit
- Journal conflict
- Reward duplicate
- iCloud unavailable
- Reinstall restore

## 6. Content validation tests

- Duplicate IDs
- Missing assets
- Missing localization
- Prohibited names
- Prohibited tone phrases
- Invalid reward reference
- Invalid game seed/version
- Missing accessibility description

A build should fail if “Sunnie Mornings” or “Sunnie Evenings” appears in user-facing content.

## 7. Audio tests

- Interruption
- Route change
- Loop gap
- Background/foreground
- Other app audio
- Volume persistence
- No auto-play after fresh install

## 8. Watch tests

- Reachable immediate action
- Unreachable queued action
- Duplicate delivery
- Phone reinstall/state reset
- Application-context update
- Physical paired-device transfer

## 9. Release quality bar

No release with:

- Known data-loss bug
- Duplicate reward bug
- Crashing permission denial
- Broken offline core flow
- Missing migration path
- Inaccessible core action
- Mature/noncanonical Sunnie production art
- Punitive copy
