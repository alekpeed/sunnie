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
            descriptor.predicate = #Predicate { $0.statusRaw != archived }
        }
        do {
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            log.error("Fetching plants failed.")
            throw DomainError.persistenceFailed(operation: "allPlants")
        }
    }

    func plant(id: UUID) async throws -> Plant? {
        try fetchPlant(id: id).map(ModelMapping.domain)
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

    func schedules(forPlantID plantID: UUID) async throws -> [PlantCareSchedule] {
        try fetchSchedules(plantID: plantID).map(ModelMapping.domain)
    }

    func enabledSchedules() async throws -> [PlantCareSchedule] {
        let descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.nextDueDate, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "enabledSchedules")
        }
    }

    func schedule(id: UUID) async throws -> PlantCareSchedule? {
        try fetchSchedule(id: id).map(ModelMapping.domain)
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

    func locations() async throws -> [PlantLocation] {
        let descriptor = FetchDescriptor<SDPlantLocation>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "locations")
        }
    }

    func save(_ location: PlantLocation) async throws {
        let id = location.id
        var descriptor = FetchDescriptor<SDPlantLocation>(
            predicate: #Predicate { $0.id == id }
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

    // MARK: - Fetch helpers

    private func fetchPlant(id: UUID) throws -> SDPlant? {
        var descriptor = FetchDescriptor<SDPlant>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSchedule(id: UUID) throws -> SDPlantCareSchedule? {
        var descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSchedules(plantID: UUID) throws -> [SDPlantCareSchedule] {
        let descriptor = FetchDescriptor<SDPlantCareSchedule>(
            predicate: #Predicate { $0.plantID == plantID }
        )
        return try modelContext.fetch(descriptor)
    }
}
