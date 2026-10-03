package days.sunnie.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Kotlin half of the turn contract (ADR-035).
 *
 * Reads `Backend/contract/turn-fixtures.json`, which the Swift suite reads too.
 * A disagreement here does not produce a wrong board — it produces both players
 * waiting for each other, which neither of them can tell apart from a bad
 * connection and neither of them can clear.
 */
class MultiplayerTurnTest {

    private val fixtures: JsonObject by lazy {
        val root = File(System.getProperty("user.dir")).parentFile.parentFile.parentFile
        val file = File(root, "Backend/contract/turn-fixtures.json")
        assertTrue(file.isFile, "Fixtures not found at ${file.absolutePath}")
        Json.parseToJsonElement(file.readText()).jsonObject
    }

    private fun cases(section: String) =
        fixtures[section]!!.jsonObject["cases"]!!.jsonArray.map { it.jsonObject }

    /** A move whose only interesting field is its ordinal. */
    private fun move(ordinal: Int) = GameMove(
        ordinal = ordinal,
        stepIndex = 0,
        action = GameMove.Action.Skip,
        atMillis = 0L,
    )

    @Test
    fun `the action key follows the contract`() {
        for (case in cases("actionKey")) {
            val sessionId = case["sessionId"]!!.jsonPrimitive.content
            val playerId = case["playerId"]!!.jsonPrimitive.content
            val ordinal = case["ordinal"]!!.jsonPrimitive.int
            assertEquals(
                case["expected"]!!.jsonPrimitive.content,
                GameMoveWire.actionKey(sessionId, playerId, ordinal),
                "actionKey($sessionId, $playerId, $ordinal)",
            )
        }
    }

    @Test
    fun `the same session spelled two ways gives one key`() {
        // The reason the contract lowercases at all: Swift prints a UUID
        // uppercase, Postgres prints it lowercase, and the database's uniqueness
        // constraint compares the strings rather than the identifiers. Without
        // this, both players could play the same turn.
        val session = "7f3a1c92-2b48-4d0e-9a61-5c8e0b2d4f71"
        val player = "1c0ffee0-0000-4000-8000-00000000beef"
        assertEquals(
            GameMoveWire.actionKey(session, player, 3),
            GameMoveWire.actionKey(session.uppercase(), player.uppercase(), 3),
        )
    }

    @Test
    fun `next sequence follows the contract`() {
        for (case in cases("nextSequence")) {
            val name = case["name"]!!.jsonPrimitive.content
            val moves = case["sequences"]!!.jsonArray.map { element ->
                val sequence = element.jsonPrimitive.int
                RemoteMove(
                    sequence = sequence,
                    playerId = "p",
                    actionKey = GameMoveWire.actionKey("s", "p", sequence),
                    move = move(sequence),
                )
            }
            assertEquals(
                case["expected"]!!.jsonPrimitive.int,
                MultiplayerTurn.nextSequence(moves),
                name,
            )
        }
    }

    @Test
    fun `seat to play follows the contract`() {
        for (case in cases("seatToPlay")) {
            val name = case["name"]!!.jsonPrimitive.content
            val step = case["currentStep"]!!.jsonPrimitive.int
            val seats = case["seatCount"]!!.jsonPrimitive.int
            val expected = case["expected"]!!.jsonPrimitive.int

            assertEquals(expected, MultiplayerTurn.seatToPlay(step, seats), name)

            // isMyTurn is the form the UI actually calls, so it is checked
            // against the same case rather than trusted to agree.
            assertTrue(MultiplayerTurn.isMyTurn(step, expected, seats), "$name: isMyTurn")
            for (seat in 0 until seats) {
                if (seat == expected) continue
                assertTrue(
                    !MultiplayerTurn.isMyTurn(step, seat, seats),
                    "$name: seat $seat should not be playing",
                )
            }
        }
    }

    @Test
    fun `unsubmitted follows the contract`() {
        val section = fixtures["unsubmitted"]!!.jsonObject
        val sessionId = section["sessionId"]!!.jsonPrimitive.content
        val playerId = section["playerId"]!!.jsonPrimitive.content
        val opponentId = section["opponentPlayerId"]!!.jsonPrimitive.content

        for (case in section["cases"]!!.jsonArray.map { it.jsonObject }) {
            val name = case["name"]!!.jsonPrimitive.content
            val pending = case["pendingOrdinals"]!!.jsonArray.map { move(it.jsonPrimitive.int) }

            fun rows(key: String, owner: String) =
                case[key]!!.jsonArray.map { element ->
                    val ordinal = element.jsonPrimitive.int
                    RemoteMove(
                        sequence = ordinal,
                        playerId = owner,
                        actionKey = GameMoveWire.actionKey(sessionId, owner, ordinal),
                        move = move(ordinal),
                    )
                }

            val remote = rows("recordedOrdinals", playerId) + rows("opponentOrdinals", opponentId)

            assertEquals(
                case["expected"]!!.jsonArray.map { it.jsonPrimitive.int },
                MultiplayerTurn.unsubmitted(pending, remote, sessionId, playerId).map { it.ordinal },
                name,
            )
        }
    }

