import Foundation

/// Builds the deterministic keys that make repeated actions safe.
///
/// The design rule: a key is derived only from *what happened*, never from which
/// device recorded it or when the record was received. Two paths that describe
/// the same real-world action therefore produce the same key and collapse to one
/// stored record.
///
/// This covers three cases the vertical slice must survive:
/// - A queued Watch transfer delivered twice.
/// - The user tapping Water on the Watch and again on the phone moments later.
/// - A notification action handled while the app was already applying it.
public enum ActionKeyFactory {
    /// Timestamps are bucketed to the minute before entering the key.
    ///
    /// Two logs of the same care type on the same plant inside one minute are the
    /// same watering, not two. A minute is long enough to absorb the round trip
    /// between Watch and phone and short enough that a genuine second watering —
    /// which realistically comes days later — is never swallowed.
    public static let timestampGranularity: TimeInterval = 60

    /// Bumped only if the key format changes. Old keys stay valid; new ones stop
    /// colliding with them.
    public static let plantCareKeyVersion = 1

    public static func plantCare(
        plantID: UUID,
        careType: CareType,
        performedAt: Date
    ) -> ActionKey {
        let bucket = bucketedEpoch(performedAt)
        let raw = [
            "plantCare.v\(plantCareKeyVersion)",
            plantID.uuidString,
            careType.storageKey,
            String(bucket)
        ].joined(separator: "|")
        return ActionKey(rawValue: raw)
    }

    /// Progression keys are derived from the care event's own action key, so
    /// evaluating the same event twice cannot award experience twice.
    public static func progression(
        type: ProgressionEventType,
        sourceActionKey: ActionKey
    ) -> String {
        "progression.v1|\(type.rawValue)|\(sourceActionKey.rawValue)"
    }

    /// Reward keys include the reward so one event may grant several distinct
    /// rewards, but never the same reward twice.
    public static func reward(
        rewardID: ContentID,
        sourceDeterministicKey: String
    ) -> String {
        "reward.v1|\(rewardID.rawValue)|\(sourceDeterministicKey)"
    }

    /// Floors to the granularity bucket. Uses `floor` rather than truncation so
    /// dates before 1970 bucket consistently instead of rounding toward zero.
    static func bucketedEpoch(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / timestampGranularity).rounded(.down))
    }
}
