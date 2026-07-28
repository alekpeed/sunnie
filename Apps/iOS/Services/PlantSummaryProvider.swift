import Foundation
import SunnieShared

/// Builds and caches the plant slice of Today.
///
/// Today does not query plant storage — it asks for a summary. That boundary is
/// what keeps the tab from growing a dependency on the Jungle feature
/// (TECHNICAL_ARCHITECTURE.md §6).
///
/// The cache is invalidated by domain events rather than by a timer, so logging
/// care refreshes Today immediately and nothing else recomputes needlessly.
actor PlantSummaryProvider {

    private let plantRepository: any PlantRepository
    private let clock: any SunnieClock
    private let upcomingWindowDays: Int

    private var cached: PlantTodaySummary?

    init(
        plantRepository: any PlantRepository,
        clock: any SunnieClock,
        upcomingWindowDays: Int = 7
    ) {
        self.plantRepository = plantRepository
        self.clock = clock
        self.upcomingWindowDays = upcomingWindowDays
    }

    /// Returns the cached summary, recomputing only when needed.
    ///
    /// A summary generated on a previous calendar day is always stale: "due
    /// today" means something different after midnight.
    func summary() async throws -> PlantTodaySummary {
        if let cached, isFresh(cached) { return cached }
        return try await rebuild()
    }

    func invalidate() {
        cached = nil
    }

    @discardableResult
    func rebuild() async throws -> PlantTodaySummary {
        let now = clock.now
        let calendar = clock.calendar
        let timeZone = clock.timeZone

        let plants = try await plantRepository.allPlants(includingArchived: false)
        let plantsByID = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0) })
        let schedules = try await plantRepository.enabledSchedules()

        var dueToday: [DueCareTask] = []
        var waiting: [DueCareTask] = []
        var upcoming: [DueCareTask] = []

        for schedule in schedules {
            guard let dueDate = schedule.nextDueDate else { continue }
            // A schedule can outlive its plant's active status; skip rather than
            // surfacing a task for an archived plant.
            guard let plant = plantsByID[schedule.plantID] else { continue }
            guard CareScheduleCalculator.isVisible(
                schedule: schedule,
                now: now,
                upcomingWindowDays: upcomingWindowDays,
                calendar: calendar,
                timeZone: timeZone
            ) else { continue }

            let urgency = CareScheduleCalculator.urgency(
                dueDate: dueDate, now: now, calendar: calendar, timeZone: timeZone
            )
            let task = DueCareTask(
                id: schedule.id,
                plantID: plant.id,
                scheduleID: schedule.id,
                plantDisplayName: plant.displayName,
                careType: schedule.careType,
                dueDate: dueDate,
                urgency: urgency,
                daysWaiting: CareScheduleCalculator.daysWaiting(
                    dueDate: dueDate, now: now, calendar: calendar, timeZone: timeZone
                )
            )

            switch urgency {
            case .dueToday: dueToday.append(task)
            case .waiting: waiting.append(task)
            case .upcoming: upcoming.append(task)
            }
        }

        let summary = PlantTodaySummary(
            dueToday: dueToday.sorted { $0.dueDate < $1.dueDate },
            waiting: waiting.sorted { $0.dueDate < $1.dueDate },
            upcoming: upcoming.sorted { $0.dueDate < $1.dueDate },
            totalActivePlants: plants.count,
            generatedAt: now
        )

        cached = summary
        return summary
    }

    private func isFresh(_ summary: PlantTodaySummary) -> Bool {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        return calendar.isDate(summary.generatedAt, inSameDayAs: clock.now)
    }
}
