# User Flows

## Flow UF-01: First launch

1. Launch app.
2. See Sunnie welcome.
3. Confirm the app is private/personal and local-first.
4. Select initial visual theme.
5. Choose notification categories and quiet hours.
6. Add first plant or skip.
7. Set no-eggs preference as preconfigured and editable only through explicit settings.
8. Connect HealthKit or skip.
9. Confirm Watch connection if available or skip.
10. Add an upcoming trip or skip.
11. Enter Today.

Rules:

- Permissions are requested only when the related step is accepted.
- Skipping does not produce pressure.
- Onboarding progress is saved.

## Flow UF-02: Daily opening

1. Open Today.
2. App loads local cached summary immediately.
3. Time engine chooses presentation.
4. Sunnie shows greeting and affirmation.
5. User reviews travel, plants, wellness, meal, and puzzle cards.
6. User chooses one action or closes app.

Success criterion: essential information is understandable within 15 seconds.

## Flow UF-03: Log plant watering from Today

1. Tap plant task card.
2. Open due-task list.
3. Tap a plant or use quick-complete.
4. Confirm watering time; optionally add note/photo.
5. Save care event locally.
6. Recalculate next due date.
7. Emit progression event.
8. Update Today summary.
9. Show short Sunnie response.
10. Queue CloudKit and Watch state updates.

## Flow UF-04: Bulk plant-care session

1. Open Jungle.
2. Select “Care session.”
3. Filter by room or care type.
4. Select multiple plants.
5. Log shared action and time.
6. Allow per-plant exceptions.
7. Save individual care events.
8. Show summary and progression.

## Flow UF-05: Prepare for a work trip

1. Open active/upcoming work trip.
2. Review date, destination, local time, and weather.
3. Complete work packing checklist.
4. Complete personal packing checklist.
5. Review meals/snacks and hydration.
6. Review sleep/jet-lag suggestion.
7. Assign plant coverage or generate self-care plan.
8. Confirm departure checklist.
9. Calendar and notifications update if enabled.

## Flow UF-06: Record travel memory

1. Open active or past trip.
2. Tap “Add memory.”
3. Select or create place.
4. Add text, photos, rating, tags, and favorite flag.
5. Optionally create postcard/stamp entry.
6. Save offline.
7. Update map and destination collection.

## Flow UF-07: Wellness check-in

1. Tap check-in on Today or Wellness.
2. Select mood.
3. Optionally record energy, stress, and sleep.
4. Add note, voice note, or photo if desired.
5. Save.
6. Sunnie acknowledges without judging.
7. App may offer one relevant calm tool.
8. User may accept, skip, or close.

## Flow UF-08: Meditation or breathing

1. Select practice and duration.
2. Choose music/ambience or silence.
3. Start timer.
4. Handle interruption safely.
5. Finish or stop early without failure language.
6. Save session.
7. Optionally write mindful-session data to HealthKit if permission exists.

## Flow UF-09: Plan meals before travel

1. Open trip or Meals.
2. Choose trip dates and meal contexts.
3. Review pantry and use-before-trip items.
4. Add recipes or quick meals.
5. Generate prep tasks and grocery list.
6. Mark food as prepared and packed.
7. Save offline and surface reminders.

## Flow UF-10: Play daily puzzle

1. Tap Daily Puzzle.
2. Load deterministic daily content.
3. Explain mechanic briefly if first play.
4. Save progress after each meaningful action.
5. Complete or leave and resume later.
6. Show explanation, score, and reward progress.
7. Never penalize skipped days.

## Flow UF-11: Watch quick plant action

1. Watch shows due plant task.
2. User taps “Watered.”
3. Watch creates action with stable ID and timestamp.
4. If phone reachable, send immediately.
5. Otherwise queue background transfer.
6. Phone processes idempotently.
7. Watch receives latest summary later.

## Flow UF-12: Notification action

1. Local notification appears.
2. User may open, complete, snooze, reschedule, or dismiss where appropriate.
3. Action routes to the correct domain use case.
4. Repeated delivery cannot create duplicate data.
5. Dismissal does not trigger negative copy.

## Flow UF-13: Change theme

1. Open Themes.
2. Preview selected theme in all three branded presentations.
3. Preview with sound only after explicit tap.
4. Apply theme.
5. Persist selection.
6. Update visible screens without data reload.

## Flow UF-14: Export data

1. Open Settings → Data.
2. Choose export categories.
3. App generates JSON/CSV and media ZIP as appropriate.
4. Present system share sheet.
5. Do not upload export to a custom server.
