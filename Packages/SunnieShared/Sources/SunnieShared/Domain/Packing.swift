import Foundation

/// Packing categories (TRAVEL_AND_FLIGHT_ATTENDANT.md §4, §6).
///
/// The work/personal/food split is the spec's own, and it is an operational need
/// rather than a nicety: someone packing for a four-day trip is answering three
/// different questions, and mixing them makes the list harder to work through.
public enum PackingCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case uniform
    case work
    case personal
    case toiletries
    case technology
    case food
    case documents
    case other

    public var localizationKey: String { "packing.category.\(rawValue)" }

    /// The three top-level sections the packing screen separates.
    public var section: Section {
        switch self {
        case .uniform, .work, .documents: .work
        case .food: .food
        case .personal, .toiletries, .technology, .other: .personal
        }
    }

    public enum Section: String, Hashable, Sendable, Codable, CaseIterable {
        case work
        case personal
        case food

        public var localizationKey: String { "packing.section.\(rawValue)" }
    }
}

/// One line on a packing list.
public struct PackingItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let tripID: UUID
    public var name: String
    public var category: PackingCategory
    public var quantity: Int
    /// Marked by the user, or carried in from a template. Never enforced —
    /// nothing refuses to let someone leave with a "required" item unpacked.
    public var isRequired: Bool
    public var isPacked: Bool
    public var notes: String?
    /// Set when the item came from a weather-driven suggestion, so the UI can say
    /// where it came from. Suggestions are always added with confirmation
    /// (TRAVEL_AND_FLIGHT_ATTENDANT.md §9).
    public var suggestionReason: String?
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        name: String,
        category: PackingCategory = .personal,
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
        self.category = category
        self.quantity = max(1, quantity)
        self.isRequired = isRequired
        self.isPacked = isPacked
        self.notes = notes
        self.suggestionReason = suggestionReason
        self.sortOrder = sortOrder
    }
}

/// A reusable packing list.
///
/// Templates are the point of the whole feature for someone who flies weekly:
/// the same fifteen things every time, and reusing last trip's list should be one
/// tap.
public struct PackingTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    /// Offered first for trips of this type. Nil means it suits any trip.
    public var tripType: TripType?
    public var entries: [Entry]
    /// Built in rather than user-created. Editable, but restored if deleted.
    public var isBuiltIn: Bool
    public let createdAt: Date
    public var modifiedAt: Date

    public struct Entry: Identifiable, Hashable, Sendable, Codable {
        public let id: UUID
        public var name: String
        public var category: PackingCategory
        public var quantity: Int
        public var isRequired: Bool

        public init(
            id: UUID = UUID(),
            name: String,
            category: PackingCategory = .personal,
            quantity: Int = 1,
            isRequired: Bool = false
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.quantity = max(1, quantity)
            self.isRequired = isRequired
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        tripType: TripType? = nil,
        entries: [Entry] = [],
        isBuiltIn: Bool = false,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.tripType = tripType
        self.entries = entries
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Turns templates into trip lists, and spots duplicates
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §6).
///
/// Pure, so applying a template twice, merging two templates, and reusing a past
/// trip are all testable as list transformations.
public enum PackingListBuilder {

    /// Applies a template to a trip, skipping anything already on the list.
    ///
    /// Duplicate detection matches on name and category, case- and
    /// diacritic-insensitively. Applying the same template twice adds nothing the
    /// second time, which is what makes "reuse last trip's list" safe to tap when
    /// you are not sure whether you already did.
    ///
    /// Existing items are never modified: an item already ticked stays ticked,
    /// and a quantity the user changed is not reset by re-applying the template
    /// it came from.
    public static func applying(
        _ template: PackingTemplate,
        to existing: [PackingItem],
        tripID: UUID
    ) -> [PackingItem] {
        var added: [PackingItem] = []
        var seen = Set(existing.map(key))
        var order = (existing.map(\.sortOrder).max() ?? -1) + 1

        for entry in template.entries {
            let entryKey = key(name: entry.name, category: entry.category)
            guard !seen.contains(entryKey) else { continue }
            seen.insert(entryKey)

            added.append(PackingItem(
                tripID: tripID,
                name: entry.name,
                category: entry.category,
                quantity: entry.quantity,
                isRequired: entry.isRequired,
                sortOrder: order
            ))
            order += 1
        }

        return added
    }

    /// Copies a past trip's list, unpacked and without its notes.
    ///
    /// Notes are dropped deliberately: "the blue one, in the side pocket" was
    /// true last time and is noise now. Quantities and required flags carry over,
    /// because those are about the trip shape rather than that trip's details.
    public static func reusing(
        _ items: [PackingItem],
        for tripID: UUID
    ) -> [PackingItem] {
        items.enumerated().map { index, item in
            PackingItem(
                tripID: tripID,
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                isRequired: item.isRequired,
                isPacked: false,
                sortOrder: index
            )
        }
    }

    /// Items that look like duplicates of each other, grouped.
    ///
    /// Surfaced rather than merged — two entries called "charger" might be two
    /// genuinely different chargers, and silently combining them would lose one.
    public static func duplicateGroups(in items: [PackingItem]) -> [[PackingItem]] {
        Dictionary(grouping: items, by: key)
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.sortOrder < $1.sortOrder } }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
    }

    /// Progress within a section, as counts rather than a percentage.
    ///
    /// "6 of 10" says what is left; "60%" invites a judgement about the other
    /// four. Nothing on the packing screen implies the user is behind.
    public static func progress(
        for items: [PackingItem],
        in section: PackingCategory.Section? = nil
    ) -> (packed: Int, total: Int) {
        let scoped = section.map { s in items.filter { $0.category.section == s } } ?? items
        return (scoped.filter(\.isPacked).count, scoped.count)
    }

    private static func key(_ item: PackingItem) -> String {
        key(name: item.name, category: item.category)
    }

    private static func key(name: String, category: PackingCategory) -> String {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return "\(category.rawValue)|\(normalized)"
    }
}

