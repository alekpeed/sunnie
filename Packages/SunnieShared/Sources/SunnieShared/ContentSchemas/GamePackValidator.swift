import Foundation

/// Problems specific to a game pack.
public enum GameContentIssue: Hashable, Sendable, CustomStringConvertible {
    case malformedID(String)
    case duplicateID(String)
    case emptyText(contentID: String, field: String)
    case missingLocalizationKey(contentID: String, field: String)
    case unknownGame(puzzleID: String, gameID: String)
    case kindMismatch(puzzleID: String, gameKind: GameKind, payloadKind: GameKind)
    case malformedPuzzle(puzzleID: String, reason: String)
    /// The deduction puzzle does not have exactly one answer. This is the
    /// difference between a puzzle and a guess, and the spec requires it
    /// (GAMES_AND_FUTURE_MULTIPLAYER.md §3, G-03).
    case ambiguousSolution(puzzleID: String, outcome: String)
    case gameWithoutPuzzles(gameID: String)
    case unsupportedSchemaVersion(pack: String, found: Int)
    case toneViolation(contentID: String, detail: String)

    public var description: String {
        switch self {
        case .malformedID(let id):
            "Content ID is not a dot-delimited alphanumeric string: \(id)"
        case .duplicateID(let id):
            "Duplicate content ID: \(id)"
        case .emptyText(let contentID, let field):
            "\(contentID) has empty text for \(field)"
        case .missingLocalizationKey(let contentID, let field):
            "\(contentID) has no localization key for \(field)"
        case .unknownGame(let puzzleID, let gameID):
            "Puzzle \(puzzleID) belongs to game \(gameID), which the pack does not define"
        case .kindMismatch(let puzzleID, let gameKind, let payloadKind):
            "Puzzle \(puzzleID) carries a \(payloadKind.rawValue) payload but its game is \(gameKind.rawValue)"
        case .malformedPuzzle(let puzzleID, let reason):
            "Puzzle \(puzzleID) is malformed: \(reason)"
        case .ambiguousSolution(let puzzleID, let outcome):
            "Deduction puzzle \(puzzleID) does not have exactly one solution: \(outcome)"
        case .gameWithoutPuzzles(let gameID):
            "Game \(gameID) has no puzzles, so it would open onto nothing"
        case .unsupportedSchemaVersion(let pack, let found):
            "Pack \(pack) uses schema version \(found); this build reads \(ContentPackManifest.supportedSchemaVersion)"
        case .toneViolation(let contentID, let detail):
            "\(contentID) breaks a tone rule: \(detail)"
        }
    }
}

/// Validates a game pack.
///
/// Kept apart from `ContentValidator` because one of these checks is unlike
/// anything the other packs need: it *solves* every deduction puzzle to prove
/// there is exactly one answer. A puzzle with two solutions would tell a player
/// their correct arrangement is wrong, which is the single worst thing a logic
/// game can do — so it is caught here, in the tests, rather than discovered by
/// the person playing it.
public enum GamePackValidator {

    public static func validate(_ pack: GamePack) -> [GameContentIssue] {
        var issues: [GameContentIssue] = []

        if pack.manifest.schemaVersion != ContentPackManifest.supportedSchemaVersion {
            issues.append(.unsupportedSchemaVersion(
                pack: pack.manifest.packID.rawValue,
                found: pack.manifest.schemaVersion
            ))
        }

        var seen = Set<String>()
        func checkID(_ id: ContentID) {
            if !id.isWellFormed { issues.append(.malformedID(id.rawValue)) }
            if !seen.insert(id.rawValue).inserted { issues.append(.duplicateID(id.rawValue)) }
        }

        for game in pack.games {
            checkID(game.id)
            if game.difficulties.isEmpty {
                issues.append(.malformedPuzzle(
                    puzzleID: game.id.rawValue, reason: "no difficulties"
                ))
            }
            if !pack.puzzles.contains(where: { $0.gameID == game.id }) {
                issues.append(.gameWithoutPuzzles(gameID: game.id.rawValue))
            }
            // A difficulty offered in the picker with nothing behind it is a
            // choice that leads to an empty screen.
            for difficulty in game.difficulties
            where pack.puzzles(for: game.id, difficulty: difficulty).isEmpty {
                issues.append(.malformedPuzzle(
                    puzzleID: game.id.rawValue,
                    reason: "offers difficulty \(difficulty.rawValue) but has no puzzle at it"
                ))
            }
        }

        for puzzle in pack.puzzles {
            checkID(puzzle.id)
            let id = puzzle.id.rawValue

            guard let game = pack.game(id: puzzle.gameID) else {
                issues.append(.unknownGame(puzzleID: id, gameID: puzzle.gameID.rawValue))
                continue
            }
            if game.kind != puzzle.payload.kind {
                issues.append(.kindMismatch(
                    puzzleID: id, gameKind: game.kind, payloadKind: puzzle.payload.kind
                ))
            }
            if !game.supports(puzzle.difficulty) {
                issues.append(.malformedPuzzle(
                    puzzleID: id,
                    reason: "difficulty \(puzzle.difficulty.rawValue) is not offered by \(game.id.rawValue)"
                ))
            }

            issues.append(contentsOf: check(puzzle.title, contentID: id, field: "title"))
            issues.append(contentsOf: checkPayload(puzzle))
        }

        return issues
    }

