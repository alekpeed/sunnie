# Feature Specification — Travel and Flight-Attendant Life

## 1. Objective

Support practical work and personal travel while preserving a joyful historical record. The feature is not an airline operations or safety system.

## 2. Trip types

- Work trip
- Personal trip
- Day trip
- Past trip imported for memories
- Custom

## 3. Trip model

Required:

- Stable ID
- Title
- Type
- Start/end dates
- Status: planning, upcoming, active, returning, completed, archived
- Home time zone
- Destination time zones
- Places
- Segments
- Notes
- Calendar link
- Weather locations
- Destination packs

## 4. Practical work-trip area

### Work checklist groups

- Uniform and appearance items
- Required work items entered by user
- Personal items
- Toiletries
- Technology/chargers
- Food and snacks
- Documents
- Custom templates

### Routines

- Before leaving home
- Airport/commute
- Hotel arrival
- Layover reset
- Wake-up/departure
- Return home
- Recovery

### Wellness helpers

- Local/home time
- Suggested sleep window based on user-entered schedule, clearly nonmedical
- Hydration plan
- Meal/snack plan
- Short movement or breathing prompt

## 5. Delta-inspired private presentation

The private build may show:

- Navy uniform
- Red accent
- Flight-attendant visual language
- Paris or destination background

Brand assets must be isolated and replaceable. Core code uses semantic identifiers. If the app is distributed beyond private use, review or replace third-party marks.

## 6. Packing system

- Reusable templates
- Trip-specific copies
- Categories
- Quantity
- Required/optional
- Packed state
- Notes
- Weather-dependent suggestions
- Work/personal/food separation
- Duplicate detection
- Past-trip reuse

## 7. Departure and return

Departure may include:

- Documents
- Chargers
- Food packed
- Plant coverage
- Trash/perishables
- Doors/windows/custom home steps

Return may include:

- Unpack
- Laundry
- Food/pantry update
- Plant review
- Recovery routine
- Add memories

No safety-critical checklist should be represented as official airline procedure.

## 8. Time zones

- Show home and local time
- Support multiple destinations
- Store IANA time-zone identifiers
- Handle daylight saving changes
- Show absolute event time and local interpretation
- Allow manual override
- Test boundary cases

## 9. Weather

Use WeatherKit when permission/network allows.

- Current conditions
- Relevant daily/hourly summary
- Last updated time
- Attribution required by Apple
- Manual location fallback
- Graceful unavailable state

Weather informs suggestions but does not automatically modify user records without confirmation.

## 10. Calendar

EventKit integration may:

- Read selected calendar events after permission
- Create trip events
- Link an app trip to a calendar event identifier
- Detect external edits

The app’s Trip remains the source of truth for Sunnie Days-specific content.

## 11. Travel memories

- Place
- Date
- Text
- Photos
- Rating/favorite
- Tags
- Linked journal
- Postcard
- Stamp
- Souvenir

Past travel may be added without a full practical itinerary.

## 12. World map

- MapKit for interactive map
- Visited/saved annotations
- Country/city list fallback
- Filters by year, trip type, favorite
- Offline access to records and cached thumbnails
- No promise of downloadable offline basemap tiles

## 13. Destination packs

Initial priorities:

- Paris
- Tokyo
- Vietnam
- Spain
- Brazil

A pack may include:

- Outfit
- Background
- Postcard template
- Stamp set
- Music/ambience
- Trivia/game content
- Decorative objects
- Saved guide content

## 14. Plant integration

Before departure:

- Identify plants with care dates during trip
- Assign caretaker or no caretaker
- Generate instructions
- Surface unresolved coverage

After return:

- Show plants likely needing review
- Avoid claiming damage without user observation

## 15. Meal integration

- Generate trip-day meal slots
- Show packed food
- Refrigeration notes
- Use-before-trip pantry items
- Layover snack plan

## 16. Offline behavior

Trip details, packing, checklists, time zones, memories, and downloaded destination content remain available. Live weather and uncached map imagery may not.
