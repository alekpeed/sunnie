import Foundation

/// Decides whether and when a reminder fires.
///
/// The whole point of this type is that it is *only* allowed to say "not now" or
/// "later". It cannot make a reminder louder, more frequent than the user asked,
/// or more insistent on repetition — `ReminderPlan` gives it no way to express
/// any of those (NOTIFICATIONS_AND_REMINDERS.md §5).
///
/// Checks run cheapest-and-most-absolute first, so a completed task or a disabled
/// category short-circuits before any date arithmetic happens.
public enum ReminderPlanner {

    public static func plan(
        _ context: ReminderContext,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> ReminderPlan {
        var zoned = calendar
        zoned.timeZone = timeZone

        // 1. The user turned this off.
        if context.cadenceLevel == .disabled {
            return .suppress(.cadenceDisabled)
        }

        // 2. Never remind about something already done. This covers completion
        //    from the Watch as well as the phone, because both write the same
        //    task state (NOTIFICATIONS_AND_REMINDERS.md §5).
        if context.isTaskComplete || context.lastResponse == .completed {
            return .suppress(.taskAlreadyComplete)
        }

        // 3. "Skip today" holds until the next calendar day, not for a rolling
        //    24 hours — the user meant today, not the next twenty-four hours.
        if let skippedFrom = context.skippedForDayStartingAt,
           zoned.isDate(skippedFrom, inSameDayAs: context.now) {
            return .suppress(.skippedForToday)
        }

        // 4. Per-task allowance for the chosen level, then the category ceiling
        //    that no level can raise.
        let sentToday = context.alreadySentToday.filter {
            zoned.isDate($0, inSameDayAs: context.now)
        }
        if sentToday.count >= context.cadenceLevel.dailyAllowance {
            return .suppress(.dailyAllowanceReached)
        }
        if sentToday.count >= context.category.dailyMaximum {
            return .suppress(.categoryMaximumReached)
        }

        // 5. Earliest moment we are allowed to fire, from every constraint that
        //    can only push later.
        var earliest = max(context.desiredFireDate, context.now)

        if let snoozedUntil = context.snoozedUntil, snoozedUntil > earliest {
            earliest = snoozedUntil
        }

        if let lastSent = sentToday.max() {
            let nextAllowed = lastSent.addingTimeInterval(
                context.category.minimumReOfferInterval
            )
            if nextAllowed > earliest { earliest = nextAllowed }
        }

        // 6. Quiet hours push the reminder to when they end, rather than
        //    cancelling it — the task is still there, it can simply wait.
        let candidate = respectingQuietHours(
            earliest,
            context: context,
            calendar: zoned,
            timeZone: timeZone
        )

        // 7. A reminder for a moment that has fully passed is dropped rather
        //    than fired late and out of context.
        guard candidate >= context.now else {
            return .suppress(.noSuitableTimeRemaining)
        }

        // 8. Re-offers must not crowd the original.
        if let lastSent = sentToday.max(),
           candidate.timeIntervalSince(lastSent) < context.category.minimumReOfferInterval {
            return .suppress(.tooSoonAfterLastReminder)
        }

        return .schedule(at: candidate)
    }

    /// Moves a fire date out of quiet hours, or leaves it if the category is
    /// permitted to sound and the user has explicitly allowed it.
    ///
    /// Both conditions are required. A category that may never bypass ignores the
    /// permission entirely.
    static func respectingQuietHours(
        _ date: Date,
        context: ReminderContext,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date {
        guard context.quietHours.isEnabled else { return date }

        let mayBypass = context.category.mayEverBypassQuietHours
            && context.userGrantedQuietHoursBypass
        if mayBypass { return date }

        let hour = calendar.component(.hour, from: date)
        guard context.quietHours.contains(hour: hour) else { return date }

        return endOfQuietHours(after: date, quietHours: context.quietHours, calendar: calendar)
            ?? date
    }

    /// The first moment at or after `date` that falls outside quiet hours.
    ///
    /// Quiet hours may wrap past midnight, so this cannot be a simple comparison
    /// against `endHour` on the same day.
    static func endOfQuietHours(
        after date: Date,
        quietHours: QuietHours,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = quietHours.endHour
        components.minute = 0
        components.second = 0

        guard let sameDayEnd = calendar.date(from: components) else { return nil }
        if sameDayEnd > date { return sameDayEnd }

        // The window ends tomorrow morning.
        return calendar.date(byAdding: .day, value: 1, to: sameDayEnd)
    }
}