    @Test
    fun `resequencing follows the contract`() {
        for (case in cases("resequenced")) {
            val name = case["name"]!!.jsonPrimitive.content
            val sessionId = case["sessionId"]!!.jsonPrimitive.content
            val playerId = case["playerId"]!!.jsonPrimitive.content
            val from = case["fromOrdinal"]!!.jsonPrimitive.int
            val to = case["toOrdinal"]!!.jsonPrimitive.int

            val renumbered = MultiplayerTurn.resequenced(move(from), to)
            assertEquals(to, renumbered.ordinal, "$name: ordinal")
            assertEquals(
                case["expectedKey"]!!.jsonPrimitive.content,
                GameMoveWire.actionKey(sessionId, playerId, renumbered.ordinal),
                "$name: key",
            )
        }
    }

    // MARK: - Properties the fixtures state by example and this states in general

    @Test
    fun `a resequenced move keeps everything except its ordinal`() {
        val original = GameMove(
            ordinal = 4,
            stepIndex = 2,
            action = GameMove.Action.Answer("lisbon"),
            atMillis = 1_700_000_000_000L,
        )
        val renumbered = MultiplayerTurn.resequenced(original, 5)

        assertEquals(original.stepIndex, renumbered.stepIndex)
        assertEquals(original.action, renumbered.action)
        assertEquals(original.atMillis, renumbered.atMillis)
        assertEquals(original.copy(ordinal = 5), renumbered)
    }

    @Test
    fun `the turn follows the board rather than the number of moves`() {
        // The property the whole design rests on, checked end to end against the
        // engine: a wrong answer and a hint are moves, but neither settles the
        // stop, so neither hands the turn over. If the turn were counted from
        // the move list instead of read off the board, this is the test that
        // would fail.
        val puzzle = AnswerChainPuzzle(
            listOf(
                AnswerChainStop(answer = "Lisbon"),
                AnswerChainStop(answer = "Porto"),
            )
        )
        val fumbling = listOf(
            GameMove(0, 0, GameMove.Action.Answer("madrid"), 0L),
            GameMove(1, 0, GameMove.Action.Hint, 0L),
            GameMove(2, 0, GameMove.Action.Answer("lisbo"), 0L),
        )

        val stillStuck = AnswerChainEngine.replay(puzzle, fumbling)
        assertEquals(0, stillStuck.currentStop)
        assertTrue(MultiplayerTurn.isMyTurn(stillStuck.currentStop, mySeat = 0))

        val solved = AnswerChainEngine.replay(
            puzzle,
            fumbling + GameMove(3, 0, GameMove.Action.Answer("Lisbon"), 0L),
        )
        assertEquals(1, solved.currentStop)
        assertTrue(MultiplayerTurn.isMyTurn(solved.currentStop, mySeat = 1))
        assertTrue(!MultiplayerTurn.isMyTurn(solved.currentStop, mySeat = 0))
    }

    @Test
    fun `a finished route belongs to nobody in particular but never crashes`() {
        // currentStop equals the stop count once the route is done, so seatToPlay
        // is still asked for an answer. It must return a seat that exists rather
        // than reading off the end of anything.
        val seat = MultiplayerTurn.seatToPlay(currentStep = 3, seatCount = 2)
        assertTrue(seat in 0 until 2)
    }

    @Test
    fun `two players at the same ordinal get different keys`() {
        // The bug this rule exists to prevent, stated directly. With the player
        // out of the key, both clients compute the same string for ordinal 0.
        // The idempotency constraint then duplicates the sequence constraint,
        // and each client sees the other's row under what it believes is its own
        // key — so it treats its turn as recorded and drops it.
        val session = "7f3a1c92-2b48-4d0e-9a61-5c8e0b2d4f71"
        val mine = GameMoveWire.actionKey(session, "1c0ffee0-0000-4000-8000-00000000beef", 0)
        val theirs = GameMoveWire.actionKey(session, "2d0ffee0-0000-4000-8000-00000000cafe", 0)
        assertTrue(mine != theirs, "the same ordinal in one session gave two players one key")
    }
}
