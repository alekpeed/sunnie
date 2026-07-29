import Foundation
import SunnieShared

/// Builds and caches the wellness slice of Today and of the history screen.
///
/// Same boundary as the plant provider: Today asks for a summary rather than
/// querying wellness storage, so the tab never grows a dependency on the Wellness
/// feature (TECHNICAL_ARCHITECTURE.md §6).
actor WellnessSummaryProvider {

    private let repository: any WellnessRepository
    private let clock: any SunnieClock
    /// How far back the history window reaches.
    private let windowDays: Int

    private var cached: WellnessSummary?

    init(
        repository: any WellnessRepository,
        clock: any SunnieClock,
        windowDays: Int = 30
    ) {
        self.repository = repository
        self.clock = clock
        self.windowDays = windowDays
    }

    func summary() async throws -> WellnessSummary {
        if let cached, isFresh(cached) { return cached }
        return try await rebuild()
    }

    func invalidate() {
        cached = nil
    }

    @discardableResult
    func rebuild() async throws -> WellnessSummary {
        let now = clock.now
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone

        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now

        let checkIns = try await repository.checkIns(from: start, to: now, limit: 500)
        let sessions = try await repository.sessions(from: start, to: now, limit: 500)

        let summary = WellnessSummaryBuilder.build(
            checkIns: checkIns,
            sessions: sessions,
            periodStart: start,
            periodEnd: now,
            now: now,
            calendar: calendar,
            timeZone: clock.timeZone
        )

        cached = summary
        return summary
    }

    /// A summary built on a previous calendar day is stale: "checked in today"
    /// means something different after midnight.
    private func isFresh(_ summary: WellnessSummary) -> Bool {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        return calendar.isDate(summary.generatedAt, inSameDayAs: clock.now)
    }
}

/// Turns a plan from `ReminderPlanner` into a real scheduled notification.
///
/// The planner decides *whether and when*; this only carries out the decision and
/// records it. Keeping them apart is what lets the whole cadence policy be tested
/// without UserNotifications, a permission prompt, or a device.
actor ReminderScheduler {

    private let planner: ReminderPlanner.Type
    private let repository: any ReminderRepository
    private let notifications: any NotificationScheduling
    private let preferencesRepository: any PreferencesRepository
    private let clock: any SunnieClock
    private let log = SunnieLog(category: .notifications)

    init(
        repository: any ReminderRepository,
        notifications: any NotificationScheduling,
        preferencesRepository: any PreferencesRepository,
        clock: any SunnieClock,
        planner: ReminderPlanner.Type = ReminderPlanner.self
    ) {
        self.repository = repository
        self.notifications = notifications
        self.preferencesRepository = preferencesRepository
        self.clock = clock
        self.planner = planner
    }

    /// Offers a reminder. Returns the plan so callers can see what happened
    /// without having to ask storage.
    @discardableResult
    func offer(
        category: ReminderCategory,
        sourceEntityID: UUID?,
        messageID: ContentID,
        route: String,
        desiredFireDate: Date,
        cadenceLevel: AdaptiveCadenceLevel,
        isTaskComplete: Bool = false,
        timeZonePolicy: ReminderTimeZonePolicy = .deviceTimeZone
    ) async -> ReminderPlan {
        // Without permission there is nothing to schedule, and asking for it here
        // would be exactly the kind of pressure the tone rules forbid. The user
        // grants notifications in Settings, when they choose to.
        guard await notifications.authorizationStatus() == .authorized else {
            return .suppress(.cadenceDisabled)
        }

        let preferences: UserPreferences
        do {
            preferences = try await preferencesRepository.preferences()
        } catch {
            preferences = .default
        }

        var sentToday: [Date] = []
        if let sourceEntityID {
            sentToday = (try? await repository.firedToday(
                sourceEntityID: sourceEntityID, category: category, now: clock.now
            )) ?? []
        }

        let plan = planner.plan(
            ReminderContext(
                category: category,
                cadenceLevel: cadenceLevel,
                desiredFireDate: desiredFireDate,
                now: clock.now,
                quietHours: preferences.quietHours,
                alreadySentToday: sentToday,
                isTaskComplete: isTaskComplete
            ),
            calendar: clock.calendar,
            timeZone: clock.timeZone
        )

        guard let fireDate = plan.fireDate else { return plan }

        let record = ScheduledReminderRecord(
            category: category,
            sourceEntityID: sourceEntityID,
            scheduledAt: fireDate,
            timeZonePolicy: timeZonePolicy,
            cadenceLevel: cadenceLevel,
            notificationRequestID: nil
        )

        do {
            try await notifications.schedule(
                ScheduledReminderRequest(
                    id: record.id,
                    messageID: messageID,
                    fireDate: fireDate,
                    route: route
                )
            )
            var stored = record
            stored.notificationRequestID = record.id.uuidString
            try await repository.record(stored)
        } catch {
            // A reminder failing to schedule costs a nudge, never data. Nothing
            // is surfaced to the user.
            log.debug("A reminder could not be scheduled.")
            return .suppress(.noSuitableTimeRemaining)
        }

        return plan
    }

    /// Cancels everything pending for a task.
    ///
    /// Called when a task completes, so a reminder never arrives for something
    /// already done — including when the Watch was what completed it
    /// (NOTIFICATIONS_AND_REMINDERS.md §5, §9).
    func cancelAll(for sourceEntityID: UUID) async {
        let categories = ReminderCategory.allCases
        for category in categories {
            let scheduled = (try? await repository.scheduled(category: category)) ?? []
            for record in scheduled where record.sourceEntityID == sourceEntityID {
                await notifications.cancel(reminderID: record.id)
            }
        }
        try? await repository.cancelAll(sourceEntityID: sourceEntityID)
    }

    func recordResponse(reminderID: UUID, response: ReminderResponse) async {
        try? await repository.markResponse(
            reminderID: reminderID, response: response, at: clock.now
        )
    }
}
