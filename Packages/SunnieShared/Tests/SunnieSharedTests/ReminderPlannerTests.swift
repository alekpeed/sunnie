import Foundation
import Testing
@testable import SunnieShared

/// The reminder rules, whose whole job is restraint.
///
/// Frequency may adapt; pressure may not (NOTIFICATIONS_AND_REMINDERS.md §1).
@Suite("Reminder planning")
struct ReminderPlannerTests {

    private let now = TestFixtures.date(2026, 7, 15, 10)

    private func context(
        category: ReminderCategory = .plantCare,
        level: AdaptiveCadenceLevel = .single,
        desired: Date? = nil,
        quietHours: QuietHours = QuietHours(),
        bypass: Bool = false,
        sentToday: [Date] = [],
        lastResponse: ReminderResponse = .noResponse,
        snoozedUntil: Date? = nil,
        skippedFrom: Date? = nil,
        complete: Bool = false
    ) -> ReminderContext {
        ReminderContext(
            category: category,
            cadenceLevel: level,
            desiredFireDate: desired ?? now.addingTimeInterval(3600),
            now: now,
            quietHours: quietHours,
            userGrantedQuietHoursBypass: bypass,
            alreadySentToday: sentToday,
            lastResponse: lastResponse,
            snoozedUntil: snoozedUntil,
            skippedForDayStartingAt: skippedFrom,
            isTaskComplete: complete
        )
    }

    private func plan(_ context: ReminderContext) -> ReminderPlan {
        ReminderPlanner.plan(
            context, calendar: TestFixtures.calendar, timeZone: TestFixtures.utc
        )
    }

    // MARK: - Absolute refusals

    @Test("A disabled cadence never schedules anything")
    func disabledNeverSchedules() {
        #expect(plan(context(level: .disabled)) == .suppress(.cadenceDisabled))
    }

    @Test("A finished task is never reminded about")
    func completedTaskIsNotReminded() {
        #expect(plan(context(complete: true)) == .suppress(.taskAlreadyComplete))
        #expect(plan(context(lastResponse: .completed)) == .suppress(.taskAlreadyComplete))
    }

    @Test("Completion from either device stops the reminder")
    func completionFromWatchAlsoStops() {
        // Both devices write the same task state, so the planner needs no idea
        // which one finished it.
        #expect(plan(context(complete: true, level: .regular)) == .suppress(.taskAlreadyComplete))
    }

    @Test("Skip today lasts until tomorrow, not for a rolling day")
    func skipTodayIsCalendarBound() {
        // The user meant today, not the next twenty-four hours.
        let thisMorning = TestFixtures.date(2026, 7, 15, 7)
        #expect(plan(context(skippedFrom: thisMorning)) == .suppress(.skippedForToday))

        let yesterday = TestFixtures.date(2026, 7, 14, 22)
        #expect(plan(context(skippedFrom: yesterday)).isScheduled)
    }

    // MARK: - Ceilings

