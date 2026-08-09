import Foundation

/// The over-the-wire form of a game move (ADR-035).
///
/// This exists because `GameMove` must not be sent as-is. `Action` is an enum
/// with associated values, and Swift's synthesized `Codable` encodes those under
/// compiler-generated keys — `{"answer": {"_0": "lisbon"}}`. That shape is not
/// specified anywhere, is free to change between compiler versions, and would
/// have a Kotlin client parsing `_0` and hoping. A format two languages must
/// agree on has to be written down rather than inherited from a macro.
///
/// So the encoding here is hand-written and dull on purpose:
///
///     {"v":1,"ordinal":0,"step":0,"atMillis":1786000000000,
///      "action":{"kind":"answer","text":"lisbon"}}
///
/// Three choices worth stating, because each replaces something that would have
/// worked in one language and bitten in two:
///
///   * **Milliseconds since epoch, not ISO 8601.** A date string means two
///     formatter configurations agreeing about fractional seconds, offsets, and
///     locale, and disagreeing silently when they do not. An integer is an
///     integer in both languages. Ordering never depends on it regardless —
///     that is `ordinal`'s job.
///   * **A `kind` discriminator with named fields**, so a move is readable in a
///     database row by a person trying to work out what happened.
///   * **An explicit `v`.** The first thing a second client needs is the ability
///     to refuse a payload it does not understand, rather than to decode half of
///     it.
public struct GameMoveWire: Hashable, Sendable, Codable {

    /// Bumped only when the shape changes incompatibly. A reader that sees a
    /// version it does not know must reject the move, not guess at it.
    public static let currentVersion = 1

    public let version: Int
    public let ordinal: Int
    public let stepIndex: Int
    public let atMillis: Int64
    public let action: WireAction

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case ordinal
        case stepIndex = "step"
        case atMillis
        case action
    }

    /// The action, flattened to a discriminator plus named fields.
    ///
    /// A struct rather than an enum precisely so the encoding is stated rather
    /// than synthesized. `kind` carries the same names as `GameMove.Action`'s
    /// cases, and unused fields are omitted rather than sent as null.
    public struct WireAction: Hashable, Sendable, Codable {
        public let kind: String
        public let text: String?
        public let index: Int?
        public let item: Int?
        public let slot: Int?
        public let clue: Int?
        public let selected: Bool?

        public init(
            kind: String,
            text: String? = nil,
            index: Int? = nil,
            item: Int? = nil,
            slot: Int? = nil,
            clue: Int? = nil,
            selected: Bool? = nil
        ) {
            self.kind = kind
            self.text = text
            self.index = index
            self.item = item
            self.slot = slot
            self.clue = clue
            self.selected = selected
        }
    }

    public init(
        version: Int = GameMoveWire.currentVersion,
        ordinal: Int,
        stepIndex: Int,
        atMillis: Int64,
        action: WireAction
    ) {
        self.version = version
        self.ordinal = ordinal
        self.stepIndex = stepIndex
        self.atMillis = atMillis
        self.action = action
    }
}

// MARK: - Mapping

public extension GameMoveWire {

    /// Every case named explicitly, with no `default`.
    ///
    /// The missing `default` is the point: adding a case to `GameMove.Action`
    /// must fail to compile here, so the wire format and the Kotlin client are
    /// updated deliberately rather than a new action silently encoding as
    /// something else.
    init(_ move: GameMove) {
        let action: WireAction = switch move.action {
        case .answer(let text):
            WireAction(kind: "answer", text: text)
        case .choose(let index):
            WireAction(kind: "choose", index: index)
        case .assign(let item, let slot):
            WireAction(kind: "assign", item: item, slot: slot)
        case .unassign(let item):
            WireAction(kind: "unassign", item: item)
        case .toggle(let item, let isSelected):
            WireAction(kind: "toggle", item: item, selected: isSelected)
        case .reveal(let clue):
            WireAction(kind: "reveal", clue: clue)
        case .hint:
            WireAction(kind: "hint")
        case .skip:
            WireAction(kind: "skip")
        case .advance:
            WireAction(kind: "advance")
        }

        self.init(
            ordinal: move.ordinal,
            stepIndex: move.stepIndex,
            // Rounded, not truncated, and this is a latent bug rather than a
            // style preference.
            //
            // `Int64(x)` truncates toward zero, and `Double(ms) / 1000 * 1000`
            // lands fractionally under its integer for some values — so a
            // millisecond is lost, and lost again on each further encode, since
            // the value is decoded back into a `Date` and may be re-encoded.
            //
            // Whether it bites depends on the magnitude, which is what makes it
            // nasty. Around 1.07e12 — early 2004 — truncation loses 24% of
            // milliseconds. At today's epoch (~1.79e12) it loses none, so the
            // obvious present-day test passes with the broken conversion and
            // the fault would surface years later, on a date nobody would
            // connect to a move arriving a millisecond early.
            //
            // Rounding is correct in every range. `GameMoveWireTests` pins it
            // with instants drawn from a range where truncation demonstrably
            // fails, because a test using only current timestamps cannot tell
            // the two implementations apart.
            atMillis: Int64((move.occurredAt.timeIntervalSince1970 * 1000).rounded()),
            action: action
        )
    }

    /// Rejects anything it cannot represent exactly.
    ///
    /// Returns nil for an unknown version or an unknown kind, and — importantly
    /// — for a known kind whose fields are missing. A `choose` with no index is
    /// not a move to be salvaged with a zero; it is a payload from a client that
    /// disagrees with this one, and playing a turn nobody made is worse than
    /// refusing it.
    func toMove() -> GameMove? {
        guard version == Self.currentVersion else { return nil }

        let resolved: GameMove.Action
        switch action.kind {
        case "answer":
            guard let text = action.text else { return nil }
            resolved = .answer(text)
        case "choose":
            guard let index = action.index else { return nil }
            resolved = .choose(index)
        case "assign":
            guard let item = action.item, let slot = action.slot else { return nil }
            resolved = .assign(item: item, slot: slot)
        case "unassign":
            guard let item = action.item else { return nil }
            resolved = .unassign(item: item)
        case "toggle":
            guard let item = action.item, let selected = action.selected else { return nil }
            resolved = .toggle(item: item, isSelected: selected)
        case "reveal":
            guard let clue = action.clue else { return nil }
            resolved = .reveal(clue: clue)
        case "hint":
            resolved = .hint
        case "skip":
            resolved = .skip
        case "advance":
            resolved = .advance
        default:
            return nil
        }

        return GameMove(
            ordinal: ordinal,
            stepIndex: stepIndex,
            action: resolved,
            occurredAt: Date(timeIntervalSince1970: Double(atMillis) / 1000)
        )
    }
}

// MARK: - Idempotency

public extension GameMoveWire {

    /// The key that makes a redelivered move one move (ADR-011, ADR-035).
    ///
    /// Derived from the session and the ordinal rather than from content or a
    /// timestamp: a retry after a dropped connection produces a byte-identical
    /// key, while a genuinely different turn cannot collide because two moves
    /// never share an ordinal in one session. A UUID generated at send time
    /// would have failed exactly the case this exists for — the retry.
    static func actionKey(sessionID: UUID, ordinal: Int) -> String {
        "game.move.\(sessionID.uuidString.lowercased()).\(ordinal)"
    }
}
