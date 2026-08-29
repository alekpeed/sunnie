import Foundation
import Testing
@testable import SunnieShared

/// The submit loop, driven against a stand-in for the table it talks to.
///
/// The fake enforces the two uniqueness constraints from
/// `Backend/supabase/migrations/0001_multiplayer.sql` and nothing else, because
/// those two are the entire contract the loop is written against. Anything more
/// would be a fake of the database rather than of the promises it makes, and
/// would start passing tests the real thing would fail.
///
/// The Kotlin suite runs the same scenarios against its own port. These are not
/// fixture-driven — the wire format is a contract, the retry policy is each
/// client's own — but the scenarios are kept in step deliberately, because a
/// client that gets these rules wrong loses a player's turn rather than
/// rendering something odd.
@Suite("Submit loop")
struct SubmitLoopTests {

    private let sessionID = UUID(uuidString: "7f3a1c92-2b48-4d0e-9a61-5c8e0b2d4f71")!
    private let me = UUID(uuidString: "1c0ffee0-0000-4000-8000-00000000beef")!
    private let them = UUID(uuidString: "2d0ffee0-0000-4000-8000-00000000cafe")!

    /// An append-only move table with `unique (session_id, sequence)` and
    /// `unique (session_id, action_key)`.
    ///
    /// `loseNextResponses` makes the next N attempts look unreachable *after*
    /// the row has been written, which is the case worth simulating: the insert
    /// succeeded and the response was lost. A fake that dropped the write
    /// instead would let a broken retry rule pass.
    private final class FakeMoves {
        var rows: [RemoteMove] = []
        var loseNextResponses = 0

        func submit(playerID: UUID, move: GameMove, actionKey: String) -> SubmitOutcome {
            if rows.contains(where: { $0.actionKey == actionKey }) { return .alreadyRecorded }
            if rows.contains(where: { $0.sequence == move.ordinal }) { return .sequenceTaken }

            rows.append(
                RemoteMove(
                    sequence: move.ordinal,
                    playerID: playerID,
                    actionKey: actionKey,
                    move: move
                )
            )

            if loseNextResponses > 0 {
                loseNextResponses -= 1
                return .unreachable("response lost after the row was written")
            }
            return .accepted
        }

        /// What the other player did, inserted directly.
        func otherPlayerTakes(sequence: Int, sessionID: UUID, playerID: UUID) {
            rows.append(
                RemoteMove(
                    sequence: sequence,
                    playerID: playerID,
                    actionKey: GameMoveWire.actionKey(
                        sessionID: sessionID, playerID: playerID, ordinal: sequence
                    ),
                    move: GameMove(
                        ordinal: sequence, stepIndex: 0, action: .skip,
                        occurredAt: Date(timeIntervalSince1970: 0)
                    )
                )
            )
        }
    }

