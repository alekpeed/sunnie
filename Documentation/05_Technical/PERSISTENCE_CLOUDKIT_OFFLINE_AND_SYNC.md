# Persistence, CloudKit, Offline Operation, and Sync

## 1. Persistence strategy

- SwiftData stores app-owned structured records.
- Repositories isolate SwiftData from features.
- The app writes locally first.
- Private iCloud/CloudKit synchronization is enabled for eligible records after schema validation.
- Media uses an explicit media repository rather than being embedded casually in every model.

## 2. Storage categories

### Structured private data

SwiftData/private CloudKit:

- Plants and care events
- Trips and checklists
- Wellness check-ins
- Journal metadata/text
- Meal plans
- Game sessions
- Progression and ownership
- Preferences

### Local derived/cache data

- Dashboard summaries
- Weather cache
- Generated thumbnails
- Content indexes
- Audio cache
- Map-view state

Derived caches can be rebuilt and should not create sync conflicts.

### Media

- Full-resolution user photos/voice notes stored through `MediaRepository`
- Metadata and references stored in SwiftData
- Initial implementation may keep media local while a CloudKit-asset synchronization spike validates behavior
- Release requires a documented media backup/sync policy

### Health data

HealthKit remains the source of truth. Store only authorization state, query anchors, selected derived summaries, and references needed to avoid duplicate writes.

## 3. CloudKit enablement

SwiftData automatic iCloud sync requires compatible schema and required capabilities. Configure:

- iCloud/CloudKit container
- Background Modes/remote notifications as required by SwiftData sync
- Development and production environments
- Explicit schema versions

Do not enable sync on an untested schema and assume migrations will work later.

## 4. Offline rules

The following must work offline:

- View and edit plants
- Log care
- Create/edit trips and checklists
- View stored time-zone data
- Journal and check in
- Plan meals
- Play installed games
- Use downloaded audio/content
- Grant local progression events
- Queue Watch actions

Unavailable while fully offline may include fresh weather, uncached map imagery, and new content-pack downloads.

## 5. Conflict strategy

### Append-only events

Keep both independent records for:

- Plant care
- Wellness check-ins
- Completed sessions
- Puzzle results
- Progression events

### Editable documents

For journal entries, trips, plant profiles, and meal plans:

- Stable ID
- Modification timestamp
- Source device
- Version token
- Merge independent field changes when safe
- Preserve both versions or create conflict record when unsafe

### Preferences

Latest explicit user change wins, with local timestamp and device metadata.

### Rewards

Deterministic key prevents duplicate grants.

### Watch actions

Action ID prevents duplicate processing.

## 6. Deletion

Use tombstone or CloudKit-compatible deletion behavior where necessary. Deleting a parent must follow explicit rules:

- Plant: offer archive; preserve history unless confirmed
- Trip: offer preserve memories
- Journal: delete attachments after confirmed lifecycle
- Game: retain earned rewards
- Content pack: retain ownership records

## 7. Sync status UX

Normal sync should be invisible. Show status only when useful:

- Saved on this device
- Waiting for iCloud
- Sync paused/no iCloud account
- Conflict needs review

Never block local saving because iCloud is unavailable.

## 8. Backup/export

Provide:

- JSON complete export
- CSV table exports
- ZIP media export
- Human-readable metadata manifest

Export is user-initiated through the system share sheet.

## 9. Migration

- Named schema versions
- Explicit migration plan
- Fixture stores from every released version
- Automated migration tests
- No destructive migration in production without explicit user-visible recovery plan

## 10. Sync testing matrix

- Two iPhones on one iCloud account
- iPhone and Watch
- Offline edit then reconnect
- Simultaneous edit
- iCloud account unavailable
- Low storage
- Reinstall and restore
- Deleted content
- Duplicate Watch action
- Content-pack version update
