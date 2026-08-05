import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Phase 7 behaviour against a real in-memory store: starting, saving mid-move,
/// resuming, finishing, and the progression safeguards.
///
/// The engines are tested in the shared package where they are pure. What is
/// tested here is everything that involves storage — which is where "save and
/// come back later" either works or quietly does not.
@Suite("Game flows")
struct GameFlowTests {

    /// 2026-02-02T12:00:00Z — noon UTC deliberately. The daily-puzzle tests move
    /// a few hours either side of it, and starting at noon keeps both instants
    /// inside the same local day for every time zone the test machine might be
    /// set to.
    private static let referenceDate = Date(timeIntervalSince1970: 1_770_033_600)

    @MainActor
    private func makeDependencies(
        now: Date = GameFlowTests.referenceDate
    ) throws -> AppDependencies {
        AppDependencies(
            modelContainer: try ModelContainerFactory.make(storage: .inMemory),
            clock: FixedClock(now: now),
            enableWatchConnectivity: false
        )
    }

    /// The moves that solve the shelf deduction puzzle.
    private func solvingMoves(
        for grid: GridPuzzle, solution: GridSolution
    ) -> [(GameMove.Action, Int)] {
        var moves: [(GameMove.Action, Int)] = []
        for (category, row) in solution.assignment.enumerated() {
            for (position, value) in row.enumerated() {
                moves.append((
                    .assign(
                        item: GridEngine.encode(
                            category: category, value: value, positions: grid.positionCount
                        ),
                        slot: position
                    ),
                    0
                ))
            }
        }
        moves.append((.advance, 0))
        return moves
    }

    // MARK: - Starting and resuming

