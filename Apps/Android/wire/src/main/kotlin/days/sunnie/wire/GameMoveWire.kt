package days.sunnie.wire

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A move in a shared game, as the domain sees it.
 *
 * Mirrors `GameMove` in the Swift shared package. The two are written
 * independently and are held together by `Backend/contract/move-fixtures.json`,
 * which both test suites read — so a change to either side that the other has
 * not made fails a test rather than producing a game where one player's turn
 * silently does nothing (ADR-035).
 */
data class GameMove(
    /** Position in the sequence, from zero. Replaying the same ordinals in order
     *  reaches the same state on both clients. */
    val ordinal: Int,
    /** Which step of the puzzle the move addresses. */
    val stepIndex: Int,
    val action: Action,
    /** Milliseconds since the epoch. See [GameMoveWire] for why not a date. */
    val atMillis: Long,
) {
    /**
     * Sealed rather than an enum with a payload, because each case carries
     * different data. The Swift side is an enum with associated values; this is
     * the closest Kotlin equivalent and maps one-to-one.
     */
    sealed interface Action {
        data class Answer(val text: String) : Action
        data class Choose(val index: Int) : Action
        data class Assign(val item: Int, val slot: Int) : Action
        data class Unassign(val item: Int) : Action
        data class Toggle(val item: Int, val isSelected: Boolean) : Action
        data class Reveal(val clue: Int) : Action
        data object Hint : Action
        data object Skip : Action
        data object Advance : Action
    }
}

/**
 * The over-the-wire form of a move.
 *
 * Field order here is load-bearing, which is unusual enough to say plainly:
 * `kotlinx.serialization` emits properties in declaration order, and the
 * contract's canonical form is JSON with keys sorted lexicographically. So the
 * properties are declared in the order their serialised names sort —
 * `action`, `atMillis`, `ordinal`, `step`, `v` — and the same again inside
 * [WireAction]. Reordering them for readability would produce JSON that is still
 * correct but no longer byte-identical to the fixtures, and the test that
 * compares against them would fail.
 *
 * That comparison is worth the constraint. Two independent implementations
 * agreeing byte-for-byte is a much stronger statement than agreeing after both
 * have been re-parsed, and it is the only version of the claim that would catch
 * a field quietly renamed on one side.
 */
@Serializable
data class GameMoveWire(
    val action: WireAction,
    val atMillis: Long,
    val ordinal: Int,
    @SerialName("step") val stepIndex: Int,
    @SerialName("v") val version: Int = CURRENT_VERSION,
) {
    companion object {
        /** Bumped only for an incompatible change. A reader that does not know a
         *  version refuses the move rather than decoding part of it. */
        const val CURRENT_VERSION: Int = 1

        /**
         * The key that makes a redelivered move one move (ADR-011, ADR-035).
         *
         * Derived from the session, the player, and the ordinal rather than from
         * content or a timestamp, so a retry after a dropped connection produces
         * a byte-identical key. Must match `GameMoveWire.actionKey` in Swift
         * exactly, including the lowercasing — the database's uniqueness
         * constraint is what enforces the idempotency, and it compares strings.
         *
         * **The player is in the key, and leaving it out is not a cosmetic
         * omission.** Without it the key is a pure function of the sequence
         * number, which makes `unique (session_id, action_key)` and
         * `unique (session_id, sequence)` the same constraint written twice: the
         * idempotency half stops doing anything, and — worse — both players
         * compute the same key for the same ordinal. A client would then see the
         * opponent's move sitting under what it believes is its own key, treat
         * its turn as already recorded, and drop it. The player watches their
         * answer disappear with nothing on screen to explain it.
         *
         * The lowercasing is pinned to [java.util.Locale.ROOT] rather than left
         * to the device's. A hex UUID contains no character the Turkish locale
         * treats specially, so this changes no output today — it is here so that
         * a later identifier which is not a UUID cannot make the key depend on
         * where the phone is.
         */
        fun actionKey(sessionId: String, playerId: String, ordinal: Int): String {
            val session = sessionId.lowercase(java.util.Locale.ROOT)
            val player = playerId.lowercase(java.util.Locale.ROOT)
            return "game.move.$session.$player.$ordinal"
        }
    }
}

/**
 * The action, flattened to a discriminator plus named fields.
 *
 * Not a sealed hierarchy with a polymorphic serialiser, deliberately: that would
 * produce whatever shape the library chooses, and the point of this type is that
 * the shape is stated rather than inherited. Same reasoning that kept the Swift
 * side off its own synthesised `Codable`.
 *
 * Declared in sorted-name order, as above.
 */
@Serializable
data class WireAction(
    val clue: Int? = null,
    val index: Int? = null,
    val item: Int? = null,
    val kind: String,
    val selected: Boolean? = null,
    val slot: Int? = null,
    val text: String? = null,
)

// MARK: - Mapping

/**
 * Every case named explicitly, with no `else`.
 *
 * `when` over a sealed interface is exhaustive, so adding an action to
 * [GameMove.Action] stops this compiling — which is the point. The wire format
 * and the Swift client get updated deliberately instead of a new action quietly
 * encoding as something else.
 */
fun GameMove.toWire(): GameMoveWire {
    val wireAction = when (val a = action) {
        is GameMove.Action.Answer -> WireAction(kind = "answer", text = a.text)
        is GameMove.Action.Choose -> WireAction(kind = "choose", index = a.index)
        is GameMove.Action.Assign -> WireAction(kind = "assign", item = a.item, slot = a.slot)
        is GameMove.Action.Unassign -> WireAction(kind = "unassign", item = a.item)
        is GameMove.Action.Toggle -> WireAction(kind = "toggle", item = a.item, selected = a.isSelected)
        is GameMove.Action.Reveal -> WireAction(kind = "reveal", clue = a.clue)
        GameMove.Action.Hint -> WireAction(kind = "hint")
        GameMove.Action.Skip -> WireAction(kind = "skip")
        GameMove.Action.Advance -> WireAction(kind = "advance")
    }
    return GameMoveWire(
        action = wireAction,
        atMillis = atMillis,
        ordinal = ordinal,
        stepIndex = stepIndex,
    )
}

/**
 * Returns null for anything this client cannot represent exactly.
 *
 * An unknown version, an unknown kind, and — importantly — a known kind missing
 * its field. A `choose` with no index is not a move to be salvaged with a zero;
 * it is a payload from a client that disagrees with this one, and playing a turn
 * nobody made is worse than refusing it.
 */
fun GameMoveWire.toMove(): GameMove? {
    if (version != GameMoveWire.CURRENT_VERSION) return null

    val resolved: GameMove.Action = when (action.kind) {
        "answer" -> action.text?.let { GameMove.Action.Answer(it) }
        "choose" -> action.index?.let { GameMove.Action.Choose(it) }
        "assign" -> {
            val item = action.item
            val slot = action.slot
            if (item != null && slot != null) GameMove.Action.Assign(item, slot) else null
        }
        "unassign" -> action.item?.let { GameMove.Action.Unassign(it) }
        "toggle" -> {
            val item = action.item
            val selected = action.selected
            if (item != null && selected != null) GameMove.Action.Toggle(item, selected) else null
        }
        "reveal" -> action.clue?.let { GameMove.Action.Reveal(it) }
        "hint" -> GameMove.Action.Hint
        "skip" -> GameMove.Action.Skip
        "advance" -> GameMove.Action.Advance
        else -> null
    } ?: return null

    return GameMove(
        ordinal = ordinal,
        stepIndex = stepIndex,
        action = resolved,
        atMillis = atMillis,
    )
}
