import Foundation
import Testing
@testable import SunnieShared

/// The cross-language move contract (ADR-035).
///
/// These read `Backend/contract/move-fixtures.json` — the same bytes the Kotlin
/// client's tests read. That is the whole point of the file: the Android app
/// reimplements the rules of a mechanic in another language, and the one thing
/// that must not drift between the two is what a move looks like on the wire.
/// A divergence here fails a test on whichever side moved, rather than
/// producing a game where one player's turn silently does nothing.
///
/// Read from the repository by path rather than bundled as a package resource,
/// so there is exactly one copy of the fixtures and no build step that could let
/// the two get out of sync.
@Suite("Game move wire format")
struct GameMoveWireTests {

    // MARK: - Fixtures

    private struct Fixtures: Decodable {
        let wireVersion: Int
        let cases: [Case]
        let rejected: [Rejection]

        struct Case: Decodable {
            let name: String
            let encoded: String
            let ordinal: Int
            let step: Int
            let atMillis: Int64
            let kind: String
        }

        struct Rejection: Decodable {
            let name: String
            let encoded: String
            let why: String
        }
    }

    /// `Backend/contract/move-fixtures.json`, found relative to this file.
    private static func loadFixtures() throws -> Fixtures {
        // …/Packages/SunnieShared/Tests/SunnieSharedTests/<this file>
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root
            .appendingPathComponent("Backend")
            .appendingPathComponent("contract")
            .appendingPathComponent("move-fixtures.json")

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixtures.self, from: data)
    }

    /// Sorted keys and no whitespace, which is what "canonical" means in the
    /// fixture file. Without sorting, two encoders that agree completely about
    /// content still produce different bytes, and the comparison below would
    /// test dictionary iteration order rather than the format.
    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    // MARK: - Round trips

    @Test("Every fixture decodes, maps to a move, and re-encodes byte-identically")
    func fixturesRoundTrip() throws {
        let fixtures = try Self.loadFixtures()
        #expect(fixtures.wireVersion == GameMoveWire.currentVersion)

        for testCase in fixtures.cases {
            let data = try #require(
                testCase.encoded.data(using: .utf8),
                "\(testCase.name): fixture is not valid UTF-8"
            )

            let wire = try JSONDecoder().decode(GameMoveWire.self, from: data)
            #expect(wire.ordinal == testCase.ordinal, "\(testCase.name): ordinal")
            #expect(wire.stepIndex == testCase.step, "\(testCase.name): step")
            #expect(wire.atMillis == testCase.atMillis, "\(testCase.name): atMillis")
            #expect(wire.action.kind == testCase.kind, "\(testCase.name): kind")

            // Through the domain type and back. Mapping in only one direction
            // would let an asymmetry sit undetected until a real game hit it.
            let move = try #require(wire.toMove(), "\(testCase.name): did not map to a move")
            let round = GameMoveWire(move)

            let reencoded = try Self.canonicalEncoder().encode(round)
            let text = try #require(String(data: reencoded, encoding: .utf8))
            #expect(
                text == testCase.encoded,
                """
                \(testCase.name): re-encoding did not match the fixture.
                  expected: \(testCase.encoded)
                  actual:   \(text)
                """
            )
        }
    }

    @Test("Every action case is covered by a fixture")
    func fixturesCoverEveryAction() throws {
        // Guards the fixtures rather than the code: adding an action to
        // `GameMove.Action` fails to compile in `GameMoveWire` by design, and
        // this makes the *contract file* fail too, so the Kotlin side is not
        // left with a case it never sees an example of.
        let expected: Set<String> = [
            "answer", "choose", "assign", "unassign",
            "toggle", "reveal", "hint", "skip", "advance"
        ]
        let covered = Set(try Self.loadFixtures().cases.map(\.kind))
        #expect(
            covered == expected,
            "Fixtures miss: \(expected.subtracting(covered)); unexpected: \(covered.subtracting(expected))"
        )
    }

    // MARK: - Refusals

    @Test("A payload this client cannot represent exactly is refused")
    func rejectedFixturesDoNotBecomeMoves() throws {
        for rejection in try Self.loadFixtures().rejected {
            let data = try #require(rejection.encoded.data(using: .utf8))

            // Some refusals fail at decoding and some at mapping; both are
            // refusals. What must never happen is a move coming out.
            let wire = try? JSONDecoder().decode(GameMoveWire.self, from: data)
            let move = wire?.toMove()
            #expect(move == nil, "\(rejection.name) produced a move. \(rejection.why)")
        }
    }

    // MARK: - Idempotency

    @Test("The action key survives a retry and separates real turns")
    func actionKeyIsStableAndDistinct() {
        let session = UUID()
        let other = UUID()
        let me = UUID()
        let them = UUID()

        // The case this exists for: the same turn sent twice after a dropped
        // connection must produce the same key, or it plays twice.
        #expect(
            GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 3)
                == GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 3)
        )
        #expect(
            GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 3)
                != GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 4)
        )
        // Two sessions may legitimately both have an ordinal 3.
        #expect(
            GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 3)
                != GameMoveWire.actionKey(sessionID: other, playerID: me, ordinal: 3)
        )
        // And so may two players in one session, before the database has
        // settled which of them actually gets it. This is what keeps the two
        // uniqueness constraints independent rather than one written twice.
        #expect(
            GameMoveWire.actionKey(sessionID: session, playerID: me, ordinal: 3)
                != GameMoveWire.actionKey(sessionID: session, playerID: them, ordinal: 3)
        )
    }

    @Test("Repeated encoding never shaves a millisecond off the instant")
    func timestampsDoNotDrift() throws {
        // These specific instants are the test.
        //
        // The conversion originally truncated, and the obvious test — a present
        // day timestamp, encoded and decoded — passes with truncation. It has
        // to: whether `Double(ms)/1000 * 1000` lands under its integer depends
        // on the binade the value sits in, and today's epoch milliseconds
        // (~1.79e12) sit in a range where it never does. Around 1.07e12 — early
        // 2004 — it does for 24% of milliseconds.
        //
        // So truncation is not a bug that is currently biting. It is one that
        // starts biting when the epoch crosses into an unlucky range, on a date
        // nobody would connect to a game move arriving a millisecond early. The
        // values below are drawn from a range where truncation demonstrably
        // fails, which is the only way this test can distinguish the fixed
        // conversion from the broken one.
        var milliseconds: [Int64] = [
            1_073_906_883_784,
            1_073_989_401_853,
            1_074_142_255_419,
            1_074_156_457_202,
            1_074_167_542_544
        ]
        // Plus a present-day span, so the everyday case is covered too.
        var value: Int64 = 1_786_000_000_000
        for step in 0..<100 {
            milliseconds.append(value)
            value += Int64(step * 7 + 1)
        }

        for start in milliseconds {
            var wire = GameMoveWire(
                GameMove(
                    ordinal: 0,
                    stepIndex: 0,
                    action: .answer("lisbon"),
                    occurredAt: Date(timeIntervalSince1970: Double(start) / 1000)
                )
            )
            #expect(wire.atMillis == start, "encoding \(start) did not preserve it")

            // And again, because drift is cumulative: a conversion that loses
            // a millisecond per pass is a slow walk backwards through time.
            for _ in 0..<3 {
                wire = GameMoveWire(try #require(wire.toMove()))
            }
            #expect(wire.atMillis == start, "\(start) drifted to \(wire.atMillis)")
        }
    }
}
