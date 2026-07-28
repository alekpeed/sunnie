import Foundation

public struct ProgressionProfile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var experience: Int
    public var level: Int
    /// Count of distinct days with at least one recorded action. Deliberately not
    /// a streak: a gap must never read as a broken streak, and nothing earned is
    /// ever taken away (MASTER_SOURCE_OF_TRUTH.md §8).
    public var activeDayCount: Int
    public var lastActivityAt: Date?

    public init(
        id: UUID = UUID(),
        experience: Int = 0,
        level: Int = 1,
        activeDayCount: Int = 0,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.experience = experience
        self.level = level
        self.activeDayCount = activeDayCount
        self.lastActivityAt = lastActivityAt
    }
}

public enum ProgressionEventType: String, Hashable, Sendable, Codable, CaseIterable {
    case plantCareCompleted
    case firstPlantAdded
    case plantCollectionMilestone
    case growthPhotoMilestone
    case travelCoverageCompleted
    case plantHealthIssueResolved
    case wellnessCheckInRecorded
    case puzzleCompleted
}

/// A recorded progression-relevant occurrence.
///
/// `deterministicKey` is the idempotency guarantee: evaluating the same source
/// action twice produces the same key, and the repository stores it once
/// (TECHNICAL_ARCHITECTURE.md §10).
public struct ProgressionEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let type: ProgressionEventType
    public let sourceEntityID: UUID?
    public let occurredAt: Date
    public let deterministicKey: String
    public let payloadVersion: Int
    public let experienceAwarded: Int

    public init(
        id: UUID = UUID(),
        type: ProgressionEventType,
        sourceEntityID: UUID?,
        occurredAt: Date,
        deterministicKey: String,
        payloadVersion: Int = 1,
        experienceAwarded: Int
    ) {
        self.id = id
        self.type = type
        self.sourceEntityID = sourceEntityID
        self.occurredAt = occurredAt
        self.deterministicKey = deterministicKey
        self.payloadVersion = payloadVersion
        self.experienceAwarded = experienceAwarded
    }
}

public struct RewardGrant: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let rewardID: ContentID
    public let grantedAt: Date
    public let sourceEventID: UUID?
    public let deterministicKey: String

    public init(
        id: UUID = UUID(),
        rewardID: ContentID,
        grantedAt: Date,
        sourceEventID: UUID?,
        deterministicKey: String
    ) {
        self.id = id
        self.rewardID = rewardID
        self.grantedAt = grantedAt
        self.sourceEventID = sourceEventID
        self.deterministicKey = deterministicKey
    }
}

/// The outcome of evaluating one domain event.
///
/// `skippedAsDuplicate` and `skippedAsImplausible` are ordinary, expected results
/// — not errors. A duplicate Watch action and an over-eager double-tap both land
/// here, and neither is surfaced to the user as a failure.
public enum ProgressionOutcome: Hashable, Sendable {
    case awarded(ProgressionEvent, rewards: [RewardGrant])
    case skippedAsDuplicate(existingKey: String)
    case skippedAsImplausible(reason: ImplausibleReason)

    public enum ImplausibleReason: String, Hashable, Sendable {
        /// The same care type was logged again sooner than physically sensible.
        /// The care event is still recorded; only the reward is withheld
        /// (PLANT_CARE.md §13).
        case repeatedTooSoon
    }

    public var event: ProgressionEvent? {
        if case .awarded(let event, _) = self { return event }
        return nil
    }

    public var rewards: [RewardGrant] {
        if case .awarded(_, let rewards) = self { return rewards }
        return []
    }
}
