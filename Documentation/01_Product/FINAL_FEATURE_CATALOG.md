# Final Feature Catalog

This catalog describes the complete intended native 2D version of Sunnie Days. Delivery is phased, but the final release should contain the systems below unless a later Architecture Decision Record explicitly changes scope.

## FC-01: Sunnie companion

- Canonical young Sunnie appearance
- Context-aware poses, expressions, and outfits
- Sleepy, happy, calm, curious, proud, and celebratory states
- First-person dialogue
- Sparse “Noonies” personalization
- Recent-message avoidance
- Positive reaction to completed actions
- Neutral handling of missed actions
- Theme, destination, time, and feature context
- Sunnie shortcut or companion panel from major screens

## FC-02: Today dashboard

- Time-aware greeting
- Daily affirmation
- Sunnie message
- Active or upcoming trip card
- Plant tasks due
- Wellness check-in
- Meal or snack recommendation
- Daily puzzle
- Progression and unlock preview
- Quick actions
- User-adjustable card order after the default experience is stable

## FC-03: Universal day-cycle presentation

- Morning, day, afternoon, evening, night, and late-night internal phases
- Public labels limited to Sunnie Days, Sunnie Afternoonies, and Sunnie Nights
- Theme-aware lighting and color adjustments
- Greeting and suggestion changes
- Sunnie pose and wardrobe variants
- Optional ambient audio changes
- Time-zone awareness
- Sunrise/sunset support when location access is available
- Manual override
- Quiet-hour integration

## FC-04: Theme system

- Lush Tropical Jungle
- Travel Scrapbook
- Day-Cycle Theme
- Theme preview and selection
- Theme-specific backgrounds, cards, decorative art, outfits, ambience, and haptics
- Accessibility variants
- Reduced-motion variants
- Locked and unlocked themes
- Expandable content-pack architecture

## FC-05: Deep plant care

- Support for 50+ plants
- Plant profile, nickname, species, variety, photos, room, light, soil, pot, and notes
- Watering, fertilizing, misting, rotating, cleaning, pruning, repotting, propagation, and custom schedules
- Care history
- Health observations, symptoms, treatments, pests, and resolution tracking
- Growth photo timeline
- Search, filter, sort, group, and bulk-care actions
- Due, overdue, upcoming, and travel-risk views
- Caretaker instructions
- Trip-specific coverage
- QR-ready plant identifiers
- Collection statistics
- Future caretaker-app compatibility

## FC-06: Practical travel and flight-attendant support

- Trip creation and status
- Personal and work-trip contexts
- Itinerary and segments
- Trip countdown
- Packing lists and templates
- Departure and return checklists
- Work uniform/equipment checklist
- Local and home time comparison
- Weather
- Calendar integration
- Sleep and jet-lag planning
- Hydration support
- Meal/snack planning
- Layover and hotel routines
- Post-trip recovery
- Plant-care handoff
- Travel document reminders
- Delta-inspired private visual mode with isolated replaceable brand assets

## FC-07: Travel memories and exploration

- Historical travel log
- Interactive world map
- Countries and cities visited
- Saved and favorite places
- Photos and notes
- Trip journal links
- Passport stamps
- Postcards
- Souvenirs
- Destination collections
- Destination-specific Sunnie outfits and home scenes
- Destination music and ambience
- App-authored downloadable country/destination packs

## FC-08: Wellness

- Mood, energy, stress, and sleep check-ins
- Daily affirmations
- Gratitude
- Self-care routines
- Breathing exercises
- Guided text/timed meditations in the initial release
- Calm sounds and ambient audio
- Short reset and grounding exercises
- Sleep wind-down
- Travel recovery routines
- Wellness history and trends
- Optional Apple Health context
- Gentle suggestions

## FC-09: Journal

- Text entries
- Voice notes
- Photo entries
- Gratitude lists
- Mood links
- Trip links
- Plant links
- Tags and favorites
- Search and calendar views
- Draft preservation
- Export

