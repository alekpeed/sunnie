import Foundation

/// What the server said about one attempt to record a move.
///
/// The three failures are kept apart because the right response to each differs,
/// and treating any two of them alike produces a specific, bad outcome in a real
/// game.
public enum SubmitOutcome: Hashable, Sendable {

    /// The move is in the table.
    case accepted

    /// `unique (session_id, sequence)` was violated: the other player took this
    /// number first. The move is fine; its position is not.
    case sequenceTaken

    /// `unique (session_id, action_key)` was violated: this exact move is
    /// already recorded. Not a failure — an earlier attempt got through and its
    /// response was lost.
    case alreadyRecorded

    /// Offline, timed out, or a server error. The distinguishing feature is that
    /// the client does not know whether the move was recorded.
    case unreachable(String)
}

/// What the client should do next.
public enum SubmitStep: Hashable, Sendable {

    /// Send this move under this key.
    ///
    /// The key travels with the move rather than being left for the caller to
    /// derive, because whether it changed between attempts is the whole
    /// substance of the rules below — and a caller recomputing it from its own
    /// copy is a place for the two to disagree.
    case send(move: GameMove, actionKey: String)

    /// The move is recorded. Stop.
    case settled

    /// Stop trying and tell the player, without losing the move.
    case gaveUp(reason: String)
}

/// The rules for getting one move recorded, as a pure function of what has
/// happened so far.
///
/// A port of `SubmitLoop` in the Android `wire` module. There is no networking
/// here, deliberately: retry logic is where this kind of feature actually goes
/// wrong, and it is the part hardest to test when it is tangled up with a
/// transport. Everything below can be exercised without a server, a socket, or a
/// clock.
///
/// The two rules worth reading before changing anything:
///
/// **A lost response is retried under the same key.** When the client cannot
/// tell whether the server got the move, it resends it unchanged. Renumbering
/// would give it a new action key, which is precisely what the idempotency
/// constraint uses to recognise a duplicate — so a timeout would play the same
/// turn twice, and the player would watch their answer submitted twice with no
/// way to undo either. This is the bug the whole action-key scheme exists to
/// prevent, and getting it wrong here would disable that scheme at the one
/// moment it matters.
///
/// **A taken sequence is retried under a new one.** The opposite case, and the
/// reason the two cannot share a code path: the server has said definitively
/// that this move is not recorded and that its number belongs to someone else.
/// Resending it unchanged would fail identically forever.
public enum SubmitLoop {

    /// Five attempts. Enough to survive both players submitting at once several
    /// times over — which needs one retry, not five — and few enough that a
    /// client wedged against a server that keeps rejecting stops rather than
    /// spinning. The move is not lost when this runs out; it stays in the
    /// outbox.
    public static let maximumAttempts = 5

    /// The first attempt: take the next free sequence number.
    public static func first(
        sessionID: UUID, playerID: UUID, move: GameMove, known: [RemoteMove]
    ) -> SubmitStep {
        let renumbered = MultiplayerTurn.resequenced(
            move, to: MultiplayerTurn.nextSequence(after: known)
        )
        return .send(
            move: renumbered,
            actionKey: GameMoveWire.actionKey(
                sessionID: sessionID, playerID: playerID, ordinal: renumbered.ordinal
            )
        )
    }

    /// What to do after an attempt.
    ///
    /// `known` is the freshest move list the client has. After
    /// ``SubmitOutcome/sequenceTaken`` the caller should re-read before calling
    /// this, since the point of that outcome is that the client's picture of the
    /// sequence is out of date.
    ///
    /// `attempt` counts attempts already made, so the first call after
    /// ``first(sessionID:playerID:move:known:)`` passes 1.
    public static func next(
        sessionID: UUID,
        playerID: UUID,
        sent: GameMove,
        outcome: SubmitOutcome,
        known: [RemoteMove],
        attempt: Int
    ) -> SubmitStep {
        // Asked before anything else, and true regardless of what the server
        // last said: if the move is in the list the client just read, it is
        // recorded. This closes the window where an accepted insert's response
        // was lost and the retry has not happened yet.
        let sentKey = GameMoveWire.actionKey(
            sessionID: sessionID, playerID: playerID, ordinal: sent.ordinal
        )
        if known.contains(where: { $0.actionKey == sentKey }) { return .settled }

        switch outcome {
        case .accepted:
            return .settled

        // Already there under this key. The earlier attempt got through and its
        // response was lost, which is a success wearing an error's clothes.
        case .alreadyRecorded:
            return .settled

        case .sequenceTaken:
            guard attempt < maximumAttempts else {
                return .gaveUp(
                    reason: "The sequence was taken on \(attempt) attempts running."
                )
            }
            // A new number, and therefore a new key — correctly, because this is
            // now a different move in the sequence.
            let renumbered = MultiplayerTurn.resequenced(
                sent, to: MultiplayerTurn.nextSequence(after: known)
            )
            return .send(
                move: renumbered,
                actionKey: GameMoveWire.actionKey(
                    sessionID: sessionID, playerID: playerID, ordinal: renumbered.ordinal
                )
            )

        case .unreachable(let detail):
            guard attempt < maximumAttempts else { return .gaveUp(reason: detail) }
            // Unchanged, key included. See the note on this type: the server may
            // have recorded this move already, and only an identical key lets
            // the uniqueness constraint recognise the retry as the same turn
            // rather than a second one.
            return .send(move: sent, actionKey: sentKey)
        }
    }
}
