import Foundation

/// A move as the server holds it: the domain move plus the row's own columns.
///
/// `sequence` and `move.ordinal` carry the same number by design — see
/// ``MultiplayerTurn/resequenced(_:to:)``. They are kept as separate fields
/// rather than collapsed because different things enforce them: the sequence by
/// a database uniqueness constraint, the ordinal by replay. Keeping both makes a
/// disagreement between them something a test can express rather than something
/// the type system quietly rules out and the database does not.
public struct RemoteMove: Hashable, Sendable {
    public let sequence: Int
    public let playerID: UUID
    public let actionKey: String
    public let move: GameMove

    public init(sequence: Int, playerID: UUID, actionKey: String, move: GameMove) {
        self.sequence = sequence
        self.playerID = playerID
        self.actionKey = actionKey
        self.move = move
    }
}

/// Whose turn it is, what number the next move takes, and which local moves the
/// server has not seen.
///
/// All three are derived from the moves rather than read from a column, and that
/// is the central choice here — the schema does carry a `turn_player_id`, and
/// trusting it would be easier.
///
/// A turn column is mutable state both clients write. It can go stale, it can be
/// written twice, and when it disagrees with the moves nothing can say which is
/// right. The failure it produces is both players looking at "waiting for the
/// other player" forever, which is indistinguishable from a network problem and
/// which neither of them can clear. Deriving the turn from the move list makes
/// that unrepresentable: moves are append-only and uniquely sequenced by the
/// database, so two clients replaying the same moves cannot reach different
/// answers about who plays next.
///
/// `turn_player_id` stays in the schema as a hook for a future server-side
/// notification, which is a thing a column is good for. Nothing reads it here,
/// and nothing should start without first deciding what happens when it
/// contradicts the moves.
///
/// Pinned to `Backend/contract/turn-fixtures.json`, which the Kotlin suite also
/// reads, so the Android client cannot drift from it (ADR-035).
public enum MultiplayerTurn {

    /// Two seats. Named rather than spelled `2` at each use site.
    public static let seatCount = 2

    /// The sequence number the next move should claim.
    ///
    /// One past the highest already taken, rather than the count: a gap — a move
    /// this client has not fetched, or one a policy filtered out — must not
    /// produce a collision with a number already in the table. The database's
    /// `unique (session_id, sequence)` is the real arbiter; this only has to be
    /// right often enough that the ordinary case does not round-trip through a
    /// rejection.
    public static func nextSequence(after moves: [RemoteMove]) -> Int {
        (moves.map(\.sequence).max() ?? -1) + 1
    }

    /// The seat whose turn it is at a given step.
    ///
    /// Seats own steps by parity: seat 0 plays stop 0, seat 1 plays stop 1, and
    /// on. This is what makes the turn a function of the board — a wrong answer
    /// or a hint leaves the step where it was and so leaves the turn with the
    /// same player, which is what anyone playing would expect. Solving or
    /// skipping moves the step on, and the turn goes with it.
    ///
    /// A step that advances by two — which happens when resuming a route where a
    /// later stop was already settled — hands one seat two turns in a row. That
    /// follows from the rule rather than being an oversight: both clients
    /// compute it identically, which is the property that matters, and taking
    /// turns strictly would mean tracking turn state apart from the board and
    /// reintroducing exactly the drift this design removes.
    public static func seatToPlay(currentStep: Int, seatCount: Int = MultiplayerTurn.seatCount) -> Int {
        precondition(seatCount > 0, "A session needs at least one seat")
        // Swift's % keeps the sign of the dividend, as Kotlin's does, so a
        // negative step — which should never arrive, but would come from a
        // corrupt save rather than from anything this module controls — is
        // folded into range instead of naming a seat that does not exist.
        return ((currentStep % seatCount) + seatCount) % seatCount
    }

    /// True when `seat` is the seat that plays at `currentStep`.
    public static func isMyTurn(
        currentStep: Int, seat: Int, seatCount: Int = MultiplayerTurn.seatCount
    ) -> Bool {
        seatToPlay(currentStep: currentStep, seatCount: seatCount) == seat
    }

    /// The local moves the server has not recorded, in order.
    ///
    /// Matched by action key rather than by ordinal or by content. A move the
    /// database accepted whose response never reached the phone is already there
    /// under its key; resubmitting it would be refused — but only after a round
    /// trip, and only while the key stays the same. Filtering here means a
    /// reconnect sends what is genuinely missing instead of replaying an outbox
    /// and relying on the server to reject most of it (ADR-011).
    public static func unsubmitted(
        pending: [GameMove], recorded: [RemoteMove], sessionID: UUID
    ) -> [GameMove] {
        let keys = Set(recorded.map(\.actionKey))
        return pending.filter {
            !keys.contains(GameMoveWire.actionKey(sessionID: sessionID, ordinal: $0.ordinal))
        }
    }

    /// Renumbers a move that lost a race for its sequence number.
    ///
    /// Both players submitting at once is not an error to be prevented — it is
    /// what happens when two people are playing. One insert wins; the other
    /// comes back with a uniqueness violation, re-reads, and takes the next free
    /// number.
    ///
    /// The ordinal moves with the sequence, and this is the part easy to get
    /// wrong: the ordinal is what replay sorts by, so a move stored at sequence
    /// 5 while still claiming ordinal 4 would replay ahead of the move that beat
    /// it. The two are the same number, and since the action key is derived from
    /// the ordinal, renumbering also gives the retry a new key — correctly,
    /// because it is now a different move in the sequence.
    public static func resequenced(_ move: GameMove, to ordinal: Int) -> GameMove {
        GameMove(
            ordinal: ordinal,
            stepIndex: move.stepIndex,
            action: move.action,
            occurredAt: move.occurredAt
        )
    }
}
