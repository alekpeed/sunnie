import Foundation

/// The rule engines behind each interaction shape.
///
/// Every engine follows the same two-function contract:
///
/// - `replay(puzzle:moves:)` rebuilds the board from the recorded moves.
/// - `grade(puzzle:board:)` says what the playthrough amounted to.
///
/// Replay, rather than a mutable board saved to disk, is what makes save/resume
/// safe across app versions: the moves are the record, and a later build that
/// changes how a board is laid out still reconstructs the same play. It is also
/// the property future turn-based multiplayer needs — two devices applying the
/// same ordered moves reach the same board (§9).
///
/// Nothing in this file touches SwiftUI, SwiftData, or a clock.

// MARK: - Answer chain (Word Layover, Lost in Translation)

public enum AnswerChainEngine {

    public static func replay(
        puzzle: AnswerChainPuzzle, moves: [GameMove]
    ) -> AnswerChainBoard {
        var stops = [AnswerChainBoard.StopState](
            repeating: .init(), count: puzzle.stops.count
        )
        var current = 0

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            let index = move.stepIndex
            guard stops.indices.contains(index) else { continue }

            switch move.action {
            case .answer(let text):
                stops[index].lastAnswer = text
                if AnswerNormalizer.matches(text, accepted: puzzle.stops[index].acceptedAnswers) {
                    stops[index].isSolved = true
                    stops[index].lastAnswerWasNearMiss = false
                    // Advance past everything already settled, so resuming a
                    // route lands on the first genuinely open stop.
                    current = max(current, nextOpenStop(from: index, in: stops))
                } else {
                    stops[index].wrongAttempts += 1
                    stops[index].lastAnswerWasNearMiss = AnswerNormalizer.isNearMiss(
                        text, accepted: puzzle.stops[index].acceptedAnswers
                    )
                }

            case .hint:
                stops[index].hintsRevealed += 1

            case .skip:
                stops[index].wasSkipped = true
                current = max(current, nextOpenStop(from: index, in: stops))

            case .choose, .assign, .unassign, .toggle, .reveal, .advance:
                // Not part of this shape. A move from a mismatched save is
                // ignored rather than treated as corruption — the rest of the
                // route still replays.
                continue
            }
        }

        return AnswerChainBoard(stops: stops, currentStop: current)
    }

    private static func nextOpenStop(
        from index: Int, in stops: [AnswerChainBoard.StopState]
    ) -> Int {
        var candidate = index + 1
        while candidate < stops.count, stops[candidate].isSolved || stops[candidate].wasSkipped {
            candidate += 1
        }
        return candidate
    }

    public static func grade(
        puzzle: AnswerChainPuzzle, board: AnswerChainBoard
    ) -> GradedPlay {
        var play = GradedPlay(isFinished: board.isComplete)

        for (index, stop) in puzzle.stops.enumerated() {
            let state = board.stops.indices.contains(index)
                ? board.stops[index] : .init()

            play.hintsUsed += state.hintsRevealed
            play.wrongAttempts += state.wrongAttempts
            if state.wasSkipped { play.skipped += 1 }

            play.steps.append(
                GameStepResult(
                    stepIndex: index,
                    prompt: stop.prompt,
                    expectedAnswer: stop.answer,
                    playerAnswer: state.isSolved ? state.lastAnswer : nil,
                    wasCorrect: state.isSolved,
                    hintsUsed: state.hintsRevealed,
                    explanation: stop.linkExplanation
                )
            )
        }
        return play
    }

    /// The hint text for a stop, or nil when the player has taken them all.
    public static func hint(
        for stop: AnswerChainStop, alreadyRevealed: Int, policy: HintPolicy
    ) -> GameText? {
        if let maximum = policy.maximumPerStep, alreadyRevealed >= maximum { return nil }
        guard stop.hints.indices.contains(alreadyRevealed) else { return nil }
        return stop.hints[alreadyRevealed]
    }
}

// MARK: - Reveal and identify (Postcard Cipher)

public enum IdentifyEngine {