    private func answer(_ text: String) -> GameMove {
        GameMove(
            ordinal: 0, stepIndex: 0, action: .answer(text),
            occurredAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Runs the loop to a terminal step.
    ///
    /// `refresh` decides what the client re-reads between attempts. It defaults
    /// to the fake's real contents; a test can pass a staler view to check that
    /// the loop does not depend on being perfectly informed.
    private func drive(
        _ server: FakeMoves,
        move: GameMove,
        playerID: UUID,
        refresh: (() -> [RemoteMove])? = nil
    ) -> (step: SubmitStep, attempts: Int) {
        let read = refresh ?? { server.rows }
        var step = SubmitLoop.first(
            sessionID: sessionID, playerID: playerID, move: move, known: read()
        )
        var attempts = 0

        while case .send(let sending, let key) = step {
            attempts += 1
            let outcome = server.submit(playerID: playerID, move: sending, actionKey: key)
            step = SubmitLoop.next(
                sessionID: sessionID, playerID: playerID, sent: sending,
                outcome: outcome, known: read(), attempt: attempts
            )
            if attempts > 20 { break } // a runaway loop is a failure, not a hang
        }
        return (step, attempts)
    }

    @Test("An ordinary submit takes one attempt and lands at sequence zero")
    func ordinarySubmit() {
        let server = FakeMoves()
        let result = drive(server, move: answer("lisbon"), playerID: me)

        #expect(result.step == .settled)
        #expect(result.attempts == 1)
        #expect(server.rows.count == 1)
        #expect(server.rows.first?.sequence == 0)
    }

    @Test("Losing the race for a sequence renumbers and succeeds")
    func losingTheRaceRenumbers() {
        let server = FakeMoves()
        server.otherPlayerTakes(sequence: 0, sessionID: sessionID, playerID: them)

        // The client's list is stale: it believes nothing has been played, so it
        // asks for sequence 0 and loses. This is the ordinary case for two
        // people submitting at once, not an exotic one.
        var stale = true
        let result = drive(server, move: answer("lisbon"), playerID: me) {
            if stale { stale = false; return [] }
            return server.rows
        }

        #expect(result.step == .settled)
        #expect(result.attempts == 2)
        #expect(server.rows.count == 2)
        #expect(server.rows.map(\.sequence).sorted() == [0, 1])
    }

    @Test("A lost response does not play the turn twice")
    func lostResponseDoesNotDuplicate() {
        // The property the action key exists for. The row is written, the
        // response never arrives, and the client retries. If the retry carried a
        // new key it would insert a second row — the player's answer submitted
        // twice, with nothing on screen explaining it and no way to take either
        // back.
        let server = FakeMoves()
        server.loseNextResponses = 1

        let result = drive(server, move: answer("lisbon"), playerID: me)

        #expect(result.step == .settled)
        #expect(result.attempts >= 1)
        #expect(server.rows.count == 1, "the same turn was recorded twice")
    }

    @Test("A retry after a lost response reuses the key rather than minting one")
    func lostResponseReusesTheKey() {
        // The rule stated directly rather than inferred from a row count: a
        // change that renumbered on `unreachable` could still leave one row in
        // the test above if the fake happened to dedupe first, so the key itself
        // is asserted.
        let sent = MultiplayerTurn.resequenced(answer("lisbon"), to: 3)
        let key = GameMoveWire.actionKey(sessionID: sessionID, playerID: me, ordinal: 3)

        let step = SubmitLoop.next(
            sessionID: sessionID, playerID: me, sent: sent,
            outcome: .unreachable("timeout"), known: [], attempt: 1
        )

        guard case .send(let move, let actionKey) = step else {
            Issue.record("A timeout is retryable, but the loop returned \(step)")
            return
        }
        #expect(actionKey == key, "the retry must carry the original key")
        #expect(move.ordinal == 3, "a timeout must not renumber the move")
    }

    @Test("A taken sequence is retried under a new key")
    func takenSequenceGetsANewKey() {
        // The opposite rule, and the reason the two outcomes cannot share a
        // path: here the server has said definitively that the move is not
        // recorded and its number belongs to someone else, so resending it
        // unchanged would fail the same way forever.
        let server = FakeMoves()
        server.otherPlayerTakes(sequence: 0, sessionID: sessionID, playerID: them)

        let step = SubmitLoop.next(
            sessionID: sessionID, playerID: me, sent: answer("lisbon"),
            outcome: .sequenceTaken, known: server.rows, attempt: 1
        )

        guard case .send(let move, let actionKey) = step else {
            Issue.record("A taken sequence is retryable, but the loop returned \(step)")
            return
        }
        #expect(move.ordinal == 1)
        #expect(
            actionKey == GameMoveWire.actionKey(
                sessionID: sessionID, playerID: me, ordinal: 1
            )
        )
    }

    @Test("A move already in the list settles whatever the server last said")
    func alreadyInTheListSettles() {
        // Closes the window where an accepted insert's response was lost and the
        // client has since re-read. Checked for every outcome, including the
        // ones that would otherwise retry.
        let server = FakeMoves()
        let sent = answer("lisbon")
        _ = server.submit(
            playerID: me, move: sent,
            actionKey: GameMoveWire.actionKey(sessionID: sessionID, playerID: me, ordinal: 0)
        )

        let outcomes: [SubmitOutcome] = [
            .accepted, .alreadyRecorded, .sequenceTaken, .unreachable("timeout")
        ]
        for outcome in outcomes {
            #expect(
                SubmitLoop.next(
                    sessionID: sessionID, playerID: me, sent: sent,
                    outcome: outcome, known: server.rows, attempt: 1
                ) == .settled,
                "outcome \(outcome) should settle once the move is in the list"
            )
        }
    }

    @Test("An unreachable server gives up rather than spinning")
    func unreachableEventuallyGivesUp() {
        let step = SubmitLoop.next(
            sessionID: sessionID, playerID: me, sent: answer("lisbon"),
            outcome: .unreachable("no route to host"), known: [],
            attempt: SubmitLoop.maximumAttempts
        )
        #expect(step == .gaveUp(reason: "no route to host"))
    }

    @Test("Giving up does not lose the move")
    func givingUpKeepsTheMove() {
        // Stated as a test because it is a product promise, not just a return
        // value: the move stays with the caller so the outbox can try again
        // later. Nothing in the loop consumes or mutates it.
        let sent = answer("lisbon")
        _ = SubmitLoop.next(
            sessionID: sessionID, playerID: me, sent: sent,
            outcome: .unreachable("offline"), known: [],
            attempt: SubmitLoop.maximumAttempts
        )
        #expect(sent.action == .answer("lisbon"))
        #expect(sent.ordinal == 0)
    }

    @Test("Two players racing repeatedly both land, with no gaps and no duplicates")
    func racingPlayersConverge() {
        // The end-to-end shape of the thing: alternating submissions where the
        // client's view is always one read behind. Every move must end up in the
        // table exactly once, and the sequence must have no holes — a hole would
        // leave nextSequence correct but replay reading a gap forever.
        let server = FakeMoves()
        var played: [String] = []

        for round in 0..<6 {
            let text = "answer-\(round)"
            played.append(text)
            let player = round.isMultiple(of: 2) ? me : them

            // Deliberately stale: the client starts each submit believing the
            // table is as it was one round ago.
            var step = SubmitLoop.first(
                sessionID: sessionID, playerID: player, move: answer(text),
                known: Array(server.rows.dropLast())
            )
            var attempts = 0
            while case .send(let sending, let key) = step {
                attempts += 1
                let outcome = server.submit(playerID: player, move: sending, actionKey: key)
                step = SubmitLoop.next(
                    sessionID: sessionID, playerID: player, sent: sending,
                    outcome: outcome, known: server.rows, attempt: attempts
                )
                if attempts > 20 { break }
            }
            #expect(step == .settled, "round \(round) did not settle")
        }

        #expect(server.rows.count == 6)
        #expect(server.rows.map(\.sequence).sorted() == Array(0..<6))
        #expect(Set(server.rows.map(\.actionKey)).count == 6)

        let texts = server.rows.sorted { $0.sequence < $1.sequence }.compactMap { row -> String? in
            if case .answer(let text) = row.move.action { return text }
            return nil
        }
        #expect(texts == played, "moves landed in an order the players did not play")
    }
}
