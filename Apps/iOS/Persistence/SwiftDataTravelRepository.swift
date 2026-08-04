import Foundation
import SwiftData
import SunnieShared

/// Trips, places, packing, checklists, and memories.
///
/// Same `@ModelActor` discipline as the other repositories: a serialized
/// executor and its own context (ADR-011).
@ModelActor
actor SwiftDataTravelRepository: TravelRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    // MARK: - Trips

    func trips(includingArchived: Bool) async throws -> [Trip] {
        let archived = TripStatus.archived.rawValue
        var descriptor = FetchDescriptor<SDTrip>(
            sortBy: [SortDescriptor(\.startsAt, order: .reverse)]
        )
        if !includingArchived {
            descriptor.predicate = #Predicate<SDTrip> { $0.statusOverrideRaw != archived }
        }
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            log.error("Fetching trips failed.")
            throw DomainError.persistenceFailed(operation: "trips")
        }
    }

    func trip(id: UUID) async throws -> Trip? {
        try fetchTrip(id: id).map { ModelMapping.domain($0) }
    }

    func save(_ trip: Trip) async throws {
        do {
            if let existing = try fetchTrip(id: trip.id) {
                ModelMapping.apply(trip, to: existing)
            } else {
                let model = SDTrip()
                ModelMapping.apply(trip, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveTrip")
        }
    }

    /// Removes a trip and everything that belongs only to it.
    ///
    /// Places survive: a place is visited by trips rather than owned by one, and
    /// deleting a trip must not erase the record that somewhere was ever visited.
    /// Memories go, because a memory of a deleted trip has nothing left to attach
    /// to — the confirmation the UI shows says so before this runs.
    func delete(tripID: UUID) async throws {
        do {
            for segment in try modelContext.fetch(FetchDescriptor<SDTripSegment>(
                predicate: #Predicate<SDTripSegment> { $0.tripID == tripID }
            )) {
                modelContext.delete(segment)
            }
            for item in try modelContext.fetch(FetchDescriptor<SDPackingItem>(
                predicate: #Predicate<SDPackingItem> { $0.tripID == tripID }
            )) {
                modelContext.delete(item)
            }
            for item in try modelContext.fetch(FetchDescriptor<SDChecklistItem>(
                predicate: #Predicate<SDChecklistItem> { $0.tripID == tripID }
            )) {
                modelContext.delete(item)
            }
            for memory in try modelContext.fetch(FetchDescriptor<SDTravelMemory>(
                predicate: #Predicate<SDTravelMemory> { $0.tripID == tripID }
            )) {
                modelContext.delete(memory)
            }
            // Coverage rows are about this trip and mean nothing without it.
            for coverage in try modelContext.fetch(FetchDescriptor<SDPlantTravelCoverage>(
                predicate: #Predicate<SDPlantTravelCoverage> { $0.tripID == tripID }
            )) {
                modelContext.delete(coverage)
            }
            if let trip = try fetchTrip(id: tripID) {
                modelContext.delete(trip)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteTrip")
        }
    }

    // MARK: - Segments

    func segments(forTripID tripID: UUID) async throws -> [TripSegment] {
        let descriptor = FetchDescriptor<SDTripSegment>(
            predicate: #Predicate<SDTripSegment> { $0.tripID == tripID },
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.startsAt, order: .forward)
            ]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "segments")
        }
    }

    func save(_ segment: TripSegment) async throws {
        let id = segment.id
        var descriptor = FetchDescriptor<SDTripSegment>(
            predicate: #Predicate<SDTripSegment> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(segment, to: existing)
            } else {
                let model = SDTripSegment()
                ModelMapping.apply(segment, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveSegment")
        }
    }

    func deleteSegment(id: UUID) async throws {
        try deleteRecord({
            var descriptor = FetchDescriptor<SDTripSegment>(
                predicate: #Predicate<SDTripSegment> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
        }, operation: "deleteSegment")
    }

    // MARK: - Places

    func places() async throws -> [Place] {
        let descriptor = FetchDescriptor<SDPlace>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "places")
        }
    }

    func place(id: UUID) async throws -> Place? {
        var descriptor = FetchDescriptor<SDPlace>(
            predicate: #Predicate<SDPlace> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ place: Place) async throws {
        let id = place.id
        var descriptor = FetchDescriptor<SDPlace>(
            predicate: #Predicate<SDPlace> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(place, to: existing)
            } else {
                let model = SDPlace()
                ModelMapping.apply(place, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePlace")
        }
    }

    /// Deleting a place leaves the trips that referenced it alone, minus the
    /// reference. Cascading would delete a trip because a place was tidied up.
    func deletePlace(id: UUID) async throws {
        do {
            for trip in try modelContext.fetch(FetchDescriptor<SDTrip>())
            where trip.placeIDs.contains(id) {
                trip.placeIDs.removeAll { $0 == id }
            }
            for memory in try modelContext.fetch(FetchDescriptor<SDTravelMemory>(
                predicate: #Predicate<SDTravelMemory> { $0.placeID == id }
            )) {
                memory.placeID = nil
            }
            var descriptor = FetchDescriptor<SDPlace>(
                predicate: #Predicate<SDPlace> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deletePlace")
        }
    }

    /// Places plus the facts the map and list filter on, in one pass.
    ///
    /// Three fetches regardless of how many places there are, then dictionary
    /// joins — the same shape as the plant collection, for the same reason.
    func placeListItems() async throws -> [PlaceListItem] {
        do {
            let places = try modelContext.fetch(FetchDescriptor<SDPlace>())
            let trips = try modelContext.fetch(FetchDescriptor<SDTrip>())
            let memories = try modelContext.fetch(FetchDescriptor<SDTravelMemory>())

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

            var years: [UUID: Set<Int>] = [:]
            var types: [UUID: Set<TripType>] = [:]
            for trip in trips {
                let type = TripType(rawValue: trip.typeRaw) ?? .custom
                let year = trip.startsAt.map { calendar.component(.year, from: $0) }
                for placeID in trip.placeIDs {
                    types[placeID, default: []].insert(type)
                    if let year { years[placeID, default: []].insert(year) }
                }
            }

            var memoryCounts: [UUID: Int] = [:]
            for memory in memories {
                guard let placeID = memory.placeID else { continue }
                memoryCounts[placeID, default: 0] += 1
                // A memory dated at a place counts as a visit, even when it was
                // added without a trip — which is how past travel gets recorded.
                years[placeID, default: []].insert(
                    calendar.component(.year, from: memory.occurredAt)
                )
            }

            return places.map { model in
                let place = ModelMapping.domain(model)
                return PlaceListItem(
                    place: place,
                    visitYears: years[place.id] ?? [],
                    tripTypes: types[place.id] ?? [],
                    memoryCount: memoryCounts[place.id] ?? 0
                )
            }
        } catch {
            log.error("Building the place list failed.")
            throw DomainError.persistenceFailed(operation: "placeListItems")
        }
    }

    // MARK: - Packing

    func packingItems(forTripID tripID: UUID) async throws -> [PackingItem] {
        let descriptor = FetchDescriptor<SDPackingItem>(
            predicate: #Predicate<SDPackingItem> { $0.tripID == tripID },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "packingItems")
        }
    }

    func save(_ item: PackingItem) async throws {
        let id = item.id
        var descriptor = FetchDescriptor<SDPackingItem>(
            predicate: #Predicate<SDPackingItem> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(item, to: existing)
            } else {
                let model = SDPackingItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePackingItem")
        }
    }

    /// One transaction for a whole template application, so a list is either
    /// applied or not — a half-applied template is confusing in a way a failed
    /// one is not.
    func savePackingItems(_ items: [PackingItem]) async throws {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                let model = SDPackingItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePackingItems")
        }
    }

    func deletePackingItem(id: UUID) async throws {
        try deleteRecord({
            var descriptor = FetchDescriptor<SDPackingItem>(
                predicate: #Predicate<SDPackingItem> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
        }, operation: "deletePackingItem")
    }

    func packingTemplates() async throws -> [PackingTemplate] {
        let descriptor = FetchDescriptor<SDPackingTemplate>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "packingTemplates")
        }
    }

    func packingTemplate(id: UUID) async throws -> PackingTemplate? {
        var descriptor = FetchDescriptor<SDPackingTemplate>(
            predicate: #Predicate<SDPackingTemplate> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ template: PackingTemplate) async throws {
        let id = template.id
        var descriptor = FetchDescriptor<SDPackingTemplate>(
            predicate: #Predicate<SDPackingTemplate> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(template, to: existing)
            } else {
                let model = SDPackingTemplate()
                ModelMapping.apply(template, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveTemplate")
        }
    }

    func deletePackingTemplate(id: UUID) async throws {
        try deleteRecord({
            var descriptor = FetchDescriptor<SDPackingTemplate>(
                predicate: #Predicate<SDPackingTemplate> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
        }, operation: "deleteTemplate")
    }

    // MARK: - Checklists

    func checklistItems(forTripID tripID: UUID) async throws -> [ChecklistItem] {
        let descriptor = FetchDescriptor<SDChecklistItem>(
            predicate: #Predicate<SDChecklistItem> { $0.tripID == tripID },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "checklistItems")
        }
    }

    func save(_ item: ChecklistItem) async throws {
        let id = item.id
        var descriptor = FetchDescriptor<SDChecklistItem>(
            predicate: #Predicate<SDChecklistItem> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(item, to: existing)
            } else {
                let model = SDChecklistItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveChecklistItem")
        }
    }

    func saveChecklistItems(_ items: [ChecklistItem]) async throws {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                let model = SDChecklistItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveChecklistItems")
        }
    }

    func deleteChecklistItem(id: UUID) async throws {
        try deleteRecord({
            var descriptor = FetchDescriptor<SDChecklistItem>(
                predicate: #Predicate<SDChecklistItem> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
        }, operation: "deleteChecklistItem")
    }

    // MARK: - Memories

    /// Newest first. A nil trip ID means memories not attached to any trip, which
    /// is how a place someone loved gets remembered without inventing a trip
    /// around it.
    func memories(forTripID tripID: UUID?) async throws -> [TravelMemory] {
        var descriptor = FetchDescriptor<SDTravelMemory>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        if let tripID {
            descriptor.predicate = #Predicate<SDTravelMemory> { $0.tripID == tripID }
        } else {
            descriptor.predicate = #Predicate<SDTravelMemory> { $0.tripID == nil }
        }
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "memories")
        }
    }

    func allMemories(limit: Int) async throws -> [TravelMemory] {
        var descriptor = FetchDescriptor<SDTravelMemory>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "allMemories")
        }
    }

    func memory(id: UUID) async throws -> TravelMemory? {
        var descriptor = FetchDescriptor<SDTravelMemory>(
            predicate: #Predicate<SDTravelMemory> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ memory: TravelMemory) async throws {
        let id = memory.id
        var descriptor = FetchDescriptor<SDTravelMemory>(
            predicate: #Predicate<SDTravelMemory> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(memory, to: existing)
            } else {
                let model = SDTravelMemory()
                ModelMapping.apply(memory, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveMemory")
        }
    }

    func deleteMemory(id: UUID) async throws {
        try deleteRecord({
            var descriptor = FetchDescriptor<SDTravelMemory>(
                predicate: #Predicate<SDTravelMemory> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
        }, operation: "deleteMemory")
    }

    // MARK: - Helpers

    /// Written out per type rather than generically.
    ///
    /// `#Predicate` needs a concrete key path at compile time, so a generic
    /// `delete<T: PersistentModel>` over a protocol with an `id` does not build.
    /// Five short methods that work beat one clever one that does not.
    private func deleteRecord(_ body: () throws -> Void, operation: String) throws {
        do {
            try body()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: operation)
        }
    }

    private func fetchTrip(id: UUID) throws -> SDTrip? {
        var descriptor = FetchDescriptor<SDTrip>(predicate: #Predicate<SDTrip> { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