    public static func replay(puzzle: IdentifyPuzzle, moves: [GameMove]) -> IdentifyBoard {
        var board = IdentifyBoard()

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            switch move.action {
            case .reveal(let clue):
                guard puzzle.clues.indices.contains(clue) else { continue }
                if !board.revealedClues.contains(clue) {
                    board.revealedClues.append(clue)
                }

            case .choose(let option):
                guard puzzle.options.indices.contains(option) else { continue }
                if option == puzzle.answerIndex {
                    board.chosenOption = option
                } else {
                    board.wrongAttempts += 1
                    // A wrong guess reveals the cheapest unopened clue rather
                    // than ending the round. The player is trying to work
                    // something out; taking the postcard away teaches nothing.
                    if let next = cheapestUnrevealed(puzzle: puzzle, board: board) {
                        board.revealedClues.append(next)
                    } else {
                        board.chosenOption = option
                    }
                }

            case .skip:
                // Ending the round without naming a place. The postcard's answer
                // and its explanation are still shown — the player wanted to know,
                // just not to keep guessing.
                board.wasSkipped = true

            case .answer, .assign, .unassign, .toggle, .hint, .advance:
                continue
            }
        }
        return board
    }

    private static func cheapestUnrevealed(
        puzzle: IdentifyPuzzle, board: IdentifyBoard
    ) -> Int? {
        puzzle.clues.indices
            .filter { !board.revealedClues.contains($0) }
            .min { puzzle.clues[$0].cost < puzzle.clues[$1].cost }
    }

    public static func grade(puzzle: IdentifyPuzzle, board: IdentifyBoard) -> GradedPlay {
        let wasCorrect = board.chosenOption == puzzle.answerIndex
        let chosen = board.chosenOption.flatMap { index in
            puzzle.options.indices.contains(index) ? puzzle.options[index].text : nil
        }
        let expected = puzzle.options.indices.contains(puzzle.answerIndex)
            ? puzzle.options[puzzle.answerIndex].text : ""

        return GradedPlay(
            steps: [
                GameStepResult(
                    stepIndex: 0,
                    prompt: puzzle.prompt,
                    expectedAnswer: expected,
                    playerAnswer: chosen,
                    wasCorrect: wasCorrect,
                    hintsUsed: 0,
                    explanation: puzzle.explanation
                )
            ],
            isFinished: board.isComplete,
            hintsUsed: 0,
            wrongAttempts: board.wrongAttempts,
            skipped: 0,
            revealCost: board.revealedClues.reduce(0) { total, index in
                total + (puzzle.clues.indices.contains(index) ? puzzle.clues[index].cost : 0)
            }
        )
    }
}

// MARK: - Grid assignment (Jungle Logic)

public enum GridEngine {

    public static func replay(puzzle: GridPuzzle, moves: [GameMove]) -> GridBoard {
        let positions = puzzle.positionCount
        var board = GridBoard(
            assignment: [[Int?]](
                repeating: [Int?](repeating: nil, count: positions),
                count: puzzle.categories.count
            )
        )

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            switch move.action {
            case .assign(let item, let slot):
                guard
                    let (category, value) = decode(item, positions: positions, puzzle: puzzle),
                    (0..<positions).contains(slot)
                else { continue }
                // A value can only be in one place, and a place can only hold one
                // value from each category, so assigning clears both conflicts.
                // Without this the board could show the same plant on two
                // shelves, which is not a state the puzzle has.
                if let existing = board.position(ofValue: value, inCategory: category) {
                    board.assignment[category][existing] = nil
                }
                board.assignment[category][slot] = value

            case .unassign(let item):
                guard let (category, value) = decode(item, positions: positions, puzzle: puzzle)
                else { continue }
                if let existing = board.position(ofValue: value, inCategory: category) {
                    board.assignment[category][existing] = nil
                }

            case .hint:
                board.hintsRevealed += 1

            case .advance:
                board.isSubmitted = true

            case .answer, .choose, .toggle, .reveal, .skip:
                continue
            }
        }
        return board
    }

    /// Values are addressed as one flat index so `GameMove` stays generic:
    /// `category * positionCount + valueIndex`.
    static func decode(
        _ item: Int, positions: Int, puzzle: GridPuzzle
    ) -> (category: Int, value: Int)? {
        guard positions > 0, item >= 0 else { return nil }
        let category = item / positions
        let value = item % positions
        guard puzzle.categories.indices.contains(category) else { return nil }
        return (category, value)
    }

    public static func encode(category: Int, value: Int, positions: Int) -> Int {
        category * positions + value
    }

    /// Grades one category per step: the player either placed that category's
    /// values correctly or did not.
    public static func grade(
        puzzle: GridPuzzle, board: GridBoard, solution: GridSolution?
    ) -> GradedPlay {
        var play = GradedPlay(
            isFinished: board.isSubmitted,
            hintsUsed: board.hintsRevealed
        )

        for (index, category) in puzzle.categories.enumerated() {
            let expected = solution.map { $0.assignment[index] }
            let actual = board.assignment.indices.contains(index)
                ? board.assignment[index] : []
            let wasCorrect = expected.map { expectedRow in
                zip(expectedRow, actual).allSatisfy { $0 == $1 }
                    && expectedRow.count == actual.count
            } ?? false

            play.steps.append(
                GameStepResult(
                    stepIndex: index,
                    prompt: category.name,
                    expectedAnswer: describe(solutionRow: expected, category: category),
                    playerAnswer: describe(row: actual, category: category),
                    wasCorrect: wasCorrect,
                    hintsUsed: 0,
                    explanation: puzzle.explanation
                )
            )
        }
        return play
    }

    private static func describe(row: [Int?]?, category: GridCategory) -> String {
        guard let row else { return "" }
        return row
            .map { value in
                value.flatMap { category.values.indices.contains($0) ? category.values[$0].text : nil }
                    ?? "—"
            }
            .joined(separator: ", ")
    }

    private static func describe(solutionRow: [Int]?, category: GridCategory) -> String {
        describe(row: solutionRow?.map { Optional($0) }, category: category)
    }

    /// A hint places one correct value. Costs score; never places more than the
    /// player asked for.
    public static func hintPlacement(
        puzzle: GridPuzzle, board: GridBoard, solution: GridSolution
    ) -> (category: Int, position: Int, value: Int)? {
        for (category, row) in solution.assignment.enumerated() {
            for (position, value) in row.enumerated()
            where board.value(category: category, position: position) != value {
                return (category, position, value)
            }
        }
        return nil
    }
}

