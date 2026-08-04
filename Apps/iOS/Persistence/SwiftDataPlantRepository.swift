import Foundation
import SwiftData
import SunnieShared

/// Plant and schedule storage.
///
/// `@ModelActor` gives this repository its own serialized executor and model
/// context. That serialization is what lets the care-event repository implement
/// check-then-insert safely without a database unique constraint.
@ModelActor
actor SwiftDataPlantRepository: PlantRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func allPlants(includingArchived: Bool) async throws -> [Plant] {
        let archived = PlantStatus.archived.rawValue
        var descriptor = FetchDescriptor<SDPlant>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        if !includingArchived {
            descriptor.predicate = #Predicate<SDPlant> { $0.statusRaw != archived }
        }
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            log.error("Fetching plants failed.")
            throw DomainError.persistenceFailed(operation: "allPlants")
        }
    }

    func plant(id: UUID) async throws -> Plant? {
        try fetchPlant(id: id).map { ModelMapping.domain($0) }
    }

    /// Resolves a scanned label.
    ///
    /// The token is checked for shape before it reaches storage, so scanning a
    /// Wi-Fi code or a product barcode costs nothing. Archived plants resolve
    /// too — a label on an archived plant should still open its record rather
    /// than appearing to be an unknown code.
    func plant(qrToken: String) async throws -> Plant? {
        guard PlantQRIdentity.isWellFormed(qrToken) else { return nil }
        var descriptor = FetchDescriptor<SDPlant>(
            predicate: #Predicate<SDPlant> { $0.qrToken == qrToken }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "plantByQRToken")
        }
    }

    /// Everything the collection screen needs, in one pass.
    ///
    /// Five fetches regardless of collection size, then dictionary joins in
    /// memory. The alternative — per-plant queries for schedules, last care, and
    /// observations — is roughly 4×N round trips, which at fifty plants is the
    /// difference between a screen that opens and one that visibly stalls
    /// (PLANT_CARE.md §1).
    func collectionItems(includingArchived: Bool) async throws -> [PlantCollectionItem] {
        do {
            let plants = try modelContext.fetch(FetchDescriptor<SDPlant>())
                .filter { includingArchived || $0.statusRaw != PlantStatus.archived.rawValue }

            let locationNames = Dictionary(
                try modelContext.fetch(FetchDescriptor<SDPlantLocation>())
                    .map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )

            // Soonest enabled due date and the scheduled care types, per plant.
            var soonestDue: [UUID: Date] = [:]
            var careTypes: [UUID: Set<CareType>] = [:]
            for schedule in try modelContext.fetch(FetchDescriptor<SDPlantCareSchedule>())
            where schedule.isEnabled {
                if let careType = CareType(storageKey: schedule.careTypeKey) {
                    careTypes[schedule.plantID, default: []].insert(careType)
                }
                if let due = schedule.nextDueDate {
                    soonestDue[schedule.plantID] = min(
                        soonestDue[schedule.plantID] ?? due, due
                    )
                }
            }

            // Most recent care per plant. Sorted descending so the first row seen
            // for a plant is its latest and the rest can be skipped.
            var lastCare: [UUID: Date] = [:]
            let events = try modelContext.fetch(FetchDescriptor<SDPlantCareEvent>(
                sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
            ))
            for event in events where lastCare[event.plantID] == nil {
                lastCare[event.plantID] = event.performedAt
            }

            var openObservations: [UUID: Int] = [:]
            for observation in try modelContext.fetch(
                FetchDescriptor<SDPlantHealthObservation>()
            ) where observation.resolvedAt == nil {
                openObservations[observation.plantID, default: 0] += 1
            }

            var caretakers: [UUID: Set<UUID>] = [:]
            for coverage in try modelContext.fetch(FetchDescriptor<SDPlantTravelCoverage>()) {
                if let caretakerID = coverage.caretakerID {
                    caretakers[coverage.plantID, default: []].insert(caretakerID)
                }
            }

            return plants.map { model in
                let plant = ModelMapping.domain(model)
                return PlantCollectionItem(
                    plant: plant,
                    locationName: plant.locationID.flatMap { locationNames[$0] },
                    nextDueDate: soonestDue[plant.id],
                    lastCareAt: lastCare[plant.id],
                    scheduledCareTypes: careTypes[plant.id] ?? [],
                    caretakerIDs: caretakers[plant.id] ?? [],
                    openObservationCount: openObservations[plant.id] ?? 0
                )
            }
        } catch {
            log.error("Building the plant collection failed.")
            throw DomainError.persistenceFailed(operation: "collectionItems")
        }
    }

    func save(_ plant: Plant) async throws {
        do {
            if let existing = try fetchPlant(id: plant.id) {
                ModelMapping.apply(plant, to: existing)
            } else {
                let model = SDPlant()
                ModelMapping.apply(plant, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePlant")
        }
    }

    /// Archiving rather than deleting is the product rule: a plant's history
    /// outlives the plant (PLANT_CARE.md §15).
    func archive(plantID: UUID, at date: Date) async throws {
        guard let model = try fetchPlant(id: plantID) else {
            throw DomainError.notFound(entity: "Plant", id: plantID)
        }
        do {
            model.statusRaw = PlantStatus.archived.rawValue
            model.modifiedAt = date

            // Disable its schedules so an archived plant stops producing due
            // tasks and pending reminders.
            for schedule in try fetchSchedules(plantID: plantID) {
                schedule.isEnabled = false
                schedule.nextDueDate = nil
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "archivePlant")
        }
    }

    /// Removes a plant and everything belonging only to it.
    ///
    /// Archiving is the reversible option and the one the UI leads with; this is
    /// for a plant added by mistake, which should not have to be archived
    /// forever. Media files are removed by the launch orphan sweep, which already
    /// deletes attachments whose owning plant is gone — doing it here would mean
    /// this repository reaching into the media file store.
    func delete(plantID: UUID) async throws {
        do {
            for schedule in try fetchSchedules(plantID: plantID) {
                modelContext.delete(schedule)
            }
            for event in try modelContext.fetch(FetchDescriptor<SDPlantCareEvent>(
                predicate: #Predicate<SDPlantCareEvent> { $0.plantID == plantID }
            )) {
                modelContext.delete(event)
            }
            for supersession in try modelContext.fetch(
                FetchDescriptor<SDCareEventSupersession>(
                    predicate: #Predicate<SDCareEventSupersession> { $0.plantID == plantID }
                )
            ) {
                modelContext.delete(supersession)
            }
            for observation in try modelContext.fetch(
                FetchDescriptor<SDPlantHealthObservation>(
                    predicate: #Predicate<SDPlantHealthObservation> { $0.plantID == plantID }
                )
            ) {
                modelContext.delete(observation)
            }
            for entry in try modelContext.fetch(FetchDescriptor<SDGrowthEntry>(
                predicate: #Predicate<SDGrowthEntry> { $0.plantID == plantID }
            )) {
                modelContext.delete(entry)
            }
            for coverage in try modelContext.fetch(FetchDescriptor<SDPlantTravelCoverage>(
                predicate: #Predicate<SDPlantTravelCoverage> { $0.plantID == plantID }
            )) {
                modelContext.delete(coverage)
            }
            if let plant = try fetchPlant(id: plantID) {
                modelContext.delete(plant)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deletePlant")
        }
    }

    func schedules(forPlantID plantID: UUID) async throws -> [PlantCareSchedule] {
        try fetchSchedules(plantID: plantID).map { ModelMapping.domain($0) }
    }

    func enabledSchedules() async throws -> [PlantCareSchedule] {
        let descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate<SDPlantCareSchedule> { $0.isEnabled },
            sortBy: [SortDescriptor(\.nextDueDate, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "enabledSchedules")
        }
    }

    func schedule(id: UUID) async throws -> PlantCareSchedule? {
        try fetchSchedule(id: id).map { ModelMapping.domain($0) }
    }

    func save(_ schedule: PlantCareSchedule) async throws {
        do {
            if let existing = try fetchSchedule(id: schedule.id) {
                ModelMapping.apply(schedule, to: existing)
            } else {
                let model = SDPlantCareSchedule()
                ModelMapping.apply(schedule, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveSchedule")
        }
    }

    func deleteSchedule(id: UUID) async throws {
        do {
            guard let model = try fetchSchedule(id: id) else { return }
            modelContext.delete(model)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteSchedule")
        }
    }

    func locations() async throws -> [PlantLocation] {
        let descriptor = FetchDescriptor<SDPlantLocation>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "locations")
        }
    }

    func save(_ location: PlantLocation) async throws {
        let id = location.id
        var descriptor = FetchDescriptor<SDPlantLocation>(
            predicate: #Predicate<SDPlantLocation> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(location, to: existing)
            } else {
                let model = SDPlantLocation()
                ModelMapping.apply(location, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveLocation")
        }
    }

    /// Deleting a location leaves its plants alone, with no location.
    ///
    /// Cascading would destroy plants because a room was renamed away, which is
    /// why locations were kept a separate record in the first place.
    func deleteLocation(id: UUID) async throws {
        do {
            for plant in try modelContext.fetch(FetchDescriptor<SDPlant>(
                predicate: #Predicate<SDPlant> { $0.locationID == id }
            )) {
                plant.locationID = nil
            }
            var descriptor = FetchDescriptor<SDPlantLocation>(
                predicate: #Predicate<SDPlantLocation> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteLocation")
        }
    }

    // MARK: - Fetch helpers

    private func fetchPlant(id: UUID) throws -> SDPlant? {
        var descriptor = FetchDescriptor<SDPlant>(predicate: #Predicate<SDPlant> { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSchedule(id: UUID) throws -> SDPlantCareSchedule? {
        var descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate<SDPlantCareSchedule> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSchedules(plantID: UUID) throws -> [SDPlantCareSchedule] {
        let descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate<SDPlantCareSchedule> { $0.plantID == plantID }
        )
        return try modelContext.fetch(descriptor)
    }
}
