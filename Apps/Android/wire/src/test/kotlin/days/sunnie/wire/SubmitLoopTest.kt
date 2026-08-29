package days.sunnie.wire

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The submit loop, driven against a stand-in for the table it talks to.
 *
 * The fake enforces the two uniqueness constraints from
 * `0001_multiplayer.sql` and nothing else, because those two are the entire
 * contract the loop is written against. Anything more would be a fake of the
 * database rather than of the promises it makes, and would start passing tests
 * the real thing would fail.
 */
class SubmitLoopTest {

    private val sessionId = "7f3a1c92-2b48-4d0e-9a61-5c8e0b2d4f71"
    private val me = "1c0ffee0-0000-4000-8000-00000000beef"
    private val them = "2d0ffee0-0000-4000-8000-00000000cafe"

    /**
     * An append-only move table with `unique (session_id, sequence)` and
     * `unique (session_id, action_key)`.
     *
     * [failNext] makes the next N attempts look unreachable *after* the row has
     * been written, which is the case worth simulating: the insert succeeded and
     * the response was lost. A fake that dropped the write instead would let a
     * broken retry rule pass.
     */
    private class FakeMoves {
        val rows = mutableListOf<RemoteMove>()
        var loseNextResponses = 0

        fun submit(sessionId: String, playerId: String, move: GameMove, actionKey: String): SubmitOutcome {
            if (rows.any { it.actionKey == actionKey }) return SubmitOutcome.AlreadyRecorded
            if (rows.any { it.sequence == move.ordinal }) return SubmitOutcome.SequenceTaken

            rows += RemoteMove(
                sequence = move.ordinal,
                playerId = playerId,
                actionKey = actionKey,
                move = move,
            )

            if (loseNextResponses > 0) {
                loseNextResponses -= 1
                return SubmitOutcome.Unreachable("response lost after the row was written")
            }
            return SubmitOutcome.Accepted
        }

        /** What the other player did, inserted directly. */
        fun otherPlayerTakes(sessionId: String, playerId: String, sequence: Int) {
            rows += RemoteMove(
                sequence = sequence,
                playerId = playerId,
                actionKey = GameMoveWire.actionKey(sessionId, playerId, sequence),
                move = GameMove(sequence, 0, GameMove.Action.Skip, 0L),
            )
        }
    }

    /**
     * Runs the loop to a terminal step.
     *
     * `refresh` decides what the client re-reads between attempts. It defaults
     * to the fake's real contents; a test can pass a staler view to check that
     * the loop does not depend on being perfectly informed.
     */
    private fun drive(
        server: FakeMoves,
        move: GameMove,
        playerId: String = me,
        refresh: () -> List<RemoteMove> = { server.rows.toList() },
    ): Pair<SubmitStep, Int> {
        var step: SubmitStep = SubmitLoop.first(sessionId, playerId, move, refresh())
        var attempts = 0

        while (step is SubmitStep.Send) {
            attempts += 1
            val outcome = server.submit(sessionId, playerId, step.move, step.actionKey)
            step = SubmitLoop.next(sessionId, playerId, step.move, outcome, refresh(), attempts)
            if (attempts > 20) break // a runaway loop is a failure, not a hang
        }
        return step to attempts
    }

    private fun answer(text: String) =
        GameMove(0, 0, GameMove.Action.Answer(text), 0L)

    @Test
    fun `an ordinary submit takes one attempt and lands at sequence zero`() {
        val server = FakeMoves()
        val (step, attempts) = drive(server, answer("lisbon"))

        assertEquals(SubmitStep.Settled, step)
        assertEquals(1, attempts)
        assertEquals(1, server.rows.size)
        assertEquals(0, server.rows.single().sequence)
    }

    @Test
    fun `losing the race for a sequence renumbers and succeeds`() {
        val server = FakeMoves()
        server.otherPlayerTakes(sessionId, them, 0)

        // The client's list is stale: it believes nothing has been played, so it
        // asks for sequence 0 and loses. This is the ordinary case for two
        // people submitting at once, not an exotic one.
        var stale = true
        val (step, attempts) = drive(server, answer("lisbon")) {
            if (stale) { stale = false; emptyList() } else server.rows.toList()
        }

        assertEquals(SubmitStep.Settled, step)
        assertEquals(2, attempts)
        assertEquals(2, server.rows.size)
        assertEquals(listOf(0, 1), server.rows.map { it.sequence }.sorted())
    }

    @Test
    fun `a lost response does not play the turn twice`() {
        // The property the action key exists for. The row is written, the
        // response never arrives, and the client retries. If the retry carried a
        // new key it would insert a second row — the player's answer submitted
        // twice, with nothing on screen explaining it and no way to take either
        // back.
        val server = FakeMoves()
        server.loseNextResponses = 1

        val (step, attempts) = drive(server, answer("lisbon"))

        assertEquals(SubmitStep.Settled, step)
        assertTrue(attempts >= 1, "the move was sent at least once")
        assertEquals(1, server.rows.size, "the same turn was recorded twice")
    }

