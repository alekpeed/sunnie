import Foundation

/// What a reward is (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §6).
///
/// The category decides where a reward appears and what can be done with it —
/// an outfit is equipped, decor is placed, music is played, a stamp is looked
/// at. It is not a rarity tier, and there is deliberately no such thing here.
public enum RewardCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case outfit
    case decor
    case decorativePlant
    case postcard
    case passportStamp
    case souvenir
    case music
    case ambience
    case storyScene
    case themeVariant
    case destinationObject
    case gameCosmetic

    public var localizationKey: String { "reward.category.\(rawValue)" }

    /// What the collection screen offers for this category.
    public var action: Action {
        switch self {
        case .outfit: .equip
        case .decor, .decorativePlant, .destinationObject: .place
        case .music, .ambience: .play
        case .postcard, .passportStamp, .souvenir, .storyScene: .view
        case .themeVariant: .apply
        case .gameCosmetic: .view
        }
    }

    public enum Action: String, Hashable, Sendable {
        case equip
        case place
        case play
        case view
        case apply

        public var localizationKey: String { "reward.action.\(rawValue)" }
    }
}

/// Why something was unlocked (§7, "rewards explain their source").
///
/// Every reward carries one. A collection where things simply appear teaches the
/// user that the app is arbitrary, and an unlock nobody can explain is
/// indistinguishable from a bug.
public enum UnlockSource: Hashable, Sendable, Codable {
    /// Owned from the first launch. Not everything has to be earned.
    case fromTheStart
    /// Reaching a level.
    case level(Int)
    /// The first time a kind of thing happened.
    case firstTime(ProgressionEventType)
    /// A count of a kind of thing.
    case milestone(ProgressionEventType, count: Int)
    /// Visiting somewhere. The place is a content ID, so a destination pack can
    /// bring its own rewards.
    case destination(ContentID)
    /// Saving a memory from a trip.
    case travelMemory
    /// Finishing a particular game.
    case game(ContentID)

    /// The key the UI uses to say where this came from, filled with the
    /// associated value where there is one.
    public var localizationKey: String {
        switch self {
        case .fromTheStart: "unlock.source.fromTheStart"
        case .level: "unlock.source.level"
        case .firstTime: "unlock.source.firstTime"
        case .milestone: "unlock.source.milestone"
        case .destination: "unlock.source.destination"
        case .travelMemory: "unlock.source.travelMemory"
        case .game: "unlock.source.game"
        }
    }

    /// The level this becomes available at, when that is what gates it.
    public var requiredLevel: Int? {
        if case .level(let level) = self { return level }
        return nil
    }
}

/// One collectible, as content (§6, §7).
public struct RewardDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let category: RewardCategory
    public let displayNameKey: String
    public let descriptionKey: String
    public let unlockSource: UnlockSource
    /// The art this will use once it exists. Nil means the neutral placeholder,
    /// which is the honest state for most of these today (§12).
    public let assetID: ContentID?
    /// Set for rewards that belong to a place, so a destination pack's
    /// collectibles group together.
    public let destinationID: ContentID?
    /// Which home zones a placeable reward may go in. Empty for anything that is
    /// not placed.
    public let zones: [HomeZone]
    /// For music and ambience: the sound this plays.
    public let soundID: ContentID?
    /// For theme variants: the theme this applies.
    public let themeID: ContentID?

    public init(
        id: ContentID,
        category: RewardCategory,
        displayNameKey: String,
        descriptionKey: String,
        unlockSource: UnlockSource,
        assetID: ContentID? = nil,
        destinationID: ContentID? = nil,
        zones: [HomeZone] = [],
        soundID: ContentID? = nil,
        themeID: ContentID? = nil
    ) {
        self.id = id
        self.category = category
        self.displayNameKey = displayNameKey
        self.descriptionKey = descriptionKey
        self.unlockSource = unlockSource
        self.assetID = assetID
        self.destinationID = destinationID
        self.zones = zones
        self.soundID = soundID
        self.themeID = themeID
    }

    /// Whether this can go in a particular zone.
    public func fits(_ zone: HomeZone) -> Bool {
        zones.contains(zone)
    }
}

/// A reward plus whether it is owned — one row of the collection screen (S-21).
///
/// Locked items are shown, not hidden. Seeing what exists and what unlocks it is
/// the point of a collection; hiding it turns the screen into a list of things
/// already done.
public struct CollectionItem: Identifiable, Hashable, Sendable {
    public let definition: RewardDefinition
    public let grantedAt: Date?
    /// True when the reward is owned but no definition in any installed pack
    /// describes it. Ownership outlives the pack that granted it (§12).
    public let isOrphaned: Bool

    public var id: ContentID { definition.id }
    public var isOwned: Bool { grantedAt != nil }

    public init(definition: RewardDefinition, grantedAt: Date?, isOrphaned: Bool = false) {
        self.definition = definition
        self.grantedAt = grantedAt
        self.isOrphaned = isOrphaned
    }
}

/// How the collection is being looked at (S-21).
public struct CollectionFilter: Hashable, Sendable, Codable {
    public enum Ownership: String, Hashable, Sendable, Codable, CaseIterable {
        case all
        case owned
        case locked

        public var localizationKey: String { "collection.ownership.\(rawValue)" }
    }

    public var category: RewardCategory?
    public var ownership: Ownership
    public var destinationID: ContentID?

    public init(
        category: RewardCategory? = nil,
        ownership: Ownership = .all,
        destinationID: ContentID? = nil
    ) {
        self.category = category
        self.ownership = ownership
        self.destinationID = destinationID
    }