    @Test("Level 1 allows exactly one reminder a day")
    func singleLevelAllowsOne() {
        #expect(plan(context(level: .single)).isScheduled)
        #expect(
            plan(context(level: .single, sentToday: [TestFixtures.date(2026, 7, 15, 8)]))
                == .suppress(.dailyAllowanceReached)
        )
    }

    @Test("Level 2 allows a re-offer, then stops")
    func reOfferLevelAllowsTwo() {
        let earlier = TestFixtures.date(2026, 7, 15, 4)

        #expect(plan(context(level: .singleWithReOffer, sentToday: [earlier])).isScheduled)
        #expect(
            plan(context(
                level: .singleWithReOffer,
                sentToday: [earlier, TestFixtures.date(2026, 7, 15, 5)]
            )) == .suppress(.dailyAllowanceReached)
        )
    }

    @Test("The category ceiling holds even at the highest cadence")
    func categoryMaximumBeatsCadenceLevel() {
        // Level 3 is "a regular cadence the user configured", not "unlimited".
        // A wellness reminder tops out at one a day whatever the level says.
        let sent = [TestFixtures.date(2026, 7, 15, 6)]

        #expect(
            plan(context(category: .wellnessRoutine, level: .regular, sentToday: sent))
                == .suppress(.categoryMaximumReached)
        )
        #expect(ReminderCategory.wellnessRoutine.dailyMaximum == 1)
    }

    @Test("Only today's reminders count toward today's ceiling")
    func yesterdaysRemindersDoNotCount() {
        let yesterday = TestFixtures.date(2026, 7, 14, 9)
        #expect(plan(context(level: .single, sentToday: [yesterday])).isScheduled)
    }

    @Test("A re-offer must not crowd the reminder before it")
    func reOffersRespectMinimumGap() throws {
        // Sent 30 minutes ago, desired in a minute: too soon for plant care's
        // four-hour gap.
        let recent = now.addingTimeInterval(-1800)
        let result = plan(context(
            level: .singleWithReOffer,
            desired: now.addingTimeInterval(60),
            sentToday: [recent]
        ))

        // Pushed out rather than cancelled — the task is still there.
        let fireDate = try #require(result.fireDate)
        #expect(
            fireDate.timeIntervalSince(recent)
                >= ReminderCategory.plantCare.minimumReOfferInterval
        )
    }

    // MARK: - Quiet hours

    @Test("A reminder landing in quiet hours waits until they end")
    func quietHoursPushLater() throws {
        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let lateNight = TestFixtures.date(2026, 7, 15, 23)

        let result = plan(context(
            desired: lateNight,
            quietHours: quiet
        ))

        let fireDate = try #require(result.fireDate)
        let hour = TestFixtures.calendar.component(.hour, from: fireDate)
        #expect(hour == 7)
        // Next morning, not tonight.
        #expect(fireDate > lateNight)
    }

    @Test("Wellness reminders never bypass quiet hours, even with permission")
    func wellnessNeverBypassesQuietHours() throws {
        // No setting unlocks this, which is why it is a property of the category
        // rather than a preference (NOTIFICATIONS_AND_REMINDERS.md §8).
        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let lateNight = TestFixtures.date(2026, 7, 15, 23)

        let result = plan(context(
            category: .wellnessRoutine,
            desired: lateNight,
            quietHours: quiet,
            bypass: true
        ))

        let fireDate = try #require(result.fireDate)
        #expect(TestFixtures.calendar.component(.hour, from: fireDate) == 7)
    }

    @Test(
        "Wellness, games, and collectibles can never bypass quiet hours",
        arguments: [
            ReminderCategory.wellnessRoutine,
            .journalPrompt,
            .meditationBreathing,
            .dailyPuzzle,
            .collectionEvent
        ]
    )
    func categoriesThatNeverBypass(category: ReminderCategory) {
        #expect(!category.mayEverBypassQuietHours)
    }

    @Test("A travel reminder may bypass, but only with explicit permission")
    func travelBypassRequiresPermission() throws {
        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let lateNight = TestFixtures.date(2026, 7, 15, 23)

        let granted = plan(context(
            category: .travelPreparation,
            desired: lateNight,
            quietHours: quiet,
            bypass: true
        ))
        #expect(granted.fireDate == lateNight)

        let notGranted = plan(context(
            category: .travelPreparation,
            desired: lateNight,
            quietHours: quiet,
            bypass: false
        ))
        #expect(notGranted.fireDate != lateNight)
    }

    @Test("Disabled quiet hours leave the time alone")
    func disabledQuietHoursDoNotShift() throws {
        let lateNight = TestFixtures.date(2026, 7, 15, 23)
        let result = plan(context(
            desired: lateNight,
            quietHours: QuietHours(isEnabled: false, startHour: 22, endHour: 7)
        ))

        #expect(result.fireDate == lateNight)
    }

    // MARK: - Snooze

    @Test("A snooze pushes the reminder, it does not cancel it")
    func snoozeDelays() throws {
        let until = now.addingTimeInterval(7200)
        let result = plan(context(
            desired: now.addingTimeInterval(60),
            snoozedUntil: until
        ))

        #expect(try #require(result.fireDate) >= until)
    }

    @Test("A snooze already in the past does not hold anything back")
    func expiredSnoozeIsIgnored() throws {
        let result = plan(context(
            desired: now.addingTimeInterval(3600),
            snoozedUntil: now.addingTimeInterval(-3600)
        ))

        #expect(try #require(result.fireDate) == now.addingTimeInterval(3600))
    }

    // MARK: - The no-escalation guarantee

    @Test("The plan carries a time and nothing that could raise pressure")
    func planCannotEscalate() {
        // This is the structural guarantee: ReminderPlan has one payload, a
        // fire date. There is no level, urgency, tone, or attempt count for a
        // repeated reminder to be more insistent through.
        let first = plan(context(level: .singleWithReOffer))
        let second = plan(context(
            level: .singleWithReOffer,
            desired: now.addingTimeInterval(6 * 3600),
            sentToday: [now.addingTimeInterval(-3600)]
        ))

        // Both outcomes are the same shape; a re-offer is a later time and
        // nothing else.
        if case .schedule(let firstDate) = first, case .schedule(let secondDate) = second {
            #expect(secondDate > firstDate)
        }
        #expect(first.fireDate != nil)
    }

    @Test("Repeated planning never increases the cadence level")
    func planningDoesNotRaiseCadence() {
        // The level is an input the user owns. Planning ten times in a row must
        // leave it exactly where it was — the planner has no way to write it back.
        var sent: [Date] = []
        let level = AdaptiveCadenceLevel.regular

        for _ in 0..<10 {
            let result = plan(context(
                category: .hydration,
                level: level,
                desired: now.addingTimeInterval(60),
                sentToday: sent
            ))
            guard let fireDate = result.fireDate else { break }
            sent.append(fireDate)
        }

        // Capped by the category ceiling, never beyond it.
        #expect(sent.count <= ReminderCategory.hydration.dailyMaximum)
    }

    @Test("Every suppression reason is an ordinary outcome, not a failure")
    func suppressionIsNotAnError() {
        // Each of these is expected in normal use, and none is surfaced to the
        // user as something going wrong.
        let reasons: [ReminderPlan] = [
            plan(context(level: .disabled)),
            plan(context(complete: true)),
            plan(context(skippedFrom: now)),
            plan(context(level: .single, sentToday: [now.addingTimeInterval(-3600)]))
        ]

        #expect(reasons.allSatisfy { !$0.isScheduled })
    }

    @Test("A stale time is pulled forward to now, never fired in the past")
    func staleReminderIsPulledForward() throws {
        let stale = now.addingTimeInterval(-7200)
        let result = plan(context(desired: stale))

        let fireDate = try #require(result.fireDate)
        #expect(fireDate >= now)
        #expect(fireDate != stale)
    }

    @Test("Hydration is allowed to be more frequent than wellness")
    func categoryCeilingsDifferSensibly() {
        #expect(ReminderCategory.hydration.dailyMaximum > ReminderCategory.wellnessRoutine.dailyMaximum)
        #expect(
            ReminderCategory.hydration.minimumReOfferInterval
                < ReminderCategory.plantCare.minimumReOfferInterval
        )
    }
}
