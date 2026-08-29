package days.sunnie.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Kotlin half of the answer-matching rules (ADR-035).
 *
 * Reads `Backend/contract/answer-fixtures.json`, which the Swift suite reads
 * too. These rules matter more than the wire format and fail more quietly: a
 * move that will not decode is visibly broken, while a rule that accepts "cafe"
 * for "café" on one phone and rejects it on the other is a game where one player
 * is simply wrong more often, with nothing on screen to explain why.
 */
class AnswerNormalizerTest {

    private val fixtures: JsonObject by lazy {
        val root = File(System.getProperty("user.dir")).parentFile.parentFile.parentFile
        val file = File(root, "Backend/contract/answer-fixtures.json")
        assertTrue(file.isFile, "Fixtures not found at ${file.absolutePath}")
        Json.parseToJsonElement(file.readText()).jsonObject
    }

    private fun section(name: String): JsonArray = fixtures[name]!!.jsonArray

    private fun JsonObject.string(key: String) = this[key]!!.jsonPrimitive.content
    private fun JsonObject.bool(key: String) = this[key]!!.jsonPrimitive.boolean
    private fun JsonObject.strings(key: String) =
        this[key]!!.jsonArray.map { it.jsonPrimitive.content }
    private fun JsonObject.why() = this["why"]?.jsonPrimitive?.content ?: ""

    @Test
    fun `normalize matches the contract`() {
        for (element in section("normalize")) {
            val case = element.jsonObject
            val input = case.string("input")
            assertEquals(
                case.string("expected"),
                AnswerNormalizer.normalize(input),
                "normalize(${input.quoted()}) — ${case.why()}",
            )
        }
    }

    @Test
    fun `matches follows the contract`() {
        for (element in section("matches")) {
            val case = element.jsonObject
            val input = case.string("input")
            val accepted = case.strings("accepted")
            assertEquals(
                case.bool("expected"),
                AnswerNormalizer.matches(input, accepted),
                "matches(${input.quoted()}, $accepted) — ${case.why()}",
            )
        }
    }

    @Test
    fun `near miss follows the contract`() {
        for (element in section("nearMiss")) {
            val case = element.jsonObject
            val input = case.string("input")
            val accepted = case.strings("accepted")
            assertEquals(
                case.bool("expected"),
                AnswerNormalizer.isNearMiss(input, accepted),
                "isNearMiss(${input.quoted()}, $accepted) — ${case.why()}",
            )
        }
    }

    @Test
    fun `edit distance is symmetric and zero only for equal strings`() {
        // Not in the fixtures because it is a property of the algorithm rather
        // than a rule the two clients negotiate. Worth asserting anyway: an
        // asymmetric distance would make "very close" depend on which side of
        // the comparison a word landed on.
        val words = listOf("", "a", "sol", "lisbon", "lisbo", "porto")
        for (a in words) {
            for (b in words) {
                assertEquals(
                    AnswerNormalizer.editDistance(a, b),
                    AnswerNormalizer.editDistance(b, a),
                    "distance($a,$b) should equal distance($b,$a)",
                )
            }
            assertEquals(0, AnswerNormalizer.editDistance(a, a))
        }
    }

    private fun String.quoted() = "\"$this\""
}
