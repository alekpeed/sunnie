# Information Architecture

## 1. Primary navigation

Use a five-tab native SwiftUI tab structure:

1. **Today**
2. **Jungle**
3. **Travel**
4. **Wellness**
5. **More**

The order is locked unless usability testing produces a documented reason to change it.

## 2. Today

Today is the daily operational center.

Default card hierarchy:

1. Greeting, affirmation, and Sunnie
2. Current or upcoming travel status
3. Plant tasks due
4. Wellness check-in
5. Meal/snack prep
6. Daily puzzle
7. Progression and recent unlock
8. Contextual quick actions

Cards may collapse after completion but must remain reviewable.

## 3. Jungle

### Landing screen

- Due today
- Overdue
- Upcoming
- Needs attention
- Travel coverage
- Recent care
- Search and filters
- Collection statistics

### Child destinations

- Plant collection
- Plant detail
- Add/edit plant
- Care logging
- Health observation
- Growth timeline
- Travel coverage plan
- Caretaker instructions
- QR identity
- Care history

## 4. Travel

### Landing screen

- Active trip
- Upcoming trips
- Work travel
- Past travel
- World map
- Saved places
- Passport and collections

### Child destinations

- Create/edit trip
- Trip overview
- Itinerary
- Packing
- Departure checklist
- Return checklist
- Time zones
- Weather
- Sleep/jet lag
- Hydration
- Meals/snacks
- Layover routine
- Hotel routine
- Plant handoff
- Travel documents
- Memories
- Place detail
- World map
- Destination pack

## 5. Wellness

### Landing screen

- Check-in
- Affirmation
- Suggested practice
- Breathing
- Meditation
- Calm sounds
- Journal shortcut
- History/trends

### Child destinations

- Mood/energy/stress/sleep check-in
- Gratitude
- Breathing player
- Meditation player
- Grounding exercise
- Sleep wind-down
- Travel recovery
- Sound library
- Wellness history
- Journal

## 6. More

The More screen uses illustrated but clearly labeled destinations:

- Meals
- Games
- Journal
- Collections
- Sunnie Home
- Themes
- Audio
- Health and Watch
- Settings

Do not hide critical daily features only inside More. Today surfaces meal, game, journal, and collection shortcuts contextually.

## 7. Meals

- Today’s plan
- Planner
- Recipes
- Grocery list
- Pantry
- Prep tasks
- Packed food
- Favorites
- History

## 8. Games

- Daily puzzle
- Continue
- Game library
- Categories
- Results/history
- Rewards
- Future shared games placeholder only after backend approval

## 9. Journal

- New entry
- Drafts
- Recent entries
- Calendar
- Search
- Tags
- Favorites
- Linked travel/plant/mood views

## 10. Collections

- Outfits
- Decor
- Plants
- Postcards
- Stamps
- Souvenirs
- Music
- Soundscapes
- Story scenes
- Theme variants

## 11. Sunnie Home

- Main room
- Outfit
- Decor edit mode
- Plant placement
- Travel nook
- Music/ambience
- Collection inspection

## 12. Themes

- Active theme
- Installed themes
- Locked themes
- Day-phase preview
- Audio preview
- Accessibility preview

## 13. Global utilities

### Search

Feature-specific search is required. A global search may be added after core feature search is stable.

### Deep links

Use a typed route system for:

- Notifications
- Widgets
- Watch handoff
- App Intents
- Internal links

Examples:

```text
sunniedays://today
sunniedays://jungle/due
sunniedays://plant/{uuid}
sunniedays://trip/{uuid}
sunniedays://wellness/checkin
sunniedays://games/daily
sunniedays://journal/new
```

### Modal use

Use sheets for short creation, confirmation, quick logging, and filters. Use navigation destinations for deep records and multi-step workflows.

## 14. Navigation-state preservation

- Preserve each tab’s navigation stack when switching tabs.
- Preserve form drafts through interruptions.
- Restore the most relevant screen after Watch, widget, or notification actions.
- Do not unexpectedly reset a map, plant filter, or game session.
