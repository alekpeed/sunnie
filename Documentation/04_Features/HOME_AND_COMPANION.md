# Feature Specification — Today and Sunnie Companion

## 1. Purpose

Today is the app’s daily command center. Sunnie makes the information feel personal, but the screen must remain fast and useful.

## 2. Today summary providers

Each feature publishes a compact read model:

- `TravelTodaySummary`
- `PlantTodaySummary`
- `WellnessTodaySummary`
- `MealTodaySummary`
- `DailyPuzzleSummary`
- `ProgressionTodaySummary`

Today does not directly query every feature’s persistence models. It requests summaries through providers/use cases.

## 3. Default presentation

### Header

- App title or branded day presentation
- Current date
- Optional small sync indicator only when needed
- Settings/notifications access

### Sunnie region

- Canonical Sunnie asset
- Greeting appropriate to time and context
- One affirmation
- Optional small contextual prop

### Cards

Travel, Jungle, Wellness, Meals, Puzzle, and Progression.

## 4. Prioritization rules

Cards may reorder only according to explicit contextual rules:

1. Real departure/return tasks due soon
2. Plant care due or overdue
3. User-selected wellness routine
4. Meal prep with a real time dependency
5. Daily puzzle
6. General progression

The app must not manufacture urgency to move cards upward.

## 5. Sunnie message selection

Inputs:

- Time phase
- Active theme
- Active trip
- Recent completed action
- Current feature
- Recent messages
- Optional mood/check-in state
- Nickname eligibility

Rules:

- Do not infer a mood from activity data.
- Avoid repeating the same message within a configurable recent window.
- Sensitive context uses neutral copy and disables nickname use.
- One primary Sunnie message per Today load; completion reactions may be separate.

## 6. Affirmations

Affirmations are content-defined and tagged by:

- General
- Travel
- Rest
- Confidence
- Calm
- Growth
- Gratitude

They should not make unsupported health claims or imply that positivity alone solves problems.

## 7. Quick actions

Initial quick actions:

- Log plant care
- Check in
- New journal entry
- Start breathing
- Add meal/prep task
- Open trip checklist

Quick actions are user-customizable after the default system is validated.

## 8. Completion behavior

When a card action completes:

- Update local state immediately.
- Show a small visual confirmation.
- Use soft haptic if enabled.
- Show a brief Sunnie reaction.
- Do not display a full-screen celebration for routine actions.
- Queue progression and sync work.

## 9. Offline behavior

Today loads from local summaries. Weather or other network-derived values may show last-updated time and a graceful unavailable state. Core actions remain usable.

## 10. Performance target

- First meaningful local content should appear without waiting for cloud sync.
- Avoid loading full photo assets for dashboard thumbnails.
- Cache derived summaries and invalidate them through domain events.

## 11. Acceptance highlights

- User understands current priorities in under 15 seconds.
- Today remains coherent with no trip, no plants, or denied permissions.
- Theme changes do not reload feature data.
- A completed action updates its card immediately.
