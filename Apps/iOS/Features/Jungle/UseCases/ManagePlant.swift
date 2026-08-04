import Foundation
import SunnieShared

/// Creating, editing, archiving, and deleting a plant, plus its schedules.
///
/// The rule that shapes this whole type is from the editor spec: **never block
/// saving because reference content is missing** (PLANT_CARE.md, S-05). A failed
/// species lookup, an absent photo, an unknown pot — none of these may stand
/// between someone and recording that they own a plant. The only thing genuinely
/// required is a name.
struct ManagePlant: Sendable {

    private let plantRepository: any PlantRepository
    private let careEventRepository: any PlantCareEventRepository
    private let progressionEngine: ProgressionEngine
    private let summaryProvider: PlantSummaryProvider
    private let reminders: any ReminderOffering
    private let eventPublisher: any DomainEventPublishing
    private let clock: any SunnieClock
    private let random: any RandomSource

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        plantRepository: any PlantRepository,
        careEventRepository: any PlantCareEventRepository,
        progressionEngine: ProgressionEngine,
        summaryProvider: PlantSummaryProvider,
        reminders: any ReminderOffering = NoReminders(),
        eventPublisher: any DomainEventPublishing,
        clock: any SunnieClock,
        random: any RandomSource = SystemRandomSource()
    ) {
        self.plantRepository = plantRepository
        self.careEventRepository = careEventRepository
        self.progressionEngine = progressionEngine
        self.summaryProvider = summaryProvider
        self.reminders = reminders
        self.eventPublisher = eventPublisher
        self.clock = clock
        self.random = random
    }

    // MARK: - Creating and editing

    /// A blank plant, ready for the editor.
    ///
    /// The QR token is minted here rather than on first print, so a label can be
    /// produced at any time without the plant record changing underneath it.
    func newDraft() -> Plant {
        let now = clock.now
        return Plant(
            name: "",
            qrToken: PlantQRIdentity.makeToken(using: random),
            createdAt: now,
            modifiedAt: now
        )
    }

    /// Saves a new or edited plant.
    ///
    /// Trims the free-text fields and turns empty ones into nil, so a field the
    /// user typed into and then cleared does not persist as an empty string that
    /// later renders as a blank line.
    @discardableResult
    func save(_ plant: Plant) async throws -> Plant {
        var cleaned = plant
        cleaned.name = plant.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        cleaned.nickname = tidy(plant.nickname)
        cleaned.speciesName = tidy(plant.speciesName)
        cleaned.variety = tidy(plant.variety)
        cleaned.source = tidy(plant.source)
        cleaned.pot = tidy(plant.pot)
        cleaned.soil = tidy(plant.soil)
        cleaned.notes = tidy(plant.notes)
        cleaned.modifiedAt = clock.now

        // A plant restored from an export, or one created before tokens were
        // minted up front, gets one now rather than printing a blank label.
        if !PlantQRIdentity.isWellFormed(cleaned.qrToken) {
            cleaned.qrToken = PlantQRIdentity.makeToken(using: random)
        }

        let isNew = try await plantRepository.plant(id: cleaned.id) == nil
        try await plantRepository.save(cleaned)
        await summaryProvider.invalidate()

        if isNew {
            await eventPublisher.publish(DomainEvent(
                type: .plantAdded,
                occurredAt: clock.now,
                sourceEntityID: cleaned.id,
                deterministicKey: "plantAdded.\(cleaned.id.uuidString)"
            ))
            await awardFirstPlantIfEligible(plantID: cleaned.id)
            await awardCollectionMilestoneIfReached()
        }

        return cleaned
    }

    /// "First plant added" earns once, ever.
    ///
    /// The key is fixed rather than derived from the plant, so adding a second
    /// plant — or deleting the first and adding another — cannot earn it again.
    private func awardFirstPlantIfEligible(plantID: UUID) async {
        _ = try? await progressionEngine.award(
            type: .firstPlantAdded,
            sourceEntityID: plantID,
            occurredAt: clock.now,
            deterministicKey: "firstPlantAdded"
        )
    }

    /// Collection milestones at round numbers.
    ///
    /// Keyed on the milestone rather than on the plant, so a collection that
    /// crosses ten, drops to nine, and crosses ten again does not earn twice.
    /// Milestones are only ever reached, never lost — nothing earned is taken
    /// away.
    private func awardCollectionMilestoneIfReached() async {
        guard let plants = try? await plantRepository.allPlants(includingArchived: false)
        else { return }

        let milestones = [5, 10, 25, 50, 100]
        guard let reached = milestones.last(where: { $0 <= plants.count }) else { return }

        _ = try? await progressionEngine.award(
            type: .plantCollectionMilestone,
            sourceEntityID: nil,
            occurredAt: clock.now,
            deterministicKey: "plantCollectionMilestone.\(reached)"
        )
    }

    /// Archives a plant and cancels anything pending for it.
    ///
    /// Reversible: the history stays, and un-archiving restores it. This is the
    /// option the UI leads with, because a plant that died is still a plant that
    /// was cared for, and destroying that record is rarely what someone means.
    func archive(plantID: UUID) async throws {
        try await plantRepository.archive(plantID: plantID, at: clock.now)
        await reminders.cancelAll(for: plantID)
        await summaryProvider.invalidate()
    }

    func unarchive(plantID: UUID) async throws {
        guard var plant = try await plantRepository.plant(id: plantID) else {
            throw DomainError.notFound(entity: "Plant", id: plantID)
        }
        plant.status = .active
        plant.modifiedAt = clock.now
        try await plantRepository.save(plant)
        await summaryProvider.invalidate()
    }

    /// Destroys a plant and its history.
    ///
    /// Only for a plant added by mistake. Callers must confirm first and must say
    /// plainly that the history goes with it.
    func delete(plantID: UUID) async throws {
        await reminders.cancelAll(for: plantID)
        try await plantRepository.delete(plantID: plantID)
        await summaryProvider.invalidate()
    }

    // MARK: - Schedules

    /// Saves a schedule and keeps its next due date consistent.
    ///
    /// Changing an interval recomputes the due date from the last completion
    /// rather than from now, so shortening a schedule surfaces the task
    /// immediately instead of granting an unearned reprieve. A schedule that has
    /// never been completed becomes due from today.
    @discardableResult
    func save(_ schedule: PlantCareSchedule) async throws -> PlantCareSchedule {
        var updated = schedule

        if schedule.isEnabled, schedule.recurrence.intervalDays != nil {
            let anchor = schedule.lastCompletedAt ?? clock.now
            updated.nextDueDate = CareScheduleCalculator.nextDueDate(
                after: anchor,
                schedule: schedule,
                calendar: clock.calendar,
                timeZone: clock.timeZone
            )
        } else {
            // A manual or disabled schedule has no due date by definition, and
            // leaving a stale one behind would keep producing due tasks.
            updated.nextDueDate = nil
        }

        try await plantRepository.save(updated)
        await summaryProvider.invalidate()

        if !updated.isEnabled || updated.nextDueDate == nil {
            await reminders.cancelAll(for: updated.plantID)
        }

        return updated
    }

    func deleteSchedule(id: UUID, plantID: UUID) async throws {
        try await plantRepository.deleteSchedule(id: id)
        await reminders.cancelAll(for: plantID)
        await summaryProvider.invalidate()
    }

    // MARK: - Locations

    @discardableResult
    func save(_ location: PlantLocation) async throws -> PlantLocation {
        var cleaned = location
        cleaned.name = location.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.room = tidy(location.room)
        cleaned.lightNotes = tidy(location.lightNotes)
        try await plantRepository.save(cleaned)
        return cleaned
    }

    func deleteLocation(id: UUID) async throws {
        try await plantRepository.deleteLocation(id: id)
        await summaryProvider.invalidate()
    }

    // MARK: - Scanning

    /// Resolves a scanned QR label to a plant.
    func plant(forScannedCode code: String) async throws -> Plant? {
        guard let token = PlantQRIdentity.token(fromScanned: code) else { return nil }
        return try await plantRepository.plant(qrToken: token)
    }

    /// Issues a fresh QR token, invalidating any label already printed.
    ///
    /// Deliberately explicit: the old label stops working, and a user who has
    /// stuck labels on fifty pots should be told that before they do this.
    @discardableResult
    func regenerateQRToken(plantID: UUID) async throws -> Plant {
        guard var plant = try await plantRepository.plant(id: plantID) else {
            throw DomainError.notFound(entity: "Plant", id: plantID)
        }
        plant.qrToken = PlantQRIdentity.makeToken(using: random)
        plant.modifiedAt = clock.now
        try await plantRepository.save(plant)
        return plant
    }

    // MARK: - History

    /// A page of care history, with the corrected entries marked.
    func history(
        plantID: UUID,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> (events: [PlantCareEvent], superseded: Set<UUID>, total: Int) {
        async let events = careEventRepository.events(
            forPlantID: plantID, limit: limit, offset: offset
        )
        async let superseded = careEventRepository.supersededEventIDs(forPlantID: plantID)
        async let total = careEventRepository.eventCount(forPlantID: plantID)
        return (try await events, try await superseded, try await total)
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
