import Foundation

/// What kind of trip this is (TRAVEL_AND_FLIGHT_ATTENDANT.md §2).
///
/// The distinction is not cosmetic: a work trip surfaces the uniform and
/// documents checklists and should be quick to set up, because Vanessa flies
/// often and a ceremonial creation flow would make the app worse than a note.
/// A past trip skips the practical side entirely — it exists to hold memories.
public enum TripType: String, Hashable, Sendable, Codable, CaseIterable {
    case work
    case personal
    case dayTrip
    /// Added after the fact, for the record rather than for planning.
    case past
    case custom

    public var localizationKey: String { "trip.type.\(rawValue)" }

    /// Whether the practical planning surfaces apply. A past trip has no packing
    /// list to fill in and no departure checklist to work through.
    public var isPlannable: Bool { self != .past }

    /// Whether the work checklists and routines are offered by default.
    public var isWork: Bool { self == .work }
}

/// Where a trip is in its life (TRAVEL_AND_FLIGHT_ATTENDANT.md §3).
///
/// Derived from dates rather than set by hand — see `TripStatusCalculator`. A
/// status the user has to remember to update is a status that is wrong.
public enum TripStatus: String, Hashable, Sendable, Codable, CaseIterable {
    /// Created, but without dates settled.
    case planning
    case upcoming
    case active
    /// The last day, or travelling home.
    case returning
    case completed
    case archived

    public var localizationKey: String { "trip.status.\(rawValue)" }

    /// Whether this trip should lead the travel dashboard.
    public var isCurrent: Bool { self == .active || self == .returning }
}

/// A place, stored once and referred to by trips and memories.
///
/// Coordinates are optional throughout: a place someone typed from memory is
/// still a place, and refusing to store it without a lookup would be the travel
/// equivalent of blocking a plant save on a species lookup.
public struct Place: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var country: String?
    public var latitude: Double?
    public var longitude: Double?
    /// IANA identifier. Stored rather than derived, because a coordinate lookup
    /// needs a network and the time zone must work offline.
    public var timeZoneID: String?
    public var notes: String?
    /// Marked by the user for its own sake, rather than because a trip went there.
    public var isSaved: Bool
    public var isFavorite: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeZoneID: String? = nil,
        notes: String? = nil,
        isSaved: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date
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

    /// True when the place can be shown on a map. A place without one still
    /// appears in the list — the map is a view of the record, not the record.
    public var hasCoordinate: Bool { latitude != nil && longitude != nil }

    public var timeZone: TimeZone? {
        timeZoneID.flatMap(TimeZone.init(identifier:))
    }
}

/// One leg of a trip: a flight, a train, a drive, a stay.
///
/// Deliberately generic. This is not an airline operations system
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §1), so a segment is "somewhere to be at a
/// time", not a flight record with equipment and crew.
public struct TripSegment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let tripID: UUID
    public var title: String
    public var kind: SegmentKind
    /// Absolute instants. The local interpretation is computed from the time
    /// zone at display time, never stored — storing a wall-clock time is how
    /// itineraries break across a daylight-saving boundary.
    public var startsAt: Date?
    public var endsAt: Date?
    public var originPlaceID: UUID?
    public var destinationPlaceID: UUID?
    /// IANA identifiers for each end, so a red-eye reads correctly at both.
    public var originTimeZoneID: String?
    public var destinationTimeZoneID: String?
    public var notes: String?
    public var sortOrder: Int

    public enum SegmentKind: String, Hashable, Sendable, Codable, CaseIterable {
        case flight
        case train
        case drive
        case stay
        case layover
        case other

        public var localizationKey: String { "segment.kind.\(rawValue)" }
    }

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        title: String,
        kind: SegmentKind = .flight,
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
        self.kind = kind
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

/// A trip (TRAVEL_AND_FLIGHT_ATTENDANT.md §3).
public struct Trip: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var type: TripType
    /// Absolute instants. `TripStatusCalculator` interprets them in the relevant
    /// zone; nothing stores a wall-clock date.
    public var startsAt: Date?
    public var endsAt: Date?
    /// Set only when the user overrides the derived status — archiving, mostly.
    public var statusOverride: TripStatus?
    public var homeTimeZoneID: String
    /// Ordered; the first is the one the trip screen shows alongside home time.
    public var destinationTimeZoneIDs: [String]
    public var placeIDs: [UUID]
    public var notes: String?
    /// EventKit identifier, when the user linked a calendar event. The trip stays
    /// the source of truth for everything Sunnie Days-specific (§10).
    public var calendarEventID: String?
    public var destinationPackIDs: [ContentID]
    public var isFavorite: Bool
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        type: TripType = .personal,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        statusOverride: TripStatus? = nil,
        homeTimeZoneID: String,
        destinationTimeZoneIDs: [String] = [],
        placeIDs: [UUID] = [],
        notes: String? = nil,
        calendarEventID: String? = nil,
        destinationPackIDs: [ContentID] = [],
        isFavorite: Bool = false,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.statusOverride = statusOverride
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

    public var homeTimeZone: TimeZone {
        TimeZone(identifier: homeTimeZoneID) ?? .current
    }

    /// The zone the trip screen shows opposite home time.
    public var primaryDestinationTimeZone: TimeZone? {
        destinationTimeZoneIDs.first.flatMap(TimeZone.init(identifier:))
    }
}

