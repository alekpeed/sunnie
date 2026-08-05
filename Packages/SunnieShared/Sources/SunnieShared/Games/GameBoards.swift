import Foundation

/// What one playthrough amounted to, before it becomes a `GameResult`.
///
/// Produced by every engine in the same shape, so scoring and the result screen
/// are written once rather than six times.
public struct GradedPlay: Hashable, Sendable {
    public var steps: [GameStepResult]
    public var isFinished: Bool
    public var hintsUsed: Int
    /// Answers given that were not right. Counted, never commented on.
    public var wrongAttempts: Int
    public var skipped: Int
    /// Score already spent by the player's own choices — revealed clues, extra
    /// study time. Separate from hints because the games charge differently for
    /// them.
    public var revealCost: Int

    public init(
        steps: [GameStepResult] = [],
        isFinished: Bool = false,
        hintsUsed: Int = 0,
        wrongAttempts: Int = 0,
        skipped: Int = 0,
        revealCost: Int = 0
    ) {
        self.steps = steps
        self.isFinished = isFinished
        self.hintsUsed = hintsUsed
        self.wrongAttempts = wrongAttempts
        self.skipped = skipped
        self.revealCost = revealCost
    }

    public var stepsCorrect: Int { steps.filter(\.wasCorrect).count }
}

// MARK: - Answer chain

public struct AnswerChainBoard: Hashable, Sendable {
    public struct StopState: Hashable, Sendable {
        public var lastAnswer: String?
        public var isSolved: Bool = false
        public var wasSkipped: Bool = false
        public var hintsRevealed: Int = 0
        public var wrongAttempts: Int = 0
        /// True when the last answer was one edit away. Drives a "very close"
        /// nudge rather than a bare rejection.
        public var lastAnswerWasNearMiss: Bool = false
    }

    public var stops: [StopState]
    /// The stop the player is on. Equal to `stops.count` once the route is done.
    public var currentStop: Int
    public var isComplete: Bool { currentStop >= stops.count }

    public init(stops: [StopState], currentStop: Int) {
        self.stops = stops
        self.currentStop = currentStop
    }
}

// MARK: - Reveal and identify

public struct IdentifyBoard: Hashable, Sendable {
    /// Clues in the order the player opened them, which is part of the puzzle.
    public var revealedClues: [Int]
    public var chosenOption: Int?
    public var wrongAttempts: Int
    /// The player asked to see the answer instead of guessing again.
    public var wasSkipped: Bool
    public var isComplete: Bool { chosenOption != nil || wasSkipped }

    public init(
        revealedClues: [Int] = [],
        chosenOption: Int? = nil,
        wrongAttempts: Int = 0,
        wasSkipped: Bool = false
    ) {
        self.revealedClues = revealedClues
        self.chosenOption = chosenOption
        self.wrongAttempts = wrongAttempts
        self.wasSkipped = wasSkipped
    }
}

// MARK: - Grid assignment

public struct GridBoard: Hashable, Sendable {
    /// `assignment[category][position]` — nil where the player has not decided.
    public var assignment: [[Int?]]
    public var hintsRevealed: Int
    public var isSubmitted: Bool

    public init(assignment: [[Int?]], hintsRevealed: Int = 0, isSubmitted: Bool = false) {
        self.assignment = assignment
        self.hintsRevealed = hintsRevealed
        self.isSubmitted = isSubmitted
    }

    public var isFullyAssigned: Bool {
        assignment.allSatisfy { row in row.allSatisfy { $0 != nil } }
    }

    public func value(category: Int, position: Int) -> Int? {
        guard
            assignment.indices.contains(category),
            assignment[category].indices.contains(position)
        else { return nil }
        return assignment[category][position]
    }

    /// Where the player put a value, if anywhere.
    public func position(ofValue value: Int, inCategory category: Int) -> Int? {
        guard assignment.indices.contains(category) else { return nil }
        return assignment[category].firstIndex { $0 == value }
    }
}

// MARK: - Study then quiz

public struct StudyBoard: Hashable, Sendable {
    public enum Phase: String, Hashable, Sendable {
        case studying
        case answering
    }

    public var phase: Phase
    /// One entry per question; nil until answered. A skipped question holds -1,
    /// which grades as unanswered rather than as a wrong guess.
    public var answers: [Int?]
    public var currentQuestion: Int

    public init(
        phase: Phase = .studying,
        answers: [Int?],
        currentQuestion: Int = 0
    ) {
        self.phase = phase
        self.answers = answers
        self.currentQuestion = currentQuestion
    }

    public var isComplete: Bool {
        phase == .answering && !answers.contains(where: { $0 == nil })
    }
}

// MARK: - Constrained selection

public struct SelectionBoard: Hashable, Sendable {
    public var selected: Set<Int>
    public var isSubmitted: Bool
    public var hintsRevealed: Int

    public init(selected: Set<Int> = [], isSubmitted: Bool = false, hintsRevealed: Int = 0) {
        self.selected = selected
        self.isSubmitted = isSubmitted
        self.hintsRevealed = hintsRevealed
    }
}

// MARK: - Branching choice

public struct BranchingBoard: Hashable, Sendable {
    public struct Visit: Hashable, Sendable {
        public let nodeID: String
        public let chosenOption: Int?

        public init(nodeID: String, chosenOption: Int?) {
            self.nodeID = nodeID
            self.chosenOption = chosenOption
        }
    }

    public var visits: [Visit]
    public var currentNodeID: String?
    public var isComplete: Bool { currentNodeID == nil }

    public init(visits: [Visit], currentNodeID: String?) {
        self.visits = visits
        self.currentNodeID = currentNodeID
    }
}

// MARK: - Envelope

/// The board a session is currently showing.
public enum GameBoard: Hashable, Sendable {
    case answerChain(AnswerChainBoard)
    case revealAndIdentify(IdentifyBoard)
    case gridAssignment(GridBoard)
    case studyThenQuiz(StudyBoard)
    case constrainedSelection(SelectionBoard)
    case branchingChoice(BranchingBoard)

    public var kind: GameKind {
        switch self {
        case .answerChain: .answerChain
        case .revealAndIdentify: .revealAndIdentify
        case .gridAssignment: .gridAssignment
        case .studyThenQuiz: .studyThenQuiz
        case .constrainedSelection: .constrainedSelection
        case .branchingChoice: .branchingChoice
        }
    }

    /// The step a new move should be recorded against.
    public var currentStepIndex: Int {
        switch self {
        case .answerChain(let board): board.currentStop
        case .revealAndIdentify: 0
        case .gridAssignment: 0
        case .studyThenQuiz(let board): board.currentQuestion
        case .constrainedSelection: 0
        case .branchingChoice(let board): board.visits.count
        }
    }

    public var isComplete: Bool {
        switch self {
        case .answerChain(let board): board.isComplete
        case .revealAndIdentify(let board): board.isComplete
        case .gridAssignment(let board): board.isSubmitted
        case .studyThenQuiz(let board): board.isComplete
        case .constrainedSelection(let board): board.isSubmitted
        case .branchingChoice(let board): board.isComplete
        }
    }
}
