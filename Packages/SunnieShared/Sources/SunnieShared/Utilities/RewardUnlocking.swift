import Foundation

/// Decides which rewards a player has earned but does not yet own
/// (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §4, §7).
///
/// Pure and idempotent by construction: it takes what is true now — a level, a
/// set of event counts, a set of visited destinations, what is already owned —
/// and returns what is missing. Running it twice returns nothing the second
/// time, and running it after a store restore returns whatever the restore left
/// behind. Nothing is ever revoked, because the function only ever adds.
///
/// The key property this preserves is the one from §4: **no experience or
/// reward is removed.** There is no path here that produces a revocation, and
/// there is no input that could ask for one.
public enum RewardUnlockPlanner {

    /// What the player has done, in the form the unlock rules need.
    public struct Progress: Hashable, Sendable {
        public let level: Int
        /// How many times each kind of event has happened.
        public let eventCounts: [ProgressionEventType: Int]
        public let visitedDestinationIDs: Set<ContentID>
        /// Games with at least one finished puzzle.
        public let finishedGameIDs: Set<ContentID>
        /// Whether at least one travel memory has been saved.
        public let hasTravelMemory: Bool

        public init(
            level: Int,
            eventCounts: [ProgressionEventType: Int] = [:],
            visitedDestinationIDs: Set<ContentID> = [],
            finishedGameIDs: Set<ContentID> = [],
            hasTravelMemory: Bool = false
        ) {
            self.level = level
            self.eventCounts = eventCounts
            self.visitedDestinationIDs = visitedDestinationIDs
            self.finishedGameIDs = finishedGameIDs
            self.hasTravelMemory = hasTravelMemory
        }
    }

    /// Whether one reward's condition is met.
    public static func isEarned(_ source: UnlockSource, progress: Progress) -> Bool {
        switch source {
        case .fromTheStart:
            return true
        case .level(let required):
            return progress.level >= required
        case .firstTime(let type):
            return (progress.eventCounts[type] ?? 0) >= 1
        case .milestone(let type, let count):
            return (progress.eventCounts[type] ?? 0) >= count
        case .destination(let id):
            return progress.visitedDestinationIDs.contains(id)
        case .travelMemory:
            return progress.hasTravelMemory
        case .game(let id):
            return progress.finishedGameIDs.contains(id)
        }
    }

