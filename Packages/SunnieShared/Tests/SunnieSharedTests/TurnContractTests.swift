import Foundation
import Testing
@testable import SunnieShared

/// The Swift half of the turn contract (ADR-035).
///
/// Reads `Backend/contract/turn-fixtures.json`, the same file the Kotlin suite
/// reads. Replay decides what the board looks like; these rules decide who plays
/// next, and their failure mode is the harder one to diagnose — not a wrong
/// board, but both players waiting for each other, which looks exactly like a
/// bad connection to both of them.
@Suite("Turn contract")
struct TurnContractTests {

    private struct Fixtures: Decodable {
        let actionKey: Section<ActionKeyCase>
        let nextSequence: Section<NextSequenceCase>
        let seatToPlay: Section<SeatCase>
        let unsubmitted: UnsubmittedSection
        let resequenced: Section<ResequenceCase>

        struct Section<Case: Decodable>: Decodable {
            let cases: [Case]
        }

        struct ActionKeyCase: Decodable {
            let sessionId: String
            let playerId: String
            let ordinal: Int
            let expected: String
            let why: String?
        }

        struct NextSequenceCase: Decodable {
            let name: String
            let sequences: [Int]
            let expected: Int
        }

        struct SeatCase: Decodable {
            let name: String
            let currentStep: Int
            let seatCount: Int
            let expected: Int
            let why: String?
        }

        struct UnsubmittedSection: Decodable {
            let sessionId: String
            let playerId: String
            let opponentPlayerId: String
            let cases: [UnsubmittedCase]
        }

        struct UnsubmittedCase: Decodable {
            let name: String
            let pendingOrdinals: [Int]
            let recordedOrdinals: [Int]
            let opponentOrdinals: [Int]
            let expected: [Int]
            let why: String?
        }

        struct ResequenceCase: Decodable {
            let name: String
            let sessionId: String
            let playerId: String
            let fromOrdinal: Int
            let toOrdinal: Int
            let expectedKey: String
            let why: String?
        }
    }

    private static func loadFixtures() throws -> Fixtures {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root
            .appendingPathComponent("Backend")
            .appendingPathComponent("contract")
            .appendingPathComponent("turn-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    /// A move whose only interesting field is its ordinal.
    private static func move(ordinal: Int) -> GameMove {
        GameMove(
            ordinal: ordinal,
            stepIndex: 0,
            action: .skip,
            occurredAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func remote(ordinal: Int, sessionID: UUID, playerID: UUID) -> RemoteMove {
        RemoteMove(
            sequence: ordinal,
            playerID: playerID,
            actionKey: GameMoveWire.actionKey(
                sessionID: sessionID, playerID: playerID, ordinal: ordinal
            ),
            move: move(ordinal: ordinal)
        )
    }

    @Test("The action key follows the contract")
    func actionKeyFollowsContract() throws {
        for testCase in try Self.loadFixtures().actionKey.cases {
            let sessionID = try #require(
                UUID(uuidString: testCase.sessionId),
                "Fixture session id is not a UUID"
            )
            let playerID = try #require(
                UUID(uuidString: testCase.playerId),
                "Fixture player id is not a UUID"
            )
            #expect(
                GameMoveWire.actionKey(
                    sessionID: sessionID, playerID: playerID, ordinal: testCase.ordinal
                ) == testCase.expected,
                "actionKey(\(testCase.sessionId), \(testCase.playerId), \(testCase.ordinal)). \(testCase.why ?? "")"
            )
        }
    }

    @Test("The same session spelled two ways gives one key")
    func caseDoesNotSplitAKey() throws {
        // Why the contract lowercases at all: Swift prints a UUID uppercase and
        // Postgres prints it lowercase, so one session reaches the two clients
        // spelled differently — and the uniqueness constraint compares the
        // strings, not the identifiers. Without this, both players could play
        // the same turn.
        let lower = try #require(UUID(uuidString: "7f3a1c92-2b48-4d0e-9a61-5c8e0b2d4f71"))
        let upper = try #require(UUID(uuidString: "7F3A1C92-2B48-4D0E-9A61-5C8E0B2D4F71"))
        let player = try #require(UUID(uuidString: "1c0ffee0-0000-4000-8000-00000000beef"))
        #expect(
            GameMoveWire.actionKey(sessionID: lower, playerID: player, ordinal: 3)
                == GameMoveWire.actionKey(sessionID: upper, playerID: player, ordinal: 3)
        )
    }

