import Foundation

/// What a game draws on (GAMES_AND_FUTURE_MULTIPLAYER.md §1).
///
/// Used for grouping on the games home and for choosing which games a daily
/// puzzle may rotate through. A game may sit in several categories.
public enum GameCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case wordplay
    case language
    case travel
    case plants
    case memory
    case trivia
    case logic
}

/// The interaction shape a game presents.
///
/// This is deliberately *not* one case per game. Seven games ship, but they
/// reduce to six interaction shapes, and two games sharing a shape share the
/// board, the accessibility alternative, and the save format while keeping
/// entirely separate rules and content. The alternative — a bespoke board per
/// game — would mean seven VoiceOver implementations to keep correct instead of
/// six, for no gain to the player.
///
/// Adding a shape is a real piece of work: a board view, an engine, a save
/// encoding, and an accessibility path. Adding a *game* to an existing shape is
/// content.
public enum GameKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// A chain of clues where each answer unlocks the next. Word Layover and
    /// Lost in Translation.
    case answerChain
    /// Clues are revealed in the player's chosen order, then a single answer is
    /// identified. Postcard Cipher.
    case revealAndIdentify
    /// Constraint deduction over a grid of categories. Jungle Logic.
    case gridAssignment
    /// Study a page, then answer questions about it from memory. Memory Atlas.
    case studyThenQuiz
    /// Choose a subset that satisfies every rule. Sunnie's Suitcase.
    case constrainedSelection
    /// A branching route where each answer picks the next node. Trivia Trail.
    case branchingChoice
}

/// Difficulty (GAMES_AND_FUTURE_MULTIPLAYER.md §5).
///
/// Three levels plus a tutorial. The names describe the puzzle, never the
/// player: there is no "easy" implying the player needed it, and no "expert"
/// implying anyone else fell short.
public enum GameDifficulty: String, Hashable, Sendable, Codable, CaseIterable {
    case tutorial
    case gentle
    case steady
    case tricky

    /// Ordering for pickers and for choosing the next puzzle up.
    public var rank: Int {
        switch self {
        case .tutorial: 0
        case .gentle: 1
        case .steady: 2
        case .tricky: 3
        }
    }

    public var localizationKey: String { "game.difficulty.\(rawValue)" }

    /// The tutorial explains as it goes and never counts against a result.
    public var isTutorial: Bool { self == .tutorial }
}

/// Languages a game's content may require (§5, "content-language requirements").
///
/// A player who has not installed a language pack should not be offered a puzzle
/// whose clues they cannot read, so this is a filter on availability rather than
/// a difficulty knob.
public enum GameLanguage: String, Hashable, Sendable, Codable, CaseIterable {
    case english
    case spanish
    case portuguese
    case french

    public var localizationKey: String { "game.language.\(rawValue)" }
}

/// How hints behave for a game.
///
/// `costPerHint` is subtracted from the score and nothing else. There is no
/// currency, no energy, and no cap that ends a session — a player who takes
/// every hint still finishes, and the result says how many they took without
/// any comment on it (§5, §7).
public struct HintPolicy: Hashable, Sendable, Codable {
    public let costPerHint: Int
    /// Hints available per stop. Nil means as many as the puzzle can produce.
    public let maximumPerStep: Int?

    public init(costPerHint: Int = 10, maximumPerStep: Int? = 2) {
        self.costPerHint = costPerHint
        self.maximumPerStep = maximumPerStep
    }

    public static let standard = HintPolicy()
    /// The tutorial's hints are free, because a tutorial that penalises asking
    /// how it works is not a tutorial.
    public static let free = HintPolicy(costPerHint: 0, maximumPerStep: nil)
}

/// A game, as content rather than code (§8).
public struct GameDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let kind: GameKind
    public let categories: [GameCategory]
    public let displayNameKey: String
    public let summaryKey: String
    public let rulesKey: String
    public let difficulties: [GameDifficulty]
    /// Languages the player must be able to read for this game's content.
    public let languages: [GameLanguage]
    public let hintPolicy: HintPolicy
    /// Whether the daily puzzle may choose this game (§4).
    public let supportsDailyPuzzle: Bool
    /// Whether the board is drag-driven and therefore needs the tap-based
    /// alternative described in §10.
    public let usesDragInteraction: Bool

    public init(
        id: ContentID,
        kind: GameKind,
        categories: [GameCategory],
        displayNameKey: String,
        summaryKey: String,
        rulesKey: String,
        difficulties: [GameDifficulty] = [.tutorial, .gentle, .steady, .tricky],
        languages: [GameLanguage] = [.english],
        hintPolicy: HintPolicy = .standard,
        supportsDailyPuzzle: Bool = true,
        usesDragInteraction: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.categories = categories
        self.displayNameKey = displayNameKey
        self.summaryKey = summaryKey
        self.rulesKey = rulesKey
        self.difficulties = difficulties
        self.languages = languages
        self.hintPolicy = hintPolicy
        self.supportsDailyPuzzle = supportsDailyPuzzle
        self.usesDragInteraction = usesDragInteraction
    }

    public func supports(_ difficulty: GameDifficulty) -> Bool {
        difficulties.contains(difficulty)
    }

    /// The policy that actually applies, which is the free one in a tutorial.
    public func hintPolicy(for difficulty: GameDifficulty) -> HintPolicy {
        difficulty.isTutorial ? .free : hintPolicy
    }
}

