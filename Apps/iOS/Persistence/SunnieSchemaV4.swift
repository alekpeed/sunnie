import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 4 — travel.
///
/// **Additive, like V2 and V3.** Trips, segments, places, packing, templates,
/// checklists, and memories are all new models; nothing that already existed
/// changes shape, so the stage stays lightweight.
///
/// That is now three additive versions in a row, and it is worth being honest
/// that the streak is not free — it holds because each phase's new records were
/// genuinely new entities rather than new fields on old ones. `PlantCoverage`
/// already carried `tripID` from V3, so trips landing here needed no change to
/// it, which is the one place this could plausibly have broken.
///
/// The next change that alters an existing model's shape still has to copy V1,
/// V2, and V3's models into frozen per-version namespaces and use a custom
/// stage (ADR-017).
enum SunnieSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SunnieSchemaV3.models + [
            SDTrip.self,
            SDTripSegment.self,
            SDPlace.self,
            SDPackingItem.self,
            SDPackingTemplate.self,
            SDChecklistItem.self,
            SDTravelMemory.self
        ]
    }
}

// MARK: - Trips

@Model
final class SDTrip {
    var id: UUID = UUID()
    var title: String = ""
    var typeRaw: String = TripType.personal.rawValue
    var startsAt: Date?
    var endsAt: Date?
    /// Only set when the user overrode the derived status — archiving, in
    /// practice. Everything else comes from `TripStatusCalculator`, so a status
    /// cannot go stale by being forgotten.
    var statusOverrideRaw: String?
    var homeTimeZoneID: String = TimeZone.current.identifier
    var destinationTimeZoneIDs: [String] = []
    var placeIDs: [UUID] = []
    var notes: String?
    /// EventKit identifier. The trip stays the source of truth for everything
    /// Sunnie Days-specific (TRAVEL_AND_FLIGHT_ATTENDANT.md §10).
    var calendarEventID: String?
    var destinationPackIDs: [String] = []
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "",
        typeRaw: String = TripType.personal.rawValue,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        statusOverrideRaw: String? = nil,
        homeTimeZoneID: String = TimeZone.current.identifier,
        destinationTimeZoneIDs: [String] = [],
        placeIDs: [UUID] = [],
        notes: String? = nil,
        calendarEventID: String? = nil,
        destinationPackIDs: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.typeRaw = typeRaw
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.statusOverrideRaw = statusOverrideRaw
        self.homeTimeZoneID = homeTimeZoneID
        self.destinationTimeZoneIDs = destinationTimeZoneIDs
        self.placeIDs = placeIDs
        self.notes = notes
        self.calendarEventID = calendarEventID
        self.destinationPackIDs = destinationPackIDs
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDTripSegment {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var title: String = ""
    var kindRaw: String = TripSegment.SegmentKind.flight.rawValue
    /// Absolute instants. The local reading is computed at display time — storing
    /// a wall-clock time is how an itinerary breaks across a daylight-saving
    /// boundary (TRAVEL_AND_FLIGHT_ATTENDANT.md §8).
    var startsAt: Date?
    var endsAt: Date?
    var originPlaceID: UUID?
    var destinationPlaceID: UUID?
    var originTimeZoneID: String?
    var destinationTimeZoneID: String?
    var notes: String?
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        tripID: UUID = UUID(),
        title: String = "",
        kindRaw: String = TripSegment.SegmentKind.flight.rawValue,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        originPlaceID: UUID? = nil,
        destinationPlaceID: UUID? = nil,
        originTimeZoneID: String? = nil,
        destinationTimeZoneID: String? = nil,
        notes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.tripID = tripID
        self.title = title
        self.kindRaw = kindRaw
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.originTimeZoneID = originTimeZoneID
        self.destinationTimeZoneID = destinationTimeZoneID
        self.notes = notes
        self.sortOrder = sortOrder
    }
}

/// A place, stored once and referred to by trips and memories.
///
/// Coordinates and time zone are optional: a place someone typed from memory is
/// still a place, and the list works without a map.
@Model
final class SDPlace {
    var id: UUID = UUID()
    var name: String = ""
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var timeZoneID: String?
    var notes: String?
    var isSaved: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeZoneID: String? = nil,
        notes: String? = nil,
        isSaved: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
        self.notes = notes
        self.isSaved = isSaved
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}

// MARK: - Packing and checklists

@Model
final class SDPackingItem {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = PackingCategory.personal.rawValue
    var quantity: Int = 1
    var isRequired: Bool = false
    var isPacked: Bool = false
    var notes: String?
    /// Set when the item arrived from a weather suggestion, so the UI can say
    /// where it came from. Suggestions are only ever added with confirmation.
    var suggestionReason: String?
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        tripID: UUID = UUID(),
        name: String = "",
        categoryRaw: String = PackingCategory.personal.rawValue,
        quantity: Int = 1,
        isRequired: Bool = false,
        isPacked: Bool = false,
        notes: String? = nil,
        suggestionReason: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.tripID = tripID
        self.name = name
        self.categoryRaw = categoryRaw
        self.quantity = quantity
        self.isRequired = isRequired
        self.isPacked = isPacked
        self.notes = notes
        self.suggestionReason = suggestionReason
        self.sortOrder = sortOrder
    }
}

/// A reusable packing list.
///
/// Entries are stored as one encoded blob rather than a child table: they are
/// read and written whole, never queried individually, and a blob keeps the
/// churn out of the migration path — the same reasoning as `SDUserPreferences`.
@Model
final class SDPackingTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var tripTypeRaw: String?
    var encodedEntries: Data = Data()
    var isBuiltIn: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        tripTypeRaw: String? = nil,
        encodedEntries: Data = Data(),
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tripTypeRaw = tripTypeRaw
        self.encodedEntries = encodedEntries
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDChecklistItem {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var kindRaw: String = ChecklistKind.beforeLeaving.rawValue
    var title: String = ""
    var isDone: Bool = false
    var notes: String?
    var linkedRoute: String?
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        tripID: UUID = UUID(),
        kindRaw: String = ChecklistKind.beforeLeaving.rawValue,
        title: String = "",
        isDone: Bool = false,
        notes: String? = nil,
        linkedRoute: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.tripID = tripID
        self.kindRaw = kindRaw
        self.title = title
        self.isDone = isDone
        self.notes = notes
        self.linkedRoute = linkedRoute
        self.sortOrder = sortOrder
    }
}

// MARK: - Memories

@Model
final class SDTravelMemory {
    var id: UUID = UUID()
    var tripID: UUID?
    var placeID: UUID?
    var occurredAt: Date = Date()
    var title: String?
    var text: String?
    var isFavorite: Bool = false
    var tags: [String] = []
    var postcardID: String?
    var stampID: String?
    var linkedJournalEntryID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        placeID: UUID? = nil,
        occurredAt: Date = Date(),
        title: String? = nil,
        text: String? = nil,
        isFavorite: Bool = false,
        tags: [String] = [],
        postcardID: String? = nil,
        stampID: String? = nil,
        linkedJournalEntryID: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.placeID = placeID
        self.occurredAt = occurredAt
        self.title = title
        self.text = text
        self.isFavorite = isFavorite
        self.tags = tags
        self.postcardID = postcardID
        self.stampID = stampID
        self.linkedJournalEntryID = linkedJournalEntryID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