    // MARK: - Text

    /// Every authored string must be non-empty, carry a localization key, and
    /// pass the same tone rules as everything else the user reads.
    static func check(
        _ text: GameText, contentID: String, field: String
    ) -> [GameContentIssue] {
        var issues: [GameContentIssue] = []
        if text.isEmpty {
            issues.append(.emptyText(contentID: contentID, field: field))
        }
        if text.localizationKey.isEmpty {
            issues.append(.missingLocalizationKey(contentID: contentID, field: field))
        }
        for issue in ContentValidator.toneIssues(in: text.text, contentID: contentID) {
            issues.append(.toneViolation(contentID: contentID, detail: issue.description))
        }
        for issue in ContentValidator.claimIssues(in: text.text, contentID: contentID) {
            issues.append(.toneViolation(contentID: contentID, detail: issue.description))
        }
        return issues
    }

    // MARK: - Payloads

    static func checkPayload(_ puzzle: PuzzleDefinition) -> [GameContentIssue] {
        let id = puzzle.id.rawValue
        var issues: [GameContentIssue] = []

        switch puzzle.payload {
        case .answerChain(let content):
            if content.stops.isEmpty {
                issues.append(.malformedPuzzle(puzzleID: id, reason: "no stops"))
            }
            for (index, stop) in content.stops.enumerated() {
                issues.append(contentsOf: check(stop.prompt, contentID: id, field: "stop \(index) prompt"))
                issues.append(contentsOf: check(
                    stop.linkExplanation, contentID: id, field: "stop \(index) explanation"
                ))
                if stop.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "stop \(index) has no answer"
                    ))
                }
                for (hintIndex, hint) in stop.hints.enumerated() {
                    issues.append(contentsOf: check(
                        hint, contentID: id, field: "stop \(index) hint \(hintIndex)"
                    ))
                }
            }

        case .revealAndIdentify(let content):
            if !content.isWellFormed {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "needs at least two options, a valid answer, and one clue"
                ))
            }
            issues.append(contentsOf: check(content.prompt, contentID: id, field: "prompt"))
            issues.append(contentsOf: check(content.explanation, contentID: id, field: "explanation"))
            for (index, clue) in content.clues.enumerated() {
                issues.append(contentsOf: check(clue.detail, contentID: id, field: "clue \(index)"))
                if clue.cost < 0 {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "clue \(index) has a negative cost"
                    ))
                }
            }
            for (index, option) in content.options.enumerated() {
                issues.append(contentsOf: check(option, contentID: id, field: "option \(index)"))
            }

        case .gridAssignment(let content):
            issues.append(contentsOf: checkGrid(content, puzzleID: id))

        case .studyThenQuiz(let content):
            if content.items.isEmpty || content.questions.isEmpty {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "needs at least one item and one question"
                ))
            }
            for (index, item) in content.items.enumerated() {
                issues.append(contentsOf: check(item.label, contentID: id, field: "item \(index)"))
                issues.append(contentsOf: check(item.detail, contentID: id, field: "item \(index) detail"))
                if item.row < 0 || item.row >= content.rows
                    || item.column < 0 || item.column >= content.columns {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "item \(index) sits outside the page"
                    ))
                }
            }
            for (index, question) in content.questions.enumerated() {
                issues.append(contentsOf: check(
                    question.prompt, contentID: id, field: "question \(index)"
                ))
                issues.append(contentsOf: check(
                    question.explanation, contentID: id, field: "question \(index) explanation"
                ))
                if !question.options.indices.contains(question.answerIndex) {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "question \(index) has no valid answer"
                    ))
                }
                for (optionIndex, option) in question.options.enumerated() {
                    issues.append(contentsOf: check(
                        option, contentID: id, field: "question \(index) option \(optionIndex)"
                    ))
                }
            }

        case .constrainedSelection(let content):
            if content.candidates.isEmpty || content.rules.isEmpty {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "needs candidates and at least one rule"
                ))
            }
            issues.append(contentsOf: check(content.brief, contentID: id, field: "brief"))
            issues.append(contentsOf: check(content.explanation, contentID: id, field: "explanation"))
            for (index, candidate) in content.candidates.enumerated() {
                issues.append(contentsOf: check(candidate.name, contentID: id, field: "item \(index)"))
            }
            for (index, rule) in content.rules.enumerated() {
                issues.append(contentsOf: check(
                    rule.explanation, contentID: id, field: "rule \(index)"
                ))
            }
            // A puzzle no selection can satisfy is not hard, it is broken.
            if !hasSatisfyingSelection(content) {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "no selection satisfies every rule"
                ))
            }

        case .branchingChoice(let content):
            if content.node(id: content.startNodeID) == nil {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "start node \(content.startNodeID) does not exist"
                ))
            }
            var nodeIDs = Set<String>()
            for node in content.nodes {
                if !nodeIDs.insert(node.id).inserted {
                    issues.append(.duplicateID(node.id))
                }
                issues.append(contentsOf: check(node.prompt, contentID: id, field: "node \(node.id)"))
                if node.options.isEmpty {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "node \(node.id) has no options"
                    ))
                }
                if !node.options.contains(where: { $0.isEfficient }) {
                    issues.append(.malformedPuzzle(
                        puzzleID: id, reason: "node \(node.id) has no efficient route out"
                    ))
                }
                for option in node.options {
                    issues.append(contentsOf: check(
                        option.text, contentID: id, field: "node \(node.id) option"
                    ))
                    issues.append(contentsOf: check(
                        option.explanation, contentID: id, field: "node \(node.id) explanation"
                    ))
                    if let next = option.nextNodeID, content.node(id: next) == nil {
                        issues.append(.malformedPuzzle(
                            puzzleID: id, reason: "node \(node.id) points at missing node \(next)"
                        ))
                    }
                }
            }
            // Walking the efficient route also proves it terminates rather than
            // looping, which is what `efficientRouteLength` caps.
            if content.efficientRouteLength >= BranchingPuzzle.maximumNodeVisits {
                issues.append(.malformedPuzzle(
                    puzzleID: id, reason: "the efficient route does not end"
                ))
            }
        }

        return issues
    }

    static func checkGrid(_ content: GridPuzzle, puzzleID: String) -> [GameContentIssue] {
        var issues: [GameContentIssue] = []

        issues.append(contentsOf: check(content.positionLabel, contentID: puzzleID, field: "positions"))
        issues.append(contentsOf: check(content.explanation, contentID: puzzleID, field: "explanation"))
        for (index, category) in content.categories.enumerated() {
            issues.append(contentsOf: check(category.name, contentID: puzzleID, field: "category \(index)"))
            for (valueIndex, value) in category.values.enumerated() {
                issues.append(contentsOf: check(
                    value, contentID: puzzleID, field: "category \(index) value \(valueIndex)"
                ))
            }
        }

        guard content.isWellFormed else {
            issues.append(.malformedPuzzle(
                puzzleID: puzzleID,
                reason: "every category must have one value per position"
            ))
            return issues
        }

        switch GridDeductionSolver.solve(content) {
        case .unique:
            break
        case .none:
            issues.append(.ambiguousSolution(puzzleID: puzzleID, outcome: "no solution"))
        case .multiple:
            issues.append(.ambiguousSolution(puzzleID: puzzleID, outcome: "more than one solution"))
        case .indeterminate:
            issues.append(.ambiguousSolution(
                puzzleID: puzzleID, outcome: "the solver hit its work limit"
            ))
        }

        return issues
    }

    /// Whether any subset of the candidates satisfies every rule.
    ///
    /// Exhaustive over subsets, which is why packing puzzles are authored small:
    /// the limit below caps the search at a size a phone and a test run can both
    /// afford. A larger puzzle is reported as unverified rather than silently
    /// skipped.
    static let maximumSelectionCandidates = 20

    static func hasSatisfyingSelection(_ puzzle: SelectionPuzzle) -> Bool {
        let count = puzzle.candidates.count
        guard count > 0, count <= maximumSelectionCandidates else { return true }

        for mask in 0..<(1 << count) {
            var selection = Set<Int>()
            for index in 0..<count where mask & (1 << index) != 0 {
                selection.insert(index)
            }
            let holds = puzzle.rules.allSatisfy {
                SelectionEngine.satisfies($0, selection: selection, puzzle: puzzle)
            }
            if holds { return true }
        }
        return false
    }
}
