# Feature Specification — Wellness, Journal, and Calm

## 1. Objective

Provide a substantial, private wellness system that supports reflection and calming routines without diagnosis, treatment claims, guilt, or compulsory engagement.

## 2. Check-in

Core fields:

- Mood
- Energy
- Stress
- Sleep quality/reflection
- Optional note
- Optional voice note
- Optional photo
- Timestamp and time zone

Mood choices may use Sunnie expressions, but every option must be neutrally labeled and accessible without relying on images.

## 3. Check-in response

After saving:

- Acknowledge the entry.
- Do not reinterpret or challenge the user’s answer.
- Offer no more than one relevant optional action.
- Allow immediate dismissal.
- Disable nickname use in sensitive low-mood contexts if it could feel trivializing.

## 4. Affirmations

- Tagged content library
- Favorite/hide
- Avoid recent repetition
- Time/theme/travel context
- No promises of outcomes
- No medical or spiritual assumption

## 5. Gratitude

- One or more short items
- Optional photo
- Journal link
- Search and history
- No streak penalty

## 6. Journal

Entry formats:

- Text
- Voice note
- Photo
- Gratitude list
- Mixed entry

Links:

- Mood
- Plant
- Trip
- Place
- Meal
- Game milestone

Features:

- Autosaved drafts
- Tags
- Favorites
- Calendar
- Search
- Export
- Delete and restore strategy

## 7. Breathing

Initial configurable practices:

- Simple equal breathing
- Longer exhale
- Box breathing, clearly optional
- Custom timer

The app should not present breathing exercises as treatment for a medical condition.

## 8. Meditation

Initial release:

- Timed silent meditation
- Text-guided meditation
- Background music/ambience
- Bell/chime start and end
- Short travel reset
- Sleep wind-down
- Grounding practice

Future recorded voice is deferred.

## 9. Calm sounds

Categories:

- Rain
- Jungle
- Ocean
- Café
- Night
- Soft room tone
- Creator music

Features:

- Timer
- Loop
- Mix music and ambience where supported
- Favorite
- Separate volume
- Interruption handling

## 10. Wellness history

Views:

- Calendar
- Recent entries
- Mood/energy/stress distributions
- Meditation minutes
- Optional HealthKit context

Language must remain descriptive:

- “You logged calm more often this week.”

Avoid causal or diagnostic claims:

- “Your heart rate proves you are anxious.”

## 11. HealthKit interaction

- Read only explicitly authorized types.
- Write mindful sessions after completed practices if enabled.
- Do not duplicate raw HealthKit history in the app.
- Explain that Health data may be incomplete.

## 12. Crisis behavior

Sunnie Days is not a crisis service. Do not invent crisis detection based on mood selections or journal text in the initial app. If a later feature adds such analysis, it requires a separate high-stakes specification.

## 13. Privacy

- Journal and wellness data remain private.
- No remote analytics of content.
- Do not include journal text in logs.
- Protect export files through normal iOS share-sheet behavior and clear user action.