// MARK: - Study then quiz (Memory Atlas)

public enum StudyEngine {

    public static func replay(puzzle: StudyPuzzle, moves: [GameMove]) -> StudyBoard {
        var board = StudyBoard(
            answers: [Int?](repeating: nil, count: puzzle.questions.count)
        )

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            switch move.action {
            case .advance:
                board.phase = .answering

            case .choose(let option):
                let index = move.stepIndex
                guard
                    board.answers.indices.contains(index),
                    puzzle.questions.indices.contains(index)
                else { continue }
                board.answers[index] = option
                board.currentQuestion = min(index + 1, puzzle.questions.count - 1)

            case .skip:
                let index = move.stepIndex
                guard board.answers.indices.contains(index) else { continue }
                // A skipped question is answered with a value no option uses, so
                // it grades as unanswered rather than as a wrong guess.
                board.answers[index] = -1
                board.currentQuestion = min(index + 1, puzzle.questions.count - 1)

            case .answer, .assign, .unassign, .toggle, .hint, .reveal:
                continue
            }
        }
        return board
    }

    public static func grade(puzzle: StudyPuzzle, board: StudyBoard) -> GradedPlay {
        var play = GradedPlay(isFinished: board.isComplete)

        for (index, question) in puzzle.questions.enumerated() {
            let answer = board.answers.indices.contains(index) ? board.answers[index] : nil
            let wasCorrect = answer == question.answerIndex
            if answer == -1 { play.skipped += 1 }
            else if let answer, !wasCorrect, question.options.indices.contains(answer) {
                play.wrongAttempts += 1
            }

            let given = answer.flatMap { value in
                question.options.indices.contains(value) ? question.options[value].text : nil
            }
            let expected = question.options.indices.contains(question.answerIndex)
                ? question.options[question.answerIndex].text : ""

            play.steps.append(
                GameStepResult(
                    stepIndex: index,
                    prompt: question.prompt,
                    expectedAnswer: expected,
                    playerAnswer: given,
                    wasCorrect: wasCorrect,
                    hintsUsed: 0,
                    explanation: question.explanation
                )
            )
        }
        return play
    }
}

// MARK: - Constrained selection (Sunnie's Suitcase)

public enum SelectionEngine {

