import Foundation

/// A piece of authored game text.
///
/// Both fields travel together for the same reason every other content type
/// carries them: `text` keeps the app coherent if a localization is missing, and
/// `localizationKey` is what the app actually displays when one exists.
public struct GameText: Hashable, Sendable, Codable {
    public let text: String
    public let localizationKey: String

    public init(text: String, localizationKey: String) {
        self.text = text
        self.localizationKey = localizationKey
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Answer chain (Word Layover, Lost in Translation)

/// One stop on a route.
///
/// The link explanation is required, not optional: the whole point of both
/// answer-chain games is the connection between one answer and the next clue,
/// and a stop that cannot say what the connection was has taught nothing
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §6).
public struct AnswerChainStop: Hashable, Sendable, Codable {
    public let prompt: GameText
    public let answer: String
    /// Other spellings and translations that count as the same answer.
    public let alternates: [String]
    public let language: GameLanguage
    /// What connects this answer to the next stop.
    public let linkExplanation: GameText
    /// Progressively more helpful. Taking one costs score, never progress.
    public let hints: [GameText]

    public init(
        prompt: GameText,
        answer: String,
        alternates: [String] = [],
        language: GameLanguage = .english,
        linkExplanation: GameText,
        hints: [GameText] = []
    ) {
        self.prompt = prompt
        self.answer = answer
        self.alternates = alternates
        self.language = language
        self.linkExplanation = linkExplanation
        self.hints = hints
    }

    /// Every spelling that resolves to this stop.
    public var acceptedAnswers: [String] { [answer] + alternates }
}

public struct AnswerChainPuzzle: Hashable, Sendable, Codable {
    public let stops: [AnswerChainStop]

    public init(stops: [AnswerChainStop]) {
        self.stops = stops
    }
}

// MARK: - Reveal and identify (Postcard Cipher)

/// A clue the player may open.
///
/// `cost` is what opening it takes off the score. Ordering is the player's
/// choice, which is what makes the same postcard a different puzzle depending on
/// where they start (§3, G-02).
public struct RevealClue: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case textFragment
        case stampMark
        case weather
        case landmark
        case localPhrase

        public var localizationKey: String { "game.clue.\(rawValue)" }
    }

    public let kind: Kind
    public let detail: GameText
    public let cost: Int

    public init(kind: Kind, detail: GameText, cost: Int) {
        self.kind = kind
        self.detail = detail
        self.cost = cost
    }
}

public struct IdentifyPuzzle: Hashable, Sendable, Codable {
    public let prompt: GameText
    public let clues: [RevealClue]
    /// Index into `options` of the correct answer.
    public let answerIndex: Int
    public let options: [GameText]
    public let explanation: GameText

    public init(
        prompt: GameText,
        clues: [RevealClue],
        answerIndex: Int,
        options: [GameText],
        explanation: GameText
    ) {
        self.prompt = prompt
        self.clues = clues
        self.answerIndex = answerIndex
        self.options = options
        self.explanation = explanation
    }

    public var isWellFormed: Bool {
        options.count >= 2
            && options.indices.contains(answerIndex)
            && !clues.isEmpty
    }
}

// MARK: - Grid assignment (Jungle Logic)

/// One category of the deduction grid: a heading and the values that fill it.
///
/// Every category has exactly as many values as there are positions, which is
/// what makes the puzzle a set of permutations rather than an open search.
public struct GridCategory: Hashable, Sendable, Codable {
    public let name: GameText
    public let values: [GameText]

    public init(name: GameText, values: [GameText]) {
        self.name = name
        self.values = values
    }
}

/// A clue, expressed against category and value indices.
///
/// Indices rather than names so a translated pack cannot break the logic by
/// renaming a value.
public enum GridConstraint: Hashable, Sendable, Codable {
    /// Two values share a position.
    case same(categoryA: Int, valueA: Int, categoryB: Int, valueB: Int)
    /// Two values are definitely not in the same position.
    case different(categoryA: Int, valueA: Int, categoryB: Int, valueB: Int)
    /// A value sits at an exact position.
    case atPosition(category: Int, value: Int, position: Int)
    /// Two values sit next to each other, either way round.
    case adjacent(categoryA: Int, valueA: Int, categoryB: Int, valueB: Int)
    /// The first value's position is strictly lower than the second's.
    case before(categoryA: Int, valueA: Int, categoryB: Int, valueB: Int)
}

