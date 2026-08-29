package days.sunnie.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.long
import kotlinx.serialization.json.contentOrNull
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Kotlin half of the cross-language move contract (ADR-035).
 *
 * Reads the same `Backend/contract/move-fixtures.json` the Swift suite reads.
 * That is the entire point of the file: two independently written
 * implementations, one set of bytes, and a divergence that fails a test on
 * whichever side moved rather than showing up as a turn that silently does
 * nothing in a real game.
 *
 * Found by path rather than copied into the module's resources, so there is
 * exactly one copy and no build step that could let them drift apart.
 */
class GameMoveWireTest {

    private val json = Json {
        // Absent rather than null, matching Swift's `encodeIfPresent` and the
        // fixtures' "optional fields omitted rather than null".
        explicitNulls = false
        // A field this client does not know must not be fatal on read; refusing
        // is the job of the version check, which is explicit.
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val fixtures: JsonObject by lazy {
        // …/Apps/Android/wire/  ->  repository root
        val root = File(System.getProperty("user.dir")).parentFile.parentFile.parentFile
        val file = File(root, "Backend/contract/move-fixtures.json")
        assertTrue(file.isFile, "Fixtures not found at ${file.absolutePath}")
        Json.parseToJsonElement(file.readText()).jsonObject
    }

    private val cases get() = fixtures["cases"]!!.let { (it as kotlinx.serialization.json.JsonArray) }
    private val rejected get() = fixtures["rejected"]!!.let { (it as kotlinx.serialization.json.JsonArray) }

    @Test
    fun `wire version matches the fixtures`() {
        assertEquals(
            fixtures["wireVersion"]!!.jsonPrimitive.int,
            GameMoveWire.CURRENT_VERSION,
        )
    }

    @Test
    fun `every fixture decodes, maps to a move, and re-encodes byte-identically`() {
        for (element in cases) {
            val case = element.jsonObject
            val name = case["name"]!!.jsonPrimitive.content
            val encoded = case["encoded"]!!.jsonPrimitive.content

            val wire = json.decodeFromString(GameMoveWire.serializer(), encoded)
            assertEquals(case["ordinal"]!!.jsonPrimitive.int, wire.ordinal, "$name: ordinal")
            assertEquals(case["step"]!!.jsonPrimitive.int, wire.stepIndex, "$name: step")
            assertEquals(case["atMillis"]!!.jsonPrimitive.long, wire.atMillis, "$name: atMillis")
            assertEquals(case["kind"]!!.jsonPrimitive.content, wire.action.kind, "$name: kind")

            // Through the domain type and back. Mapping in one direction only
            // would let an asymmetry sit undetected until a real game hit it.
            val move = assertNotNull(wire.toMove(), "$name: did not map to a move")
            val reencoded = json.encodeToString(GameMoveWire.serializer(), move.toWire())

            assertEquals(
                encoded,
                reencoded,
                "$name: re-encoding did not match the fixture byte for byte",
            )
        }
    }

    @Test
    fun `fixtures cover every action`() {
        val expected = setOf(
            "answer", "choose", "assign", "unassign",
            "toggle", "reveal", "hint", "skip", "advance",
        )
        val covered = cases.map { it.jsonObject["kind"]!!.jsonPrimitive.content }.toSet()
        assertEquals(expected, covered, "Fixture coverage drifted from the action list")
    }

    @Test
    fun `a payload this client cannot represent exactly is refused`() {
        for (element in rejected) {
            val case = element.jsonObject
            val name = case["name"]!!.jsonPrimitive.content
            val why = case["why"]!!.jsonPrimitive.content
            val encoded = case["encoded"]!!.jsonPrimitive.content

            // Some refusals fail at decoding and some at mapping; both are
            // refusals. What must never happen is a move coming out.
            val move = runCatching {
                json.decodeFromString(GameMoveWire.serializer(), encoded).toMove()
            }.getOrNull()

            assertNull(move, "$name produced a move. $why")
        }
    }

    @Test
    fun `the action key survives a retry and separates real turns`() {
        val session = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        val other = "8A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"

        // The case this exists for: the same turn sent twice after a dropped
        // connection must produce the same key, or it plays twice.
        assertEquals(
            GameMoveWire.actionKey(session, 3),
            GameMoveWire.actionKey(session, 3),
        )
        assertTrue(GameMoveWire.actionKey(session, 3) != GameMoveWire.actionKey(session, 4))
        assertTrue(GameMoveWire.actionKey(session, 3) != GameMoveWire.actionKey(other, 3))

        // Lowercased, because Swift lowercases and the database compares strings.
        // An uppercase UUID from one client and a lowercase one from the other
        // would defeat the uniqueness constraint that makes retries safe.
        assertEquals(
            "game.move.3f2504e0-4f89-11d3-9a0c-0305e82c3301.3",
            GameMoveWire.actionKey(session, 3),
        )
    }

    @Test
    fun `an unknown field does not break a move this client understands`() {
        // Forward compatibility in the direction that is safe: a newer client
        // adding a field must not stop an older one reading the move. Refusing
        // is reserved for a version bump, which is explicit and deliberate.
        val withExtra = """{"action":{"kind":"hint"},"atMillis":1786000000000,"ordinal":0,"step":0,"v":1,"future":"x"}"""
        val wire = json.decodeFromString(GameMoveWire.serializer(), withExtra)
        assertNotNull(wire.toMove())
    }
}