    @Test("Starting a game stores a resumable session")
    @MainActor
    func startingStoresASession() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.wordLayover", difficulty: .gentle
            )
        )

        #expect(session.status == .inProgress)
        #expect(session.moves.isEmpty)

        let resumable = try await dependencies.playGame.resumableSessions()
        #expect(resumable.map(\.id).contains(session.id))
    }

    @Test("Every move is saved as it happens, not on the way out")
    @MainActor
    func movesArePersistedImmediately() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.wordLayover", difficulty: .gentle
            )
        )

        _ = try await dependencies.playGame.apply(
            .answer("Paris"), stepIndex: 0, to: session
        )

        // Read back through the repository rather than the returned value: what
        // matters is that a session interrupted here — not exited, interrupted —
        // still has the move.
        let stored = try #require(try await dependencies.gameRepository.session(id: session.id))
        #expect(stored.moves.count == 1)
        #expect(stored.moves[0].action == .answer("Paris"))
    }

    @Test("A resumed session replays to the same board")
    @MainActor
    func resumeRebuildsTheBoard() async throws {
        let dependencies = try makeDependencies()
        var session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.wordLayover", difficulty: .gentle
            )
        )
        let puzzle = try #require(dependencies.playGame.puzzle(id: session.puzzleID))
        guard case .answerChain(let content) = puzzle.payload else {
            Issue.record("word layover puzzle is not an answer chain")
            return
        }

        session = try await dependencies.playGame.apply(
            .answer(content.stops[0].answer), stepIndex: 0, to: session
        )
        _ = try await dependencies.playGame.setAside(session)

        let resumed = try #require(try await dependencies.playGame.session(id: session.id))
        let board = GameHost.board(puzzle: puzzle, moves: resumed.moves)
        guard case .answerChain(let chainBoard) = board else {
            Issue.record("resumed board is the wrong shape")
            return
        }
        #expect(chainBoard.stops[0].isSolved)
        #expect(chainBoard.currentStop == 1)
    }

    @Test("Setting a session aside keeps it, and never records a failure")
    @MainActor
    func settingAsideIsNotAFailure() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.jungleLogic", difficulty: .gentle
            )
        )

        let aside = try await dependencies.playGame.setAside(session)
        #expect(aside.status == .setAside)
        #expect(aside.isResumable)

        // Nothing was written to the results list, so no history entry says the
        // player gave up on anything.
        #expect(try await dependencies.playGame.recentResults().isEmpty)
    }

    // MARK: - Finishing

    @Test("Solving the shelf puzzle records a result and awards experience once")
    @MainActor
    func finishingAwardsOnce() async throws {
        let dependencies = try makeDependencies()
        var session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.jungleLogic", difficulty: .gentle
            )
        )
        let puzzle = try #require(dependencies.playGame.puzzle(id: session.puzzleID))
        guard case .gridAssignment(let grid) = puzzle.payload else {
            Issue.record("jungle logic puzzle is not a grid")
            return
        }
        let solution = try #require(await dependencies.playGame.gridSolution(for: puzzle))

        for (action, step) in solvingMoves(for: grid, solution: solution) {
            session = try await dependencies.playGame.apply(action, stepIndex: step, to: session)
        }

        let first = try await dependencies.playGame.finish(
            session, puzzle: puzzle, gridSolution: solution
        )
        #expect(first.result.completion == .solvedUnaided)
        #expect(first.result.stepsCorrect == first.result.stepsTotal)
        #expect(first.outcome?.event != nil)

        let awarded = try #require(first.outcome?.event?.experienceAwarded)
        #expect(awarded > 0)

        // Finishing the same session again returns the stored result and awards
        // nothing further — a double tap on "see how it went" is not a second
        // puzzle solved.
        let second = try await dependencies.playGame.finish(
            session, puzzle: puzzle, gridSolution: solution
        )
        #expect(second.result.id == first.result.id)
        if let outcome = second.outcome {
            #expect(outcome.event == nil, "a replay awarded experience again")
        }

        let profile = try await dependencies.progressionRepository.profile()
        #expect(profile.experience == awarded)
    }

    @Test("Replaying a puzzle in a fresh session earns nothing new")
    @MainActor
    func replayingEarnsNothing() async throws {
        let dependencies = try makeDependencies()
        let puzzle = try #require(
            dependencies.playGame.puzzle(id: "sunnie.puzzle.jungleLogic.shelf")
        )
        guard case .gridAssignment(let grid) = puzzle.payload else { return }
        let solution = try #require(await dependencies.playGame.gridSolution(for: puzzle))

        func playThrough() async throws -> PlayGame.Finish {
            var session = GameHost.makeSession(
                game: try #require(dependencies.playGame.game(id: puzzle.gameID)),
                puzzle: puzzle,
                seed: 1,
                now: Self.referenceDate
            )
            try await dependencies.gameRepository.save(session)
            for (action, step) in solvingMoves(for: grid, solution: solution) {
                session = try await dependencies.playGame.apply(
                    action, stepIndex: step, to: session
                )
            }
            return try await dependencies.playGame.finish(
                session, puzzle: puzzle, gridSolution: solution
            )
        }

        let first = try await playThrough()
        let awarded = try #require(first.outcome?.event?.experienceAwarded)

        // A genuinely separate session, with its own id and its own result row.
        let second = try await playThrough()
        #expect(second.result.id != first.result.id)
        #expect(second.outcome?.event == nil)

        let profile = try await dependencies.progressionRepository.profile()
        #expect(profile.experience == awarded, "replaying a puzzle awarded twice")
    }

    @Test("Starting and abandoning sessions repeatedly earns nothing")
    @MainActor
    func abandoningEarnsNothing() async throws {
        let dependencies = try makeDependencies()

        for _ in 0..<5 {
            let session = try #require(
                try await dependencies.playGame.start(
                    gameID: "sunnie.game.wordLayover", difficulty: .gentle
                )
            )
            _ = try await dependencies.playGame.apply(
                .answer("something"), stepIndex: 0, to: session
            )
            _ = try await dependencies.playGame.setAside(session)
        }

        let profile = try await dependencies.progressionRepository.profile()
        #expect(profile.experience == 0)
        #expect(try await dependencies.playGame.recentResults().isEmpty)
    }

    // MARK: - Daily puzzle

    @Test("Opening the daily puzzle twice resumes rather than restarting")
    @MainActor
    func dailyResumesRatherThanRestarting() async throws {
        let dependencies = try makeDependencies()

        let first = try #require(try await dependencies.playGame.startDaily())
        let updated = try await dependencies.playGame.apply(
            .answer("something"), stepIndex: 0, to: first
        )
        #expect(updated.moves.count == 1)

        let second = try #require(try await dependencies.playGame.startDaily())
        #expect(second.id == first.id)
        #expect(second.moves.count == 1, "the day's puzzle was restarted from scratch")
    }

    @Test("The daily puzzle is the same one on every launch of the same day")
    @MainActor
    func dailyIsStableWithinADay() async throws {
        let morning = try makeDependencies(now: Self.referenceDate)
        let evening = try makeDependencies(
            now: Self.referenceDate.addingTimeInterval(6 * 3600)
        )

        let a = try #require(await morning.playGame.daily())
        let b = try #require(await evening.playGame.daily())
        #expect(a.puzzle.id == b.puzzle.id)
    }

    @Test("The daily key follows the player's own calendar")
    @MainActor
    func dailyKeyIsLocal() async throws {
        let dependencies = try makeDependencies()
        let key = dependencies.playGame.todayKey
        #expect(key.count == 10)
        #expect(key.split(separator: "-").count == 3)
    }

    // MARK: - History

    @Test("A finished session is stored once even if the result is saved twice")
    @MainActor
    func resultsAreIdempotentPerSession() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.triviaTrail", difficulty: .gentle
            )
        )

        let result = GameResult(
            sessionID: session.id,
            gameID: session.gameID,
            puzzleID: session.puzzleID,
            difficulty: session.difficulty,
            completion: .solvedUnaided,
            score: 100,
            stepsCorrect: 3,
            stepsTotal: 3,
            hintsUsed: 0,
            elapsedSeconds: 60,
            steps: [],
            finishedAt: Self.referenceDate
        )

        let created = try await dependencies.gameRepository.save(result)
        #expect(created.wasCreated)

        // A different id, same session: still one row.
        let duplicate = GameResult(
            sessionID: session.id,
            gameID: session.gameID,
            puzzleID: session.puzzleID,
            difficulty: session.difficulty,
            completion: .solvedWithHints,
            score: 40,
            stepsCorrect: 2,
            stepsTotal: 3,
            hintsUsed: 4,
            elapsedSeconds: 900,
            steps: [],
            finishedAt: Self.referenceDate
        )
        let again = try await dependencies.gameRepository.save(duplicate)
        #expect(!again.wasCreated)
        #expect(again.value.score == 100)

        #expect(try await dependencies.playGame.recentResults().count == 1)
    }

    @Test("Only finished results mark a puzzle as played")
    @MainActor
    func setAsideDoesNotCountAsPlayed() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.triviaTrail", difficulty: .gentle
            )
        )

        _ = try await dependencies.gameRepository.save(GameResult(
            sessionID: session.id,
            gameID: session.gameID,
            puzzleID: session.puzzleID,
            difficulty: session.difficulty,
            completion: .setAside,
            score: 0,
            stepsCorrect: 0,
            stepsTotal: 3,
            hintsUsed: 0,
            elapsedSeconds: 10,
            steps: [],
            finishedAt: Self.referenceDate
        ))

        #expect(
            try await dependencies.gameRepository.hasFinished(puzzleID: session.puzzleID) == false
        )
    }

    // MARK: - Storage round trip

    @Test("A session survives the store, including its largest possible seed")
    @MainActor
    func sessionSurvivesStorage() async throws {
        let dependencies = try makeDependencies()

        var session = GameSessionState(
            gameID: "sunnie.game.wordLayover",
            puzzleID: "sunnie.puzzle.wordLayover.seine",
            difficulty: .gentle,
            seed: UInt64.max,
            dailyKey: "2026-08-05",
            startedAt: Self.referenceDate,
            lastPlayedAt: Self.referenceDate
        )
        session.append(.reveal(clue: 2), stepIndex: 0, at: Self.referenceDate)
        session.append(.toggle(item: 1, isSelected: true), stepIndex: 0, at: Self.referenceDate)
        try await dependencies.gameRepository.save(session)

        let stored = try #require(try await dependencies.gameRepository.session(id: session.id))
        #expect(stored.seed == UInt64.max)
        #expect(stored.dailyKey == "2026-08-05")
        #expect(stored.moves == session.moves)

        // And the daily lookup finds it by its key.
        let byDay = try await dependencies.gameRepository.session(dailyKey: "2026-08-05")
        #expect(byDay?.id == session.id)
    }

    @Test("A session with no daily key is not returned by the daily lookup")
    @MainActor
    func freePlayIsNotTheDailyPuzzle() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.wordLayover", difficulty: .gentle
            )
        )
        #expect(session.dailyKey == nil)

        let byDay = try await dependencies.gameRepository.session(
            dailyKey: dependencies.playGame.todayKey
        )
        #expect(byDay == nil)
    }

    // MARK: - Routing

    @Test("A game session route round-trips through its identifier")
    @MainActor
    func gameRouteCarriesTheSession() async throws {
        let dependencies = try makeDependencies()
        let session = try #require(
            try await dependencies.playGame.start(
                gameID: "sunnie.game.memoryAtlas", difficulty: .steady
            )
        )

        let route = AppRoute.game(session.id.uuidString)
        #expect(route.tab == .more)
        guard case .game(let raw) = route else {
            Issue.record("route lost its identifier")
            return
        }
        #expect(UUID(uuidString: raw) == session.id)
    }
}