public struct GridPuzzle: Hashable, Sendable, Codable {
    /// What the positions are — shelves, rooms, windowsills.
    public let positionLabel: GameText
    public let categories: [GridCategory]
    public let constraints: [GridConstraint]
    /// Each category's clue, for the explanation screen.
    public let explanation: GameText

    public init(
        positionLabel: GameText,
        categories: [GridCategory],
        constraints: [GridConstraint],
        explanation: GameText
    ) {
        self.positionLabel = positionLabel
        self.categories = categories
        self.constraints = constraints
        self.explanation = explanation
    }

    /// Number of positions, taken from the first category's value count.
    public var positionCount: Int { categories.first?.values.count ?? 0 }

    /// Every category must cover every position exactly once.
    public var isWellFormed: Bool {
        guard positionCount > 0, categories.count >= 2 else { return false }
        return categories.allSatisfy { $0.values.count == positionCount }
    }
}

// MARK: - Study then quiz (Memory Atlas)

/// One thing on the scrapbook page.
///
/// `row` and `column` are the spatial detail the questions can ask about, and
/// they are also what makes the page describable to VoiceOver as a grid rather
/// than as a picture (§10).
public struct StudyItem: Hashable, Sendable, Codable {
    public let label: GameText
    public let detail: GameText
    public let row: Int
    public let column: Int

    public init(label: GameText, detail: GameText, row: Int, column: Int) {
        self.label = label
        self.detail = detail
        self.row = row
        self.column = column
    }
}

public struct StudyQuestion: Hashable, Sendable, Codable {
    public let prompt: GameText
    public let options: [GameText]
    public let answerIndex: Int
    public let explanation: GameText

    public init(
        prompt: GameText,
        options: [GameText],
        answerIndex: Int,
        explanation: GameText
    ) {
        self.prompt = prompt
        self.options = options
        self.answerIndex = answerIndex
        self.explanation = explanation
    }
}

public struct StudyPuzzle: Hashable, Sendable, Codable {
    public let rows: Int
    public let columns: Int
    public let items: [StudyItem]
    public let questions: [StudyQuestion]
    /// How long the page is shown by default. The player may extend it or remove
    /// the limit entirely, because a fixed exposure time is exactly the kind of
    /// barrier §10 requires an alternative for.
    public let defaultStudySeconds: Int

    public init(
        rows: Int,
        columns: Int,
        items: [StudyItem],
        questions: [StudyQuestion],
        defaultStudySeconds: Int = 20
    ) {
        self.rows = rows
        self.columns = columns
        self.items = items
        self.questions = questions
        self.defaultStudySeconds = defaultStudySeconds
    }
}

// MARK: - Constrained selection (Sunnie's Suitcase)

public struct SelectionCandidate: Hashable, Sendable, Codable {
    public let name: GameText
    /// Free-form tags the rules refer to: `warm`, `formal`, `liquid`.
    public let tags: [String]
    /// Arbitrary units — the puzzle's own weight budget, not grams.
    public let weight: Int

    public init(name: GameText, tags: [String], weight: Int) {
        self.name = name
        self.tags = tags
        self.weight = weight
    }
}

/// A packing rule.
///
/// Each carries its own explanation so the result screen can say which rule a
/// choice broke, rather than only that something was wrong.
public struct SelectionRule: Hashable, Sendable, Codable {
    public enum Requirement: Hashable, Sendable, Codable {
        /// At least `count` items carrying this tag.
        case atLeast(tag: String, count: Int)
        /// At most `count` items carrying this tag.
        case atMost(tag: String, count: Int)
        /// Nothing with this tag.
        case forbid(tag: String)
        /// Total weight no greater than this.
        case weightLimit(Int)
        /// Exactly this many items in total.
        case itemLimit(Int)
        /// These two items cannot both be chosen.
        case incompatible(itemA: Int, itemB: Int)
    }

