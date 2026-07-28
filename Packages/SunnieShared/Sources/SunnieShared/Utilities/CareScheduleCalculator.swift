import Foundation

/// Computes when care is next due and how a due task should be presented.
///
/// The app schedules reminders; it does not claim biological certainty. Nothing
/// here decides that a plant *must* be watered — only that a scheduled interval
/// has elapsed (PLANT_CARE.md §4).
public enum CareScheduleCalculator {

    /// Next due date after a completion.
    ///
    /// Anchors to the schedule's preferred hour in the user's time zone rather
    /// than adding a raw interval, so a task logged at 23:50 does not become due
    /// at 23:50 several days later and drift across the calendar. Returns nil for
    /// manual schedules, which have no due date by definition.
    public static func nextDueDate(
        after completion: Date,
        schedule: PlantCareSchedule,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date? {
        guard let baseInterval = schedule.recurrence.intervalDays, baseInterval > 0 else {
            return nil
        }

        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone

        let month = zonedCalendar.component(.month, from: completion)
        let season = Season.from(month: month)
        let multiplier = schedule.seasonalModifier.multiplier(for: season)

        // A seasonal multiplier must never collapse an interval to zero, which
        // would make a task perpetually due.
        let adjusted = max(1, Int((Double(baseInterval) * multiplier).rounded()))

        guard let shifted = zonedCalendar.date(
            byAdding: .day, value: adjusted, to: completion
        ) else {
            return nil
        }

        var components = zonedCalendar.dateComponents(
            [.year, .month, .day], from: shifted
        )
        components.hour = min(max(schedule.preferredHour, 0), 23)
        components.minute = 0
        components.second = 0
        components.timeZone = timeZone

        return zonedCalendar.date(from: components) ?? shifted
    }

    /// Applies a completion to a schedule, returning the updated value.
    ///
    /// Pure: takes and returns values, touches no storage. The use case persists
    /// the result inside the same transaction as the care event.
    public static func applyingCompletion(
        to schedule: PlantCareSchedule,
        completedAt: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> PlantCareSchedule {
        var updated = schedule
        updated.lastCompletedAt = completedAt
        updated.nextDueDate = nextDueDate(
            after: completedAt,
            schedule: schedule,
            calendar: calendar,
            timeZone: timeZone
        )
        return updated
    }

    /// Classifies a due date relative to now.
    ///
    /// A past-due task is `.waiting`, not "overdue" or "late". The vocabulary is
    /// deliberate: the state is that the task is still there, not that the user
    /// failed (TONE_COPY_AND_BEHAVIOR.md, missed task).
    public static func urgency(
        dueDate: Date,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> DueUrgency {
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone

        let dueDay = zonedCalendar.startOfDay(for: dueDate)
        let today = zonedCalendar.startOfDay(for: now)

        if dueDay < today { return .waiting }
        if dueDay == today { return .dueToday }
        return .upcoming
    }

    /// Whole days a task has been waiting past its due date. Zero when not past due.
    public static func daysWaiting(
        dueDate: Date,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Int {
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone

        let dueDay = zonedCalendar.startOfDay(for: dueDate)
        let today = zonedCalendar.startOfDay(for: now)
        guard dueDay < today else { return 0 }

        return zonedCalendar.dateComponents([.day], from: dueDay, to: today).day ?? 0
    }

    /// Whether a schedule should surface within a lookahead window.
    public static func isVisible(
        schedule: PlantCareSchedule,
        now: Date,
        upcomingWindowDays: Int,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        guard schedule.isEnabled, let dueDate = schedule.nextDueDate else { return false }

        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone

        guard let horizon = zonedCalendar.date(
            byAdding: .day, value: upcomingWindowDays, to: zonedCalendar.startOfDay(for: now)
        ) else {
            return false
        }
        return dueDate < horizon
    }

    /// Whether logging this care type again is plausible yet.
    ///
    /// Used only to decide whether a reward is granted. The care event itself is
    /// always recorded — the user's record of what they did is never refused
    /// (PLANT_CARE.md §13).
    public static func isPlausibleRepeat(
        careType: CareType,
        lastPerformedAt: Date?,
        candidate: Date
    ) -> Bool {
        guard let lastPerformedAt else { return true }
        let elapsed = candidate.timeIntervalSince(lastPerformedAt)
        // A backdated entry is a correction, not a repeat, so it stays eligible.
        guard elapsed >= 0 else { return true }
        return elapsed >= careType.minimumPlausibleRepeat
    }
}
