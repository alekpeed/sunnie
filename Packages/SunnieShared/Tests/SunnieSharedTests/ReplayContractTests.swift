import Foundation
import Testing
@testable import SunnieShared

/// The Swift half of the replay contract (ADR-035).
///
/// Reads `Backend/contract/replay-fixtures.json`, the same file the Kotlin suite
/// reads. Replay is the mechanism the whole feature rests on: the server stores
/// moves rather than boards, and each client rebuilds the board itself. Neither
/// side is authoritative, so the only thing making them agree is that both
/// implementations of `replay` behave identically.
///
/// A divergence here is not a cosmetic bug. It is two players looking at
/// different games while both believe they are looking at the same one — one
/// seeing a stop as solved that the other still shows as open.
@Suite("Replay contract")
struct ReplayContractTests {

    private struct Fixtures: Decodable {
        let puzzle: PuzzleFixture
        let cases: [Case]

        struct PuzzleFixture: Decodable {
            let stops: [StopFixture]
            struct StopFixture: Decodable {
                let answer: String
                let alternates: [String]
            }
        }

        struct Case: Decodable {
            let name: String
            let moves: [MoveFixture]
            let expected: Expected
            let why: String?
        }

        struct MoveFixture: Decodable {
            let ordinal: Int
            let step: Int
            let kind: String
            let text: String?
            let index: Int?
        }

        struct Expected: Decodable {
            let currentStop: Int
            let stops: [StopExpectation]
        }

        struct StopExpectation: Decodable {
            let lastAnswer: String?
            let isSolved: Bool
            let wasSkipped: Bool
            let hintsRevealed: Int
            let wrongAttempts: Int
            let lastAnswerWasNearMiss: Bool
        }
    }

    private static func loadFixtures() throws -> Fixtures {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root
            .appendingPathComponent("Backend")
            .appendingPathComponent("contract")
            .appendingPathComponent("replay-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    /// The fixture puzzle, with only the fields replay actually reads.
    ///
    /// The prompt, hints, language, and link explanation are filled with
    /// placeholders on purpose: none of them affects the board, and putting real
    /// content in the fixture would mean maintaining a second content model
    /// alongside the rules the file exists to pin.
    private static func puzzle(from fixture: Fixtures.PuzzleFixture) -> AnswerChainPuzzle {
        AnswerChainPuzzle(
            stops: fixture.stops.map { stop in
                AnswerChainStop(
                    prompt: GameText(text: "", localizationKey: ""),
                    answer: stop.answer,
                    alternates: stop.alternates,
                    linkExplanation: GameText(text: "", localizationKey: "")
                )
            }
        )
    }

    private static func move(from fixture: Fixtures.MoveFixture) throws -> GameMove {
        let action: GameMove.Action
        switch fixture.kind {
        case "answer":
            action = .answer(try #require(fixture.text, "answer fixture has no text"))
        case "hint":
            action = .hint
        case "skip":
            action = .skip
        case "choose":
            action = .choose(try #require(fixture.index, "choose fixture has no index"))
        case "advance":
            action = .advance
        default:
            Issue.record("Fixture uses an action this test cannot build: \(fixture.kind)")
            action = .skip
        }

        return GameMove(
            ordinal: fixture.ordinal,
            stepIndex: fixture.step,
            action: action,
            occurredAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Every replay fixture reaches the board the contract states")
    func replayMatchesContract() throws {
        let fixtures = try Self.loadFixtures()
        let puzzle = Self.puzzle(from: fixtures.puzzle)

        for testCase in fixtures.cases {
            let moves = try testCase.moves.map { try Self.move(from: $0) }
            let board = AnswerChainEngine.replay(puzzle: puzzle, moves: moves)

            #expect(
                board.currentStop == testCase.expected.currentStop,
                "\(testCase.name): currentStop was \(board.currentStop), contract says \(testCase.expected.currentStop). \(testCase.why ?? "")"
            )
            #expect(
                board.stops.count == testCase.expected.stops.count,
                "\(testCase.name): stop count"
            )

            for (index, expected) in testCase.expected.stops.enumerated()
            where index < board.stops.count {
                let actual = board.stops[index]
                let where_ = "\(testCase.name): stop \(index)"

                #expect(actual.lastAnswer == expected.lastAnswer, "\(where_) lastAnswer")
                #expect(actual.isSolved == expected.isSolved, "\(where_) isSolved")
                #expect(actual.wasSkipped == expected.wasSkipped, "\(where_) wasSkipped")
                #expect(actual.hintsRevealed == expected.hintsRevealed, "\(where_) hintsRevealed")
                #expect(actual.wrongAttempts == expected.wrongAttempts, "\(where_) wrongAttempts")
                #expect(
                    actual.lastAnswerWasNearMiss == expected.lastAnswerWasNearMiss,
                    "\(where_) lastAnswerWasNearMiss"
                )
            }
        }
    }

    @Test("Arrival order does not change the board")
    func arrivalOrderDoesNotMatter() throws {
        // The ordinal is the sequence; the order moves happen to arrive in is
        // latency. If those two were ever confused, a game would replay
        // differently on a slow connection than a fast one — which is the kind
        // of bug that reproduces for one person and not the other.
        let fixtures = try Self.loadFixtures()
        let puzzle = Self.puzzle(from: fixtures.puzzle)

        for testCase in fixtures.cases where testCase.moves.count > 1 {
            let moves = try testCase.moves.map { try Self.move(from: $0) }
            let forward = AnswerChainEngine.replay(puzzle: puzzle, moves: moves)
            let backward = AnswerChainEngine.replay(puzzle: puzzle, moves: moves.reversed())

            #expect(forward == backward, "\(testCase.name): reversed arrival order changed the board")
        }
    }

    @Test("Replaying the same moves twice gives the same board")
    func replayIsDeterministic() throws {
        // The server stores moves rather than state, so replay has to be a pure
        // function of them. Anything reaching for a clock or a random seed
        // breaks the premise that both clients can rebuild the same board.
        let fixtures = try Self.loadFixtures()
        let puzzle = Self.puzzle(from: fixtures.puzzle)

        for testCase in fixtures.cases {
            let moves = try testCase.moves.map { try Self.move(from: $0) }
            #expect(
                AnswerChainEngine.replay(puzzle: puzzle, moves: moves)
                    == AnswerChainEngine.replay(puzzle: puzzle, moves: moves),
                testCase.name
            )
        }
    }
}
