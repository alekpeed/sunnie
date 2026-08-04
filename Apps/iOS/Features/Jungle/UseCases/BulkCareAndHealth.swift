import Foundation
import SunnieShared

/// Logs care for several plants at once (PLANT_CARE.md §6).
///
/// Each plant goes through `LogPlantCare` individually rather than through a
/// bulk-specific path, which is what makes bulk care idempotent, correctly
/// scheduled, and progression-eligible for free. It also means a bulk action and
/// fifteen separate taps produce identical records.
///
/// **Failures are per plant.** Fifteen watered and one failed is fifteen
/// watered; rolling the others back to keep the operation atomic would destroy
/// real work to preserve a tidy abstraction (PLANT_CARE.md §15).
struct LogBulkCare: Sendable {

    private let logCare: LogPlantCare
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(logCare: LogPlantCare, clock: any SunnieClock) {
        self.logCare = logCare
        self.clock = clock
    }

    func callAsFunction(
        careType: CareType,
        items: [BulkCareItem],
        performedAt: Date? = nil
    ) async -> BulkCareResult {
        // One timestamp for the whole action rather than one per plant. Watering
        // six plants is a single act, and it should read as one moment in the
        // history rather than six timestamps a few milliseconds apart.
        let timestamp = performedAt ?? clock.now
        var outcomes: [UUID: BulkCareResult.Outcome] = [:]

        for item in items where item.isIncluded {
            do {
                let result = try await logCare(
                    plantID: item.plantID,
                    careType: item.careTypeOverride ?? careType,
                    performedAt: timestamp,
                    note: item.note
                )
                outcomes[item.plantID] = result.wasNewlyRecorded
                    ? .recorded
                    : .alreadyRecorded
            } catch {
                // The message is not surfaced verbatim; it identifies which plant
                // to offer a retry for.
                outcomes[item.plantID] = .failed(String(describing: type(of: error)))
                log.error("One plant in a bulk care action could not be recorded.")
            }
        }

        return BulkCareResult(outcomes: outcomes)
    }
}

/// Health observations and the growth timeline (PLANT_CARE.md §8, §9).
///
/// The app records what the user noticed. It does not diagnose, does not infer a
/// cause, and does not decide that something is resolved — every interpretive
/// field is written by the user and only by the user.
struct ManagePlantHealth: Sendable {

    private let repository: any PlantHealthRepository
    private let progressionEngine: ProgressionEngine
    private let clock: any SunnieClock
    private let deviceID: DeviceID

    init(
        repository: any PlantHealthRepository,
        progressionEngine: ProgressionEngine,
        clock: any SunnieClock,
        deviceID: DeviceID
    ) {
        self.repository = repository
        self.progressionEngine = progressionEngine
        self.clock = clock
        self.deviceID = deviceID
    }

    // MARK: - Observations

    func newObservation(plantID: UUID) -> PlantHealthObservation {
        let now = clock.now
        return PlantHealthObservation(
            plantID: plantID,
            observedAt: now,
            category: .other,
            sourceDeviceID: deviceID,
            createdAt: now,
            modifiedAt: now
        )
    }

    func observations(forPlantID plantID: UUID) async throws -> [PlantHealthObservation] {
        try await repository.observations(forPlantID: plantID)
    }

    func openObservations() async throws -> [PlantHealthObservation] {
        try await repository.openObservations()
    }

    @discardableResult
    func save(_ observation: PlantHealthObservation) async throws -> PlantHealthObservation {
        var cleaned = observation
        cleaned.notes = tidy(observation.notes)
        cleaned.suspectedCause = tidy(observation.suspectedCause)
        cleaned.treatment = tidy(observation.treatment)
        cleaned.modifiedAt = clock.now

        let wasResolved = try await repository
            .observation(id: observation.id)?.isResolved ?? false

        try await repository.save(cleaned)

        // "Health issue resolved" is an eligible progression event
        // (PLANT_CARE.md §13). Awarded on the transition only, and keyed to the
        // observation, so toggling resolved off and on cannot farm it.
        if cleaned.isResolved, !wasResolved {
            _ = try? await progressionEngine.award(
                type: .plantHealthIssueResolved,
                sourceEntityID: cleaned.plantID,
                occurredAt: cleaned.resolvedAt ?? clock.now,
                deterministicKey: "healthResolved.\(cleaned.id.uuidString)"
            )
        }

        return cleaned
    }

