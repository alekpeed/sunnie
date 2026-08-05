import Foundation

/// The shared host every game runs inside
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §2).
///
/// The host owns session creation, replay, hints, scoring, and results. Each
/// game owns its rules and its board. Splitting it this way is what keeps
/// save/resume, accessibility, and the reward path written once — a new game is
/// an engine plus content, not a seventh implementation of "what happens when you
/// leave mid-puzzle".
///
/// Everything here is pure: no clock, no storage, no audio. The use case layer
/// supplies the time and persists what comes back.
public enum GameHost {

    /// Score deductions. Data rather than magic numbers so a pack can tune them
    /// later without the rules moving.
    public struct Scoring: Hashable, Sendable {
        public var wrongAttemptPenalty: Int
        public var skipPenalty: Int
        /// The floor. A score never goes below this, because a negative score
        /// would be the app telling someone their afternoon was worth less than
        /// nothing.
        public var minimumScore: Int

        public init(
            wrongAttemptPenalty: Int = 5,
            skipPenalty: Int = 15,
            minimumScore: Int = 0
        ) {
            self.wrongAttemptPenalty = wrongAttemptPenalty
            self.skipPenalty = skipPenalty
            self.minimumScore = minimumScore
        }

        public static let standard = Scoring()
    }

    // MARK: - Sessions

    /// Starts a session.
    ///
    /// The seed is stored rather than re-derived, so a session resumed after the
    /// app updates plays the same puzzle it started as.
    public static func makeSession(
        game: GameDefinition,
        puzzle: PuzzleDefinition,
        seed: UInt64,
        dailyKey: String? = nil,
        now: Date
    ) -> GameSessionState {
        GameSessionState(
            gameID: game.id,
            puzzleID: puzzle.id,
            difficulty: puzzle.difficulty,
            seed: seed,
            dailyKey: dailyKey,
            startedAt: now,
            lastPlayedAt: now
        )
    }

    /// Rebuilds the board from the recorded moves.
    ///
    /// `solution` is only consulted for the grid game and may be nil elsewhere.
    public static func board(
        puzzle: PuzzleDefinition, moves: [GameMove]
    ) -> GameBoard {
        switch puzzle.payload {
        case .answerChain(let content):
            .answerChain(AnswerChainEngine.replay(puzzle: content, moves: moves))
        case .revealAndIdentify(let content):
            .revealAndIdentify(IdentifyEngine.replay(puzzle: content, moves: moves))
        case .gridAssignment(let content):
            .gridAssignment(GridEngine.replay(puzzle: content, moves: moves))
        case .studyThenQuiz(let content):
            .studyThenQuiz(StudyEngine.replay(puzzle: content, moves: moves))
        case .constrainedSelection(let content):
            .constrainedSelection(SelectionEngine.replay(puzzle: content, moves: moves))
        case .branchingChoice(let content):
            .branchingChoice(BranchingEngine.replay(puzzle: content, moves: moves))
        }
    }

    /// Grades a board.
    ///
    /// The grid game needs its solution, which the caller computes once when the
    /// session opens rather than on every keystroke — solving is the expensive
    /// part of this feature.
    public static func grade(
        puzzle: PuzzleDefinition, board: GameBoard, gridSolution: GridSolution? = nil
    ) -> GradedPlay {
        switch (puzzle.payload, board) {
        case (.answerChain(let content), .answerChain(let board)):
            return AnswerChainEngine.grade(puzzle: content, board: board)
        case (.revealAndIdentify(let content), .revealAndIdentify(let board)):
            return IdentifyEngine.grade(puzzle: content, board: board)
        case (.gridAssignment(let content), .gridAssignment(let board)):
            return GridEngine.grade(puzzle: content, board: board, solution: gridSolution)
        case (.studyThenQuiz(let content), .studyThenQuiz(let board)):
            return StudyEngine.grade(puzzle: content, board: board)
        case (.constrainedSelection(let content), .constrainedSelection(let board)):
            return SelectionEngine.grade(puzzle: content, board: board)
        case (.branchingChoice(let content), .branchingChoice(let board)):
            return BranchingEngine.grade(puzzle: content, board: board)
        default:
            // A board built for a different puzzle. Returns an empty, unfinished
            // play rather than crashing: the session is unusable, but the app is
            // not, and nothing false is recorded.
            return GradedPlay()
        }
    }

    // MARK: - Scoring

