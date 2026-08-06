import Foundation

/// A short illustrated scene (§11).
///
/// Panels are text today and pictures later. Story scenes are explicitly
/// optional content and must never gate a practical feature — nothing in the
/// app reads `StoryScene` to decide whether something else is available.
public struct StoryScene: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let titleKey: String
    /// One key per panel, in order.
    public let panelKeys: [String]
    public let unlockSource: UnlockSource
    public let destinationID: ContentID?

    public init(
        id: ContentID,
        titleKey: String,
        panelKeys: [String],
        unlockSource: UnlockSource,
        destinationID: ContentID? = nil
    ) {
        self.id = id
        self.titleKey = titleKey
        self.panelKeys = panelKeys
        self.unlockSource = unlockSource
        self.destinationID = destinationID
    }
}

/// A place, and the things that belong to it (§10, TRAVEL_AND_FLIGHT_ATTENDANT.md §13).
///
/// A destination pack is a grouping rather than a container: its rewards live in
/// the same list as everything else and simply carry its `destinationID`. That
/// keeps ownership flat, which is what makes ownership survive a pack being
/// removed (§12).
public struct DestinationDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let displayNameKey: String
    /// ISO region, used to match a trip's destination to this pack.
    public let regionCode: String?
    /// Country names a user might have typed for a place here, in the languages
    /// this app speaks. Free-text matching, because `Place.country` is typed by
    /// hand and "France" and "França" are the same country.
    public let countryNames: [String]
    /// The stamp granted for visiting.
    public let stampID: ContentID?
    /// The postcard template a memory from here can use.
    public let postcardID: ContentID?
    public let themeID: ContentID?

    public init(
        id: ContentID,
        displayNameKey: String,
        regionCode: String? = nil,
        countryNames: [String] = [],
        stampID: ContentID? = nil,
        postcardID: ContentID? = nil,
        themeID: ContentID? = nil
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.regionCode = regionCode
        self.countryNames = countryNames
        self.stampID = stampID
        self.postcardID = postcardID
        self.themeID = themeID
    }
}

/// The collectibles pack.
public struct CollectionPack: Hashable, Sendable, Codable {
    public let manifest: ContentPackManifest
    public let rewards: [RewardDefinition]
    public let slots: [DecorSlot]
    public let storyScenes: [StoryScene]
    public let destinations: [DestinationDefinition]

    public init(
        manifest: ContentPackManifest,
        rewards: [RewardDefinition],
        slots: [DecorSlot],
        storyScenes: [StoryScene] = [],
        destinations: [DestinationDefinition] = []
    ) {
        self.manifest = manifest
        self.rewards = rewards
        self.slots = slots
        self.storyScenes = storyScenes
        self.destinations = destinations
    }

    public func reward(id: ContentID) -> RewardDefinition? {
        rewards.first { $0.id == id }
    }

    public func slot(id: ContentID) -> DecorSlot? {
        slots.first { $0.id == id }
    }

    public func destination(id: ContentID) -> DestinationDefinition? {
        destinations.first { $0.id == id }
    }

    public func slots(in zone: HomeZone) -> [DecorSlot] {
        slots.filter { $0.zone == zone }.sorted { $0.order < $1.order }
    }

    public func rewards(in category: RewardCategory) -> [RewardDefinition] {
        rewards.filter { $0.category == category }
    }

    /// Looks a destination up by region code.
    ///
    /// Matched on region rather than on a typed place name so a trip to "Lyon"
    /// still finds the France pack.
    public func destination(regionCode: String) -> DestinationDefinition? {
        let wanted = regionCode.uppercased()
        return destinations.first { $0.regionCode?.uppercased() == wanted }
    }

    /// Looks a destination up by a country the user typed.
    ///
    /// Case- and accent-insensitive, reusing the same folding the games use, so
    /// "franca" finds França. Returns nil rather than guessing at a partial
    /// match — a wrong stamp in someone's passport is worse than no stamp.
    public func destination(countryName: String) -> DestinationDefinition? {
        let wanted = AnswerNormalizer.normalize(countryName)
        guard !wanted.isEmpty else { return nil }
        return destinations.first { destination in
            destination.countryNames.contains { AnswerNormalizer.normalize($0) == wanted }
        }
    }
}

/// Problems in a collection pack.
public enum CollectionContentIssue: Hashable, Sendable, CustomStringConvertible {
    case malformedID(String)
    case duplicateID(String)
    case missingLocalizationKey(contentID: String, field: String)
    case unsupportedSchemaVersion(pack: String, found: Int)
    /// A placeable reward that no slot in any zone can hold — owned, and with
    /// nowhere to go.
    case unplaceableReward(rewardID: String)
    /// A slot that accepts a category no reward in the pack belongs to.
    case emptySlot(slotID: String)
    case unknownDestination(rewardID: String, destinationID: String)
    case unknownReward(referencedBy: String, rewardID: String)
    /// A reward category whose action needs a value it does not have — music
    /// with no sound, a theme variant with no theme.
    case incompleteReward(rewardID: String, missing: String)
    case levelOutOfRange(rewardID: String, level: Int)