    /// Marks an observation better. Only ever called from an explicit tap — the
    /// app cannot tell whether a plant has recovered.
    @discardableResult
    func resolve(observationID: UUID) async throws -> PlantHealthObservation {
        guard var observation = try await repository.observation(id: observationID) else {
            throw DomainError.notFound(entity: "PlantHealthObservation", id: observationID)
        }
        observation.resolvedAt = clock.now
        return try await save(observation)
    }

    /// Reopens an observation. Nothing is lost by having marked it resolved.
    @discardableResult
    func reopen(observationID: UUID) async throws -> PlantHealthObservation {
        guard var observation = try await repository.observation(id: observationID) else {
            throw DomainError.notFound(entity: "PlantHealthObservation", id: observationID)
        }
        observation.resolvedAt = nil
        return try await save(observation)
    }

    func deleteObservation(id: UUID) async throws {
        try await repository.deleteObservation(id: id)
    }

    // MARK: - Growth

    func newGrowthEntry(plantID: UUID) -> GrowthEntry {
        let now = clock.now
        return GrowthEntry(
            plantID: plantID,
            recordedAt: now,
            sourceDeviceID: deviceID,
            createdAt: now
        )
    }

    func growthEntries(forPlantID plantID: UUID) async throws -> [GrowthEntry] {
        try await repository.growthEntries(forPlantID: plantID)
    }

    @discardableResult
    func save(_ entry: GrowthEntry) async throws -> GrowthEntry {
        var cleaned = entry
        cleaned.note = tidy(entry.note)
        cleaned.unit = tidy(entry.unit)
        cleaned.milestoneLabel = tidy(entry.milestoneLabel)

        // A count has no unit, and storing "cm" against a leaf count would make
        // the comparison rules behave oddly later.
        if cleaned.metric?.isCount == true { cleaned.unit = nil }
        // A value with no metric cannot be compared or labelled, so it is a note
        // rather than a measurement.
        if cleaned.metric == nil { cleaned.value = nil; cleaned.unit = nil }

        guard !cleaned.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        try await repository.save(cleaned)
        await awardPhotoMilestoneIfReached(plantID: cleaned.plantID)
        return cleaned
    }

    func deleteGrowthEntry(id: UUID) async throws {
        try await repository.deleteGrowthEntry(id: id)
    }

    /// The two entries a side-by-side comparison should open with: the earliest
    /// and the latest that can actually be compared.
    ///
    /// Returns nil when there is nothing meaningful to compare, so the UI can
    /// leave the control out rather than showing a comparison of one thing
    /// against itself.
    func comparisonPair(
        forPlantID plantID: UUID
    ) async throws -> (earliest: GrowthEntry, latest: GrowthEntry)? {
        let entries = try await repository.growthEntries(forPlantID: plantID)
            .sorted { $0.recordedAt < $1.recordedAt }

        guard let latest = entries.last else { return nil }
        guard let earliest = entries.first(where: {
            $0.id != latest.id && $0.isComparable(with: latest)
        }) else {
            // No comparable measurement. Two photos are still worth comparing.
            guard
                latest.photoAttachmentID != nil,
                let earliestPhoto = entries.first(where: {
                    $0.id != latest.id && $0.photoAttachmentID != nil
                })
            else { return nil }
            return (earliestPhoto, latest)
        }
        return (earliest, latest)
    }

    /// Growth-photo milestones at round counts (PLANT_CARE.md §13).
    private func awardPhotoMilestoneIfReached(plantID: UUID) async {
        guard let entries = try? await repository.growthEntries(forPlantID: plantID)
        else { return }

        let photoCount = entries.filter { $0.photoAttachmentID != nil }.count
        let milestones = [1, 5, 10, 25]
        guard let reached = milestones.last(where: { $0 <= photoCount }) else { return }

        _ = try? await progressionEngine.award(
            type: .growthPhotoMilestone,
            sourceEntityID: plantID,
            occurredAt: clock.now,
            deterministicKey: "growthPhotos.\(plantID.uuidString).\(reached)"
        )
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