    public static func score(
        puzzle: PuzzleDefinition,
        play: GradedPlay,
        hintPolicy: HintPolicy,
        scoring: Scoring = .standard
    ) -> Int {
        let deductions = play.hintsUsed * hintPolicy.costPerHint
            + play.wrongAttempts * scoring.wrongAttemptPenalty
            + play.skipped * scoring.skipPenalty
            + play.revealCost
        return max(scoring.minimumScore, puzzle.baseScore - deductions)
    }

    /// Names how the session ended.
    ///
    /// Revealed clues do not stop a round counting as unaided: opening the
    /// postcard *is* the game, and charging the player for playing it would be
    /// incoherent. Hints and skips are what mark a solve as assisted.
    public static func completion(_ play: GradedPlay) -> GameCompletion {
        guard play.isFinished else { return .setAside }

        let allCorrect = !play.steps.isEmpty && play.stepsCorrect == play.steps.count
        if allCorrect {
            return play.hintsUsed == 0 && play.skipped == 0 ? .solvedUnaided : .solvedWithHints
        }
        return .finishedWithHelp
    }

    /// Builds the record a finished session leaves behind (§6).
    public static func makeResult(
        session: GameSessionState,
        puzzle: PuzzleDefinition,
        play: GradedPlay,
        hintPolicy: HintPolicy,
        scoring: Scoring = .standard,
        finishedAt: Date
    ) -> GameResult {
        GameResult(
            sessionID: session.id,
            gameID: session.gameID,
            puzzleID: session.puzzleID,
            difficulty: session.difficulty,
            completion: completion(play),
            // A tutorial is for learning the rules, so its score is not the
            // point and is not deducted from. It still records what happened.
            score: session.difficulty.isTutorial
                ? puzzle.baseScore
                : score(puzzle: puzzle, play: play, hintPolicy: hintPolicy, scoring: scoring),
            stepsCorrect: play.stepsCorrect,
            stepsTotal: play.steps.count,
            hintsUsed: play.hintsUsed,
            elapsedSeconds: session.elapsedSeconds,
            steps: play.steps,
            dailyKey: session.dailyKey,
            finishedAt: finishedAt
        )
    }
}

/// Chooses the day's puzzle (§4).
///
/// Three properties matter and all three come from the same decision to derive
/// everything from the calendar day rather than from a stored schedule:
///
/// - **Deterministic.** The same day gives the same puzzle on every device,
///   with no server and no sync.
/// - **Offline.** Nothing is fetched; the pack is already installed.
/// - **No penalty for a missed day.** There is no state to break. Yesterday's
///   puzzle is still yesterday's puzzle, and skipping a week costs nothing —
///   this is why there is no streak counter anywhere in this type.
public enum DailyPuzzleScheduler {

    /// The day's stable key, `yyyy-MM-dd` in the player's own calendar.
    ///
    /// Built from date components rather than a `DateFormatter`, so a device set
    /// to a non-Gregorian calendar or a locale with different digits still
    /// produces the same key format.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// A seed derived from the day key.
    ///
    /// FNV-1a rather than `String.hashValue`: Swift's hashing is seeded per
    /// process, so two launches on the same day would otherwise disagree about
    /// which puzzle today is.
    public static func seed(forDayKey key: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The game and puzzle for a given day.
    ///
    /// Rotation is `seed % eligibleGames.count`, then a puzzle chosen from that
    /// game by the same seed. A day whose game has no puzzle at the preferred
    /// difficulty falls back to any non-tutorial puzzle rather than leaving the
    /// day empty — the daily puzzle must always be playable offline.
    public static func selection(
        pack: GamePack,
        dayKey: String,
        preferredDifficulty: GameDifficulty = .steady
    ) -> (game: GameDefinition, puzzle: PuzzleDefinition)? {
        let games = pack.dailyEligibleGames
        guard !games.isEmpty else { return nil }

        let seed = seed(forDayKey: dayKey)
        let game = games[Int(seed % UInt64(games.count))]

        let atPreferred = pack.puzzles(for: game.id, difficulty: preferredDifficulty)
        let candidates = atPreferred.isEmpty
            ? pack.puzzles.filter { $0.gameID == game.id && !$0.difficulty.isTutorial }
            : atPreferred
        guard !candidates.isEmpty else { return nil }

        // Sorted so the choice does not depend on the order the pack happened to
        // be authored in.
        let ordered = candidates.sorted { $0.id.rawValue < $1.id.rawValue }
        // Shifted before the second modulo so puzzle choice is not perfectly
        // correlated with game choice.
        let index = Int((seed >> 32) % UInt64(ordered.count))
        return (game, ordered[index])
    }
}
