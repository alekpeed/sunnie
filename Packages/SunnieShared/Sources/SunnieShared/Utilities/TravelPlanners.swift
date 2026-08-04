import Foundation

/// Home time and local time, side by side (TRAVEL_AND_FLIGHT_ATTENDANT.md §8).
///
/// The signature element of the trip screen, and the one place where getting
/// time zones wrong is immediately visible. Everything here works from absolute
/// instants and IANA identifiers; nothing stores or compares wall-clock times,
/// which is what makes a daylight-saving boundary a non-event.
public struct TimeZoneContext: Hashable, Sendable {
    public let homeTimeZoneID: String
    public let localTimeZoneID: String
    public let instant: Date

    public init(homeTimeZoneID: String, localTimeZoneID: String, instant: Date) {
        self.homeTimeZoneID = homeTimeZoneID
        self.localTimeZoneID = localTimeZoneID
        self.instant = instant
    }

    public var homeTimeZone: TimeZone { TimeZone(identifier: homeTimeZoneID) ?? .current }
    public var localTimeZone: TimeZone { TimeZone(identifier: localTimeZoneID) ?? .current }

    /// Offset between the two zones **at this instant**.
    ///
    /// Computed rather than stored, because it changes: two zones five hours
    /// apart in January can be four apart in March if they switch to summer time
    /// on different dates. A cached offset is wrong twice a year.
    public var offsetSeconds: Int {
        localTimeZone.secondsFromGMT(for: instant)
            - homeTimeZone.secondsFromGMT(for: instant)
    }

    public var offsetHours: Double { Double(offsetSeconds) / 3600 }

    /// Whether local time is on a different calendar day from home.
    public func isDifferentDay(calendar: Calendar) -> Bool {
        var home = calendar
        home.timeZone = homeTimeZone
        var local = calendar
        local.timeZone = localTimeZone
        return home.startOfDay(for: instant) != local.startOfDay(for: instant)
    }

    /// True when either zone changes its offset within the next day — the case
    /// worth telling someone about, because their alarm is about to be an hour
    /// out.
    public func hasUpcomingTransition(withinHours hours: Double = 24) -> Bool {
        let horizon = instant.addingTimeInterval(hours * 3600)
        for zone in [homeTimeZone, localTimeZone] {
            if let next = zone.nextDaylightSavingTimeTransition(after: instant), next <= horizon {
                return true
            }
        }
        return false
    }
}

/// A suggested sleep window (TRAVEL_AND_FLIGHT_ATTENDANT.md §4).
///
/// **Explicitly non-medical, and the spec says so.** This does not model
/// circadian rhythm, does not diagnose jet lag, and makes no claim about health.
/// It does one arithmetic thing: takes the sleep schedule the user entered and
/// shows what those same hours look like in the destination's clock, so they can
/// decide for themselves.
///
/// Every string built from this must stay descriptive. "Your usual bedtime is
/// 3am there" is a fact about clocks. "You should sleep now" is advice this app
/// does not give.
public enum SleepWindowPlanner {

    public struct Window: Hashable, Sendable {
        /// The user's usual hours, as they'd read them at home.
        public let homeBedHour: Int
        public let homeWakeHour: Int
        /// The same instants, read in the destination's clock.
        public let localBedHour: Int
        public let localWakeHour: Int
        /// How far the clock has moved. Positive means the destination is ahead.
        public let shiftHours: Double

        public init(
            homeBedHour: Int,
            homeWakeHour: Int,
            localBedHour: Int,
            localWakeHour: Int,
            shiftHours: Double
        ) {
            self.homeBedHour = homeBedHour
            self.homeWakeHour = homeWakeHour
            self.localBedHour = localBedHour
            self.localWakeHour = localWakeHour
            self.shiftHours = shiftHours
        }

        /// Whether the shift is big enough to be worth mentioning at all. Under
        /// two hours, saying anything would be noise.
        public var isWorthMentioning: Bool { abs(shiftHours) >= 2 }
    }

    /// Translates the user's usual hours into the destination's clock.
    ///
    /// Rounds to the hour: the input is "I usually go to bed about eleven", and
    /// presenting the result to the minute would imply a precision the input
    /// never had.
    public static func window(
        homeBedHour: Int,
        homeWakeHour: Int,
        context: TimeZoneContext
    ) -> Window {
        let shift = context.offsetHours
        return Window(
            homeBedHour: wrap(homeBedHour),
            homeWakeHour: wrap(homeWakeHour),
            localBedHour: wrap(homeBedHour + Int(shift.rounded())),
            localWakeHour: wrap(homeWakeHour + Int(shift.rounded())),
            shiftHours: shift
        )
    }

    private static func wrap(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }
}

/// A hydration plan for a travel day (TRAVEL_AND_FLIGHT_ATTENDANT.md §4).
///
/// Also non-medical. It spaces a number of reminders across the waking hours the
/// user described — it does not calculate a fluid requirement, and nothing built
/// from it may suggest it knows what someone's body needs.
public enum HydrationPlanner {

