# Feature Specification — HealthKit, Apple Watch, Widgets, and App Intents

## 1. Principles

- Every integration is optional.
- Request minimum necessary permission.
- The iPhone app remains functional without HealthKit or Watch.
- Health data never produces guilt or diagnosis.
- The iPhone is the primary source of truth for Sunnie Days-owned data.

## 2. HealthKit read candidates

Individually permissioned:

- Step count
- Sleep analysis
- Heart rate
- Resting heart rate
- Workouts
- Active energy
- Stand-related data where useful and available
- Mindful sessions
- Dietary water, if hydration logging is enabled

Do not request every type merely because it exists.

## 3. HealthKit write candidates

- Mindful session after meditation
- Mindful session after qualifying breathing exercise
- Dietary water after explicit hydration log, if enabled

Write only after clear user action and successful session completion.

## 4. Health presentation

Examples:

- “You recorded 12 mindful minutes today.”
- “Sleep data is available from Health.”

Avoid:

- Diagnosing anxiety from heart rate
- Rating the user’s health
- Prescriptive medical advice
- Presenting incomplete data as complete

## 5. Watch app navigation

Suggested compact destinations:

- Today
- Check In
- Plants
- Calm
- Travel

## 6. Watch features

### Today

- Affirmation
- Next important task
- Trip/local time summary
- Plant due count

### Check In

- Mood
- Optional energy
- Save with stable action ID

### Plants

- Selected due tasks
- Quick completion
- Open on iPhone for detail

### Calm

- Breathing timer
- Meditation timer
- Haptic pacing option

### Travel

- Trip countdown
- Local/home time
- Selected checklist
- Meal/hydration reminder

## 7. WatchConnectivity policy

Use:

- `sendMessage` for active reachable interactions requiring immediate response
- `updateApplicationContext` for latest replaceable summary state
- `transferUserInfo` for queued background actions
- `transferFile` only for appropriate larger files

Every Watch-originated action includes:

- Stable action ID
- Type
- Timestamp
- Source device
- Payload version

Phone processing is idempotent.

## 8. Widgets

Potential widgets:

- Today summary
- Plant tasks
- Trip countdown/local time
- Affirmation
- Daily puzzle
- Calm shortcut

Widgets expose only privacy-appropriate content and respect lock-screen sensitivity.

## 9. App Intents

Initial useful intents:

- Log plant care
- Start check-in
- Start breathing
- Open current trip
- Add journal entry
- Show daily puzzle
- Log water

App Intents call the same use cases as the app UI.

## 10. Complications and Smart Stack

Where supported:

- Trip countdown
- Plant due count
- Calm shortcut
- Affirmation

Avoid frequent refreshes that waste battery.

## 11. Physical-device testing

Queued WatchConnectivity transfers must be tested on paired physical devices. Simulator behavior is not sufficient for all transfer methods.

## 12. Permission changes

- Handle authorization denial and revocation.
- Recalculate summaries without crashing.
- Keep last derived display clearly marked if stale, or remove it.
- Provide settings instructions without repeated prompting.
