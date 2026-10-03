package days.sunnie.wire

/**
 * One stop on a chain: a question, and every spelling that answers it.
 *
 * Deliberately smaller than the Swift `AnswerChainStop`, which also carries the
 * prompt, hints, language, and the explanation of how one answer links to the
 * next. None of that affects replay, and this module's job is to reach the same
 * board state from the same moves — not to render the puzzle. The Android UI
 * gets the display content from the session, and carrying it here would mean two
 * content models to keep in step instead of one rule set.
 */
data class AnswerChainStop(
    val answer: String,
    val alternates: List<String> = emptyList(),
) {
    /** Every spelling that resolves to this stop. Mirrors `acceptedAnswers`. */
    val acceptedAnswers: List<String> get() = listOf(answer) + alternates
}

data class AnswerChainPuzzle(val stops: List<AnswerChainStop>)

/** The state of one stop after replaying the moves that touched it. */
data class StopState(
    val lastAnswer: String? = null,
    val isSolved: Boolean = false,
    val wasSkipped: Boolean = false,
    val hintsRevealed: Int = 0,
    val wrongAttempts: Int = 0,
    /** True when the last answer was one edit away, which drives a "very close"
     *  nudge rather than a bare rejection. */
    val lastAnswerWasNearMiss: Boolean = false,
)

data class AnswerChainBoard(
    val stops: List<StopState>,
    /** The stop the player is on; equal to `stops.size` once the route is done. */
    val currentStop: Int,
) {
    val isComplete: Boolean get() = currentStop >= stops.size
}

/**
 * Rebuilds a board from the moves recorded against it.
 *
 * A port of `AnswerChainEngine.replay` in the Swift shared package. Replay is
 * what makes two clients able to agree without either being authoritative: the
 * server stores moves, both sides replay them, and the same moves in the same
 * order must produce the same board. A difference here is not a cosmetic bug —
 * it is two players looking at different games.
 *
 * Three behaviours are easy to lose in a port, and each is deliberate in the
 * original:
 *
 *  - **Moves are sorted by ordinal, not taken in arrival order.** Turns can
 *    arrive out of order over a network; the ordinal is the sequence.
 *  - **A move for an out-of-range stop is skipped, not an error.** It comes from
 *    a save that does not match this puzzle, and the rest of the route still
 *    replays.
 *  - **Actions belonging to other game shapes are ignored** for the same reason,
 *    rather than being treated as corruption.
 */
object AnswerChainEngine {

    fun replay(puzzle: AnswerChainPuzzle, moves: List<GameMove>): AnswerChainBoard {
        val stops = MutableList(puzzle.stops.size) { StopState() }
        var current = 0

        for (move in moves.sortedBy { it.ordinal }) {
            val index = move.stepIndex
            if (index !in stops.indices) continue

            when (val action = move.action) {
                is GameMove.Action.Answer -> {
                    val accepted = puzzle.stops[index].acceptedAnswers
                    if (AnswerNormalizer.matches(action.text, accepted)) {
                        stops[index] = stops[index].copy(
                            lastAnswer = action.text,
                            isSolved = true,
                            lastAnswerWasNearMiss = false,
                        )
                        // Advance past everything already settled, so resuming a
                        // route lands on the first genuinely open stop.
                        current = maxOf(current, nextOpenStop(index, stops))
                    } else {
                        stops[index] = stops[index].copy(
                            lastAnswer = action.text,
                            wrongAttempts = stops[index].wrongAttempts + 1,
                            lastAnswerWasNearMiss =
                                AnswerNormalizer.isNearMiss(action.text, accepted),
                        )
                    }
                }

                GameMove.Action.Hint -> {
                    stops[index] = stops[index].copy(
                        hintsRevealed = stops[index].hintsRevealed + 1,
                    )
                }

                GameMove.Action.Skip -> {
                    stops[index] = stops[index].copy(wasSkipped = true)
                    current = maxOf(current, nextOpenStop(index, stops))
                }

                // Not part of this shape. A move from a mismatched save is
                // ignored rather than treated as corruption.
                is GameMove.Action.Choose,
                is GameMove.Action.Assign,
                is GameMove.Action.Unassign,
                is GameMove.Action.Toggle,
                is GameMove.Action.Reveal,
                GameMove.Action.Advance,
                -> Unit
            }
        }

        return AnswerChainBoard(stops = stops, currentStop = current)
    }

    private fun nextOpenStop(from: Int, stops: List<StopState>): Int {
        var candidate = from + 1
        while (candidate < stops.size && (stops[candidate].isSolved || stops[candidate].wasSkipped)) {
            candidate += 1
        }
        return candidate
    }
}
