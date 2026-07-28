# Apple and System Integrations

## 1. Integration rule

Every framework is wrapped behind a service protocol. Features receive domain-safe values and errors, not raw framework types.

## 2. HealthKit

Adapter responsibilities:

- Availability
- Authorization request/status
- Queries
- Background-delivery configuration where used
- Mindful-session and hydration writes
- Deduplication metadata
- Domain summary mapping

## 3. WatchConnectivity

Adapter responsibilities:

- Session activation
- Reachability
- Immediate messages
- Application context
- Queued user-info transfer
- File transfer if needed
- Payload versioning
- Outstanding-transfer monitoring

## 4. EventKit

Adapter responsibilities:

- Permission
- Read selected calendars/events
- Create/update linked trip events
- Store event identifiers
- Detect external changes
- Domain mapping

## 5. MapKit

Adapter responsibilities:

- Place search
- Geocoding/reverse geocoding using current supported APIs
- Map annotations
- Look Around if later desired
- Domain `Place` mapping
- Graceful offline behavior

## 6. WeatherKit

Adapter responsibilities:

- Fetch current/hourly/daily data needed by travel
- Cache selected summaries
- Provide attribution metadata
- Respect call limits
- Map framework conditions to domain values

## 7. UserNotifications

Adapter responsibilities:

- Authorization
- Category/action registration
- Schedule/cancel
- Retrieve pending/delivered
- Route responses
- Stable request IDs

## 8. WidgetKit

- Read small shared summaries
- Use App Group/shared container if required
- Avoid direct full database access without a deliberate design
- Respect privacy and refresh budgets

## 9. App Intents

- Use domain use cases
- Define app entities for plants/trips only where safe and useful
- Keep titles/descriptions localized
- Support Shortcuts, Siri, widgets, and system actions

## 10. AVFAudio/Core MIDI

- Central audio graph/session
- Runtime MIDI only through audio service
- Creator source not exposed
- Handle interruptions and route changes

## 11. Photos and microphone

- Prefer system photo picker
- Request microphone at first voice-note action
- Media repository handles file lifecycle

## 12. Location

Use Core Location only when needed for:

- Sunrise/sunset behavior
- Current travel place
- Weather

Offer manual alternatives and do not continuously track location in the initial app.