    @Test
    fun `a retry after a lost response reuses the key rather than minting one`() {
        // The rule stated directly, rather than inferred from the row count: a
        // future change that renumbered on Unreachable would still keep one row
        // in the test above if the fake happened to dedupe first, so the key
        // itself is asserted.
        val sent = answer("lisbon").let { MultiplayerTurn.resequenced(it, 3) }
        val key = GameMoveWire.actionKey(sessionId, me, 3)

        val step = SubmitLoop.next(
            sessionId = sessionId,
            playerId = me,
            sent = sent,
            outcome = SubmitOutcome.Unreachable("timeout"),
            known = emptyList(),
            attempt = 1,
        )

        assertTrue(step is SubmitStep.Send, "a timeout is retryable")
        assertEquals(key, step.actionKey, "the retry must carry the original key")
        assertEquals(3, step.move.ordinal, "a timeout must not renumber the move")
    }

    @Test
    fun `a taken sequence is retried under a new key`() {
        // The opposite rule, and the reason the two outcomes cannot share a path:
        // here the server has said definitively that the move is not recorded and
        // that its number belongs to someone else, so resending it unchanged
        // would fail the same way forever.
        val server = FakeMoves()
        server.otherPlayerTakes(sessionId, them, 0)
        val sent = answer("lisbon") // ordinal 0

        val step = SubmitLoop.next(
            sessionId = sessionId,
            playerId = me,
            sent = sent,
            outcome = SubmitOutcome.SequenceTaken,
            known = server.rows.toList(),
            attempt = 1,
        )

        assertTrue(step is SubmitStep.Send)
        assertEquals(1, step.move.ordinal)
        assertEquals(GameMoveWire.actionKey(sessionId, me, 1), step.actionKey)
    }

    @Test
    fun `a move already in the list settles whatever the server last said`() {
        // Closes the window where an accepted insert's response was lost and the
        // client has since re-read. Checked for every outcome, including the ones
        // that would otherwise retry.
        val server = FakeMoves()
        val sent = answer("lisbon")
        server.submit(sessionId, me, sent, GameMoveWire.actionKey(sessionId, me, 0))

        val outcomes = listOf(
            SubmitOutcome.Accepted,
            SubmitOutcome.AlreadyRecorded,
            SubmitOutcome.SequenceTaken,
            SubmitOutcome.Unreachable("timeout"),
        )
        for (outcome in outcomes) {
            assertEquals(
                SubmitStep.Settled,
                SubmitLoop.next(sessionId, me, sent, outcome, server.rows.toList(), attempt = 1),
                "outcome $outcome should settle once the move is in the list",
            )
        }
    }

    @Test
    fun `an unreachable server gives up rather than spinning`() {
        val sent = answer("lisbon")
        val step = SubmitLoop.next(
            sessionId = sessionId,
            playerId = me,
            sent = sent,
            outcome = SubmitOutcome.Unreachable("no route to host"),
            known = emptyList(),
            attempt = SubmitLoop.MAX_ATTEMPTS,
        )

        assertTrue(step is SubmitStep.GaveUp)
        assertEquals("no route to host", step.reason)
    }

    @Test
    fun `giving up does not lose the move`() {
        // Stated as a test because it is a product promise, not just a return
        // value: the move stays with the caller, so the outbox can try again
        // later. Nothing in the loop consumes or mutates it.
        val sent = answer("lisbon")
        SubmitLoop.next(
            sessionId, me, sent, SubmitOutcome.Unreachable("offline"),
            emptyList(), SubmitLoop.MAX_ATTEMPTS,
        )
        assertEquals(GameMove.Action.Answer("lisbon"), sent.action)
        assertEquals(0, sent.ordinal)
    }

    @Test
    fun `two players racing repeatedly both land, with no gaps and no duplicates`() {
        // The end-to-end shape of the thing: alternating submissions where the
        // client's view is always one read behind. Every move must end up in the
        // table exactly once, and the sequence must have no holes — a hole would
        // make nextSequence correct but leave replay reading a gap forever.
        val server = FakeMoves()
        val played = mutableListOf<String>()

        for (round in 0 until 6) {
            val text = "answer-$round"
            played += text
            // Deliberately stale: the client starts each submit believing the
            // table is as it was one round ago.
            val stale = server.rows.dropLast(1)
            val player = if (round % 2 == 0) me else them
            var step: SubmitStep = SubmitLoop.first(sessionId, player, answer(text), stale)
            var attempts = 0
            while (step is SubmitStep.Send) {
                attempts += 1
                val outcome = server.submit(sessionId, player, step.move, step.actionKey)
                step = SubmitLoop.next(sessionId, player, step.move, outcome, server.rows.toList(), attempts)
            }
            assertEquals(SubmitStep.Settled, step, "round $round did not settle")
        }

        assertEquals(6, server.rows.size)
        assertEquals((0 until 6).toList(), server.rows.map { it.sequence }.sorted())
        assertEquals(6, server.rows.map { it.actionKey }.toSet().size)

        val texts = server.rows
            .sortedBy { it.sequence }
            .mapNotNull { (it.move.action as? GameMove.Action.Answer)?.text }
        assertEquals(played, texts, "moves landed in an order the players did not play")
    }
}