/// Works out a trip's status from its dates.
///
/// Pure, so every boundary — the day it starts, the last day, a trip spanning a
/// daylight-saving change, a trip with no dates at all — is testable without a
/// store or a clock (TRAVEL_AND_FLIGHT_ATTENDANT.md §8).
///
/// Comparisons are by *day* in the relevant zone rather than by instant. A trip
/// that starts at 06:00 is already active at 09:00 on that date, and a trip
/// ending today is still `returning` at 23:00 rather than having quietly become
/// history at midnight UTC.
public enum TripStatusCalculator {

    public static func status(
        for trip: Trip,
        now: Date,
        calendar: Calendar
    ) -> TripStatus {
        // An explicit archive always wins. Everything else is derived, so a
        // status can never go stale.
        if let override = trip.statusOverride, override == .archived {
            return .archived
        }

        // A past trip is a record, not a plan, whatever its dates say.
        if trip.type == .past { return .completed }

        guard let start = trip.startsAt else {
            return trip.statusOverride ?? .planning
        }

        // The trip is lived in the destination's day where there is one: someone
        // in Tokyo should not see their trip end because it is still yesterday
        // at home.
        var zoned = calendar
        zoned.timeZone = trip.primaryDestinationTimeZone ?? trip.homeTimeZone

        let today = zoned.startOfDay(for: now)
        let startDay = zoned.startOfDay(for: start)
        let endDay = trip.endsAt.map { zoned.startOfDay(for: $0) } ?? startDay

        if today < startDay { return .upcoming }
        if today > endDay { return .completed }
        // The last day is "returning" rather than "active", because that is the
        // day the return checklist matters.
        if today == endDay, endDay != startDay { return .returning }
        return .active
    }

    /// Whole days until a trip starts. Nil once it has begun, or with no date.
    public static func daysUntilDeparture(
        _ trip: Trip,
        now: Date,
        calendar: Calendar
    ) -> Int? {
        guard let start = trip.startsAt else { return nil }
        var zoned = calendar
        zoned.timeZone = trip.homeTimeZone

        let today = zoned.startOfDay(for: now)
        let startDay = zoned.startOfDay(for: start)
        guard startDay > today else { return nil }
        return zoned.dateComponents([.day], from: today, to: startDay).day
    }

    /// The window a trip covers, for plant coverage and meal planning.
    ///
    /// Runs to the *end* of the last day rather than its start, so care due on
    /// the afternoon of the return day is correctly inside the absence.
    public static func absenceWindow(
        for trip: Trip,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard let start = trip.startsAt else { return nil }
        var zoned = calendar
        zoned.timeZone = trip.homeTimeZone

        let end = trip.endsAt ?? start
        guard let endOfLastDay = zoned.date(
            byAdding: .day, value: 1, to: zoned.startOfDay(for: end)
        ) else { return (start, end) }

        return (start, endOfLastDay)
    }

    /// Sort order for the dashboard: current trips first, then soonest upcoming,
    /// then most recent past.
    public static func dashboardOrder(
        _ trips: [Trip],
        now: Date,
        calendar: Calendar
    ) -> [Trip] {
        trips.sorted { lhs, rhs in
            let lhsStatus = status(for: lhs, now: now, calendar: calendar)
            let rhsStatus = status(for: rhs, now: now, calendar: calendar)

            if lhsStatus.isCurrent != rhsStatus.isCurrent { return lhsStatus.isCurrent }

            let lhsUpcoming = lhsStatus == .upcoming
            let rhsUpcoming = rhsStatus == .upcoming
            if lhsUpcoming != rhsUpcoming { return lhsUpcoming }

            switch (lhs.startsAt, rhs.startsAt) {
            case let (l?, r?):
                // Upcoming: soonest first. Everything else: most recent first.
                if l == r { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
                return lhsUpcoming ? l < r : l > r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil):
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}
