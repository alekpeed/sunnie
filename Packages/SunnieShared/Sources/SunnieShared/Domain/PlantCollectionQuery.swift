import Foundation

/// How the collection is sorted (PLANT_CARE.md §6).
public enum PlantSortOrder: String, Hashable, Sendable, Codable, CaseIterable {
    case name
    case nextDue
    case lastCare
    case acquiredDate

    public var localizationKey: String { "collection.sort.\(rawValue)" }
}

public enum PlantPresentationMode: String, Hashable, Sendable, Codable, CaseIterable {
    case list
    case grid
}

/// Everything the collection screen is filtering and sorting by.
///
/// One value rather than a dozen properties on a view model, because it is
/// persisted between launches (filter state must survive a tab switch —
/// INFORMATION_ARCHITECTURE.md §14) and because it makes the filtering itself a
/// pure function that can be tested without a store or a screen.
public struct PlantCollectionQuery: Hashable, Sendable, Codable {
    public var searchText: String
    public var locationIDs: Set<UUID>
    public var species: Set<String>
    public var statuses: Set<PlantStatus>
    public var careTypes: Set<CareType>
    public var caretakerIDs: Set<UUID>
    /// Show only plants with something due within this many days. Nil means no
    /// due filter at all.
    public var dueWithinDays: Int?
    public var sortOrder: PlantSortOrder
    public var mode: PlantPresentationMode

    /// The default view: everything active, by name, as a list.
    ///
    /// Archived plants are excluded by default rather than removed — archiving is
    /// how a plant leaves the daily view without its history being destroyed.
    public static let `default` = PlantCollectionQuery(
        searchText: "",
        locationIDs: [],
        species: [],
        statuses: [.active],
        careTypes: [],
        caretakerIDs: [],
        dueWithinDays: nil,
        sortOrder: .name,
        mode: .list
    )

    public init(
        searchText: String = "",
        locationIDs: Set<UUID> = [],
        species: Set<String> = [],
        statuses: Set<PlantStatus> = [.active],
        careTypes: Set<CareType> = [],
        caretakerIDs: Set<UUID> = [],
        dueWithinDays: Int? = nil,
        sortOrder: PlantSortOrder = .name,
        mode: PlantPresentationMode = .list
    ) {
        self.searchText = searchText
        self.locationIDs = locationIDs
        self.species = species
        self.statuses = statuses
        self.careTypes = careTypes
        self.caretakerIDs = caretakerIDs
        self.dueWithinDays = dueWithinDays
        self.sortOrder = sortOrder
        self.mode = mode
    }

    /// Whether anything is narrowing the results.
    ///
    /// Drives the "filters are on" indicator. Without it, a filter left on from
    /// last week looks like a collection that lost half its plants. Sort order and
    /// presentation mode are deliberately excluded — neither hides anything.
    public var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !locationIDs.isEmpty
            || !species.isEmpty
            || !careTypes.isEmpty
            || !caretakerIDs.isEmpty
            || dueWithinDays != nil
            || statuses != PlantCollectionQuery.default.statuses
    }

    /// How many distinct filters are on, for a badge next to the filter control.
    public var activeFilterCount: Int {
        var count = 0
        if !locationIDs.isEmpty { count += 1 }
        if !species.isEmpty { count += 1 }
        if !careTypes.isEmpty { count += 1 }
        if !caretakerIDs.isEmpty { count += 1 }
        if dueWithinDays != nil { count += 1 }
        if statuses != PlantCollectionQuery.default.statuses { count += 1 }
        return count
    }

    /// Clears the filters but keeps how the user likes to look at the collection.
    /// Sort order and grid/list are preferences, not filters, and resetting them
    /// alongside would be an unasked-for change.
    public func clearingFilters() -> PlantCollectionQuery {
        var cleared = PlantCollectionQuery.default
        cleared.sortOrder = sortOrder
        cleared.mode = mode
        return cleared
    }
}

/// One plant plus the facts the collection screen needs to filter and sort it.
///
/// Assembled once by the repository so filtering does not have to go back to
/// storage per plant — the difference between one query and 100 at fifty-plus
/// plants (PLANT_CARE.md §1).
public struct PlantCollectionItem: Identifiable, Hashable, Sendable {
    public let plant: Plant
    public let locationName: String?
    /// Soonest due date across the plant's enabled schedules, if any.
    public let nextDueDate: Date?
    public let lastCareAt: Date?
    /// Care types this plant has an enabled schedule for.
    public let scheduledCareTypes: Set<CareType>
    /// Caretakers assigned to this plant on any trip.
    public let caretakerIDs: Set<UUID>
    /// Unresolved health observations, for the "needs attention" section.
    public let openObservationCount: Int

    public var id: UUID { plant.id }

    public init(
        plant: Plant,
        locationName: String? = nil,
        nextDueDate: Date? = nil,
        lastCareAt: Date? = nil,
        scheduledCareTypes: Set<CareType> = [],
        caretakerIDs: Set<UUID> = [],
        openObservationCount: Int = 0
    ) {
        self.plant = plant
        self.locationName = locationName
        self.nextDueDate = nextDueDate
        self.lastCareAt = lastCareAt
        self.scheduledCareTypes = scheduledCareTypes
        self.caretakerIDs = caretakerIDs
        self.openObservationCount = openObservationCount
    }
}

