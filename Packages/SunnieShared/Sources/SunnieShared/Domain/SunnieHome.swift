import Foundation

/// The zones of Sunnie's home (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §8).
public enum HomeZone: String, Hashable, Sendable, Codable, CaseIterable {
    case cozyRoom
    case indoorJungle
    case travelNook
    case musicCorner
    /// The window, which carries the day cycle rather than holding decor.
    case window

    public var localizationKey: String { "home.zone.\(rawValue)" }

    /// The window shows the time of day and the weather outside it; nothing is
    /// placed there.
    public var acceptsDecor: Bool { self != .window }
}

/// A place something can go (§8, "constrained placement rather than a full
/// freeform physics editor").
///
/// Slots are content, so a destination pack can add a shelf without any code
/// change, and every placement in the app is one of these — there is no
/// free-dragging path to maintain alongside it, and therefore no second
/// accessibility story to get right.
public struct DecorSlot: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let zone: HomeZone
    public let displayNameKey: String
    /// What can go here. A shelf takes small things; a wall takes art.
    public let accepts: [RewardCategory]
    /// Ordering within the zone, so the edit list is stable.
    public let order: Int

    public init(
        id: ContentID,
        zone: HomeZone,
        displayNameKey: String,
        accepts: [RewardCategory],
        order: Int
    ) {
        self.id = id
        self.zone = zone
        self.displayNameKey = displayNameKey
        self.accepts = accepts
        self.order = order
    }

    public func accepts(_ reward: RewardDefinition) -> Bool {
        accepts.contains(reward.category) && reward.fits(zone)
    }
}

/// One thing, in one slot.
public struct HomePlacement: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let slotID: ContentID
    public let rewardID: ContentID
    public let placedAt: Date

    public init(
        id: UUID = UUID(),
        slotID: ContentID,
        rewardID: ContentID,
        placedAt: Date
    ) {
        self.id = id
        self.slotID = slotID
        self.rewardID = rewardID
        self.placedAt = placedAt
    }
}

/// Everything the user has chosen about their home (§8).
///
/// A single record. Placements live separately because they are a list that
/// changes one row at a time, and merging two devices' placement edits row by
/// row is tractable in a way that merging two copies of a whole scene is not.
public struct HomeSceneState: Hashable, Sendable, Codable {
    public var equippedOutfitID: ContentID?
    /// The **reward** whose sound is playing, not the sound itself. Storing the
    /// reward keeps the scene's record in the same vocabulary as everything else
    /// the user chose, and the sound is looked up through it.
    public var selectedSoundRewardID: ContentID?
    /// Memories displayed in the travel nook, newest first.
    public var displayedMemoryIDs: [UUID]
    /// Plants shown in the indoor jungle. Real plants from the user's jungle,
    /// not decorative ones.
    public var favoritePlantIDs: [UUID]
    public var updatedAt: Date

    public init(
        equippedOutfitID: ContentID? = nil,
        selectedSoundRewardID: ContentID? = nil,
        displayedMemoryIDs: [UUID] = [],
        favoritePlantIDs: [UUID] = [],
        updatedAt: Date
    ) {
        self.equippedOutfitID = equippedOutfitID
        self.selectedSoundRewardID = selectedSoundRewardID
        self.displayedMemoryIDs = displayedMemoryIDs
        self.favoritePlantIDs = favoritePlantIDs
        self.updatedAt = updatedAt
    }

    /// How many memories and plants the nook and the jungle show.
    ///
    /// Bounded so the scene stays a scene rather than becoming a second list
    /// view of everything the user owns.
    public static let maximumDisplayedMemories = 6
    public static let maximumFavoritePlants = 5
}

/// Why placing something was refused.
///
/// Refusals are specific because a generic "can't do that" leaves the user
/// guessing which of several rules they hit.
public enum PlacementRefusal: Hashable, Sendable {
    case notOwned(ContentID)
    case slotUnknown(ContentID)
    case wrongCategory(slot: ContentID, category: RewardCategory)
    case zoneDoesNotSuit(slot: ContentID, zone: HomeZone)

    public var localizationKey: String {
        switch self {
        case .notOwned: "home.refusal.notOwned"
        case .slotUnknown: "home.refusal.slotUnknown"
        case .wrongCategory: "home.refusal.wrongCategory"
        case .zoneDoesNotSuit: "home.refusal.zoneDoesNotSuit"
        }
    }
}

/// The placement rules, as a pure function of what is owned and what fits.
public enum PlacementRules {

    /// Whether a reward may go in a slot.
    public static func check(
        reward: RewardDefinition,
        slot: DecorSlot?,
        isOwned: Bool
    ) -> PlacementRefusal? {
        guard let slot else { return .slotUnknown(reward.id) }
        guard isOwned else { return .notOwned(reward.id) }
        guard slot.accepts.contains(reward.category) else {
            return .wrongCategory(slot: slot.id, category: reward.category)
        }
        guard reward.fits(slot.zone) else {
            return .zoneDoesNotSuit(slot: slot.id, zone: slot.zone)
        }
        return nil
    }

