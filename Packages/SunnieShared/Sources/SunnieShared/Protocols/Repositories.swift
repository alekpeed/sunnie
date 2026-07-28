import Foundation

/// Storage boundary for plants and their schedules.
///
/// Views never touch these; feature models reach them through use cases
/// (TECHNICAL_ARCHITECTURE.md §3).
public protocol PlantRepository: Sendable {
    func allPlants(includingArchived: Bool) async throws -> [Plant]
    func plant(id: UUID) async throws -> Plant?
    func save(_ plant: Plant) async throws
    func archive(plantID: UUID, at date: Date) async throws

    func schedules(forPlantID plantID: UUID) async throws -> [PlantCareSchedule]
    func enabledSchedules() async throws -> [PlantCareSchedule]
    func schedule(id: UUID) async throws -> PlantCareSchedule?
    func save(_ schedule: PlantCareSchedule) async throws

    func locations() async throws -> [PlantLocation]
    func save(_ location: PlantLocation) async throws
}

/// Append-only care history.
public protocol PlantCareEventRepository: Sendable {
    /// Stores the event unless one with the same `actionKey` already exists.
    ///
    /// Implementations must make this atomic. A duplicate returns
    /// `.alreadyExisted` with the original record — replaying a queued Watch
    /// action must never create a second event.
    func save(_ event: PlantCareEvent) async throws -> SaveOutcome<PlantCareEvent>

    func event(actionKey: ActionKey) async throws -> PlantCareEvent?
    func events(forPlantID plantID: UUID, limit: Int) async throws -> [PlantCareEvent]
    func mostRecentEvent(
        forPlantID plantID: UUID,
        careType: CareType
    ) async throws -> PlantCareEvent?
}

public protocol ProgressionRepository: Sendable {
    func profile() async throws -> ProgressionProfile
    func save(_ profile: ProgressionProfile) async throws

    /// Stores the event unless `deterministicKey` is already present.
    func save(_ event: ProgressionEvent) async throws -> SaveOutcome<ProgressionEvent>
    func event(deterministicKey: String) async throws -> ProgressionEvent?

    func save(_ grant: RewardGrant) async throws -> SaveOutcome<RewardGrant>
    func grants(limit: Int) async throws -> [RewardGrant]
}

public protocol PreferencesRepository: Sendable {
    func profile() async throws -> UserProfile
    func save(_ profile: UserProfile) async throws
    func preferences() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
}

/// Durable queue of actions received from the Watch that have not yet been
/// applied. Survives relaunch so a transfer delivered while the phone app was
/// terminated is not lost.
public protocol PendingWatchActionRepository: Sendable {
    func enqueue(_ action: PendingWatchAction) async throws -> SaveOutcome<PendingWatchAction>
    func unprocessedActions() async throws -> [PendingWatchAction]
    func markProcessed(actionID: UUID, at date: Date) async throws
}
