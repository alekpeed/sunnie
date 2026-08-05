import Foundation
import SunnieShared

/// Everything a game session does that is not drawing
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §2).
///
/// One use case rather than one per game, because the host owns the lifecycle:
/// starting, saving after each move, resuming, finishing, and awarding. The
/// rules and the boards live in `SunnieShared` and in the screens respectively —
/// nothing in this type knows what a postcard or a shelf is.
///
/// Three safeguards from §7 are enforced here rather than left to the UI:
///
/// - Progression is keyed on the puzzle, so finishing it a second time earns
///   nothing and replaying stays free.
/// - Only a finished session awards, so starting and abandoning earns nothing.
/// - Nothing is ever taken away, and there is no streak to break.
struct PlayGame: Sendable {

    private let repository: any GameRepository
    private let pack: GamePack
    private let progressionEngine: ProgressionEngine
    private let eventPublisher: any DomainEventPublishing
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        repository: any GameRepository,
        pack: GamePack,
        progressionEngine: ProgressionEngine,
        eventPublisher: any DomainEventPublishing,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.pack = pack
        self.progressionEngine = progressionEngine
        self.eventPublisher = eventPublisher
        self.clock = clock
    }

    // MARK: - Catalogue

    var games: [GameDefinition] { pack.games }

    func game(id: ContentID) -> GameDefinition? { pack.game(id: id) }

    func puzzle(id: ContentID) -> PuzzleDefinition? { pack.puzzle(id: id) }

    func games(in category: GameCategory) -> [GameDefinition] {
        pack.games.filter { $0.categories.contains(category) }
    }

    /// Today's key in the player's own calendar.
    var todayKey: String {
        DailyPuzzleScheduler.dayKey(for: clock.now, calendar: clock.calendar)
    }

    // MARK: - Daily puzzle

    /// The day's puzzle, and the session for it if one was started.
    ///
    /// Resolved rather than stored: the choice is a pure function of the date, so
    /// nothing is scheduled ahead, nothing expires, and a day that was never
    /// opened leaves no trace to feel behind on (§4).
    func daily() async -> (
        game: GameDefinition, puzzle: PuzzleDefinition, session: GameSessionState?
    )? {
        let key = todayKey
        guard let choice = DailyPuzzleScheduler.selection(pack: pack, dayKey: key) else {
            return nil
        }
        let session = try? await repository.session(dailyKey: key)
        return (choice.game, choice.puzzle, session)
    }

    /// Opens the day's puzzle, resuming the existing session if there is one.
    func startDaily() async throws -> GameSessionState? {
        let key = todayKey
        guard let choice = DailyPuzzleScheduler.selection(pack: pack, dayKey: key) else {
            return nil
        }
        if let existing = try await repository.session(dailyKey: key) {
            return existing
        }
        let session = GameHost.makeSession(
            game: choice.game,
            puzzle: choice.puzzle,
            seed: DailyPuzzleScheduler.seed(forDayKey: key),
            dailyKey: key,
            now: clock.now
        )
        try await repository.save(session)
        return session
    }

    // MARK: - Free play

    /// Starts a game at a difficulty.
    ///
    /// Chooses the puzzle the player has finished least recently, so working
    /// through a game does not mean replaying the first puzzle forever. Once
    /// every puzzle has been played it cycles rather than refusing — replaying is
    /// allowed, it simply earns nothing new.
    func start(
        gameID: ContentID, difficulty: GameDifficulty
    ) async throws -> GameSessionState? {
        guard let game = pack.game(id: gameID) else { return nil }

        let candidates = pack.puzzles(for: gameID, difficulty: difficulty)
        guard !candidates.isEmpty else { return nil }

        var unplayed: [PuzzleDefinition] = []
        for puzzle in candidates {
            let played = (try? await repository.hasFinished(puzzleID: puzzle.id)) ?? false
            if !played { unplayed.append(puzzle) }
        }
        let pool = unplayed.isEmpty ? candidates : unplayed

        // Seeded from the clock so two sessions started minutes apart are not the
        // same board, and stored on the session so a resume is.
        let seed = UInt64(bitPattern: Int64(clock.now.timeIntervalSince1970.rounded()))
        let puzzle = pool[Int(seed % UInt64(pool.count))]

        let session = GameHost.makeSession(
            game: game, puzzle: puzzle, seed: seed, now: clock.now
        )
        try await repository.save(session)
        return session
    }

    func resumableSessions() async throws -> [GameSessionState] {
        try await repository.resumableSessions()
    }

    func session(id: UUID) async throws -> GameSessionState? {
        try await repository.session(id: id)
    }

    // MARK: - Playing

    /// Records a move and saves.
    ///
    /// Saving on every move rather than on exit is what makes "leave mid-puzzle"
    /// safe — including the case where leaving was the phone dying rather than a
    /// decision.
    @discardableResult
    func apply(
        _ action: GameMove.Action, stepIndex: Int, to session: GameSessionState
    ) async throws -> GameSessionState {
        var updated = session
        updated.append(action, stepIndex: stepIndex, at: clock.now)
        try await repository.save(updated)
        return updated
    }

    /// Adds played time.
    ///
    /// Accumulated in chunks by the screen rather than derived from
    /// `startedAt`, so a puzzle left open overnight does not report eight hours.
    @discardableResult
    func addElapsed(
        _ seconds: Int, to session: GameSessionState
    ) async throws -> GameSessionState {
        guard seconds > 0 else { return session }
        var updated = session
        updated.elapsedSeconds += seconds
        updated.lastPlayedAt = clock.now
        try await repository.save(updated)
        return updated
    }

    /// Leaves a session for later.
    ///
    /// Not a failure and not recorded as one: the status is `setAside`, the
    /// moves are kept, and the session appears under Continue.
    @discardableResult
    func setAside(_ session: GameSessionState) async throws -> GameSessionState {
        guard session.status != .completed else { return session }
        var updated = session
        updated.status = .setAside
        updated.lastPlayedAt = clock.now
        try await repository.save(updated)
        return updated
    }

    /// The one solve of a deduction puzzle.
    ///
    /// Called when a session opens and held by the screen. Solving on every tap
    /// would be the only expensive thing in this feature.
    ///
    /// `async` on a non-isolated type, which is what keeps the search off the
    /// main actor: the five-position puzzle explores about 144,000 arrangements,
    /// and doing that between two frames would be visible.
    func gridSolution(for puzzle: PuzzleDefinition) async -> GridSolution? {
        guard case .gridAssignment(let content) = puzzle.payload else { return nil }
        if case .unique(let solution) = GridDeductionSolver.solve(content) {
            return solution
        }
        // A pack whose puzzle is not uniquely solvable fails validation in the
        // tests. Reaching here at runtime means an added pack got through, and
        // the honest response is to grade nothing rather than to grade wrongly.
        log.error("Deduction puzzle \(puzzle.id.rawValue) has no unique solution.")
        return nil
    }

    // MARK: - Finishing

    /// What finishing produced.
    struct Finish: Sendable {
        let result: GameResult
        /// The progression outcome, which is `skippedAsDuplicate` on a replay.
        /// Surfaced so the result screen can show experience only when it was
        /// actually earned, rather than showing "+15" every time.
        let outcome: ProgressionOutcome?
        let dailyOutcome: ProgressionOutcome?
    }

    /// Closes a session and records what happened.
    ///
    /// Safe to call twice: the result is keyed on the session and the awards on
    /// the puzzle and the day, so a second call returns the stored result and
    /// awards nothing further.
    func finish(
        _ session: GameSessionState,
        puzzle: PuzzleDefinition,
        gridSolution: GridSolution? = nil
    ) async throws -> Finish {
        guard let game = pack.game(id: session.gameID) else {
            throw DomainError.contentInvalid(reason: "unknown game \(session.gameID.rawValue)")
        }

        let now = clock.now
        let board = GameHost.board(puzzle: puzzle, moves: session.moves)
        let play = GameHost.grade(puzzle: puzzle, board: board, gridSolution: gridSolution)

        var closed = session
        closed.status = play.isFinished ? .completed : .setAside
        closed.lastPlayedAt = now
        try await repository.save(closed)

        let result = GameHost.makeResult(
            session: closed,
            puzzle: puzzle,
            play: play,
            hintPolicy: game.hintPolicy(for: session.difficulty),
            finishedAt: now
        )
        let stored = try await repository.save(result)

        guard result.earnsProgression else {
            return Finish(result: stored.value, outcome: nil, dailyOutcome: nil)
        }

        let outcome = try? await progressionEngine.award(
            type: .puzzleCompleted,
            sourceEntityID: closed.id,
            occurredAt: now,
            deterministicKey: ActionKeyFactory.progression(
                type: .puzzleCompleted,
                sourceActionKey: ActionKeyFactory.gamePuzzle(
                    puzzleID: puzzle.id, difficulty: session.difficulty
                )
            )
        )

        var dailyOutcome: ProgressionOutcome?
        if let dailyKey = closed.dailyKey {
            dailyOutcome = try? await progressionEngine.award(
                type: .dailyPuzzleCompleted,
                sourceEntityID: closed.id,
                occurredAt: now,
                deterministicKey: ActionKeyFactory.progression(
                    type: .dailyPuzzleCompleted,
                    sourceActionKey: ActionKeyFactory.dailyPuzzle(dayKey: dailyKey)
                )
            )
        }

        await eventPublisher.publish(
            DomainEvent(
                type: .puzzleCompleted,
                occurredAt: now,
                sourceEntityID: closed.id,
                deterministicKey: outcome?.event?.deterministicKey
            )
        )

        return Finish(result: stored.value, outcome: outcome, dailyOutcome: dailyOutcome)
    }

    // MARK: - History

    func recentResults(limit: Int = 5) async throws -> [GameResult] {
        try await repository.results(limit: limit)
    }

    func results(for gameID: ContentID, limit: Int = 10) async throws -> [GameResult] {
        try await repository.results(gameID: gameID, limit: limit)
    }

    func hasFinished(puzzleID: ContentID) async -> Bool {
        (try? await repository.hasFinished(puzzleID: puzzleID)) ?? false
    }
}