    public static func replay(puzzle: SelectionPuzzle, moves: [GameMove]) -> SelectionBoard {
        var board = SelectionBoard()

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            switch move.action {
            case .toggle(let item, let isSelected):
                guard puzzle.candidates.indices.contains(item) else { continue }
                if isSelected { board.selected.insert(item) } else { board.selected.remove(item) }

            case .hint:
                board.hintsRevealed += 1

            case .advance:
                board.isSubmitted = true

            case .answer, .choose, .assign, .unassign, .reveal, .skip:
                continue
            }
        }
        return board
    }

    /// Whether a rule holds for the chosen set.
    public static func satisfies(
        _ rule: SelectionRule, selection: Set<Int>, puzzle: SelectionPuzzle
    ) -> Bool {
        func count(tag: String) -> Int {
            selection.filter { index in
                puzzle.candidates.indices.contains(index)
                    && puzzle.candidates[index].tags.contains(tag)
            }.count
        }

        switch rule.requirement {
        case .atLeast(let tag, let required): return count(tag: tag) >= required
        case .atMost(let tag, let limit): return count(tag: tag) <= limit
        case .forbid(let tag): return count(tag: tag) == 0
        case .weightLimit(let limit):
            let total = selection.reduce(0) { sum, index in
                sum + (puzzle.candidates.indices.contains(index)
                    ? puzzle.candidates[index].weight : 0)
            }
            return total <= limit
        case .itemLimit(let limit): return selection.count <= limit
        case .incompatible(let a, let b):
            return !(selection.contains(a) && selection.contains(b))
        }
    }

    public static func totalWeight(
        selection: Set<Int>, puzzle: SelectionPuzzle
    ) -> Int {
        selection.reduce(0) { sum, index in
            sum + (puzzle.candidates.indices.contains(index)
                ? puzzle.candidates[index].weight : 0)
        }
    }

    /// One step per rule, so the result screen can say which rule was missed and
    /// why — the point of the game is the reasoning, not the packing (§3, G-06).
    public static func grade(puzzle: SelectionPuzzle, board: SelectionBoard) -> GradedPlay {
        var play = GradedPlay(
            isFinished: board.isSubmitted,
            hintsUsed: board.hintsRevealed
        )

        for (index, rule) in puzzle.rules.enumerated() {
            let held = satisfies(rule, selection: board.selected, puzzle: puzzle)
            if board.isSubmitted, !held { play.wrongAttempts += 1 }

            play.steps.append(
                GameStepResult(
                    stepIndex: index,
                    prompt: rule.explanation,
                    expectedAnswer: describe(rule.requirement, puzzle: puzzle),
                    playerAnswer: nil,
                    wasCorrect: held,
                    hintsUsed: 0,
                    explanation: rule.explanation
                )
            )
        }
        return play
    }

    /// A plain-text form of the requirement for the result list.
    ///
    /// Tags and numbers only — this is a diagnostic line beside the rule's own
    /// authored explanation, not a sentence shown on its own.
    static func describe(_ requirement: SelectionRule.Requirement, puzzle: SelectionPuzzle) -> String {
        switch requirement {
        case .atLeast(let tag, let count): "\(tag) ≥ \(count)"
        case .atMost(let tag, let count): "\(tag) ≤ \(count)"
        case .forbid(let tag): "\(tag): 0"
        case .weightLimit(let limit): "≤ \(limit)"
        case .itemLimit(let limit): "≤ \(limit)"
        case .incompatible(let a, let b):
            [a, b]
                .map { puzzle.candidates.indices.contains($0) ? puzzle.candidates[$0].name.text : "?" }
                .joined(separator: " / ")
        }
    }
}

// MARK: - Branching choice (Trivia Trail)

public enum BranchingEngine {

    public static func replay(puzzle: BranchingPuzzle, moves: [GameMove]) -> BranchingBoard {
        var visits: [BranchingBoard.Visit] = []
        var current: String? = puzzle.startNodeID

        for move in moves.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard visits.count < BranchingPuzzle.maximumNodeVisits else { break }
            guard let nodeID = current, let node = puzzle.node(id: nodeID) else { break }

            switch move.action {
            case .choose(let option):
                guard node.options.indices.contains(option) else { continue }
                visits.append(.init(nodeID: nodeID, chosenOption: option))
                current = node.options[option].nextNodeID

            case .skip:
                visits.append(.init(nodeID: nodeID, chosenOption: nil))
                // Skipping still travels: the trail takes the first route out,
                // so the journey continues rather than stopping at a question
                // the player did not want.
                current = node.options.first?.nextNodeID

            case .answer, .assign, .unassign, .toggle, .reveal, .hint, .advance:
                continue
            }
        }

        return BranchingBoard(visits: visits, currentNodeID: current)
    }

    public static func grade(puzzle: BranchingPuzzle, board: BranchingBoard) -> GradedPlay {
        var play = GradedPlay(isFinished: board.isComplete)

        for (index, visit) in board.visits.enumerated() {
            guard let node = puzzle.node(id: visit.nodeID) else { continue }
            let chosen = visit.chosenOption.flatMap { option in
                node.options.indices.contains(option) ? node.options[option] : nil
            }
            let efficient = node.options.first(where: { $0.isEfficient })
            let wasCorrect = chosen?.isEfficient ?? false

            if visit.chosenOption == nil { play.skipped += 1 }
            else if !wasCorrect { play.wrongAttempts += 1 }

            play.steps.append(
                GameStepResult(
                    stepIndex: index,
                    prompt: node.prompt,
                    expectedAnswer: efficient?.text.text ?? "",
                    playerAnswer: chosen?.text.text,
                    wasCorrect: wasCorrect,
                    hintsUsed: 0,
                    explanation: chosen?.explanation ?? efficient?.explanation
                )
            )
        }
        return play
    }
}