## FC-10: Adaptive reminders

- Plant care
- Travel preparation
- Meals and food prep
- Hydration
- Wellness routines
- Journal prompts
- Quiet hours
- Snooze, reschedule, dismiss, and disable
- Time-zone-aware scheduling
- User-adjustable cadence
- Engagement-aware re-offering without emotional escalation
- Local notifications in the initial build

## FC-11: Meals and preparation

- Home-day, work-day, travel-day, layover, and recovery-day planning
- Meal and snack suggestions
- Egg-free filtering
- Recipe library
- Grocery list
- Pantry inventory
- Expiration and use-before-trip prompts
- Batch prep
- Portable meal and snack guidance
- Food packing checklist
- Storage and refrigeration notes
- Prep timers
- Favorites and history

## FC-12: Games

- Daily puzzle
- Game library
- Wordplay
- Multilingual clues
- Trivia
- Memory
- Logic deduction
- Pattern recognition
- Plant and travel themes
- Difficulty levels
- Hints
- Save/resume
- Results and explanations
- Reward integration
- Downloadable game packs
- Deterministic state model for future turn-based play

## FC-13: Progression and collectibles

- Experience and levels
- Gentle rhythm/streak celebrations
- Milestones
- No punishment for missed days
- Outfits
- Room decor
- Rare plants
- Postcards
- Passport stamps
- Souvenirs
- Music and soundscapes
- Story scenes
- Theme variants
- Destination objects
- Source-of-unlock explanations

## FC-14: Sunnie Home

- Cozy room
- Indoor jungle
- Travel nook
- Outfit selection
- Decor placement
- Displayed souvenirs and plants
- Theme and day-cycle transformation
- Destination transformation
- Music and ambience selection
- Interactive 2D objects
- Future renderer abstraction for animation or 3D

## FC-15: Apple Health

Optional read access, as individually enabled:

- Steps
- Sleep analysis
- Heart rate
- Resting heart rate
- Workouts
- Active energy
- Stand data where available and useful
- Mindful sessions
- Dietary water where available and enabled

Optional write access:

- Mindful sessions
- App-recorded meditation sessions
- App-recorded breathing sessions
- Dietary water only if the user explicitly enables logging

## FC-16: Apple Watch

- Quick mood check-in
- Hydration log
- Complete selected plant tasks
- Breathing and meditation timer
- Daily affirmation
- Trip countdown
- Local/home time
- Travel reminders
- Meal/snack reminder
- Daily puzzle prompt or lightweight interaction
- Progress glance
- Smart Stack/widget support where practical
- Offline action queue and idempotent synchronization

## FC-17: Music and audio

- Creator-managed soundtrack
- No user-facing MIDI import
- Rendered music assets
- Optional adaptive runtime MIDI
- Theme music
- Destination music
- Game music
- Meditation and breathing audio
- Plant-care cues
- Reward sounds
- Jungle, rain, city, café, and night ambience
- Crossfades and interruption handling
- Separate music, ambience, narration, and effects controls

## FC-18: Apple ecosystem integration

- Calendar through EventKit
- Maps through MapKit
- Weather through WeatherKit
- Local notifications through UserNotifications
- Widgets through WidgetKit
- Siri/Shortcuts/system actions through App Intents
- Private iCloud synchronization

## FC-19: Privacy, reliability, and accessibility

- Local-first operation
- Private iCloud sync
- Offline access
- Export and deletion
- No ads
- No mandatory custom account
- Dynamic Type
- VoiceOver
- Reduced motion
- Sufficient contrast
- Haptic alternatives
- Migration support
- Conflict-safe actions

## FC-20: Future extensions, not part of the initial 2D implementation

- Lightweight Android game companion
- Turn-based cross-platform play
- Plant caretaker companion app
- LifeOS integration
- Recorded or synthesized Sunnie voice
- Advanced 2D character rigging
- 3D Sunnie and environments
- Custom cross-platform backend
- Optional AI-assisted plant and meal tools