    public let requirement: Requirement
    public let explanation: GameText

    public init(requirement: Requirement, explanation: GameText) {
        self.requirement = requirement
        self.explanation = explanation
    }
}

public struct SelectionPuzzle: Hashable, Sendable, Codable {
    public let brief: GameText
    public let candidates: [SelectionCandidate]
    public let rules: [SelectionRule]
    public let explanation: GameText

    public init(
        brief: GameText,
        candidates: [SelectionCandidate],
        rules: [SelectionRule],
        explanation: GameText
    ) {
        self.brief = brief
        self.candidates = candidates
        self.rules = rules
        self.explanation = explanation
    }
}

// MARK: - Branching choice (Trivia Trail)

public struct TrailOption: Hashable, Sendable, Codable {
    public let text: GameText
    /// The node this choice leads to. Nil ends the trail.
    public let nextNodeID: String?
    /// Whether this is the answer that takes the efficient route. A wrong answer
    /// still continues the journey — it just takes the long way round, which is
    /// the difference between a branching trail and a quiz that stops you (§3,
    /// G-07).
    public let isEfficient: Bool
    public let explanation: GameText

    public init(
        text: GameText,
        nextNodeID: String?,
        isEfficient: Bool,
        explanation: GameText
    ) {
        self.text = text
        self.nextNodeID = nextNodeID
        self.isEfficient = isEfficient
        self.explanation = explanation
    }
}

public struct TrailNode: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let prompt: GameText
    public let options: [TrailOption]

    public init(id: String, prompt: GameText, options: [TrailOption]) {
        self.id = id
        self.prompt = prompt
        self.options = options
    }
}

public struct BranchingPuzzle: Hashable, Sendable, Codable {
    public let startNodeID: String
    public let nodes: [TrailNode]

    public init(startNodeID: String, nodes: [TrailNode]) {
        self.startNodeID = startNodeID
        self.nodes = nodes
    }

    public func node(id: String) -> TrailNode? {
        nodes.first { $0.id == id }
    }

    /// Bounds replay of a pack whose nodes accidentally loop. A malformed pack
    /// should end the trail, not hang the app.
    public static let maximumNodeVisits = 24

    /// How many stops the efficient route has.
    ///
    /// Walked rather than counted, because a trail's node list includes the
    /// detours: `nodes.count` would report a longer journey than any player takes.
    public var efficientRouteLength: Int {
        var visited = Set<String>()
        var current = startNodeID
        var length = 0

        while length < Self.maximumNodeVisits, visited.insert(current).inserted {
            guard let node = node(id: current) else { break }
            length += 1
            guard
                let next = node.options.first(where: { $0.isEfficient })?.nextNodeID
            else { break }
            current = next
        }
        return length
    }
}

// MARK: - Puzzle envelope

/// A puzzle, tagged by the interaction shape that plays it.
///
/// Encoded with an explicit `kind` discriminator rather than Swift's synthesised
/// enum encoding, which nests payloads under `_0`. Content packs are authored and
/// reviewed by hand, so the JSON has to be readable.
public enum PuzzlePayload: Hashable, Sendable {
    case answerChain(AnswerChainPuzzle)
    case revealAndIdentify(IdentifyPuzzle)
    case gridAssignment(GridPuzzle)
    case studyThenQuiz(StudyPuzzle)
    case constrainedSelection(SelectionPuzzle)
    case branchingChoice(BranchingPuzzle)

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

    /// How many steps a full playthrough has, used for progress and scoring.
    public var stepCount: Int {
        switch self {
        case .answerChain(let puzzle): puzzle.stops.count
        case .revealAndIdentify: 1
        case .gridAssignment(let puzzle): puzzle.categories.count
        case .studyThenQuiz(let puzzle): puzzle.questions.count
        case .constrainedSelection: 1
        case .branchingChoice(let puzzle): puzzle.efficientRouteLength
        }
    }
}