    public static let everything = CollectionFilter()

    public func matches(_ item: CollectionItem) -> Bool {
        if let category, item.definition.category != category { return false }
        if let destinationID, item.definition.destinationID != destinationID { return false }
        switch ownership {
        case .all: return true
        case .owned: return item.isOwned
        case .locked: return !item.isOwned
        }
    }
}

/// Builds the collection view from definitions and grants.
///
/// Pure, so the ordering rules and the orphan handling are testable without a
/// store.
public enum CollectionBuilder {

    /// Owned first, then locked, each in a stable order.
    ///
    /// Locked items sort by how close they are — the level they need, then the
    /// name — so the list reads as "here is what is next" rather than as an
    /// arbitrary backlog.
    public static func items(
        definitions: [RewardDefinition],
        grants: [RewardGrant]
    ) -> [CollectionItem] {
        var grantedAt: [ContentID: Date] = [:]
        for grant in grants {
            // Keep the earliest grant: a reward granted twice through two paths
            // was first owned at the earlier moment, and that is the date the
            // collection should show.
            if let existing = grantedAt[grant.rewardID], existing <= grant.grantedAt { continue }
            grantedAt[grant.rewardID] = grant.grantedAt
        }

        var items = definitions.map { definition in
            CollectionItem(definition: definition, grantedAt: grantedAt[definition.id])
        }

        // Anything owned that no installed pack describes still appears, as
        // itself, rather than vanishing from the collection (§12).
        let described = Set(definitions.map(\.id))
        for (rewardID, date) in grantedAt where !described.contains(rewardID) {
            items.append(
                CollectionItem(
                    definition: RewardDefinition(
                        id: rewardID,
                        category: .souvenir,
                        displayNameKey: "collection.orphan.name",
                        descriptionKey: "collection.orphan.description",
                        unlockSource: .fromTheStart
                    ),
                    grantedAt: date,
                    isOrphaned: true
                )
            )
        }

        return items.sorted { left, right in
            if left.isOwned != right.isOwned { return left.isOwned }
            if let a = left.grantedAt, let b = right.grantedAt, a != b { return a > b }
            let leftLevel = left.definition.unlockSource.requiredLevel ?? Int.max
            let rightLevel = right.definition.unlockSource.requiredLevel ?? Int.max
            if leftLevel != rightLevel { return leftLevel < rightLevel }
            return left.definition.id.rawValue < right.definition.id.rawValue
        }
    }

    /// Counts per category, for the filter row.
    public static func counts(
        _ items: [CollectionItem]
    ) -> [RewardCategory: (owned: Int, total: Int)] {
        var counts: [RewardCategory: (owned: Int, total: Int)] = [:]
        for item in items {
            var entry = counts[item.definition.category] ?? (0, 0)
            entry.total += 1
            if item.isOwned { entry.owned += 1 }
            counts[item.definition.category] = entry
        }
        return counts
    }
}

// MARK: - Rhythm

/// Repeated activity, described without a streak (§5).
///
/// The distinction is the whole of it: this counts days on which something
/// happened, and it never counts days on which nothing did. There is no current
/// run to break, so a gap changes the number and nothing else — and `best` is
/// kept because a personal best is a thing that happened, not a bar to clear
/// again.
public struct RhythmSummary: Hashable, Sendable, Codable {
    /// Distinct days with at least one recorded action, this week.
    public let daysThisWeek: Int
    /// Days in the week so far, so "3 of 5" reads honestly mid-week.
    public let daysSoFar: Int
    /// The most days in any single week, ever.
    public let bestWeek: Int
    /// The user's choice to see any of this at all (§5).
    public let isVisible: Bool

    public init(daysThisWeek: Int, daysSoFar: Int, bestWeek: Int, isVisible: Bool) {
        self.daysThisWeek = daysThisWeek
        self.daysSoFar = daysSoFar
        self.bestWeek = bestWeek
        self.isVisible = isVisible
    }

    /// Whether this week matches the best ever.
    ///
    /// Used only to say something warm when it is true. There is deliberately no
    /// `isBelowBest`, because that would be the comparison §5 forbids.
    public var matchesBest: Bool {
        bestWeek > 0 && daysThisWeek >= bestWeek
    }
}

/// Counts caring days from recorded events.
public enum RhythmCalculator {

    /// Days in the current week with at least one event.
    ///
    /// Takes the events rather than a stored counter, so there is no running
    /// total that a missed day could reset — the number is recomputed from what
    /// happened, every time.
    public static func summary(
        eventDates: [Date],
        now: Date,
        calendar: Calendar,
        isVisible: Bool
    ) -> RhythmSummary {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return RhythmSummary(
                daysThisWeek: 0, daysSoFar: 1, bestWeek: 0, isVisible: isVisible
            )
        }

        var daysByWeek: [Date: Set<Date>] = [:]
        for date in eventDates {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { continue }
            daysByWeek[interval.start, default: []].insert(calendar.startOfDay(for: date))
        }

        let thisWeek = daysByWeek[week.start]?.count ?? 0
        let best = daysByWeek.values.map(\.count).max() ?? 0
        let soFar = (calendar.dateComponents(
            [.day], from: week.start, to: calendar.startOfDay(for: now)
        ).day ?? 0) + 1

        return RhythmSummary(
            daysThisWeek: thisWeek,
            daysSoFar: max(1, min(7, soFar)),
            bestWeek: best,
            isVisible: isVisible
        )
    }
}
