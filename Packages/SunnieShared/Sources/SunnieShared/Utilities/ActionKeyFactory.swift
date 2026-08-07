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

    /// Key for a wellness check-in.
    ///
    /// Bucketed to the minute like plant care, so a check-in saved on the Watch
    /// and redelivered resolves to the same entry rather than appearing twice in
    /// the history. Two genuinely separate check-ins minutes apart are rare, and
    /// a duplicated entry would be the more confusing outcome.
    public static func wellnessCheckIn(recordedAt: Date) -> ActionKey {
        ActionKey(rawValue: "wellnessCheckIn.v1|\(bucketedEpoch(recordedAt))")
    }

    /// Key for a completed practice session.
    ///
    /// Keyed on the session's own identity rather than its timestamp: sessions
    /// have a real start and end, so the identifier is already unique, and two
    /// short breathing exercises inside one minute are two real sessions.
    public static func wellnessSession(sessionID: UUID) -> ActionKey {
        ActionKey(rawValue: "wellnessSession.v1|\(sessionID.uuidString)")
    }

    /// Key for ticking a trip checklist item.
    ///
    /// Keyed on the item, not the moment: ticking the same item on the wrist and
    /// again on the phone is one item done, and the second tick is a no-op rather
    /// than a duplicate.
    public static func checklistItem(itemID: UUID) -> ActionKey {
        ActionKey(rawValue: "checklistItem.v1|\(itemID.uuidString)")
    }

    /// Key for a hydration log.
    ///
    /// Bucketed to the minute like plant care, and including the amount: two
    /// glasses logged in the same minute are almost certainly one glass logged
    /// twice, but 250 ml and 500 ml in the same minute are two deliberate
    /// entries.
    public static func hydration(millilitres: Int, loggedAt: Date) -> ActionKey {
        ActionKey(rawValue: "hydration.v1|\(millilitres)|\(bucketedEpoch(loggedAt))")
    }

    /// Key for finishing a puzzle.
    ///
    /// Derived from the puzzle and difficulty, deliberately **not** from the
    /// session. That is the whole of the "no reward for repeatedly starting and
    /// abandoning sessions" safeguard (GAMES_AND_FUTURE_MULTIPLAYER.md §7):
    /// starting the same puzzle ten times and finishing it ten times earns what
    /// finishing it once earns. Replaying stays free and stays fun; it just is
    /// not a source of experience.
    public static func gamePuzzle(
        puzzleID: ContentID, difficulty: GameDifficulty
    ) -> ActionKey {
        ActionKey(rawValue: "gamePuzzle.v1|\(puzzleID.rawValue)|\(difficulty.rawValue)")
    }

    /// Key for the day's puzzle, keyed on the day rather than on what was played.
    ///
    /// One day, one award — and because the key is the local date, finishing the
    /// daily puzzle on the phone and again on another device is still one award.
    public static func dailyPuzzle(dayKey: String) -> ActionKey {
        ActionKey(rawValue: "dailyPuzzle.v1|\(dayKey)")
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