    /// Evenly spaced reminder times across the waking window.
    ///
    /// Capped at the category's own daily ceiling, so a plan can never ask for
    /// more notifications than the reminder rules allow
    /// (NOTIFICATIONS_AND_REMINDERS.md).
    public static func reminderTimes(
        wakingStart: Date,
        wakingEnd: Date,
        count: Int,
        calendar: Calendar
    ) -> [Date] {
        let ceiling = ReminderCategory.hydration.dailyMaximum
        let wanted = min(max(count, 0), ceiling)
        guard wanted > 0, wakingEnd > wakingStart else { return [] }

        let span = wakingEnd.timeIntervalSince(wakingStart)
        // Spaced across the interior of the window rather than from its edges:
        // a reminder at the moment of waking and another at the moment of
        // sleeping are the two least useful ones.
        let step = span / Double(wanted + 1)

        return (1...wanted).map { index in
            wakingStart.addingTimeInterval(step * Double(index))
        }
    }
}

/// Turns a trip and its records into the numbers the trip screen shows
/// (SCREEN_SPECIFICATIONS.md S-07).
///
/// Progress is reported as counts, never percentages, and never as a score. "6
/// of 10 packed" states what is left; "60% ready" invites a judgement about the
/// other four.
public struct TripProgress: Hashable, Sendable {
    public let packing: Counts
    public let leavingChecklist: Counts
    public let returningChecklist: Counts
    /// Plants with something due during the absence and no decision recorded.
    public let undecidedPlantCoverage: Int
    public let totalPlantsNeedingCare: Int

    public struct Counts: Hashable, Sendable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        public var isEmpty: Bool { total == 0 }
        public var isComplete: Bool { total > 0 && done == total }
        public var remaining: Int { max(0, total - done) }
    }

    public init(
        packing: Counts,
        leavingChecklist: Counts,
        returningChecklist: Counts,
        undecidedPlantCoverage: Int,
        totalPlantsNeedingCare: Int
    ) {
        self.packing = packing
        self.leavingChecklist = leavingChecklist
        self.returningChecklist = returningChecklist
        self.undecidedPlantCoverage = undecidedPlantCoverage
        self.totalPlantsNeedingCare = totalPlantsNeedingCare
    }

    public static func build(
        packingItems: [PackingItem],
        checklistItems: [ChecklistItem],
        undecidedPlantCoverage: Int = 0,
        totalPlantsNeedingCare: Int = 0
    ) -> TripProgress {
        func counts(_ items: [ChecklistItem]) -> Counts {
            Counts(done: items.filter(\.isDone).count, total: items.count)
        }

        let packed = PackingListBuilder.progress(for: packingItems)

        return TripProgress(
            packing: Counts(done: packed.packed, total: packed.total),
            leavingChecklist: counts(checklistItems.filter { $0.kind.phase == .leaving }),
            returningChecklist: counts(checklistItems.filter { $0.kind.phase == .returning }),
            undecidedPlantCoverage: undecidedPlantCoverage,
            totalPlantsNeedingCare: totalPlantsNeedingCare
        )
    }
}

/// Filters for the world map and the places list
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §12).
public struct PlaceQuery: Hashable, Sendable, Codable {
    public var searchText: String
    public var year: Int?
    public var tripTypes: Set<TripType>
    public var favoritesOnly: Bool

    public static let `default` = PlaceQuery(
        searchText: "", year: nil, tripTypes: [], favoritesOnly: false
    )

    public init(
        searchText: String = "",
        year: Int? = nil,
        tripTypes: Set<TripType> = [],
        favoritesOnly: Bool = false
    ) {
        self.searchText = searchText
        self.year = year
        self.tripTypes = tripTypes
        self.favoritesOnly = favoritesOnly
    }

    public var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || year != nil
            || !tripTypes.isEmpty
            || favoritesOnly
    }
}

/// A place plus what the map and list need to filter it.
public struct PlaceListItem: Identifiable, Hashable, Sendable {
    public let place: Place
    /// Trips that visited it, most recent first.
    public let visitYears: Set<Int>
    public let tripTypes: Set<TripType>
    public let memoryCount: Int

    public var id: UUID { place.id }

    public init(
        place: Place,
        visitYears: Set<Int> = [],
        tripTypes: Set<TripType> = [],
        memoryCount: Int = 0
    ) {
        self.place = place
        self.visitYears = visitYears
        self.tripTypes = tripTypes
        self.memoryCount = memoryCount
    }
}

/// Applies a `PlaceQuery`. Pure, like the plant collection filter, and for the
/// same reason: this is where the map screen's behaviour actually lives.
public enum PlaceFilter {

    public static func apply(
        _ query: PlaceQuery,
        to items: [PlaceListItem]
    ) -> [PlaceListItem] {
        items
            .filter { matches(query, item: $0) }
            .sorted {
                $0.place.name.localizedStandardCompare($1.place.name) == .orderedAscending
            }
    }

    public static func matches(_ query: PlaceQuery, item: PlaceListItem) -> Bool {
        if query.favoritesOnly, !item.place.isFavorite { return false }

        if let year = query.year, !item.visitYears.contains(year) { return false }

        if !query.tripTypes.isEmpty, query.tripTypes.isDisjoint(with: item.tripTypes) {
            return false
        }

        let needle = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        return [item.place.name, item.place.country, item.place.notes]
            .compactMap { $0 }
            .contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }

    /// Years with at least one visit, newest first, for the filter menu.
    public static func availableYears(in items: [PlaceListItem]) -> [Int] {
        Set(items.flatMap(\.visitYears)).sorted(by: >)
    }
}