    public var description: String {
        switch self {
        case .malformedID(let id):
            "Content ID is not a dot-delimited alphanumeric string: \(id)"
        case .duplicateID(let id):
            "Duplicate content ID: \(id)"
        case .missingLocalizationKey(let contentID, let field):
            "\(contentID) has no localization key for \(field)"
        case .unsupportedSchemaVersion(let pack, let found):
            "Pack \(pack) uses schema version \(found); this build reads \(ContentPackManifest.supportedSchemaVersion)"
        case .unplaceableReward(let rewardID):
            "\(rewardID) can be placed but no slot accepts it, so owning it would do nothing"
        case .emptySlot(let slotID):
            "Slot \(slotID) accepts nothing the pack contains"
        case .unknownDestination(let rewardID, let destinationID):
            "\(rewardID) belongs to destination \(destinationID), which the pack does not define"
        case .unknownReward(let referencedBy, let rewardID):
            "\(referencedBy) refers to reward \(rewardID), which the pack does not define"
        case .incompleteReward(let rewardID, let missing):
            "\(rewardID) is missing \(missing), which its category needs"
        case .levelOutOfRange(let rewardID, let level):
            "\(rewardID) unlocks at level \(level), which is not a level anyone reaches"
        }
    }
}

/// Validates a collection pack.
///
/// The check worth naming is `unplaceableReward`. A decor item that no slot
/// accepts is worse than a missing one: the user earns it, sees it in their
/// collection, taps Place, and finds nowhere to put it. That is the app
/// promising something it cannot deliver, so it fails the tests instead.
public enum CollectionPackValidator {

    /// The highest level the reward table should gate anything behind.
    ///
    /// Not a cap on levels — those keep going. It is a cap on *unlocks*, so a
    /// typo cannot park a reward behind a level nobody reaches for years.
    public static let maximumUnlockLevel = 50

    public static func validate(_ pack: CollectionPack) -> [CollectionContentIssue] {
        var issues: [CollectionContentIssue] = []

        if pack.manifest.schemaVersion != ContentPackManifest.supportedSchemaVersion {
            issues.append(.unsupportedSchemaVersion(
                pack: pack.manifest.packID.rawValue,
                found: pack.manifest.schemaVersion
            ))
        }

        var seen = Set<String>()
        func checkID(_ id: ContentID) {
            if !id.isWellFormed { issues.append(.malformedID(id.rawValue)) }
            if !seen.insert(id.rawValue).inserted { issues.append(.duplicateID(id.rawValue)) }
        }

        let destinationIDs = Set(pack.destinations.map(\.id))
        let rewardIDs = Set(pack.rewards.map(\.id))

        for destination in pack.destinations {
            checkID(destination.id)
            if destination.displayNameKey.isEmpty {
                issues.append(.missingLocalizationKey(
                    contentID: destination.id.rawValue, field: "displayName"
                ))
            }
            for (label, referenced) in [
                ("stamp", destination.stampID), ("postcard", destination.postcardID)
            ] {
                if let referenced, !rewardIDs.contains(referenced) {
                    issues.append(.unknownReward(
                        referencedBy: "\(destination.id.rawValue).\(label)",
                        rewardID: referenced.rawValue
                    ))
                }
            }
        }

        for slot in pack.slots {
            checkID(slot.id)
            if slot.displayNameKey.isEmpty {
                issues.append(.missingLocalizationKey(
                    contentID: slot.id.rawValue, field: "displayName"
                ))
            }
            if !pack.rewards.contains(where: { slot.accepts($0) }) {
                issues.append(.emptySlot(slotID: slot.id.rawValue))
            }
        }

        for reward in pack.rewards {
            checkID(reward.id)
            let id = reward.id.rawValue

            if reward.displayNameKey.isEmpty {
                issues.append(.missingLocalizationKey(contentID: id, field: "displayName"))
            }
            if reward.descriptionKey.isEmpty {
                issues.append(.missingLocalizationKey(contentID: id, field: "description"))
            }
            if let destinationID = reward.destinationID,
               !destinationIDs.contains(destinationID) {
                issues.append(.unknownDestination(
                    rewardID: id, destinationID: destinationID.rawValue
                ))
            }
            if let level = reward.unlockSource.requiredLevel,
               level < 1 || level > maximumUnlockLevel {
                issues.append(.levelOutOfRange(rewardID: id, level: level))
            }

            switch reward.category {
            case .music, .ambience:
                if reward.soundID == nil {
                    issues.append(.incompleteReward(rewardID: id, missing: "a sound"))
                }
            case .themeVariant:
                if reward.themeID == nil {
                    issues.append(.incompleteReward(rewardID: id, missing: "a theme"))
                }
            case .decor, .decorativePlant, .destinationObject:
                if reward.zones.isEmpty {
                    issues.append(.incompleteReward(rewardID: id, missing: "a zone"))
                } else if !pack.slots.contains(where: { $0.accepts(reward) }) {
                    issues.append(.unplaceableReward(rewardID: id))
                }
            case .outfit, .postcard, .passportStamp, .souvenir, .storyScene, .gameCosmetic:
                break
            }
        }

        for scene in pack.storyScenes {
            checkID(scene.id)
            if scene.titleKey.isEmpty {
                issues.append(.missingLocalizationKey(contentID: scene.id.rawValue, field: "title"))
            }
            if scene.panelKeys.isEmpty {
                issues.append(.incompleteReward(rewardID: scene.id.rawValue, missing: "panels"))
            }
            if let destinationID = scene.destinationID, !destinationIDs.contains(destinationID) {
                issues.append(.unknownDestination(
                    rewardID: scene.id.rawValue, destinationID: destinationID.rawValue
                ))
            }
        }

        return issues
    }
}
