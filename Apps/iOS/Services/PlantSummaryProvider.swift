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

    /// Bumped by every `invalidate()`, so a rebuild can tell whether the world
    /// changed underneath it. See `rebuild()`.
    private var generation: Int = 0

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
        generation &+= 1
    }

    /// Rebuilds, and refuses to return an answer the store has already moved on
    /// from.
    ///
    /// Reading the jungle is several `await`s long, and an actor suspends at
    /// each one. So a rebuild that began against an empty store can finish —
    /// and cache its empty result — *after* a seed or a save has completed and
    /// invalidated everything. The late writer wins, the cache holds data that
    /// was already wrong when it was stored, and the screen that asked shows it.
    ///
    /// That is not hypothetical: it is the second half of the first-launch bug
    /// recorded in `SampleData`, where Today could publish an empty jungle over
    /// a correct one purely on timing. Fixing only the event left the race.
    ///
    /// So the generation is read before the work and checked after it. If it
    /// moved, the result is known to be stale before anyone sees it, and the
    /// only useful thing to do is compute it again against the store as it now
    /// is. Bounded, because a retry loop that cannot end is a worse failure than
    /// a slightly stale card.
    @discardableResult
    func rebuild() async throws -> PlantTodaySummary {
        let maximumAttempts = 3

        for attempt in 1...maximumAttempts {
            let generationAtStart = generation
            let summary = try await computeSummary()

            if generation == generationAtStart {
                cached = summary
                return summary
            }

            if attempt == maximumAttempts {
                // Something is invalidating faster than the jungle can be read.
                // The freshest available answer still beats an error, and it is
                // deliberately not cached — the next caller should try again.
                SunnieLog(category: .ui).debug(
                    "Plant summary invalidated during every rebuild attempt; using the last one uncached."
                )
                return summary
            }
        }

        // Unreachable: the loop returns on its final attempt.
        return try await computeSummary()
    }

    private func computeSummary() async throws -> PlantTodaySummary {
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

        return summary
    }

    private func isFresh(_ summary: PlantTodaySummary) -> Bool {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        return calendar.isDate(summary.generatedAt, inSameDayAs: clock.now)
    }
}