// MARK: - Session state

/// One player's move, recorded in order.
///
/// Deliberately data rather than a closure or a view event: a session's whole
/// history is `[GameMove]`, which is what makes save/resume a plain encode and
/// what will make an asynchronous multiplayer turn a transferable value later
/// (§9). Nothing in here is platform- or CloudKit-specific.
public struct GameMove: Hashable, Sendable, Codable {
    /// Position in the sequence, starting at zero. Two clients applying the same
    /// ordinals in order reach the same state.
    public let ordinal: Int
    /// Which step of the puzzle the move addresses.
    public let stepIndex: Int
    public let action: Action
    public let occurredAt: Date

    public enum Action: Hashable, Sendable, Codable {
        /// A typed answer.
        case answer(String)
        /// A chosen option, by its index in the step's options.
        case choose(Int)
        /// Assign an item to a slot, by index into the puzzle's item and slot
        /// lists.
        case assign(item: Int, slot: Int)
        /// Clear an assignment.
        case unassign(item: Int)
        /// Include or drop a candidate.
        case toggle(item: Int, isSelected: Bool)
        /// Reveal a clue the player chose to open.
        case reveal(clue: Int)
        /// Ask for a hint.
        case hint
        /// Skip a step, which scores nothing but never blocks the route.
        case skip
        /// Move past the current phase — finish studying, submit a selection.
        case advance
    }

    public init(ordinal: Int, stepIndex: Int, action: Action, occurredAt: Date) {
        self.ordinal = ordinal
        self.stepIndex = stepIndex
        self.action = action
        self.occurredAt = occurredAt
    }
}

/// Where a session stands.
public enum GameSessionStatus: String, Hashable, Sendable, Codable {
    case inProgress
    case completed
    /// The player left without finishing. Resumable, and never described to them
    /// as a failure or an abandonment.
    case setAside
}

/// A saved, resumable session (§2).
///
/// Everything needed to rebuild the board is here: the puzzle it was drawn from,
/// the seed that generated it, and the moves in order. The board itself is never
/// persisted — it is recomputed by replaying moves, so a board layout change in a
/// later build cannot corrupt a saved game.
public struct GameSessionState: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let gameID: ContentID
    public let puzzleID: ContentID
    public let difficulty: GameDifficulty
    public let seed: UInt64
    /// Set when this session is a day's daily puzzle, as `yyyy-MM-dd` in the
    /// player's calendar. Nil for a freely chosen game.
    public let dailyKey: String?
    public var moves: [GameMove]
    public var status: GameSessionStatus
    public let startedAt: Date
    public var lastPlayedAt: Date
    /// Accumulated play time. Stored rather than derived from timestamps so a
    /// session set aside overnight does not read as an eight-hour game.
    public var elapsedSeconds: Int

    public init(
        id: UUID = UUID(),
        gameID: ContentID,
        puzzleID: ContentID,
        difficulty: GameDifficulty,
        seed: UInt64,
        dailyKey: String? = nil,
        moves: [GameMove] = [],
        status: GameSessionStatus = .inProgress,
        startedAt: Date,
        lastPlayedAt: Date,
        elapsedSeconds: Int = 0
    ) {
        self.id = id
        self.gameID = gameID
        self.puzzleID = puzzleID
        self.difficulty = difficulty
        self.seed = seed
        self.dailyKey = dailyKey
        self.moves = moves
        self.status = status
        self.startedAt = startedAt
        self.lastPlayedAt = lastPlayedAt
        self.elapsedSeconds = elapsedSeconds
    }

    public var hintsUsed: Int {
        moves.filter { $0.action == .hint }.count
    }

    public var isResumable: Bool {
        status != .completed
    }

    /// Appends a move with the next ordinal.
    public mutating func append(_ action: GameMove.Action, stepIndex: Int, at date: Date) {
        moves.append(
            GameMove(
                ordinal: moves.count, stepIndex: stepIndex, action: action, occurredAt: date
            )
        )
        lastPlayedAt = date
    }
}

