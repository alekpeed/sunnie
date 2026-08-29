import Foundation
import Testing
@testable import SunnieShared

/// The Swift half of the answer-matching contract (ADR-035).
///
/// Reads `Backend/contract/answer-fixtures.json`, the same file the Kotlin
/// suite reads. Without this, the fixtures would constrain only the Android
/// client and the "shared" contract would be a document rather than a check.
///
/// This is the rule set most worth pinning, and the one whose drift is quietest.
/// A move that fails to decode is visibly broken and someone investigates. A
/// normaliser that accepts "cafe" for "café" on one phone and rejects it on the
/// other produces a game where one player is simply wrong more often, with
/// nothing on screen to explain why — and nothing in either log either.
@Suite("Answer contract")
struct AnswerContractTests {

    private struct Fixtures: Decodable {
        let normalize: [NormalizeCase]
        let matches: [MatchCase]
        let nearMiss: [MatchCase]

        struct NormalizeCase: Decodable {
            let input: String
            let expected: String
            let why: String?
        }

        struct MatchCase: Decodable {
            let input: String
            let accepted: [String]
            let expected: Bool
            let why: String?
        }
    }

    /// Found by path relative to this file, so there is one copy of the
    /// fixtures and no build step that could let the two clients drift apart.
    private static func loadFixtures() throws -> Fixtures {
        // …/Packages/SunnieShared/Tests/SunnieSharedTests/<this file>
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root
            .appendingPathComponent("Backend")
            .appendingPathComponent("contract")
            .appendingPathComponent("answer-fixtures.json")

        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    @Test("Normalising follows the contract")
    func normalizeMatchesContract() throws {
        for testCase in try Self.loadFixtures().normalize {
            #expect(
                AnswerNormalizer.normalize(testCase.input) == testCase.expected,
                """
                normalize("\(testCase.input)") gave \
                "\(AnswerNormalizer.normalize(testCase.input))", contract says \
                "\(testCase.expected)". \(testCase.why ?? "")
                """
            )
        }
    }

    @Test("Matching follows the contract")
    func matchingFollowsContract() throws {
        for testCase in try Self.loadFixtures().matches {
            #expect(
                AnswerNormalizer.matches(testCase.input, accepted: testCase.accepted)
                    == testCase.expected,
                """
                matches("\(testCase.input)", \(testCase.accepted)) disagrees with \
                the contract. \(testCase.why ?? "")
                """
            )
        }
    }

    @Test("Near misses follow the contract")
    func nearMissFollowsContract() throws {
        for testCase in try Self.loadFixtures().nearMiss {
            #expect(
                AnswerNormalizer.isNearMiss(testCase.input, accepted: testCase.accepted)
                    == testCase.expected,
                """
                isNearMiss("\(testCase.input)", \(testCase.accepted)) disagrees with \
                the contract. \(testCase.why ?? "")
                """
            )
        }
    }

    @Test("The contract covers the cases that would otherwise diverge silently")
    func contractCoversTheHardCases() throws {
        // Guards the fixture file rather than the code. Each of these is a place
        // the two implementations use genuinely different machinery — Swift's
        // `folding(options:locale:)` against the JVM's NFKD plus a category
        // check — so dropping one from the fixtures would quietly remove the
        // only thing holding them together.
        let inputs = Set(try Self.loadFixtures().normalize.map(\.input))

        let required = [
            "café",          // accent folding
            "don’t",         // a curly apostrophe the keyboard substitutes
            "`quoted`",      // backtick: a symbol, not punctuation, in Unicode
            "el—sol",        // em dash
            ""               // empty in, empty out rather than a trap
        ]

        for input in required {
            #expect(
                inputs.contains(input),
                "The answer contract no longer covers \"\(input)\", which is a case the two clients implement differently."
            )
        }
    }
}