    /// The rewards that could go in a slot, from what is owned.
    public static func candidates(
        for slot: DecorSlot, owned: [RewardDefinition]
    ) -> [RewardDefinition] {
        owned
            .filter { slot.accepts($0) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

// MARK: - Scene context

/// What the home scene is responding to right now (§9).
///
/// Every input is something the app already knows for a stated reason. There is
/// nothing inferred about how the user is doing, and nothing here reads a mood.
public struct HomeSceneContext: Hashable, Sendable {
    public let themeID: ContentID
    public let phase: TimePhase
    /// The place a current trip is to, when there is one.
    public let destinationID: ContentID?
    /// Something unlocked recently enough to still be worth showing.
    public let recentUnlockID: ContentID?
    public let season: Season

    public init(
        themeID: ContentID,
        phase: TimePhase,
        destinationID: ContentID? = nil,
        recentUnlockID: ContentID? = nil,
        season: Season
    ) {
        self.themeID = themeID
        self.phase = phase
        self.destinationID = destinationID
        self.recentUnlockID = recentUnlockID
        self.season = season
    }

    /// How recent a "recent unlock" is.
    ///
    /// Two days: long enough that something earned on Friday evening is still
    /// there on Sunday morning, short enough that the scene does not keep
    /// pointing at the same thing for a week.
    public static let recentUnlockWindow: TimeInterval = 2 * 24 * 3600
}

/// What the scene should show, resolved from context and ownership.
public struct HomeSceneVariant: Hashable, Sendable {
    public let phase: TimePhase
    public let season: Season
    /// The destination whose look the scene is wearing, if any.
    public let destinationID: ContentID?
    /// The outfit actually shown, which may be a destination outfit rather than
    /// the equipped one.
    public let outfitID: ContentID?
    /// A reward to draw attention to, once.
    public let highlightedRewardID: ContentID?
    public let visualState: SunnieVisualState

    public init(
        phase: TimePhase,
        season: Season,
        destinationID: ContentID?,
        outfitID: ContentID?,
        highlightedRewardID: ContentID?,
        visualState: SunnieVisualState
    ) {
        self.phase = phase
        self.season = season
        self.destinationID = destinationID
        self.outfitID = outfitID
        self.highlightedRewardID = highlightedRewardID
        self.visualState = visualState
    }
}

/// Chooses what the home scene shows (§9, §10).
public enum HomeSceneResolver {

    /// Resolves the scene.
    ///
    /// The destination outfit wins over the equipped one *while a trip is on*,
    /// and only if it is owned — Sunnie in a beret during a Paris trip is the
    /// point of destination packs. Outside a trip the user's choice stands,
    /// because a home that quietly overrides what someone chose is not theirs.
    public static func variant(
        context: HomeSceneContext,
        state: HomeSceneState,
        ownedRewardIDs: Set<ContentID>,
        definitions: [ContentID: RewardDefinition],
        reduceMotion: Bool
    ) -> HomeSceneVariant {
        var outfitID = state.equippedOutfitID
        if outfitID.map({ !ownedRewardIDs.contains($0) }) ?? false {
            // The equipped outfit is no longer owned — which can only happen if
            // a store was restored oddly. Fall back to none rather than showing
            // something the user does not have.
            outfitID = nil
        }

        if let destinationID = context.destinationID {
            let destinationOutfit = definitions.values.first { reward in
                reward.category == .outfit
                    && reward.destinationID == destinationID
                    && ownedRewardIDs.contains(reward.id)
            }
            if let destinationOutfit { outfitID = destinationOutfit.id }
        }

        let highlight = context.recentUnlockID.flatMap { id in
            ownedRewardIDs.contains(id) ? id : nil
        }

        return HomeSceneVariant(
            phase: context.phase,
            season: context.season,
            destinationID: context.destinationID,
            outfitID: outfitID,
            highlightedRewardID: highlight,
            visualState: SunnieVisualState(
                expression: expression(for: context),
                pose: pose(for: context),
                presence: .prominent,
                outfitID: outfitID,
                propID: highlight,
                // Reduce Motion pins this to zero rather than merely slowing it,
                // which is what the static fallback in S-22 means.
                animationIntensity: reduceMotion ? 0 : 1
            )
        )
    }

    /// Sunnie's expression at home.
    ///
    /// Driven by the hour and by whether a trip is on. Never by how much the
    /// user has done, and never by anything they have not done — there is no
    /// input here that could make him look disappointed.
    static func expression(for context: HomeSceneContext) -> SunnieExpression {
        if context.recentUnlockID != nil { return .excitedDiscovery }
        // Switched on the branded presentation rather than the internal phase, so
        // there is one behaviour per thing the user can actually see (ADR-008).
        switch context.phase.brandedPresentation {
        case .sunnieDays: return context.destinationID == nil ? .happyOpenEyed : .traveling
        case .sunnieAfternoonies: return .happyClosedEyed
        case .sunnieNights: return .sleepyHalfLidded
        }
    }

    static func pose(for context: HomeSceneContext) -> SunniePose {
        if context.destinationID != nil { return .wearingTravelUniform }
        switch context.phase.brandedPresentation {
        case .sunnieDays: return .standingNeutral
        case .sunnieAfternoonies: return .holdingMug
        case .sunnieNights: return .sleepingCurled
        }
    }
}
