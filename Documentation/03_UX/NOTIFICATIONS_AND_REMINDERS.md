# Notifications and Adaptive Reminders

## 1. Purpose

Reminders should reduce forgotten tasks without becoming pressure. Frequency may adapt; tone may not escalate.

## 2. Initial notification categories

- Plant care
- Travel preparation
- Departure/return checklist
- Meal prep
- Packed food/snacks
- Hydration
- Wellness routine
- Journal prompt
- Meditation/breathing
- Daily puzzle
- Collection or destination event, sparingly

## 3. Scheduling model

Use local notifications for the initial product. Each scheduled reminder records:

- Stable ID
- Category
- Source entity
- Scheduled date/time
- Time-zone behavior
- Recurrence rule
- Quiet-hour rule
- User response history
- Adaptive cadence level
- Enabled state

## 4. Time-zone behavior

Each reminder category must choose one policy:

- Fixed absolute instant
- Follow current device time zone
- Follow home time zone
- Follow active destination time zone

The policy must be visible for travel-sensitive reminders.

## 5. Adaptive cadence

The system may re-offer a reminder when prior reminders are dismissed or ignored, but must obey:

- Per-category maximum frequency
- Quiet hours
- User snooze/reschedule
- No emotional escalation
- No duplicate notifications for one task
- No repeated reminders after task completion

Suggested levels:

- Level 0: disabled
- Level 1: one gentle reminder
- Level 2: one reminder plus optional later re-offer
- Level 3: user-configured regular cadence

Do not automatically move to a higher level without clear user settings or a documented rule the user can control.

## 6. Actions

Where appropriate:

- Complete
- Open
- Snooze
- Reschedule
- Skip today
- Dismiss

Notification actions call domain use cases and use stable action IDs.

## 7. Copy rules

Approved:

- “Two plants may be ready for water.”
- “Your trip checklist is waiting whenever you’re ready.”
- “Would a snack-prep reminder help before you leave?”

Prohibited:

- “You ignored your plants again.”
- “Last chance.”
- “Don’t break your streak.”
- “Sunnie is worried because you didn’t respond.”

## 8. Quiet hours

- Default quiet hours should be selected during onboarding.
- Travel mode may ask whether quiet hours follow local or home time.
- Genuine user-configured travel-document deadlines may bypass ordinary quiet rules only with explicit permission.
- Wellness, games, and collectible notifications never bypass quiet hours.

## 9. Notification center hygiene

- Cancel superseded requests.
- Use thread/category identifiers.
- Avoid badges by default or keep badge behavior user-controlled.
- Clear related notifications after completion.

## 10. Testing

Test:

- Daylight saving transitions
- Time-zone changes
- Trip start/end
- Quiet-hour boundaries
- Duplicate scheduling
- Completion from Watch and phone
- Denied permission
- App reinstall/data restore behavior
