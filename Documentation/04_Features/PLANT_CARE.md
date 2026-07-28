# Feature Specification — Jungle and Plant Care

## 1. Objective

Make a collection of more than 50 plants easy to understand and maintain. The feature must support quick routine care and deep historical records.

## 2. Plant profile

Required fields:

- Stable ID
- Display name
- Optional nickname
- Species/common name
- Variety/cultivar
- Primary photo
- Additional photos
- Room/location
- Light profile
- Care difficulty
- Acquired date
- Source
- Pot type and size
- Soil/substrate
- General notes
- Active/inactive/archive status
- QR-ready identity

## 3. Care types

Built-in:

- Water
- Fertilize
- Mist
- Rotate
- Clean leaves
- Prune
- Repot
- Propagate
- Pest treatment
- Health inspection
- Custom action

Each care type may define recurrence, seasonality, preferred time, instructions, and enabled state.

## 4. Schedule calculation

The app schedules reminders but does not claim biological certainty. Each schedule contains:

- Base interval or recurrence
- Last completed date
- Next due date
- Seasonal adjustment
- User override
- Snooze/reschedule history

Use copy such as “may be ready” rather than “must be watered” unless the user explicitly creates a fixed instruction.

## 5. Dashboard

Sections:

- Due today
- Overdue
- Upcoming
- Needs attention
- Travel risk
- Recent care
- Collection statistics

## 6. Collection management

Support:

- Grid/list
- Search
- Room filter
- Species filter
- Status filter
- Care-type filter
- Caretaker filter
- Sort by name, last care, next due, acquired date
- Multi-select
- Bulk care with per-plant overrides
- Archive

## 7. Care events

Care events are append-only records with:

- Plant
- Care type
- Timestamp
- Source device
- Caretaker
- Note
- Photo
- Quantity/duration if relevant
- Stable action ID

Editing a care event should preserve an audit-friendly modification record or replacement relationship when practical.

## 8. Health observations

Fields:

- Observation date
- Symptom category
- Severity selected by user
- Photos
- Notes
- Suspected cause entered by user
- Treatment/action
- Follow-up date
- Resolved date

The app does not diagnose. Future AI support requires a separate specification.

## 9. Growth timeline

- Chronological photos
- Measurements if user adds them
- Notes
- Milestone flags
- Side-by-side comparison
- Storage-efficient thumbnails

## 10. Travel coverage

For an active trip:

- Estimate which scheduled tasks fall within absence
- Identify high-attention plants using user rules
- Assign caretaker or “self-managed/no caretaker”
- Generate concise caretaker instructions
- Record last care before departure
- Record caretaker updates when available later
- Highlight unresolved coverage without alarmist language

## 11. QR identities

Each plant receives a stable QR payload that resolves to a plant ID, not private notes embedded directly in the code.

Initial app:

- Generate and display/print QR
- Scan within the main app
- Open plant detail or quick care

Future caretaker app:

- Resolve shared assignment through a backend or shared CloudKit design defined later

## 12. Import and export

- CSV import may be added after manual model stability.
- JSON/CSV export is required.
- Photos are included in media export.

## 13. Progression integration

Eligible events:

- First plant added
- Care action completed
- Collection milestone
- Growth photo milestone
- Travel coverage completed
- Health issue resolved

Rewards must not encourage overwatering or unnecessary actions. Repeated care events within unrealistic intervals should not be farmable for rewards.

## 14. Watch support

- Show selected due tasks
- Quick-complete care
- Queue action offline
- Require confirmation for ambiguous actions
- Do not expose full health/photo history on Watch

## 15. Edge cases

- Plant deleted with history
- Duplicate names
- Same care event from Watch and phone
- Time-zone changes
- Archived plant with pending notification
- Bulk action partially fails
- Cloud conflict
- No photo
- 500+ history records