    @Test("Next sequence follows the contract")
    func nextSequenceFollowsContract() throws {
        let sessionID = UUID()
        let playerID = UUID()
        for testCase in try Self.loadFixtures().nextSequence.cases {
            let moves = testCase.sequences.map {
                Self.remote(ordinal: $0, sessionID: sessionID, playerID: playerID)
            }
            #expect(
                MultiplayerTurn.nextSequence(after: moves) == testCase.expected,
                "\(testCase.name): got \(MultiplayerTurn.nextSequence(after: moves)), contract says \(testCase.expected)"
            )
        }
    }

    @Test("Seat to play follows the contract")
    func seatToPlayFollowsContract() throws {
        for testCase in try Self.loadFixtures().seatToPlay.cases {
            let seat = MultiplayerTurn.seatToPlay(
                currentStep: testCase.currentStep, seatCount: testCase.seatCount
            )
            #expect(
                seat == testCase.expected,
                "\(testCase.name): got seat \(seat), contract says \(testCase.expected). \(testCase.why ?? "")"
            )

            // isMyTurn is the form the UI calls, so it is checked against the
            // same case rather than trusted to agree with seatToPlay.
            #expect(
                MultiplayerTurn.isMyTurn(
                    currentStep: testCase.currentStep,
                    seat: testCase.expected,
                    seatCount: testCase.seatCount
                ),
                "\(testCase.name): isMyTurn disagreed with seatToPlay"
            )
            for other in 0..<testCase.seatCount where other != testCase.expected {
                #expect(
                    !MultiplayerTurn.isMyTurn(
                        currentStep: testCase.currentStep,
                        seat: other,
                        seatCount: testCase.seatCount
                    ),
                    "\(testCase.name): seat \(other) should not be playing"
                )
            }
        }
    }

    @Test("Unsubmitted follows the contract")
    func unsubmittedFollowsContract() throws {
        let section = try Self.loadFixtures().unsubmitted
        let sessionID = try #require(UUID(uuidString: section.sessionId))
        let playerID = try #require(UUID(uuidString: section.playerId))
        let opponentID = try #require(UUID(uuidString: section.opponentPlayerId))

        for testCase in section.cases {
            let pending = testCase.pendingOrdinals.map { Self.move(ordinal: $0) }
            let mine = testCase.recordedOrdinals.map {
                Self.remote(ordinal: $0, sessionID: sessionID, playerID: playerID)
            }
            let theirs = testCase.opponentOrdinals.map {
                Self.remote(ordinal: $0, sessionID: sessionID, playerID: opponentID)
            }
            let result = MultiplayerTurn.unsubmitted(
                pending: pending, recorded: mine + theirs,
                sessionID: sessionID, playerID: playerID
            )
            #expect(
                result.map(\.ordinal) == testCase.expected,
                "\(testCase.name): got \(result.map(\.ordinal)), contract says \(testCase.expected). \(testCase.why ?? "")"
            )
        }
    }

    @Test("Resequencing follows the contract")
    func resequencingFollowsContract() throws {
        for testCase in try Self.loadFixtures().resequenced.cases {
            let sessionID = try #require(UUID(uuidString: testCase.sessionId))
            let playerID = try #require(UUID(uuidString: testCase.playerId))
            let renumbered = MultiplayerTurn.resequenced(
                Self.move(ordinal: testCase.fromOrdinal), to: testCase.toOrdinal
            )
            #expect(renumbered.ordinal == testCase.toOrdinal, "\(testCase.name): ordinal")
            #expect(
                GameMoveWire.actionKey(
                    sessionID: sessionID, playerID: playerID, ordinal: renumbered.ordinal
                ) == testCase.expectedKey,
                "\(testCase.name): key. \(testCase.why ?? "")"
            )
        }
    }

    // MARK: - Properties the fixtures state by example and this states in general

    @Test("Resequencing changes the ordinal and nothing else")
    func resequencingChangesOnlyTheOrdinal() {
        let original = GameMove(
            ordinal: 4,
            stepIndex: 2,
            action: .answer("lisbon"),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let renumbered = MultiplayerTurn.resequenced(original, to: 5)

        #expect(renumbered.stepIndex == original.stepIndex)
        #expect(renumbered.action == original.action)
        #expect(renumbered.occurredAt == original.occurredAt)
        #expect(renumbered == MultiplayerTurn.resequenced(original, to: 5))
    }

    @Test("The turn follows the board, not the number of moves")
    func theTurnFollowsTheBoard() {
        // The property the whole design rests on, checked against the engine: a
        // wrong answer and a hint are both moves, but neither settles the stop,
        // so neither hands the turn over. If the turn were counted from the move
        // list instead of read off the board, this is the test that would fail.
        let puzzle = AnswerChainPuzzle(
            stops: [
                AnswerChainStop(
                    prompt: GameText(text: "", localizationKey: ""),
                    answer: "Lisbon",
                    linkExplanation: GameText(text: "", localizationKey: "")
                ),
                AnswerChainStop(
                    prompt: GameText(text: "", localizationKey: ""),
                    answer: "Porto",
                    linkExplanation: GameText(text: "", localizationKey: "")
                )
            ]
        )
        let epoch = Date(timeIntervalSince1970: 0)
        let fumbling = [
            GameMove(ordinal: 0, stepIndex: 0, action: .answer("madrid"), occurredAt: epoch),
            GameMove(ordinal: 1, stepIndex: 0, action: .hint, occurredAt: epoch),
            GameMove(ordinal: 2, stepIndex: 0, action: .answer("lisbo"), occurredAt: epoch)
        ]

        let stillStuck = AnswerChainEngine.replay(puzzle: puzzle, moves: fumbling)
        #expect(stillStuck.currentStop == 0)
        #expect(MultiplayerTurn.isMyTurn(currentStep: stillStuck.currentStop, seat: 0))

        let solved = AnswerChainEngine.replay(
            puzzle: puzzle,
            moves: fumbling + [
                GameMove(ordinal: 3, stepIndex: 0, action: .answer("Lisbon"), occurredAt: epoch)
            ]
        )
        #expect(solved.currentStop == 1)
        #expect(MultiplayerTurn.isMyTurn(currentStep: solved.currentStop, seat: 1))
        #expect(!MultiplayerTurn.isMyTurn(currentStep: solved.currentStop, seat: 0))
    }

    @Test("A finished route still names a seat that exists")
    func finishedRouteNamesARealSeat() {
        // currentStop equals the stop count once the route is done, so seatToPlay
        // is still asked. It must answer with a seat that exists rather than
        // reading off the end of anything.
        let seat = MultiplayerTurn.seatToPlay(currentStep: 3, seatCount: 2)
        #expect(seat >= 0 && seat < 2)
    }
}
