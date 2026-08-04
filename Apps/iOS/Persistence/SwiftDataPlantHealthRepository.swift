import Foundation
import SwiftData
import SunnieShared

/// Health observations, the growth timeline, caretakers, and travel coverage.
///
/// Same `@ModelActor` discipline as the other repositories: a serialized
/// executor and its own context, so check-then-insert is safe without a database
/// unique constraint (ADR-011).
@ModelActor
actor SwiftDataPlantHealthRepository: PlantHealthRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    // MARK: - Observations

    /// Newest first, so the most recent thing noticed is at the top.
    func observations(forPlantID plantID: UUID) async throws -> [PlantHealthObservation] {
        let descriptor = FetchDescriptor<SDPlantHealthObservation>(
            predicate: #Predicate<SDPlantHealthObservation> { $0.plantID == plantID },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "observationsForPlant")
        }
    }

    func openObservations() async throws -> [PlantHealthObservation] {
        let descriptor = FetchDescriptor<SDPlantHealthObservation>(
            predicate: #Predicate<SDPlantHealthObservation> { $0.resolvedAt == nil },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "openObservations")
        }
    }

    func observation(id: UUID) async throws -> PlantHealthObservation? {
        try fetchObservation(id: id).map { ModelMapping.domain($0) }
    }

    func save(_ observation: PlantHealthObservation) async throws {
        do {
            if let existing = try fetchObservation(id: observation.id) {
                ModelMapping.apply(observation, to: existing)
            } else {
                modelContext.insert(ModelMapping.model(observation))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveObservation")
        }
    }

    func deleteObservation(id: UUID) async throws {
        do {
            guard let model = try fetchObservation(id: id) else { return }
            modelContext.delete(model)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteObservation")
        }
    }

    // MARK: - Growth

    func growthEntries(forPlantID plantID: UUID) async throws -> [GrowthEntry] {
        let descriptor = FetchDescriptor<SDGrowthEntry>(
            predicate: #Predicate<SDGrowthEntry> { $0.plantID == plantID },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "growthEntries")
        }
    }

    func growthEntry(id: UUID) async throws -> GrowthEntry? {
        try fetchGrowthEntry(id: id).map { ModelMapping.domain($0) }
    }

    func save(_ entry: GrowthEntry) async throws {
        do {
            if let existing = try fetchGrowthEntry(id: entry.id) {
                ModelMapping.apply(entry, to: existing)
            } else {
                modelContext.insert(ModelMapping.model(entry))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveGrowthEntry")
        }
    }

    func deleteGrowthEntry(id: UUID) async throws {
        do {
            guard let model = try fetchGrowthEntry(id: id) else { return }
            modelContext.delete(model)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteGrowthEntry")
        }
    }

    // MARK: - Caretakers

    func caretakers(includingInactive: Bool) async throws -> [Caretaker] {
        var descriptor = FetchDescriptor<SDCaretaker>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        if !includingInactive {
            descriptor.predicate = #Predicate<SDCaretaker> { $0.isActive }
        }
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "caretakers")
        }
    }

    func caretaker(id: UUID) async throws -> Caretaker? {
        var descriptor = FetchDescriptor<SDCaretaker>(
            predicate: #Predicate<SDCaretaker> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "caretaker")
        }
    }

    func save(_ caretaker: Caretaker) async throws {
        let id = caretaker.id
        var descriptor = FetchDescriptor<SDCaretaker>(
            predicate: #Predicate<SDCaretaker> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(caretaker, to: existing)
            } else {
                modelContext.insert(ModelMapping.model(caretaker))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveCaretaker")
        }
    }

    // MARK: - Coverage

    func coverage(forTripID tripID: UUID) async throws -> [PlantTravelCoverage] {
        let descriptor = FetchDescriptor<SDPlantTravelCoverage>(
            predicate: #Predicate<SDPlantTravelCoverage> { $0.tripID == tripID }
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "coverageForTrip")
        }
    }

    func coverage(forPlantID plantID: UUID) async throws -> [PlantTravelCoverage] {
        let descriptor = FetchDescriptor<SDPlantTravelCoverage>(
            predicate: #Predicate<SDPlantTravelCoverage> { $0.plantID == plantID }
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "coverageForPlant")
        }
    }

    /// One coverage row per plant per trip.
    ///
    /// Matched on trip and plant rather than on the row's own ID, because the
    /// coverage screen builds a fresh value each time it recalculates and would
    /// otherwise insert a second row for the same plant on every visit.
    func save(_ coverage: PlantTravelCoverage) async throws {
        let tripID = coverage.tripID
        let plantID = coverage.plantID
        var descriptor = FetchDescriptor<SDPlantTravelCoverage>(
            predicate: #Predicate<SDPlantTravelCoverage> {
                $0.tripID == tripID && $0.plantID == plantID
            }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(coverage, to: existing)
            } else {
                modelContext.insert(ModelMapping.model(coverage))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveCoverage")
        }
    }

    // MARK: - Fetch helpers

    private func fetchObservation(id: UUID) throws -> SDPlantHealthObservation? {
        var descriptor = FetchDescriptor<SDPlantHealthObservation>(
            predicate: #Predicate<SDPlantHealthObservation> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchGrowthEntry(id: UUID) throws -> SDGrowthEntry? {
        var descriptor = FetchDescriptor<SDGrowthEntry>(
            predicate: #Predicate<SDGrowthEntry> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
