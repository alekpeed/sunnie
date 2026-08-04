import Foundation
import SunnieShared

/// Mapping for the models added in schema V4.
///
/// Same discipline as before: nothing outside Persistence sees an `SD` type, and
/// an unreadable raw value falls back to a safe default rather than trapping.
extension ModelMapping {

    // MARK: - Trips

    static func domain(_ model: SDTrip) -> Trip {
        Trip(
            id: model.id,
            title: model.title,
            // An unknown type reads as a custom trip rather than being dropped.
            // The trip's dates, packing, and memories are the substance; the
            // type only decides which surfaces are offered.
            type: TripType(rawValue: model.typeRaw) ?? .custom,
            startsAt: model.startsAt,
            endsAt: model.endsAt,
            statusOverride: model.statusOverrideRaw.flatMap(TripStatus.init(rawValue:)),
            homeTimeZoneID: model.homeTimeZoneID,
            destinationTimeZoneIDs: model.destinationTimeZoneIDs,
            placeIDs: model.placeIDs,
            notes: model.notes,
            calendarEventID: model.calendarEventID,
            destinationPackIDs: model.destinationPackIDs.map(ContentID.init(rawValue:)),
            isFavorite: model.isFavorite,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ trip: Trip, to model: SDTrip) {
        model.id = trip.id
        model.title = trip.title
        model.typeRaw = trip.type.rawValue
        model.startsAt = trip.startsAt
        model.endsAt = trip.endsAt
        model.statusOverrideRaw = trip.statusOverride?.rawValue
        model.homeTimeZoneID = trip.homeTimeZoneID
        model.destinationTimeZoneIDs = trip.destinationTimeZoneIDs
        model.placeIDs = trip.placeIDs
        model.notes = trip.notes
        model.calendarEventID = trip.calendarEventID
        model.destinationPackIDs = trip.destinationPackIDs.map(\.rawValue)
        model.isFavorite = trip.isFavorite
        model.createdAt = trip.createdAt
        model.modifiedAt = trip.modifiedAt
    }

    static func domain(_ model: SDTripSegment) -> TripSegment {
        TripSegment(
            id: model.id,
            tripID: model.tripID,
            title: model.title,
            kind: TripSegment.SegmentKind(rawValue: model.kindRaw) ?? .other,
            startsAt: model.startsAt,
            endsAt: model.endsAt,
            originPlaceID: model.originPlaceID,
            destinationPlaceID: model.destinationPlaceID,
            originTimeZoneID: model.originTimeZoneID,
            destinationTimeZoneID: model.destinationTimeZoneID,
            notes: model.notes,
            sortOrder: model.sortOrder
        )
    }

    static func apply(_ segment: TripSegment, to model: SDTripSegment) {
        model.id = segment.id
        model.tripID = segment.tripID
        model.title = segment.title
        model.kindRaw = segment.kind.rawValue
        model.startsAt = segment.startsAt
        model.endsAt = segment.endsAt
        model.originPlaceID = segment.originPlaceID
        model.destinationPlaceID = segment.destinationPlaceID
        model.originTimeZoneID = segment.originTimeZoneID
        model.destinationTimeZoneID = segment.destinationTimeZoneID
        model.notes = segment.notes
        model.sortOrder = segment.sortOrder
    }

    // MARK: - Places

    static func domain(_ model: SDPlace) -> Place {
        Place(
            id: model.id,
            name: model.name,
            country: model.country,
            latitude: model.latitude,
            longitude: model.longitude,
            timeZoneID: model.timeZoneID,
            notes: model.notes,
            isSaved: model.isSaved,
            isFavorite: model.isFavorite,
            createdAt: model.createdAt
        )
    }

    static func apply(_ place: Place, to model: SDPlace) {
        model.id = place.id
        model.name = place.name
        model.country = place.country
        model.latitude = place.latitude
        model.longitude = place.longitude
        model.timeZoneID = place.timeZoneID
        model.notes = place.notes
        model.isSaved = place.isSaved
        model.isFavorite = place.isFavorite
        model.createdAt = place.createdAt
    }

    // MARK: - Packing

    static func domain(_ model: SDPackingItem) -> PackingItem {
        PackingItem(
            id: model.id,
            tripID: model.tripID,
            name: model.name,
            category: PackingCategory(rawValue: model.categoryRaw) ?? .other,
            quantity: model.quantity,
            isRequired: model.isRequired,
            isPacked: model.isPacked,
            notes: model.notes,
            suggestionReason: model.suggestionReason,
            sortOrder: model.sortOrder
        )
    }

    static func apply(_ item: PackingItem, to model: SDPackingItem) {
        model.id = item.id
        model.tripID = item.tripID
        model.name = item.name
        model.categoryRaw = item.category.rawValue
        model.quantity = item.quantity
        model.isRequired = item.isRequired
        model.isPacked = item.isPacked
        model.notes = item.notes
        model.suggestionReason = item.suggestionReason
        model.sortOrder = item.sortOrder
    }

    /// A template whose entries cannot be decoded comes back with none rather
    /// than being dropped: the user keeps a named template they can refill, which
    /// is less confusing than one that silently disappeared.
    static func domain(_ model: SDPackingTemplate) -> PackingTemplate {
        let entries = (try? JSONDecoder().decode(
            [PackingTemplate.Entry].self, from: model.encodedEntries
        )) ?? []

        return PackingTemplate(
            id: model.id,
            name: model.name,
            tripType: model.tripTypeRaw.flatMap(TripType.init(rawValue:)),
            entries: entries,
            isBuiltIn: model.isBuiltIn,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ template: PackingTemplate, to model: SDPackingTemplate) {
        model.id = template.id
        model.name = template.name
        model.tripTypeRaw = template.tripType?.rawValue
        model.encodedEntries = (try? JSONEncoder().encode(template.entries)) ?? Data()
        model.isBuiltIn = template.isBuiltIn
        model.createdAt = template.createdAt
        model.modifiedAt = template.modifiedAt
    }

    // MARK: - Checklists

    static func domain(_ model: SDChecklistItem) -> ChecklistItem {
        ChecklistItem(
            id: model.id,
            tripID: model.tripID,
            kind: ChecklistKind(rawValue: model.kindRaw) ?? .beforeLeaving,
            title: model.title,
            isDone: model.isDone,
            notes: model.notes,
            linkedRoute: model.linkedRoute,
            sortOrder: model.sortOrder
        )
    }

    static func apply(_ item: ChecklistItem, to model: SDChecklistItem) {
        model.id = item.id
        model.tripID = item.tripID
        model.kindRaw = item.kind.rawValue
        model.title = item.title
        model.isDone = item.isDone
        model.notes = item.notes
        model.linkedRoute = item.linkedRoute
        model.sortOrder = item.sortOrder
    }

    // MARK: - Memories

    static func domain(_ model: SDTravelMemory) -> TravelMemory {
        TravelMemory(
            id: model.id,
            tripID: model.tripID,
            placeID: model.placeID,
            occurredAt: model.occurredAt,
            title: model.title,
            text: model.text,
            isFavorite: model.isFavorite,
            tags: model.tags,
            postcardID: model.postcardID.map(ContentID.init(rawValue:)),
            stampID: model.stampID.map(ContentID.init(rawValue:)),
            linkedJournalEntryID: model.linkedJournalEntryID,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ memory: TravelMemory, to model: SDTravelMemory) {
        model.id = memory.id
        model.tripID = memory.tripID
        model.placeID = memory.placeID
        model.occurredAt = memory.occurredAt
        model.title = memory.title
        model.text = memory.text
        model.isFavorite = memory.isFavorite
        model.tags = memory.tags
        model.postcardID = memory.postcardID?.rawValue
        model.stampID = memory.stampID?.rawValue
        model.linkedJournalEntryID = memory.linkedJournalEntryID
        model.createdAt = memory.createdAt
        model.modifiedAt = memory.modifiedAt
    }
}
