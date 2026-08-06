import Foundation

/// Turns domain events into experience and rewards, exactly once each.
///
/// Two guards sit in front of every award, and both are ordinary outcomes rather
/// than errors:
///
/// 1. **Idempotency.** The deterministic key derives from the source action, so a
///    replayed Watch transfer or a double-tap evaluates to the same key and the
///    second attempt is a no-op.
/// 2. **Plausibility.** Repeating the same care within an implausibly short
///    window earns nothing, so rewards cannot be farmed by tapping Water ten
///    times (PLANT_CARE.md §13). The care event itself is still recorded — the
///    user's record of what they did is never refused.
///
/// Nothing here can ever take something away. There is no decay, no expiry, and
/// no penalty for a gap (MASTER_SOURCE_OF_TRUTH.md §8).
public struct ProgressionEngine: Sendable {

    private let repository: any ProgressionRepository
    private let rules: RewardRules

    public init(repository: any ProgressionRepository, rules: RewardRules = .standard) {
        self.repository = repository
        self.rules = rules
    }

    /// Experience and reward table. Data rather than branching, so Phase 8 can
    /// move it into a content pack without changing this engine.
    public struct RewardRules: Sendable {
        public var experience: [ProgressionEventType: Int]
        /// Rewards granted the first time an event type occurs.
        public var firstTimeRewards: [ProgressionEventType: ContentID]
        public var experiencePerLevel: Int

        public static let standard = RewardRules(
            experience: [
                .plantCareCompleted: 10,
                .firstPlantAdded: 25,
                .plantCollectionMilestone: 40,
                .growthPhotoMilestone: 20,
                .travelCoverageCompleted: 35,
                .plantHealthIssueResolved: 30,
                .wellnessCheckInRecorded: 10,
                .puzzleCompleted: 15,
                .dailyPuzzleCompleted: 25,
                .mealsPlanned: 15,
                .mealPrepCompleted: 20,
                .tripMemorySaved: 20,
                .destinationVisited: 40
            ],
            firstTimeRewards: [
                .firstPlantAdded: "sunnie.reward.collectible.firstSprout",
                .plantCareCompleted: "sunnie.reward.collectible.wateringCan",
                .puzzleCompleted: "sunnie.reward.collectible.luggageTag"
            ],
            experiencePerLevel: 100
        )

        public init(
            experience: [ProgressionEventType: Int],
            firstTimeRewards: [ProgressionEventType: ContentID],
            experiencePerLevel: Int
        ) {
            self.experience = experience
            self.firstTimeRewards = firstTimeRewards
            self.experiencePerLevel = experiencePerLevel
        }
    }

    /// Evaluates one care completion.
    ///
    /// `previousCareAt` is the timestamp of the last event of the same care type
    /// on the same plant *before* this one, used for the plausibility check.
    public func evaluatePlantCare(
        actionKey: ActionKey,
        plantID: UUID,
        careType: CareType,
        performedAt: Date,
        previousCareAt: Date?
    ) async throws -> ProgressionOutcome {
        let key = ActionKeyFactory.progression(
            type: .plantCareCompleted,
            sourceActionKey: actionKey
        )

        if let existing = try await repository.event(deterministicKey: key) {
            return .skippedAsDuplicate(existingKey: existing.deterministicKey)
        }

        guard CareScheduleCalculator.isPlausibleRepeat(
            careType: careType,
            lastPerformedAt: previousCareAt,
            candidate: performedAt
        ) else {
            return .skippedAsImplausible(reason: .repeatedTooSoon)
        }

        return try await award(
            type: .plantCareCompleted,
            sourceEntityID: plantID,
            occurredAt: performedAt,
            deterministicKey: key
        )
    }

    /// Records an event and any rewards it earns.
    ///
    /// The duplicate check runs twice — once optimistically above and once via
    /// the repository's `SaveOutcome` — because two callers can race. The
    /// repository's uniqueness constraint is the authority; this method just
    /// declines to double-count when it loses the race.
    public func award(
        type: ProgressionEventType,
        sourceEntityID: UUID?,
        occurredAt: Date,
        deterministicKey: String
    ) async throws -> ProgressionOutcome {
        let experience = rules.experience[type] ?? 0

        let event = ProgressionEvent(
            type: type,
            sourceEntityID: sourceEntityID,
            occurredAt: occurredAt,
            deterministicKey: deterministicKey,
            experienceAwarded: experience
        )

        let outcome = try await repository.save(event)
        guard outcome.wasCreated else {
            return .skippedAsDuplicate(existingKey: deterministicKey)
        }
        let storedEvent = outcome.value

        var profile = try await repository.profile()
        profile.experience += experience
        profile.level = level(forExperience: profile.experience)
        profile.lastActivityAt = occurredAt
        profile.activeDayCount += 1
        try await repository.save(profile)

        var grants: [RewardGrant] = []
        if let rewardID = rules.firstTimeRewards[type] {
            let rewardKey = ActionKeyFactory.reward(
                rewardID: rewardID,
                // Keyed on the reward and event type, not this specific event, so
                // a first-time reward is granted once ever rather than once per
                // care action.
                sourceDeterministicKey: "firstTime|\(type.rawValue)"
            )
            let grant = RewardGrant(
                rewardID: rewardID,
                grantedAt: occurredAt,
                sourceEventID: storedEvent.id,
                deterministicKey: rewardKey
            )
            let grantOutcome = try await repository.save(grant)
            if grantOutcome.wasCreated {
                grants.append(grantOutcome.value)
            }
        }

        return .awarded(storedEvent, rewards: grants)
    }

    /// Levels start at 1 and only ever increase.
    public func level(forExperience experience: Int) -> Int {
        guard rules.experiencePerLevel > 0 else { return 1 }
        return 1 + max(0, experience) / rules.experiencePerLevel
    }
}