// MARK: - Results

/// How a session ended.
///
/// There is no `failed`. A puzzle the player did not solve is `finishedWithHelp`
/// or `setAside` — both of which are things that happened, not verdicts on the
/// person (TONE_COPY_AND_BEHAVIOR.md).
public enum GameCompletion: String, Hashable, Sendable, Codable {
    /// Solved with no hints and no skipped steps.
    case solvedUnaided
    /// Solved, having taken hints along the way.
    case solvedWithHints
    /// Reached the end with some steps skipped or revealed.
    case finishedWithHelp
    /// Left before the end.
    case setAside

    public var isFinished: Bool { self != .setAside }

    public var localizationKey: String { "game.completion.\(rawValue)" }
}

/// One step's outcome, used to build the explanation screen.
public struct GameStepResult: Hashable, Sendable, Codable {
    public let stepIndex: Int
    public let prompt: GameText
    public let expectedAnswer: String
    public let playerAnswer: String?
    public let wasCorrect: Bool
    public let hintsUsed: Int
    /// Why the answer is what it is. Present for every knowledge or logic step
    /// (§6) — the explanation is the part that teaches, so a step without one is
    /// a content error the validator catches.
    public let explanation: GameText?

    public init(
        stepIndex: Int,
        prompt: GameText,
        expectedAnswer: String,
        playerAnswer: String?,
        wasCorrect: Bool,
        hintsUsed: Int,
        explanation: GameText?
    ) {
        self.stepIndex = stepIndex
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.playerAnswer = playerAnswer
        self.wasCorrect = wasCorrect
        self.hintsUsed = hintsUsed
        self.explanation = explanation
    }
}

/// A finished session's record (§6).
public struct GameResult: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let sessionID: UUID
    public let gameID: ContentID
    public let puzzleID: ContentID
    public let difficulty: GameDifficulty
    public let completion: GameCompletion
    public let score: Int
    /// Correct steps over total steps, 0...1. Reported alongside score because
    /// "six of seven" is more legible than a point total.
    public let stepsCorrect: Int
    public let stepsTotal: Int
    public let hintsUsed: Int
    /// Seconds played. Shown only where the game says time is meaningful — an
    /// untimed deduction puzzle does not need a stopwatch reported at it.
    public let elapsedSeconds: Int
    public let steps: [GameStepResult]
    public let dailyKey: String?
    public let finishedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        gameID: ContentID,
        puzzleID: ContentID,
        difficulty: GameDifficulty,
        completion: GameCompletion,
        score: Int,
        stepsCorrect: Int,
        stepsTotal: Int,
        hintsUsed: Int,
        elapsedSeconds: Int,
        steps: [GameStepResult],
        dailyKey: String? = nil,
        finishedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.gameID = gameID
        self.puzzleID = puzzleID
        self.difficulty = difficulty
        self.completion = completion
        self.score = score
        self.stepsCorrect = stepsCorrect
        self.stepsTotal = stepsTotal
        self.hintsUsed = hintsUsed
        self.elapsedSeconds = elapsedSeconds
        self.steps = steps
        self.dailyKey = dailyKey
        self.finishedAt = finishedAt
    }

    /// Whether this result earns progression.
    ///
    /// Only a finished session counts, which is the whole of the "no reward for
    /// repeatedly starting and abandoning" safeguard (§7). Setting a puzzle aside
    /// costs nothing either — it simply earns nothing yet.
    public var earnsProgression: Bool {
        completion.isFinished
    }
}

// MARK: - Future multiplayer

/// A stable player identity for future turn-based play (§9).
///
/// Present now so game state is already shaped for it: the initial app has one
/// local player, and every move it records already carries an owner.
public struct PlayerID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The only player in the initial app.
    public static let local = PlayerID(rawValue: "local")
}

/// The seam a future multiplayer implementation slots into.
///
/// No network code exists behind this and none is planned for the initial app —
/// the point is that `GameSessionState` and `GameMove` are already serializable,
/// deterministic, and free of CloudKit types, so adding a transport later is not
/// a rewrite of the games.
public protocol MultiplayerService: Sendable {
    var isAvailable: Bool { get }
    func submit(move: GameMove, sessionID: UUID, player: PlayerID) async throws
    func pendingMoves(sessionID: UUID) async throws -> [GameMove]
}

/// The implementation the initial app composes: multiplayer is unavailable, and
/// every call is a no-op rather than a crash or a fabricated success.
public struct NoMultiplayer: MultiplayerService {
    public init() {}
    public var isAvailable: Bool { false }
    public func submit(move: GameMove, sessionID: UUID, player: PlayerID) async throws {}
    public func pendingMoves(sessionID: UUID) async throws -> [GameMove] { [] }
}
