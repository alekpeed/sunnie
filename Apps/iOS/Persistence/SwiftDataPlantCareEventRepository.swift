import Foundation
import SwiftData
import SunnieShared

/// Append-only care history, with idempotency enforced here rather than by a
/// database constraint.
///
/// `save` is check-then-insert. That is only safe because `@ModelActor`
/// serializes every call on this repository's executor — two concurrent saves
/// with the same action key cannot interleave between the check and the insert.
/// This is deliberate: CloudKit's private database does not support unique
/// constraints, so enforcing uniqueness in code keeps the guarantee identical
/// whether or not sync is enabled (ADR-011).
@ModelActor
actor SwiftDataPlantCareEventRepository: PlantCareEventRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func save(_ event: PlantCareEvent) async throws -> SaveOutcome<PlantCareEvent> {
        if let existing = try fetchEvent(actionKey: event.actionKey.rawValue) {
            log.debug("Care event already exists for this action; not duplicating.")
            return .alreadyExisted(ModelMapping.domain(existing))
        }

        do {
            let model = ModelMapping.model(event)
            modelContext.insert(model)
            try modelContext.save()
            return .created(ModelMapping.domain(model))
        } catch {
            // Leave no partial state behind: either the event is stored or
            // nothing changed.
            modelContext.rollback()
            log.error("Saving a care event failed.")
            throw DomainError.persistenceFailed(operation: "savePlantCareEvent")
        }
    }

    func event(actionKey: ActionKey) async throws -> PlantCareEvent? {
        try fetchEvent(actionKey: actionKey.rawValue).map { ModelMapping.domain($0) }
    }

    func events(forPlantID plantID: UUID, limit: Int) async throws -> [PlantCareEvent] {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate<SDPlantCareEvent> { $0.plantID == plantID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "careEventsForPlant")
        }
    }

    /// A page of history. Paged rather than fetched whole because a plant with
    /// 500+ events would otherwise load the lot to show twenty rows
    /// (PLANT_CARE.md §15).
    func events(
        forPlantID plantID: UUID,
        limit: Int,
        offset: Int
    ) async throws -> [PlantCareEvent] {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate<SDPlantCareEvent> { $0.plantID == plantID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        descriptor.fetchOffset = max(0, offset)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "careEventPage")
        }
    }

    func eventCount(forPlantID plantID: UUID) async throws -> Int {
        do {
            return try modelContext.fetchCount(FetchDescriptor<SDPlantCareEvent>(
                predicate: #Predicate<SDPlantCareEvent> { $0.plantID == plantID }
            ))
        } catch {
            throw DomainError.persistenceFailed(operation: "careEventCount")
        }
    }

    func allEvents(limit: Int) async throws -> [PlantCareEvent] {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "allCareEvents")
        }
    }

    /// Records a correction.
    ///
    /// The replacement is saved through the normal idempotent path, so a repeated
    /// correction does not create a second event. The supersession link is then
    /// written only if it is not already there — correcting the same event twice
    /// with the same replacement is a no-op rather than a growing pile of links.
    ///
    /// If the replacement turns out to be a duplicate of an event that is *not*
    /// the one being corrected, the link still points at the stored event, which
    /// keeps the history honest about what actually replaced what.
    func replace(
        eventID: UUID,
        with replacement: PlantCareEvent
    ) async throws -> SaveOutcome<PlantCareEvent> {
        let outcome = try await save(replacement)
        let stored = outcome.value

        // Nothing supersedes itself.
        guard stored.id != eventID else { return outcome }

        let storedID = stored.id
        var existing = FetchDescriptor<SDCareEventSupersession>(
            predicate: #Predicate<SDCareEventSupersession> {
                $0.supersededEventID == eventID && $0.replacementEventID == storedID
            }
        )
        existing.fetchLimit = 1

        do {
            if try modelContext.fetch(existing).isEmpty {
                modelContext.insert(SDCareEventSupersession(
                    plantID: stored.plantID,
                    supersededEventID: eventID,
                    replacementEventID: storedID,
                    recordedAt: stored.createdAt
                ))
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            // The replacement is already stored. Failing to record the link costs
            // the "superseded" marker in the history, not the correction itself,
            // so the outcome is still returned rather than thrown away.
            log.error("Recording a care-event supersession failed.")
        }

        return outcome
    }

    func supersededEventIDs(forPlantID plantID: UUID) async throws -> Set<UUID> {
        do {
            let links = try modelContext.fetch(FetchDescriptor<SDCareEventSupersession>(
                predicate: #Predicate<SDCareEventSupersession> { $0.plantID == plantID }
            ))
            return Set(links.map(\.supersededEventID))
        } catch {
            throw DomainError.persistenceFailed(operation: "supersededEventIDs")
        }
    }

    func mostRecentEvent(
        forPlantID plantID: UUID,
        careType: CareType
    ) async throws -> PlantCareEvent? {
        let key = careType.storageKey
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate<SDPlantCareEvent> { $0.plantID == plantID && $0.careTypeKey == key },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "mostRecentCareEvent")
        }
    }

    private func fetchEvent(actionKey: String) throws -> SDPlantCareEvent? {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate<SDPlantCareEvent> { $0.actionKey == actionKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Progression storage. Same check-then-insert discipline as care events, for
/// the same reason: a replayed action must never award twice.
@ModelActor
actor SwiftDataProgressionRepository: ProgressionRepository {

    func profile() async throws -> ProgressionProfile {
        if let existing = try fetchProfile() {
            return ModelMapping.domain(existing)
        }
        // The profile is created lazily on first read so a fresh install has one
        // without needing a seeding step.
        let model = SDProgressionProfile()
        modelContext.insert(model)
        try? modelContext.save()
        return ModelMapping.domain(model)
    }

    func save(_ profile: ProgressionProfile) async throws {
        do {
            if let existing = try fetchProfile() {
                ModelMapping.apply(profile, to: existing)
            } else {
                let model = SDProgressionProfile()
                ModelMapping.apply(profile, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveProgressionProfile")
        }
    }

    func save(_ event: ProgressionEvent) async throws -> SaveOutcome<ProgressionEvent> {
        if let existing = try fetchEvent(deterministicKey: event.deterministicKey),
           let domain = ModelMapping.domain(existing) {
            return .alreadyExisted(domain)
        }

        do {
            let model = ModelMapping.model(event)
            modelContext.insert(model)
            try modelContext.save()
            return .created(event)
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveProgressionEvent")
        }
    }

    func event(deterministicKey: String) async throws -> ProgressionEvent? {
        try fetchEvent(deterministicKey: deterministicKey).flatMap { ModelMapping.domain($0) }
    }

    func save(_ grant: RewardGrant) async throws -> SaveOutcome<RewardGrant> {
        let key = grant.deterministicKey
        var descriptor = FetchDescriptor<SDRewardGrant>(
            predicate: #Predicate<SDRewardGrant> { $0.deterministicKey == key }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return .alreadyExisted(ModelMapping.domain(existing))
        }

        do {
            let model = ModelMapping.model(grant)
            modelContext.insert(model)
            try modelContext.save()
            return .created(grant)
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveRewardGrant")
        }
    }

    func grants(limit: Int) async throws -> [RewardGrant] {
        var descriptor = FetchDescriptor<SDRewardGrant>(
            sortBy: [SortDescriptor(\.grantedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "rewardGrants")
        }
    }

    /// Every grant, newest first.
    ///
    /// Unbounded on purpose. The collection screen shows what someone owns, and
    /// a limit here would silently drop the oldest things they earned — which
    /// are usually the ones they earned first and remember best.
    func allGrants() async throws -> [RewardGrant] {
        do {
            return try modelContext
                .fetch(FetchDescriptor<SDRewardGrant>(
                    sortBy: [SortDescriptor(\.grantedAt, order: .reverse)]
                ))
                .map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "allRewardGrants")
        }
    }

    /// How many times each kind of event has happened.
    ///
    /// Fetched as raw type strings and tallied here rather than with a grouped
    /// query, which SwiftData does not offer. An unrecognised string — an event
    /// type written by a newer build — is skipped rather than crashing, so an
    /// older build opening a newer store still counts what it understands.
    func eventCounts() async throws -> [ProgressionEventType: Int] {
        do {
            var counts: [ProgressionEventType: Int] = [:]
            for model in try modelContext.fetch(FetchDescriptor<SDProgressionEvent>()) {
                guard let type = ProgressionEventType(rawValue: model.typeRaw) else { continue }
                counts[type, default: 0] += 1
            }
            return counts
        } catch {
            throw DomainError.persistenceFailed(operation: "progressionEventCounts")
        }
    }

    /// When things happened, for the rhythm summary.
    func eventDates(since: Date) async throws -> [Date] {
        do {
            return try modelContext
                .fetch(FetchDescriptor<SDProgressionEvent>(
                    predicate: #Predicate<SDProgressionEvent> { $0.occurredAt >= since },
                    sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
                ))
                .map(\.occurredAt)
        } catch {
            throw DomainError.persistenceFailed(operation: "progressionEventDates")
        }
    }

    private func fetchProfile() throws -> SDProgressionProfile? {
        var descriptor = FetchDescriptor<SDProgressionProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchEvent(deterministicKey: String) throws -> SDProgressionEvent? {
        var descriptor = FetchDescriptor<SDProgressionEvent>(
            predicate: #Predicate<SDProgressionEvent> { $0.deterministicKey == deterministicKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