/// The routines a trip moves through (TRAVEL_AND_FLIGHT_ATTENDANT.md §4, §7).
///
/// **None of these is an airline procedure.** They are the user's own reminders
/// to themselves, and no copy anywhere may present them as official
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §1, §7).
public enum ChecklistKind: String, Hashable, Sendable, Codable, CaseIterable {
    case beforeLeaving
    case airport
    case hotelArrival
    case layoverReset
    case wakeUp
    case departure
    case returnHome
    case recovery

    public var localizationKey: String { "checklist.kind.\(rawValue)" }

    /// Which end of the trip this belongs to, so the trip screen offers the
    /// right ones at the right time rather than all eight at once.
    public var phase: Phase {
        switch self {
        case .beforeLeaving, .airport, .departure: .leaving
        case .hotelArrival, .layoverReset, .wakeUp: .away
        case .returnHome, .recovery: .returning
        }
    }

    public enum Phase: String, Hashable, Sendable, Codable, CaseIterable {
        case leaving
        case away
        case returning
    }
}

/// One line on a checklist.
public struct ChecklistItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let tripID: UUID
    public var kind: ChecklistKind
    public var title: String
    public var isDone: Bool
    public var notes: String?
    /// Links a checklist line to something the app already knows about — plant
    /// coverage, packed food — so ticking it can open the real screen rather than
    /// asking the user to remember what it referred to.
    public var linkedRoute: String?
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        kind: ChecklistKind,
        title: String,
        isDone: Bool = false,
        notes: String? = nil,
        linkedRoute: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.tripID = tripID
        self.kind = kind
        self.title = title
        self.isDone = isDone
        self.notes = notes
        self.linkedRoute = linkedRoute
        self.sortOrder = sortOrder
    }
}

/// Something worth remembering (TRAVEL_AND_FLIGHT_ATTENDANT.md §11).
///
/// A past trip may have nothing but these — no itinerary, no packing list. The
/// memory is the point; the planning was only ever scaffolding.
public struct TravelMemory: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var tripID: UUID?
    public var placeID: UUID?
    public var occurredAt: Date
    public var title: String?
    public var text: String?
    public var isFavorite: Bool
    public var tags: [String]
    /// Set when the user turned this into a postcard or earned a stamp for it.
    public var postcardID: ContentID?
    public var stampID: ContentID?
    public var linkedJournalEntryID: UUID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        placeID: UUID? = nil,
        occurredAt: Date,
        title: String? = nil,
        text: String? = nil,
        isFavorite: Bool = false,
        tags: [String] = [],
        postcardID: ContentID? = nil,
        stampID: ContentID? = nil,
        linkedJournalEntryID: UUID? = nil,
        createdAt: Date,
        modifiedAt: Date
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

    /// Photos attach to the memory, so they live with what they were about.
    public var mediaOwner: MediaOwner? {
        tripID.map(MediaOwner.trip)
    }

    public var hasContent: Bool {
        !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || placeID != nil
    }
}
