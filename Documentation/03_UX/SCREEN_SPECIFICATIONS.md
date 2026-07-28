# Core Screen Specifications

Every screen must define loading, empty, error, offline, denied-permission, Dynamic Type, VoiceOver, and reduced-motion behavior.

## S-01: Today

### Purpose

Show the most important current information and one-tap entry points.

### Required regions

- App/day presentation header
- Sunnie and greeting
- Affirmation
- Travel card
- Jungle card
- Wellness card
- Meal/prep card
- Daily puzzle card
- Progress/collection card
- Quick actions

### Primary actions

- Open current trip
- Complete plant task
- Check in
- Open meal plan
- Play daily puzzle
- Visit Sunnie Home

### States

- No trip, upcoming trip, active trip, returning today
- No plant tasks, due tasks, overdue tasks
- Check-in pending/completed
- Meal plan empty/ready
- Puzzle unstarted/in progress/completed
- Offline/sync pending

## S-02: Jungle dashboard

### Required regions

- Due today
- Overdue
- Needs attention
- Upcoming
- Travel coverage
- Search/filter controls
- Recent care
- Collection summary

### Primary actions

- Add plant
- Start care session
- Open plant
- Create travel plan

## S-03: Plant collection

- Grid/list toggle
- Search
- Filter by room, species, status, care type, caretaker, travel risk
- Sort by name, next due, last care, acquired date
- Multi-select for bulk care
- Persistent filter state

## S-04: Plant detail

- Hero photo
- Name/nickname/species
- Status and next due actions
- Quick-care buttons
- Schedule
- History
- Health
- Growth photos
- Location/light/soil/pot
- Notes
- Travel coverage
- QR identity
- Edit

## S-05: Plant editor

Use sections with progressive disclosure. Species lookup is optional; manual entry always works. Never block saving because reference content is missing.

## S-06: Travel dashboard

- Active trip
- Upcoming trips
- Work travel shortcut
- World map
- Recent memories
- Saved places
- Passport summary
- Create trip

## S-07: Trip overview

- Dates/status
- Destination/local and home time
- Weather summary
- Checklist progress
- Packing progress
- Plant coverage status
- Meal prep status
- Itinerary
- Notes

## S-08: Packing

- Template selection
- Categories
- Required/optional
- Quantity
- Packed state
- Search/add custom item
- Reuse template
- Separate work/personal/food sections

## S-09: World map

- MapKit map
- Visited/saved place annotations
- Filters
- List fallback
- Offline state showing cached place records without promising map imagery
- Add past trip/place

## S-10: Wellness dashboard

- Check-in status
- Affirmation
- Recommended calm tool
- Breathing
- Meditation
- Sounds
- Journal
- Trends

## S-11: Check-in

- Mood first
- Optional energy, stress, sleep
- Note/voice/photo
- Save
- Skip optional fields
- No “bad answer” state

## S-12: Calm player

- Practice name
- Duration
- Progress
- Pause/resume/stop
- Music and ambience
- Captions/instructions
- Interruption recovery
- HealthKit write status only after completion

## S-13: Journal home

- New entry
- Drafts
- Recent entries
- Calendar
- Search
- Tags
- Favorites

## S-14: Journal editor

- Autosaved draft
- Text
- Voice note
- Photos
- Gratitude items
- Mood/trip/plant links
- Tags
- Save/delete draft

## S-15: Meals dashboard

- Today’s plan
- Travel context
- Prep tasks
- Packed food
- Grocery list
- Pantry/use-before-trip
- Suggestions

## S-16: Meal planner

- Day/context selector
- Meal slots
- Recipe/custom meal
- Prep date
- Pack/refrigerate flags
- Grocery impact

## S-17: Grocery list

- Group by category
- Linked meals
- Quantity
- Purchased state
- Add custom item
- Pantry transfer

## S-18: Games home

- Daily puzzle
- Continue
- Categories
- Featured games
- Rewards
- Recent results

## S-19: Game session

Game-specific layout inside a common host with:

- Exit/save
- Rules/help
- Hint
- Audio/haptics
- Progress
- Accessibility alternative

## S-20: Game result

- Result/score
- Clear explanation
- Reward progress
- Sunnie reaction
- Replay or next action

## S-21: Collections

- Category tabs or filter
- Owned/locked
- Source of unlock
- Preview/equip/place/play

## S-22: Sunnie Home

- Scene canvas
- Sunnie
- Edit/decor mode
- Outfit
- Music/ambience
- Travel nook
- Collection inspection
- Static fallback under reduced motion

## S-23: Theme gallery

- Active theme
- Installed/locked
- Preview in Sunnie Days, Sunnie Afternoonies, Sunnie Nights
- Audio preview
- Apply
- Accessibility preview

## S-24: Settings

- Profile
- Day cycle
- Notifications/quiet hours
- Audio
- Health
- Watch
- Calendar
- Location/weather
- Accessibility
- iCloud/sync
- Export/delete
- About/credits

## S-25: Permission explainer

Before system prompt:

- State the benefit
- State what data is requested
- State that permission is optional
- Offer Not Now
- Avoid asking for unrelated data together
