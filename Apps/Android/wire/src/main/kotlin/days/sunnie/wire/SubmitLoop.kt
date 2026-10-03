package days.sunnie.wire

/**
 * What the server said about one attempt to record a move.
 *
 * The three failures are kept apart because the right response to each is
 * different, and treating any two of them the same produces a specific, bad
 * outcome in a real game.
 */
sealed interface SubmitOutcome {

    /** The move is in the table. */
    data object Accepted : SubmitOutcome

    /**
     * `unique (session_id, sequence)` was violated: the other player took this
     * number first. The move is fine; its position is not.
     */
    data object SequenceTaken : SubmitOutcome

    /**
     * `unique (session_id, action_key)` was violated: this exact move is already
     * recorded. Not a failure — it is an earlier attempt that got through and
     * whose response was lost.
     */
    data object AlreadyRecorded : SubmitOutcome

    /**
     * Offline, timed out, or a server error. The distinguishing feature is that
     * the client does not know whether the move was recorded.
     */
    data class Unreachable(val detail: String) : SubmitOutcome
}

/** What the client should do next. */
sealed interface SubmitStep {

    /**
     * Send this move under this key.
     *
     * The key is included rather than left for the caller to derive, because
     * whether it changed between attempts is the whole substance of the retry
     * rules below, and a caller recomputing it from its own copy of the move is
     * a place for the two to disagree.
     */
    data class Send(val move: GameMove, val actionKey: String) : SubmitStep

    /** The move is recorded. Stop. */
    data object Settled : SubmitStep

    /** Stop trying and tell the player, without losing the move. */
    data class GaveUp(val reason: String) : SubmitStep
}

/**
 * The rules for getting one move recorded, as a pure function of what has
 * happened so far.
 *
 * There is no networking here, and that is deliberate: retry logic is where this
 * kind of feature actually goes wrong, and it is the part hardest to test when
 * it is tangled up with a transport. Everything below can be exercised without a
 * server, a socket, or a clock.
 *
 * The two rules worth reading before changing anything:
 *
 * **A lost response is retried under the same key.** When the client cannot tell
 * whether the server got the move, it resends it unchanged. Renumbering it would
 * give it a new action key, which is precisely what the idempotency constraint
 * uses to recognise a duplicate — so a timeout would play the same turn twice,
 * and the player would watch their answer submitted twice with no way to undo
 * either. This is the bug the whole action-key scheme exists to prevent, and
 * getting it wrong here would quietly disable that scheme at the only moment it
 * matters.
 *
 * **A taken sequence is retried under a new one.** This is the opposite case and
 * the reason the two cannot share a code path. The server has said, definitively,
 * that this move is not recorded and that its number belongs to someone else.
 * Resending it unchanged would fail identically forever.
 */
object SubmitLoop {

    /**
     * Five attempts. Enough to survive both players submitting at once several
     * times over — which needs one retry, not five — and few enough that a
     * client wedged against a server that keeps rejecting stops rather than
     * spinning. The move is not lost when this runs out; it stays in the outbox.
     */
    const val MAX_ATTEMPTS: Int = 5

    /** The first attempt: take the next free sequence number. */
    fun first(
        sessionId: String,
        playerId: String,
        move: GameMove,
        known: List<RemoteMove>,
    ): SubmitStep.Send {
        val renumbered = MultiplayerTurn.resequenced(move, MultiplayerTurn.nextSequence(known))
        return SubmitStep.Send(
            move = renumbered,
            actionKey = GameMoveWire.actionKey(sessionId, playerId, renumbered.ordinal),
        )
    }

    /**
     * What to do after an attempt.
     *
     * [known] is the freshest move list the client has. After a
     * [SubmitOutcome.SequenceTaken] the caller should re-read before calling
     * this, since the whole point of that outcome is that the client's picture
     * of the sequence is out of date.
     *
     * [attempt] counts attempts already made, so the first call after [first]
     * passes 1.
     */
    fun next(
        sessionId: String,
        playerId: String,
        sent: GameMove,
        outcome: SubmitOutcome,
        known: List<RemoteMove>,
        attempt: Int,
    ): SubmitStep {
        // Asked before anything else, and true regardless of what the server
        // last said: if the move is in the list the client just read, it is
        // recorded. This is what closes the window where an accepted insert's
        // response was lost and the retry has not happened yet.
        val sentKey = GameMoveWire.actionKey(sessionId, playerId, sent.ordinal)
        if (known.any { it.actionKey == sentKey }) return SubmitStep.Settled

        return when (outcome) {
            SubmitOutcome.Accepted -> SubmitStep.Settled

            // Already there under this key. The earlier attempt got through and
            // its response was lost, which is a success wearing an error's
            // clothes.
            SubmitOutcome.AlreadyRecorded -> SubmitStep.Settled

            SubmitOutcome.SequenceTaken ->
                if (attempt >= MAX_ATTEMPTS) {
                    SubmitStep.GaveUp(
                        "The sequence was taken on $attempt attempts running."
                    )
                } else {
                    // A new number, and therefore a new key — correctly, because
                    // this is now a different move in the sequence.
                    val renumbered = MultiplayerTurn.resequenced(
                        sent, MultiplayerTurn.nextSequence(known)
                    )
                    SubmitStep.Send(
                        move = renumbered,
                        actionKey = GameMoveWire.actionKey(sessionId, playerId, renumbered.ordinal),
                    )
                }

            is SubmitOutcome.Unreachable ->
                if (attempt >= MAX_ATTEMPTS) {
                    SubmitStep.GaveUp(outcome.detail)
                } else {
                    // Unchanged, key included. See the note on this object: the
                    // server may have recorded this move already, and only an
                    // identical key lets the uniqueness constraint recognise the
                    // retry as the same turn rather than a second one.
                    SubmitStep.Send(move = sent, actionKey = sentKey)
                }
        }
    }
}
