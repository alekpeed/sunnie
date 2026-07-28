# Onboarding, Settings, and Permissions

## Onboarding principles

- Keep the initial path short enough to reach Today quickly.
- Allow every optional integration to be skipped.
- Explain value before invoking a system permission prompt.
- Do not request all permissions on first launch.
- Save progress if onboarding is interrupted.

## Recommended onboarding sequence

1. Welcome and Sunnie introduction
2. Choose initial theme
3. Confirm time/day-cycle behavior
4. Configure quiet hours and reminder categories
5. Add first plant or skip
6. Confirm no-eggs dietary rule
7. Add an upcoming or past trip or skip
8. Explain Apple Health and request selected permissions only if accepted
9. Detect Apple Watch and explain companion features
10. Enter Today

## Permission timing

### Notifications

Request after the user has selected useful categories. If denied, keep in-app reminders and provide a settings path.

### HealthKit

Request from Health settings or the related onboarding step. Show exact read/write categories. Never imply full access is required.

### Calendar

Request when the user enables calendar import/export or creates a calendar-linked trip.

### Location

Request when enabling sunrise/sunset, local weather, or current-place travel behavior. Offer manual location and time-zone entry.

### Photos

Use the system picker where possible. Request broader library access only when required.

### Microphone

Request only when starting the first voice note.

## Settings structure

### Profile

- Display name
- Nickname behavior
- Home time zone
- Languages
- Dietary rules

### Appearance

- Theme
- Automatic day cycle
- Manual preview
- Night brightness
- Motion

### Notifications

- Category toggles
- Quiet hours
- Cadence
- Travel behavior
- Sound

### Audio

- Master
- Music
- Ambience
- Narration/future voice
- Effects
- Background playback behavior

### Integrations

- Health
- Watch
- Calendar
- Location
- Weather
- iCloud

### Accessibility

- Follow system Dynamic Type
- High contrast
- Reduce motion behavior
- Haptics
- Captions

### Data

- Sync status
- Export
- Delete categories
- Delete all data
- Reset onboarding

## Denied-permission behavior

- App continues functioning.
- Explain the missing enhancement, not a broken app.
- Provide a direct route to system settings when appropriate.
- Do not repeatedly prompt after denial.

## Private-app defaults

- No analytics permission screen
- No marketing consent
- No public username
- No custom account creation
