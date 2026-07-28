# Data Model Specification

## 1. Modeling rules

- Stable UUID for user-created entities
- Stable string ID for shipped content
- Creation and modification timestamps
- Source-device metadata where sync/idempotency requires it
- Domain models separated from SwiftData model classes
- Append-only event history where practical
- Explicit deletion behavior

## 2. Identity and settings

### UserProfile

- id
- displayName
- preferredNickname
- homeTimeZoneID
- preferredLocale
- enabledLanguageIDs
- createdAt
- modifiedAt

### UserPreferences

- activeThemeID
- automaticDayCycle
- dayCycleOverride
- quietHours
- audio settings
- haptic settings
- accessibility overrides
- nicknameProbability
- dietaryRuleIDs

## 3. Plants

### Plant

- id
- name
- nickname
- speciesName
- variety
- locationID
- lightProfile
- difficulty
- acquiredDate
- source
- pot
- soil
- notes
- status
- qrToken
- primaryPhotoID
- createdAt/modifiedAt

### PlantLocation

- id
- name
- room
- light notes
- sort order

### PlantCareSchedule

- id
- plantID
- careType
- recurrence definition
- preferred time
- seasonal modifier
- enabled
- nextDueDate

### PlantCareEvent

- id
- plantID
- careType
- performedAt
- sourceDeviceID
- caretakerID
- note
- photoID
- measurement
- actionKey

### PlantHealthObservation

- id
- plantID
- observedAt
- symptom
- severity
- notes
- treatment
- photoIDs
- followUpDate
- resolvedAt

### PlantPhoto

- id
- plantID
- type
- local media reference
- cloud media reference
- capturedAt
- note

### PlantTravelCoverage

- id
- plantID
- tripID
- caretakerID
- instructions
- status
- expectedCareDates
- lastPreTripCare

## 4. Travel

### Trip

- id
- title
- type
- status
- startDate/endDate
- homeTimeZoneID
- notes
- calendarEventID
- createdAt/modifiedAt

### TripSegment

- id
- tripID
- type
- originPlaceID
- destinationPlaceID
- start/end
- confirmation reference
- notes

### Place

- id
- displayName
- countryCode
- region
- latitude/longitude
- timeZoneID
- mapItemIdentifier where available
- favorite
- notes

### PackingTemplate / PackingItem

- stable IDs
- category
- name
- quantity
- required
- packed
- notes
- trip/template relationships

### TravelChecklistItem

- id
- tripID
- checklist type
- title
- dueAt
- completedAt
- actionKey

### TravelMemory

- id
- tripID
- placeID
- date
- title
- body
- photoIDs
- tags
- favorite
- postcardID
- stampID

## 5. Wellness and journal

### WellnessCheckIn

- id
- recordedAt
- timeZoneID
- mood
- energy
- stress
- sleepQuality
- note
- voiceNoteID
- photoID
- sourceDeviceID
- actionKey

### WellnessSession

- id
- type
- startedAt/endedAt
- duration
- completion state
- audioCueID
- HealthKit reference
- sourceDeviceID

### JournalEntry

- id
- title
- body
- draft state
- createdAt/modifiedAt
- linked check-in/trip/place/plant/meal IDs
- tags
- favorite
- attachment IDs
- gratitude items

### MediaAttachment

- id
- owner type/ID
- media type
- local URL token
- cloud asset token
- thumbnail token
- createdAt

## 6. Meals

### MealPlan

- id
- date range
- context
- tripID
- createdAt/modifiedAt

### Meal

- id
- planID
- date
- slot
- recipeID
- custom title
- preparedAt
- packedAt
- storage state
- notes

### Recipe

- id
- title
- ingredient relationships
- steps
- prep/cook minutes
- servings
- storage notes
- refrigeration flag
- travel metadata
- dietary tags
- favorite
- photoID

### Ingredient

- id
- name
- normalized key
- dietary tags

### GroceryList / GroceryItem

- id
- date/context
- item
- quantity/unit
- purchasedAt
- linked meal IDs

### PantryItem

- id
- ingredient/custom name
- quantity/unit
- purchase/open/expiration dates
- storage location
- useBeforeTrip

### PrepTask

- id
- meal/trip link
- title
- dueAt
- completedAt
- reminder ID

## 7. Games

### GameDefinitionReference

- stable content ID
- pack ID/version
- game type
- display name
- enabled

### GameSession

- id
- gameID
- seed
- serialized state
- difficulty
- started/updated/completed dates
- score
- daily date
- state version

### PuzzleResult

- id
- sessionID
- success
- score
- duration
- hints
- explanation content ID
- progression event ID

## 8. Progression and content ownership

### ProgressionProfile

- id
- experience
- level
- rhythm metrics
- last activity

### ProgressionEvent

- id
- type
- source ID
- occurredAt
- deterministic key
- payload version/data

### RewardGrant

- id
- rewardID
- grantedAt
- source event ID
- deterministic key

### CollectibleOwnership

- id
- collectibleID
- acquiredAt
- equipped
- placement data

### SunnieHomeState

- id
- equipped outfit
- active room/theme
- placed items
- displayed souvenirs
- music/ambience selection

## 9. Themes/audio/content

### ThemeSelection

- active theme ID
- selectedAt
- override preferences

### ContentPackState

- pack ID
- installed version
- installation date
- enabled
- validation state

### AudioCuePreference

- context ID
- user override
- enabled/gain

## 10. Notifications and sync

### ScheduledReminder

- id
- category
- source entity
- scheduledAt
- time-zone policy
- recurrence
- quiet-hours policy
- adaptive level
- response state
- notification request ID

### PendingWatchAction

- action ID
- type
- payload version/data
- createdAt
- source device
- processedAt
- state

### SyncConflict

- id
- entity type/ID
- local version metadata
- remote version metadata
- resolution state

## 11. Schema evolution

Implement models by phase. The final domain specification does not require defining every SwiftData class on day one. Each phase adds an explicit schema version and migration tests.