/// Applies a `PlantCollectionQuery` to a list of items.
///
/// Pure and synchronous. All the collection-management behaviour — every filter,
/// every sort, the search-matching rules — is tested here against arrays, with no
/// store, no screen, and no timing.
public enum PlantCollectionFilter {

    public static func apply(
        _ query: PlantCollectionQuery,
        to items: [PlantCollectionItem],
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [PlantCollectionItem] {
        let matched = items.filter { matches(query, item: $0, now: now, calendar: calendar, timeZone: timeZone) }
        return sort(matched, by: query.sortOrder)
    }

    public static func matches(
        _ query: PlantCollectionQuery,
        item: PlantCollectionItem,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Bool {
        // An empty status set means "no status is acceptable", which would show
        // nothing and read as a broken screen. Treated as unfiltered instead.
        if !query.statuses.isEmpty, !query.statuses.contains(item.plant.status) {
            return false
        }

        if !query.locationIDs.isEmpty {
            guard let locationID = item.plant.locationID,
                  query.locationIDs.contains(locationID)
            else { return false }
        }

        if !query.species.isEmpty {
            guard let species = item.plant.speciesName,
                  query.species.contains(where: { $0.caseInsensitiveCompare(species) == .orderedSame })
            else { return false }
        }

        if !query.careTypes.isEmpty {
            guard !query.careTypes.isDisjoint(with: item.scheduledCareTypes) else {
                return false
            }
        }

        if !query.caretakerIDs.isEmpty {
            guard !query.caretakerIDs.isDisjoint(with: item.caretakerIDs) else {
                return false
            }
        }

        if let dueWithinDays = query.dueWithinDays {
            guard let nextDue = item.nextDueDate else { return false }
            var zoned = calendar
            zoned.timeZone = timeZone
            guard let horizon = zoned.date(
                byAdding: .day, value: dueWithinDays, to: zoned.startOfDay(for: now)
            ) else { return false }
            // Already-waiting tasks are inside every window: a plant that needed
            // water yesterday certainly needs it in the next seven days.
            guard nextDue < horizon else { return false }
        }

        return matchesSearch(query.searchText, item: item)
    }

    /// Search covers the fields someone would actually type: name, nickname,
    /// species, variety, room, and notes. Case- and diacritic-insensitive, so
    /// "monstera" finds "Monstera" and "Sanseviéria" is reachable by typing
    /// "sanseviera".
    public static func matchesSearch(_ text: String, item: PlantCollectionItem) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        let haystacks: [String?] = [
            item.plant.name,
            item.plant.nickname,
            item.plant.speciesName,
            item.plant.variety,
            item.locationName,
            item.plant.notes
        ]

        return haystacks.compactMap { $0 }.contains { field in
            field.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    public static func sort(
        _ items: [PlantCollectionItem],
        by order: PlantSortOrder
    ) -> [PlantCollectionItem] {
        switch order {
        case .name:
            items.sorted { byName($0, $1) }

        case .nextDue:
            // Plants with nothing scheduled sort last rather than first. They are
            // not urgent, and putting "nothing due" at the top of a list sorted by
            // due date would be actively unhelpful.
            items.sorted { lhs, rhs in
                switch (lhs.nextDueDate, rhs.nextDueDate) {
                case let (l?, r?): l == r ? byName(lhs, rhs) : l < r
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): byName(lhs, rhs)
                }
            }

        case .lastCare:
            // Longest since last care first — that is what someone sorting by
            // "last care" is looking for. Never cared for at all sorts first of
            // all, for the same reason.
            items.sorted { lhs, rhs in
                switch (lhs.lastCareAt, rhs.lastCareAt) {
                case let (l?, r?): l == r ? byName(lhs, rhs) : l < r
                case (nil, _?): true
                case (_?, nil): false
                case (nil, nil): byName(lhs, rhs)
                }
            }

        case .acquiredDate:
            // Newest first: a plant acquired last week is the one you are
            // wondering about. Unknown acquisition dates sort last.
            items.sorted { lhs, rhs in
                switch (lhs.plant.acquiredDate, rhs.plant.acquiredDate) {
                case let (l?, r?): l == r ? byName(lhs, rhs) : l > r
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): byName(lhs, rhs)
                }
            }
        }
    }

    /// Name comparison used both directly and as the tiebreaker everywhere else,
    /// so equal sort keys never produce an unstable order between refreshes.
    /// Falls back to the ID so two plants genuinely called the same thing still
    /// have a fixed order (PLANT_CARE.md §15, duplicate names).
    private static func byName(_ lhs: PlantCollectionItem, _ rhs: PlantCollectionItem) -> Bool {
        let comparison = lhs.plant.displayName.localizedStandardCompare(rhs.plant.displayName)
        if comparison == .orderedSame {
            return lhs.plant.id.uuidString < rhs.plant.id.uuidString
        }
        return comparison == .orderedAscending
    }
}
