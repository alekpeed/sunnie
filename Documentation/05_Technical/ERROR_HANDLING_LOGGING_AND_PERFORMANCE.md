# Error Handling, Logging, and Performance

## 1. Error categories

### User-recoverable

- Invalid or missing form field
- Permission denied
- iCloud unavailable
- Weather unavailable
- Watch unreachable
- Media import failure

Provide a clear next action.

### Background-recoverable

- Sync retry
- Watch queued transfer
- Thumbnail generation
- Content-index rebuild

Do not interrupt the user unnecessarily.

### Developer/content errors

- Duplicate stable ID
- Missing required asset
- Invalid manifest
- Impossible reward rule
- Unsupported schema version

Fail loudly in development and tests; use safe fallback in production.

## 2. Error presentation

- Preserve locally saved work.
- State what succeeded.
- Avoid raw technical messages.
- Offer retry when meaningful.
- Do not blame the user.

## 3. Logging

Categories:

- App lifecycle
- Persistence
- Sync
- Watch
- Health authorization/query
- Notifications
- Content validation
- Audio
- Performance

Redact private content.

## 4. Performance targets

- Today local content appears promptly without cloud wait.
- Lists remain responsive with 50+ plants and large histories.
- Game interactions maintain smooth frame rate.
- Theme switches do not reload data stores.
- Images use thumbnails in lists.
- Audio assets load lazily.
- Destination packs load on demand.
- Watch payloads remain compact.

## 5. Caching

Cache:

- Today summaries
- Thumbnails
- Weather summary with timestamp
- Content indexes
- Game pack indexes

Do not cache mutable domain data in a way that becomes a second source of truth.

## 6. Memory

- Avoid holding full-resolution photo arrays in memory.
- Cancel image tasks when cells disappear.
- Use lazy stacks/grids.
- Release audio nodes/assets when contexts change.

## 7. Background behavior

- Use only justified background modes.
- Do not poll.
- Let CloudKit, notifications, Health background delivery, and WatchConnectivity use their intended mechanisms.
- Avoid battery-heavy location tracking.

## 8. Diagnostics

Private debug builds may include:

- Content-pack validator
- Sync status inspector
- Theme/time preview
- Sunnie state inspector
- Notification schedule list
- In-memory sample data reset

Do not expose creator/developer diagnostics in Vanessa’s normal interface.
