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
        try fetchEvent(actionKey: actionKey.rawValue).map(ModelMapping.domain)
    }

    func events(forPlantID plantID: UUID, limit: Int) async throws -> [PlantCareEvent] {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate { $0.plantID == plantID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "careEventsForPlant")
        }
    }

    func mostRecentEvent(
        forPlantID plantID: UUID,
        careType: CareType
    ) async throws -> PlantCareEvent? {
        let key = careType.storageKey
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate { $0.plantID == plantID && $0.careTypeKey == key },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first.map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "mostRecentCareEvent")
        }
    }

    private func fetchEvent(actionKey: String) throws -> SDPlantCareEvent? {
        var descriptor = FetchDescriptor<SDPlantCareEvent>(
            predicate: #Predicate { $0.actionKey == actionKey }
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
        try fetchEvent(deterministicKey: deterministicKey).flatMap(ModelMapping.domain)
    }

    func save(_ grant: RewardGrant) async throws -> SaveOutcome<RewardGrant> {
        let key = grant.deterministicKey
        var descriptor = FetchDescriptor<SDRewardGrant>(
            predicate: #Predicate { $0.deterministicKey == key }
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
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "rewardGrants")
        }
    }

    private func fetchProfile() throws -> SDProgressionProfile? {
        var descriptor = FetchDescriptor<SDProgressionProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchEvent(deterministicKey: String) throws -> SDProgressionEvent? {
        var descriptor = FetchDescriptor<SDProgressionEvent>(
            predicate: #Predicate { $0.deterministicKey == deterministicKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
