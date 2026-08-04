import Foundation

/// Storage boundary for plants and their schedules.
///
/// Views never touch these; feature models reach them through use cases
/// (TECHNICAL_ARCHITECTURE.md §3).
public protocol PlantRepository: Sendable {
    func allPlants(includingArchived: Bool) async throws -> [Plant]
    func plant(id: UUID) async throws -> Plant?
    /// Resolves a scanned QR label. Nil when the token belongs to no plant —
    /// scanning a stranger's label, or one from a plant since deleted.
    func plant(qrToken: String) async throws -> Plant?
    func save(_ plant: Plant) async throws
    func archive(plantID: UUID, at date: Date) async throws
    /// Removes the plant and everything that belongs only to it: schedules, care
    /// events, observations, growth entries, coverage rows, and media.
    ///
    /// Archiving is the reversible option and the one the UI leads with. This
    /// exists because a plant added by mistake should not have to be archived
    /// forever (PLANT_CARE.md §15, "plant deleted with history").
    func delete(plantID: UUID) async throws

    /// The collection screen's data, assembled in one pass.
    ///
    /// A screen that fetched schedules and history per plant would issue a
    /// hundred queries at fifty plants. Filtering and sorting happen in
    /// `PlantCollectionFilter` on the result.
    func collectionItems(includingArchived: Bool) async throws -> [PlantCollectionItem]

    func schedules(forPlantID plantID: UUID) async throws -> [PlantCareSchedule]
    func enabledSchedules() async throws -> [PlantCareSchedule]
    func schedule(id: UUID) async throws -> PlantCareSchedule?
    func save(_ schedule: PlantCareSchedule) async throws
    func deleteSchedule(id: UUID) async throws

    func locations() async throws -> [PlantLocation]
    func save(_ location: PlantLocation) async throws
    func deleteLocation(id: UUID) async throws
}

/// Health observations and the growth timeline (PLANT_CARE.md §8, §9).
///
/// Separate from `PlantRepository` because these are records *about* a plant
/// rather than the plant itself, and because a screen that only shows growth
/// photos should not gain the ability to archive plants.
public protocol PlantHealthRepository: Sendable {
    func observations(forPlantID plantID: UUID) async throws -> [PlantHealthObservation]
    /// Unresolved observations across every plant, for "needs attention".
    func openObservations() async throws -> [PlantHealthObservation]
    func observation(id: UUID) async throws -> PlantHealthObservation?
    func save(_ observation: PlantHealthObservation) async throws
    func deleteObservation(id: UUID) async throws

    /// Newest first.
    func growthEntries(forPlantID plantID: UUID) async throws -> [GrowthEntry]
    func growthEntry(id: UUID) async throws -> GrowthEntry?
    func save(_ entry: GrowthEntry) async throws
    func deleteGrowthEntry(id: UUID) async throws

    func caretakers(includingInactive: Bool) async throws -> [Caretaker]
    func caretaker(id: UUID) async throws -> Caretaker?
    func save(_ caretaker: Caretaker) async throws

    func coverage(forTripID tripID: UUID) async throws -> [PlantTravelCoverage]
    func coverage(forPlantID plantID: UUID) async throws -> [PlantTravelCoverage]
    func save(_ coverage: PlantTravelCoverage) async throws
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
    /// Page through a long history. At 500+ records per plant, loading the lot to
    /// show the first twenty is the difference between a screen that opens and one
    /// that stalls (PLANT_CARE.md §15).
    func events(
        forPlantID plantID: UUID,
        limit: Int,
        offset: Int
    ) async throws -> [PlantCareEvent]
    func eventCount(forPlantID plantID: UUID) async throws -> Int
    func mostRecentEvent(
        forPlantID plantID: UUID,
        careType: CareType
    ) async throws -> PlantCareEvent?
    /// Every event in a window, for export.
    func allEvents(limit: Int) async throws -> [PlantCareEvent]

    /// Records a correction: `replacement` supersedes `eventID`.
    ///
    /// The log is append-only, so a correction adds a record and marks the old
    /// one superseded rather than editing it in place — which is what makes the
    /// history trustworthy after the fact (PLANT_CARE.md §7).
    ///
    /// The link lives in its own record rather than as a field on the event, so
    /// the care-event row keeps the exact shape it had in schema V1 (ADR-017).
    func replace(
        eventID: UUID,
        with replacement: PlantCareEvent
    ) async throws -> SaveOutcome<PlantCareEvent>

    /// Event IDs that have been corrected. History screens show these as
    /// superseded rather than hiding them — a correction is part of the record.
    func supersededEventIDs(forPlantID plantID: UUID) async throws -> Set<UUID>
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
