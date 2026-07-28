import Foundation

/// How urgent a due task is. Note there is no "critical" or "alarm" level:
/// overdue plant care uses neutral attention treatment, never red-alert language
/// (VISUAL_DESIGN_SYSTEM.md §3).
public enum DueUrgency: String, Hashable, Sendable, Codable, CaseIterable {
    case upcoming
    case dueToday
    case waiting
}

/// One actionable care task, already resolved for display.
public struct DueCareTask: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let plantID: UUID
    public let scheduleID: UUID
    public let plantDisplayName: String
    public let careType: CareType
    public let dueDate: Date
    public let urgency: DueUrgency
    /// Whole days past the due date. Zero when due today or upcoming. Shown as
    /// neutral context ("waiting since Tuesday"), never as a reprimand.
    public let daysWaiting: Int

    public init(
        id: UUID,
        plantID: UUID,
        scheduleID: UUID,
        plantDisplayName: String,
        careType: CareType,
        dueDate: Date,
        urgency: DueUrgency,
        daysWaiting: Int
    ) {
        self.id = id
        self.plantID = plantID
        self.scheduleID = scheduleID
        self.plantDisplayName = plantDisplayName
        self.careType = careType
        self.dueDate = dueDate
        self.urgency = urgency
        self.daysWaiting = daysWaiting
    }
}

/// The plant slice of Today. Computed by a summary provider and cached; Today
/// never queries plant storage itself (TECHNICAL_ARCHITECTURE.md §6).
public struct PlantTodaySummary: Hashable, Sendable {
    public let dueToday: [DueCareTask]
    public let waiting: [DueCareTask]
    public let upcoming: [DueCareTask]
    public let totalActivePlants: Int
    public let generatedAt: Date

    public init(
        dueToday: [DueCareTask],
        waiting: [DueCareTask],
        upcoming: [DueCareTask],
        totalActivePlants: Int,
        generatedAt: Date
    ) {
        self.dueToday = dueToday
        self.waiting = waiting
        self.upcoming = upcoming
        self.totalActivePlants = totalActivePlants
        self.generatedAt = generatedAt
    }

    public static func empty(generatedAt: Date) -> PlantTodaySummary {
        PlantTodaySummary(
            dueToday: [], waiting: [], upcoming: [],
            totalActivePlants: 0, generatedAt: generatedAt
        )
    }

    /// Tasks needing attention now, waiting-longest first so the card leads with
    /// what has been patient the longest.
    public var actionableTasks: [DueCareTask] {
        (waiting + dueToday).sorted { $0.dueDate < $1.dueDate }
    }

    public var hasAnythingToDo: Bool { !actionableTasks.isEmpty }
}