extension PuzzlePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case answerChain
        case revealAndIdentify
        case gridAssignment
        case studyThenQuiz
        case constrainedSelection
        case branchingChoice
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(GameKind.self, forKey: .kind)

        switch kind {
        case .answerChain:
            self = .answerChain(
                try container.decode(AnswerChainPuzzle.self, forKey: .answerChain)
            )
        case .revealAndIdentify:
            self = .revealAndIdentify(
                try container.decode(IdentifyPuzzle.self, forKey: .revealAndIdentify)
            )
        case .gridAssignment:
            self = .gridAssignment(
                try container.decode(GridPuzzle.self, forKey: .gridAssignment)
            )
        case .studyThenQuiz:
            self = .studyThenQuiz(
                try container.decode(StudyPuzzle.self, forKey: .studyThenQuiz)
            )
        case .constrainedSelection:
            self = .constrainedSelection(
                try container.decode(SelectionPuzzle.self, forKey: .constrainedSelection)
            )
        case .branchingChoice:
            self = .branchingChoice(
                try container.decode(BranchingPuzzle.self, forKey: .branchingChoice)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .answerChain(let puzzle):
            try container.encode(puzzle, forKey: .answerChain)
        case .revealAndIdentify(let puzzle):
            try container.encode(puzzle, forKey: .revealAndIdentify)
        case .gridAssignment(let puzzle):
            try container.encode(puzzle, forKey: .gridAssignment)
        case .studyThenQuiz(let puzzle):
            try container.encode(puzzle, forKey: .studyThenQuiz)
        case .constrainedSelection(let puzzle):
            try container.encode(puzzle, forKey: .constrainedSelection)
        case .branchingChoice(let puzzle):
            try container.encode(puzzle, forKey: .branchingChoice)
        }
    }
}

/// One playable puzzle.
public struct PuzzleDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let gameID: ContentID
    public let difficulty: GameDifficulty
    public let title: GameText
    public let payload: PuzzlePayload
    /// Base score before hints and mistakes are taken off.
    public let baseScore: Int
    /// Whether elapsed time is worth reporting for this puzzle (§6, "time, only
    /// if relevant"). A deduction puzzle sets this false.
    public let reportsTime: Bool

    public init(
        id: ContentID,
        gameID: ContentID,
        difficulty: GameDifficulty,
        title: GameText,
        payload: PuzzlePayload,
        baseScore: Int = 100,
        reportsTime: Bool = false
    ) {
        self.id = id
        self.gameID = gameID
        self.difficulty = difficulty
        self.title = title
        self.payload = payload
        self.baseScore = baseScore
        self.reportsTime = reportsTime
    }
}

/// A game pack (§8).
public struct GamePack: Hashable, Sendable, Codable {
    public let manifest: ContentPackManifest
    public let games: [GameDefinition]
    public let puzzles: [PuzzleDefinition]

    public init(
        manifest: ContentPackManifest,
        games: [GameDefinition],
        puzzles: [PuzzleDefinition]
    ) {
        self.manifest = manifest
        self.games = games
        self.puzzles = puzzles
    }

    // A game pack carries no reward table. What a game unlocks is expressed the
    // other way round — a `RewardDefinition` in the collection pack declares
    // `UnlockSource.game(...)` — so there is exactly one place that answers
    // "what does finishing this earn?" rather than two that can disagree
    // (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §7).

    public func game(id: ContentID) -> GameDefinition? {
        games.first { $0.id == id }
    }

    public func puzzle(id: ContentID) -> PuzzleDefinition? {
        puzzles.first { $0.id == id }
    }

    public func puzzles(for gameID: ContentID, difficulty: GameDifficulty) -> [PuzzleDefinition] {
        puzzles.filter { $0.gameID == gameID && $0.difficulty == difficulty }
    }

    /// Games the daily puzzle may draw from, in a stable order.
    ///
    /// A game with no puzzles is excluded rather than offered and then found
    /// empty — the daily puzzle must always resolve to something playable
    /// offline (§4).
    public var dailyEligibleGames: [GameDefinition] {
        games
            .filter { game in
                game.supportsDailyPuzzle
                    && puzzles.contains { $0.gameID == game.id && !$0.difficulty.isTutorial }
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
