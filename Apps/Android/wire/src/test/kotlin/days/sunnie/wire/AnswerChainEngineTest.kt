package days.sunnie.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Kotlin half of the replay contract (ADR-035).
 *
 * Reads `Backend/contract/replay-fixtures.json`, which the Swift suite reads
 * too. Replay is what lets two clients agree without either being
 * authoritative — the server keeps moves, both sides rebuild the board — so a
 * divergence here is not a cosmetic bug. It is two players looking at different
 * games while both believe they are looking at the same one.
 */
class AnswerChainEngineTest {

    private val fixtures: JsonObject by lazy {
        val root = File(System.getProperty("user.dir")).parentFile.parentFile.parentFile
        val file = File(root, "Backend/contract/replay-fixtures.json")
        assertTrue(file.isFile, "Fixtures not found at ${file.absolutePath}")
        Json.parseToJsonElement(file.readText()).jsonObject
    }

    private val puzzle: AnswerChainPuzzle by lazy {
        val stops = fixtures["puzzle"]!!.jsonObject["stops"]!!.jsonArray.map { element ->
            val stop = element.jsonObject
            AnswerChainStop(
                answer = stop["answer"]!!.jsonPrimitive.content,
                alternates = stop["alternates"]!!.jsonArray.map { it.jsonPrimitive.content },
            )
        }
        AnswerChainPuzzle(stops)
    }

    /**
     * The compact fixture move, turned into a domain move.
     *
     * The wire encoding is not reused here on purpose: it has its own fixtures,
     * and threading every replay case through it would test the decoder twice
     * while making this file unreadable to anyone deciding whether a rule is
     * right.
     */
    private fun moveFrom(json: JsonObject): GameMove {
        val action: GameMove.Action = when (val kind = json["kind"]!!.jsonPrimitive.content) {
            "answer" -> GameMove.Action.Answer(json["text"]!!.jsonPrimitive.content)
            "hint" -> GameMove.Action.Hint
            "skip" -> GameMove.Action.Skip
            "choose" -> GameMove.Action.Choose(json["index"]!!.jsonPrimitive.int)
            "advance" -> GameMove.Action.Advance
            else -> error("Fixture uses an action this test cannot build: $kind")
        }
        return GameMove(
            ordinal = json["ordinal"]!!.jsonPrimitive.int,
            stepIndex = json["step"]!!.jsonPrimitive.int,
            action = action,
            atMillis = 0L,
        )
    }

    @Test
    fun `every replay fixture reaches the board the contract states`() {
        for (element in fixtures["cases"]!!.jsonArray) {
            val case = element.jsonObject
            val name = case["name"]!!.jsonPrimitive.content
            val moves = case["moves"]!!.jsonArray.map { moveFrom(it.jsonObject) }

            val board = AnswerChainEngine.replay(puzzle, moves)
            val expected = case["expected"]!!.jsonObject

            assertEquals(
                expected["currentStop"]!!.jsonPrimitive.int,
                board.currentStop,
                "$name: currentStop",
            )

            val expectedStops = expected["stops"]!!.jsonArray
            assertEquals(expectedStops.size, board.stops.size, "$name: stop count")

            for ((index, stopElement) in expectedStops.withIndex()) {
                val stop = stopElement.jsonObject
                val actual = board.stops[index]
                val where = "$name: stop $index"

                // `contentOrNull` is null for JSON null and the string
                // otherwise, which is exactly the distinction the fixture draws
                // between a stop never answered and one answered with text.
                assertEquals(
                    stop["lastAnswer"]!!.jsonPrimitive.contentOrNull,
                    actual.lastAnswer,
                    "$where lastAnswer",
                )
                assertEquals(stop["isSolved"]!!.jsonPrimitive.boolean, actual.isSolved, "$where isSolved")
                assertEquals(stop["wasSkipped"]!!.jsonPrimitive.boolean, actual.wasSkipped, "$where wasSkipped")
                assertEquals(stop["hintsRevealed"]!!.jsonPrimitive.int, actual.hintsRevealed, "$where hintsRevealed")
                assertEquals(stop["wrongAttempts"]!!.jsonPrimitive.int, actual.wrongAttempts, "$where wrongAttempts")
                assertEquals(
                    stop["lastAnswerWasNearMiss"]!!.jsonPrimitive.boolean,
                    actual.lastAnswerWasNearMiss,
                    "$where lastAnswerWasNearMiss",
                )
            }
        }
    }

    @Test
    fun `replaying the same moves twice gives the same board`() {
        // Determinism is the property the whole design leans on: the server
        // stores moves rather than state, so replay has to be a pure function of
        // them. Anything reaching for a clock or a random seed breaks this.
        for (element in fixtures["cases"]!!.jsonArray) {
            val case = element.jsonObject
            val moves = case["moves"]!!.jsonArray.map { moveFrom(it.jsonObject) }
            assertEquals(
                AnswerChainEngine.replay(puzzle, moves),
                AnswerChainEngine.replay(puzzle, moves),
                case["name"]!!.jsonPrimitive.content,
            )
        }
    }

    @Test
    fun `shuffling the move list does not change the board`() {
        // The stronger form of the ordinal rule: not just that a reversed list
        // replays correctly, but that no arrival order changes the outcome.
        for (element in fixtures["cases"]!!.jsonArray) {
            val case = element.jsonObject
            val moves = case["moves"]!!.jsonArray.map { moveFrom(it.jsonObject) }
            if (moves.size < 2) continue

            val expected = AnswerChainEngine.replay(puzzle, moves)
            assertEquals(
                expected,
                AnswerChainEngine.replay(puzzle, moves.reversed()),
                "${case["name"]!!.jsonPrimitive.content}: reversed arrival order",
            )
            assertEquals(
                expected,
                AnswerChainEngine.replay(puzzle, moves.shuffled(kotlin.random.Random(7))),
                "${case["name"]!!.jsonPrimitive.content}: shuffled arrival order",
            )
        }
    }

    @Test
    fun `an empty move list leaves an untouched board`() {
        val board = AnswerChainEngine.replay(puzzle, emptyList())
        assertEquals(0, board.currentStop)
        assertTrue(board.stops.all { it == StopState() })
        assertTrue(!board.isComplete)
    }
}