    /// The rewards that are earned and not yet owned.
    ///
    /// Sorted so the order a batch of unlocks is presented in is stable rather
    /// than dictionary order — a player who earns three things at once should
    /// see them the same way every time.
    public static func due(
        rewards: [RewardDefinition],
        progress: Progress,
        ownedRewardIDs: Set<ContentID>
    ) -> [RewardDefinition] {
        rewards
            .filter { !ownedRewardIDs.contains($0.id) && isEarned($0.unlockSource, progress: progress) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The story scenes that are earned and not yet seen.
    public static func dueScenes(
        scenes: [StoryScene],
        progress: Progress,
        ownedRewardIDs: Set<ContentID>
    ) -> [StoryScene] {
        scenes
            .filter { !ownedRewardIDs.contains($0.id) && isEarned($0.unlockSource, progress: progress) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The grant a due reward becomes.
    ///
    /// The deterministic key is built from the reward and its unlock source and
    /// nothing else — not the moment, not the device, not the event that
    /// happened to trigger the sweep. Two devices that both notice the same
    /// level being reached therefore produce the same key, and the second grant
    /// collapses into the first (§7).
    public static func grant(
        for reward: RewardDefinition, at date: Date, sourceEventID: UUID? = nil
    ) -> RewardGrant {
        RewardGrant(
            rewardID: reward.id,
            grantedAt: date,
            sourceEventID: sourceEventID,
            deterministicKey: ActionKeyFactory.reward(
                rewardID: reward.id,
                sourceDeterministicKey: unlockKey(reward.unlockSource)
            )
        )
    }

    /// A stable string for an unlock source, used inside the grant key.
    static func unlockKey(_ source: UnlockSource) -> String {
        switch source {
        case .fromTheStart: "fromTheStart"
        case .level(let level): "level|\(level)"
        case .firstTime(let type): "firstTime|\(type.rawValue)"
        case .milestone(let type, let count): "milestone|\(type.rawValue)|\(count)"
        case .destination(let id): "destination|\(id.rawValue)"
        case .travelMemory: "travelMemory"
        case .game(let id): "game|\(id.rawValue)"
        }
    }

    /// The next thing coming, for the "what's next" line on the collection
    /// screen.
    ///
    /// Returns the nearest level-gated reward above the current level. Only
    /// level unlocks qualify because only they have a number the user can see
    /// themselves approaching — "visit Paris" is a plan, not a progress bar, and
    /// showing it as one would invent a deadline nobody set.
    public static func nextLevelUnlock(
        rewards: [RewardDefinition], level: Int
    ) -> (reward: RewardDefinition, level: Int)? {
        rewards
            .compactMap { reward -> (RewardDefinition, Int)? in
                guard let required = reward.unlockSource.requiredLevel, required > level else {
                    return nil
                }
                return (reward, required)
            }
            .min { left, right in
                left.1 != right.1 ? left.1 < right.1 : left.0.id.rawValue < right.0.id.rawValue
            }
            .map { (reward: $0.0, level: $0.1) }
    }
}

/// Turns a saved travel memory into its stamp and postcard
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §11, PROGRESSION §6).
///
/// Kept separate from the level-based planner because the trigger is different:
/// a memory is a specific thing the user made about a specific place, and the
/// stamp belongs to that place rather than to a threshold.
public enum TravelKeepsakes {

    /// What a memory earns.
    public struct Keepsakes: Hashable, Sendable {
        public let stampID: ContentID?
        public let postcardID: ContentID?

        public var isEmpty: Bool { stampID == nil && postcardID == nil }

        public init(stampID: ContentID?, postcardID: ContentID?) {
            self.stampID = stampID
            self.postcardID = postcardID
        }
    }

    /// The stamp and postcard for a memory, from the destination it is about.
    ///
    /// A memory from somewhere with no destination pack earns nothing rather
    /// than a generic stamp. A passport full of identical blank stamps is worse
    /// than a passport with gaps in it.
    public static func keepsakes(
        for destination: DestinationDefinition?
    ) -> Keepsakes {
        Keepsakes(stampID: destination?.stampID, postcardID: destination?.postcardID)
    }

    /// The grant a keepsake becomes.
    ///
    /// Both the stamp and the postcard are keyed on the **destination**, not on
    /// the memory that triggered them. The postcard is a template the memory
    /// then uses — `TravelMemory.postcardID` refers to it — so a second trip to
    /// Lisbon does not grant a second identical postcard that the collection
    /// would have to explain. Six memories from Lisbon are six memories, sharing
    /// one stamp and one template.
    ///
    /// This is also what makes saving a memory idempotent: editing and
    /// re-saving it produces the same two keys, which collapse into the grants
    /// already there.
    public static func grant(
        rewardID: ContentID, destinationID: ContentID, kind: Kind, at date: Date
    ) -> RewardGrant {
        RewardGrant(
            rewardID: rewardID,
            grantedAt: date,
            sourceEventID: nil,
            deterministicKey: ActionKeyFactory.reward(
                rewardID: rewardID,
                sourceDeterministicKey: "\(kind.rawValue)|\(destinationID.rawValue)"
            )
        )
    }

    public enum Kind: String, Hashable, Sendable {
        case stamp
        case postcard
    }

    /// Every grant a memory from this destination earns, in a stable order.
    public static func grants(
        for destination: DestinationDefinition, at date: Date
    ) -> [RewardGrant] {
        var grants: [RewardGrant] = []
        if let stampID = destination.stampID {
            grants.append(grant(
                rewardID: stampID, destinationID: destination.id, kind: .stamp, at: date
            ))
        }
        if let postcardID = destination.postcardID {
            grants.append(grant(
                rewardID: postcardID, destinationID: destination.id, kind: .postcard, at: date
            ))
        }
        return grants
    }
}
