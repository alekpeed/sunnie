import Foundation
import Testing
@testable import SunnieShared

@Suite("Care schedule calculation")
struct CareScheduleCalculatorTests {

    @Test("Next due date lands the interval later at the preferred hour")
    func nextDueDateAnchorsToPreferredHour() throws {
        let schedule = TestFixtures.schedule(everyDays: 7, preferredHour: 9)
        let completion = TestFixtures.date(2026, 7, 15, 23, 50)

        let next = try #require(CareScheduleCalculator.nextDueDate(
            after: completion,
            schedule: schedule,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ))

        #expect(next == TestFixtures.date(2026, 7, 22, 9, 0))
    }

    @Test("A late-night completion does not drift the due time across the calendar")
    func lateCompletionDoesNotDrift() throws {
        var schedule = TestFixtures.schedule(everyDays: 3, preferredHour: 8)
        var current = TestFixtures.date(2026, 3, 1, 23, 55)

        // Three cycles, each logged just before midnight. Adding a raw interval
        // would creep the due time later each round; anchoring must not.
        for _ in 0..<3 {
            let next = try #require(CareScheduleCalculator.nextDueDate(
                after: current,
                schedule: schedule,
                calendar: TestFixtures.calendar,
                timeZone: TestFixtures.utc
            ))
            let hour = TestFixtures.calendar.component(.hour, from: next)
            #expect(hour == 8)
            schedule.nextDueDate = next
            current = next.addingTimeInterval(60 * 60 * 15)
        }
    }

    @Test("Manual schedules have no due date")
    func manualScheduleHasNoDueDate() {
        let schedule = PlantCareSchedule(
            plantID: TestFixtures.plantID,
            careType: .prune,
            recurrence: .manual
        )

        let next = CareScheduleCalculator.nextDueDate(
            after: TestFixtures.date(2026, 7, 15),
            schedule: schedule,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        )

        #expect(next == nil)
    }

    @Test("Winter stretches the interval, summer shortens it")
    func seasonalModifierAdjustsInterval() throws {
        let seasonal = SeasonalModifier(
            springMultiplier: 1,
            summerMultiplier: 0.5,
            autumnMultiplier: 1,
            winterMultiplier: 2
        )
        let schedule = TestFixtures.schedule(
            everyDays: 10, preferredHour: 9, seasonal: seasonal
        )

        let summer = try #require(CareScheduleCalculator.nextDueDate(
            after: TestFixtures.date(2026, 7, 1, 9),
            schedule: schedule,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ))
        #expect(summer == TestFixtures.date(2026, 7, 6, 9))

        let winter = try #require(CareScheduleCalculator.nextDueDate(
            after: TestFixtures.date(2026, 1, 1, 9),
            schedule: schedule,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ))
        #expect(winter == TestFixtures.date(2026, 1, 21, 9))
    }

    @Test("A zero multiplier cannot make a task perpetually due")
    func zeroMultiplierClampsToOneDay() throws {
        let seasonal = SeasonalModifier(
            springMultiplier: 0, summerMultiplier: 0,
            autumnMultiplier: 0, winterMultiplier: 0
        )
        let schedule = TestFixtures.schedule(
            everyDays: 7, preferredHour: 9, seasonal: seasonal
        )

        let next = try #require(CareScheduleCalculator.nextDueDate(
            after: TestFixtures.date(2026, 7, 1, 9),
            schedule: schedule,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ))

        #expect(next == TestFixtures.date(2026, 7, 2, 9))
    }

    @Test("Applying a completion updates both last-completed and next-due")
    func applyingCompletionUpdatesSchedule() throws {
        let schedule = TestFixtures.schedule(everyDays: 5, preferredHour: 7)
        let completedAt = TestFixtures.date(2026, 6, 10, 18, 30)

        let updated = CareScheduleCalculator.applyingCompletion(
            to: schedule,
            completedAt: completedAt,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        )

        #expect(updated.lastCompletedAt == completedAt)
        #expect(updated.nextDueDate == TestFixtures.date(2026, 6, 15, 7))
        #expect(updated.id == schedule.id)
    }

    @Test(
        "Urgency classifies by calendar day, not elapsed hours",
        arguments: [
            (TestFixtures.date(2026, 7, 14, 9), DueUrgency.waiting),
            (TestFixtures.date(2026, 7, 15, 1), DueUrgency.dueToday),
            (TestFixtures.date(2026, 7, 15, 23), DueUrgency.dueToday),
            (TestFixtures.date(2026, 7, 16, 0), DueUrgency.upcoming)
        ]
    )
    func urgencyByCalendarDay(dueDate: Date, expected: DueUrgency) {
        let now = TestFixtures.date(2026, 7, 15, 12)

        let urgency = CareScheduleCalculator.urgency(
            dueDate: dueDate,
            now: now,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        )

        #expect(urgency == expected)
    }

    @Test("Days waiting counts whole calendar days and never goes negative")
    func daysWaitingCountsCalendarDays() {
        let now = TestFixtures.date(2026, 7, 15, 12)

        #expect(CareScheduleCalculator.daysWaiting(
            dueDate: TestFixtures.date(2026, 7, 12, 9),
            now: now,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ) == 3)

        #expect(CareScheduleCalculator.daysWaiting(
            dueDate: TestFixtures.date(2026, 7, 20, 9),
            now: now,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ) == 0)
    }

    @Test("Disabled schedules never surface")
    func disabledScheduleIsNotVisible() {
        let schedule = TestFixtures.schedule(
            isEnabled: false,
            nextDueDate: TestFixtures.date(2026, 7, 15, 9)
        )

        #expect(!CareScheduleCalculator.isVisible(
            schedule: schedule,
            now: TestFixtures.date(2026, 7, 15, 12),
            upcomingWindowDays: 7,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        ))
    }

    @Test("Repeating water the same day is implausible; a week later is fine")
    func plausibleRepeatWindow() {
        let watered = TestFixtures.date(2026, 7, 15, 9)

        #expect(!CareScheduleCalculator.isPlausibleRepeat(
            careType: .water,
            lastPerformedAt: watered,
            candidate: watered.addingTimeInterval(60 * 5)
        ))

        #expect(CareScheduleCalculator.isPlausibleRepeat(
            careType: .water,
            lastPerformedAt: watered,
            candidate: TestFixtures.date(2026, 7, 22, 9)
        ))
    }

    @Test("First-ever care is always plausible")
    func firstCareIsPlausible() {
        #expect(CareScheduleCalculator.isPlausibleRepeat(
            careType: .water,
            lastPerformedAt: nil,
            candidate: TestFixtures.date(2026, 7, 15, 9)
        ))
    }

    @Test("A backdated correction stays eligible rather than counting as a repeat")
    func backdatedEntryIsPlausible() {
        let watered = TestFixtures.date(2026, 7, 15, 9)

        #expect(CareScheduleCalculator.isPlausibleRepeat(
            careType: .water,
            lastPerformedAt: watered,
            candidate: watered.addingTimeInterval(-60 * 60 * 2)
        ))
    }
}
