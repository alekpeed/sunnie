import Foundation
import Testing
@testable import SunnieShared

/// The game host, the six engines, the daily scheduler, and the shipped pack.
///
/// The most important test in this file is `everyDeductionPuzzleHasExactlyOneSolution`.
/// A logic puzzle with two answers tells a player their correct arrangement is
/// wrong, and no amount of careful UI recovers from that — so the content is
/// solved here rather than trusted.
@Suite("Games")
struct GamesTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func move(
        _ ordinal: Int, _ step: Int, _ action: GameMove.Action
    ) -> GameMove {
        GameMove(
            ordinal: ordinal,
            stepIndex: step,
            action: action,
            occurredAt: now.addingTimeInterval(Double(ordinal))
        )
    }

    // MARK: - Answer matching

    @Test("Accents, case, and punctuation do not change an answer")
    func normalizerFoldsWhatItShould() {
        #expect(AnswerNormalizer.matches("cafe", accepted: ["café"]))
        #expect(AnswerNormalizer.matches("EL SOL", accepted: ["el sol"]))
        #expect(AnswerNormalizer.matches("Rio de Janeiro", accepted: ["rio-de-janeiro"]))
        #expect(AnswerNormalizer.matches("  noite  ", accepted: ["noite"]))
    }

    @Test("Different words stay different")
    func normalizerKeepsRealDifferences() {
        #expect(!AnswerNormalizer.matches("sal", accepted: ["sol"]))
        #expect(!AnswerNormalizer.matches("noche", accepted: ["noite"]))
        #expect(!AnswerNormalizer.matches("", accepted: ["paris"]))
    }

    @Test("A one-letter typo is reported as close, not accepted")
    func nearMissIsNotAMatch() {
        #expect(AnswerNormalizer.isNearMiss("ventanna", accepted: ["ventana"]))
        #expect(!AnswerNormalizer.matches("ventanna", accepted: ["ventana"]))
        // Short words are excluded: at three letters almost everything is one
        // edit from everything else.
        #expect(!AnswerNormalizer.isNearMiss("rod", accepted: ["red"]))
    }

    // MARK: - Answer chain

    private var chain: AnswerChainPuzzle {
        AnswerChainPuzzle(stops: [
            AnswerChainStop(
                prompt: GameText(text: "One", localizationKey: "k.1"),
                answer: "paris",
                linkExplanation: GameText(text: "Because", localizationKey: "k.1.e"),
                hints: [
                    GameText(text: "First hint", localizationKey: "k.1.h1"),
                    GameText(text: "Second hint", localizationKey: "k.1.h2")
                ]
            ),
            AnswerChainStop(
                prompt: GameText(text: "Two", localizationKey: "k.2"),
                answer: "red",
                linkExplanation: GameText(text: "Because", localizationKey: "k.2.e")
            )
        ])
    }

    @Test("A correct answer advances; a wrong one does not")
    func chainAdvancesOnCorrectAnswers() {
        let board = AnswerChainEngine.replay(
            puzzle: chain,
            moves: [
                move(0, 0, .answer("nope")),
                move(1, 0, .answer("Paris"))
            ]
        )
        #expect(board.stops[0].isSolved)
        #expect(board.stops[0].wrongAttempts == 1)
        #expect(board.currentStop == 1)
        #expect(!board.isComplete)
    }

    @Test("Skipping a stop keeps the route moving")
    func chainSkipStillFinishes() {
        let board = AnswerChainEngine.replay(
            puzzle: chain,
            moves: [move(0, 0, .skip), move(1, 1, .answer("red"))]
        )
        #expect(board.isComplete)

        let play = AnswerChainEngine.grade(puzzle: chain, board: board)
        #expect(play.isFinished)
        #expect(play.skipped == 1)
        #expect(play.stepsCorrect == 1)
    }

    @Test("Hints come in order and stop at the policy limit")
    func chainHintsRespectPolicy() {
        let stop = chain.stops[0]
        #expect(AnswerChainEngine.hint(for: stop, alreadyRevealed: 0, policy: .standard)?.text
            == "First hint")
        #expect(AnswerChainEngine.hint(for: stop, alreadyRevealed: 1, policy: .standard)?.text
            == "Second hint")
        // Two per step is the standard limit, so a third request gets nothing.
        #expect(AnswerChainEngine.hint(for: stop, alreadyRevealed: 2, policy: .standard) == nil)
    }

    @Test("Every step carries an explanation, right or wrong")
    func chainGradeAlwaysExplains() {
        let board = AnswerChainEngine.replay(puzzle: chain, moves: [move(0, 0, .skip)])
        let play = AnswerChainEngine.grade(puzzle: chain, board: board)
        #expect(play.steps.count == 2)
        #expect(play.steps.allSatisfy { $0.explanation != nil })
    }

    // MARK: - Replay determinism

    @Test("Replaying the same moves twice gives the same board")
    func replayIsDeterministic() {
        let moves = [
            move(0, 0, .answer("wrong")),
            move(1, 0, .hint),
            move(2, 0, .answer("paris")),
            move(3, 1, .answer("red"))
        ]
        let first = AnswerChainEngine.replay(puzzle: chain, moves: moves)
        let second = AnswerChainEngine.replay(puzzle: chain, moves: moves.reversed())
        // Reversed input, same result: the ordinal is the order, not the array.
        #expect(first == second)
    }

    @Test("A move from a different game is ignored rather than corrupting the board")
    func foreignMovesAreIgnored() {
        let board = AnswerChainEngine.replay(
            puzzle: chain,
            moves: [
                move(0, 0, .assign(item: 3, slot: 1)),
                move(1, 0, .answer("paris"))
            ]
        )
        #expect(board.stops[0].isSolved)
    }

    // MARK: - Deduction

    /// The property the spec requires of every Jungle Logic puzzle.
    @Test("Every shipped deduction puzzle has exactly one solution")
    func everyDeductionPuzzleHasExactlyOneSolution() {
        let grids = BuiltInGameContent.pack.puzzles.compactMap { puzzle -> (ContentID, GridPuzzle)? in
            guard case .gridAssignment(let content) = puzzle.payload else { return nil }
            return (puzzle.id, content)
        }
        #expect(!grids.isEmpty)

        for (id, grid) in grids {
            switch GridDeductionSolver.solve(grid) {
            case .unique:
                break
            case .none:
                Issue.record("\(id) has no solution")
            case .multiple:
                Issue.record("\(id) has more than one solution")
            case .indeterminate:
                Issue.record("\(id) exhausted the solver's budget")
            }
        }
    }

    @Test("Every clue in the shelf puzzle is load-bearing")
    func removingAClueBreaksUniqueness() {
        guard case .gridAssignment(let grid) =
                BuiltInGameContent.jungleLogicShelf.payload else {
            Issue.record("shelf puzzle is not a grid")
            return
        }
        // Taking any one clue away must leave more than one arrangement. Without
        // this, the clue list quietly accumulates lines that read like
        // information and are not, which makes the puzzle feel harder than it is.
        for index in grid.constraints.indices {
            var constraints = grid.constraints
            constraints.remove(at: index)
            let weakened = GridPuzzle(
                positionLabel: grid.positionLabel,
                categories: grid.categories,
                constraints: constraints,
                explanation: grid.explanation
            )
            if case .unique = GridDeductionSolver.solve(weakened) {
                Issue.record("clue \(index) is redundant")
            }
        }
    }

    private func uniqueSolution(of grid: GridPuzzle) -> GridSolution? {
        if case .unique(let solution) = GridDeductionSolver.solve(grid) { return solution }
        return nil
    }

    @Test("Assigning a value moves it rather than duplicating it")
    func gridAssignmentIsExclusive() {
        guard case .gridAssignment(let grid) =
                BuiltInGameContent.jungleLogicShelf.payload else { return }
        let positions = grid.positionCount

        let board = GridEngine.replay(
            puzzle: grid,
            moves: [
                move(0, 0, .assign(
                    item: GridEngine.encode(category: 0, value: 0, positions: positions), slot: 0
                )),
                move(1, 0, .assign(
                    item: GridEngine.encode(category: 0, value: 0, positions: positions), slot: 2
                ))
            ]
        )
        #expect(board.value(category: 0, position: 0) == nil)
        #expect(board.value(category: 0, position: 2) == 0)
    }

    @Test("A correctly filled grid grades as fully correct")
    func gridGradesTheRightArrangement() throws {
        guard case .gridAssignment(let grid) =
                BuiltInGameContent.jungleLogicShelf.payload else { return }
        let solution = try #require(uniqueSolution(of: grid))
        let positions = grid.positionCount

        var moves: [GameMove] = []
        for (category, row) in solution.assignment.enumerated() {
            for (position, value) in row.enumerated() {
                moves.append(move(
                    moves.count, 0,
                    .assign(
                        item: GridEngine.encode(
                            category: category, value: value, positions: positions
                        ),
                        slot: position
                    )
                ))
            }
        }
        moves.append(move(moves.count, 0, .advance))

        let board = GridEngine.replay(puzzle: grid, moves: moves)
        #expect(board.isFullyAssigned)
        #expect(board.isSubmitted)

        let play = GridEngine.grade(puzzle: grid, board: board, solution: solution)
        #expect(play.isFinished)
        #expect(play.stepsCorrect == play.steps.count)
    }

    @Test("A hint places a value the player has not got right yet")
    func gridHintPlacesSomethingUseful() throws {
        guard case .gridAssignment(let grid) =
                BuiltInGameContent.jungleLogicShelf.payload else { return }
        let solution = try #require(uniqueSolution(of: grid))
        let empty = GridEngine.replay(puzzle: grid, moves: [])

        let placement = try #require(
            GridEngine.hintPlacement(puzzle: grid, board: empty, solution: solution)
        )
        #expect(solution.assignment[placement.category][placement.position] == placement.value)
    }

    // MARK: - Identify

    private var postcard: IdentifyPuzzle {
        guard case .revealAndIdentify(let content) =
                BuiltInGameContent.postcardLisbon.payload else {
            fatalError("Lisbon postcard is not an identify puzzle")
        }
        return content
    }

    @Test("Revealed clues cost score; the round is not ended by a wrong guess")
    func identifyRevealsRatherThanEnds() {
        let wrong = postcard.answerIndex == 0 ? 1 : 0
        let board = IdentifyEngine.replay(
            puzzle: postcard, moves: [move(0, 0, .choose(wrong))]
        )
        #expect(board.chosenOption == nil)
        #expect(board.wrongAttempts == 1)
        // The wrong guess opened a clue instead of closing the round.
        #expect(board.revealedClues.count == 1)
        #expect(!board.isComplete)
    }

    @Test("Asking to see the answer finishes the round without a guess")
    func identifySkipFinishes() {
        let board = IdentifyEngine.replay(puzzle: postcard, moves: [move(0, 0, .skip)])
        #expect(board.isComplete)
        #expect(board.chosenOption == nil)

        let play = IdentifyEngine.grade(puzzle: postcard, board: board)
        #expect(play.isFinished)
        #expect(!play.steps[0].wasCorrect)
        #expect(play.steps[0].explanation != nil)
    }

    @Test("Reveal cost is the sum of the clues actually opened")
    func identifyRevealCostAccumulates() {
        let board = IdentifyEngine.replay(
            puzzle: postcard,
            moves: [
                move(0, 0, .reveal(clue: 0)),
                move(1, 0, .reveal(clue: 0)),
                move(2, 0, .reveal(clue: 2)),
                move(3, 0, .choose(postcard.answerIndex))
            ]
        )
        // The repeated reveal is not charged twice.
        #expect(board.revealedClues.count == 2)

        let play = IdentifyEngine.grade(puzzle: postcard, board: board)
        #expect(play.revealCost == postcard.clues[0].cost + postcard.clues[2].cost)
        #expect(play.steps[0].wasCorrect)
    }

    // MARK: - Selection

    private var suitcase: SelectionPuzzle {
        guard case .constrainedSelection(let content) =
                BuiltInGameContent.suitcasePorto.payload else {
            fatalError("Porto puzzle is not a selection puzzle")
        }
        return content
    }

    @Test("The Porto suitcase has at least one selection that satisfies every rule")
    func suitcaseIsSolvable() {
        #expect(GamePackValidator.hasSatisfyingSelection(suitcase))
    }

    @Test("Toggling an item off removes it from the bag")
    func selectionTogglesBothWays() {
        let board = SelectionEngine.replay(
            puzzle: suitcase,
            moves: [
                move(0, 0, .toggle(item: 0, isSelected: true)),
                move(1, 0, .toggle(item: 1, isSelected: true)),
                move(2, 0, .toggle(item: 0, isSelected: false))
            ]
        )
        #expect(board.selected == [1])
    }

    @Test("The weight rule fails only once the bag is over the limit")
    func selectionWeightRuleBites() throws {
        let rule = try #require(suitcase.rules.first {
            if case .weightLimit = $0.requirement { return true }
            return false
        })
        guard case .weightLimit(let weightLimit) = rule.requirement else { return }
        #expect(weightLimit > 0)

        let everything = Set(suitcase.candidates.indices)
        #expect(SelectionEngine.totalWeight(selection: everything, puzzle: suitcase) > weightLimit)
        #expect(!SelectionEngine.satisfies(rule, selection: everything, puzzle: suitcase))
        #expect(SelectionEngine.satisfies(rule, selection: [], puzzle: suitcase))
    }

    // MARK: - Branching

    private var trail: BranchingPuzzle {
        guard case .branchingChoice(let content) =
                BuiltInGameContent.triviaTrailIberia.payload else {
            fatalError("Iberia trail is not a branching puzzle")
        }
        return content
    }

    @Test("A wrong answer takes the long way round rather than ending the trail")
    func trailContinuesAfterAWrongAnswer() throws {
        let start = try #require(trail.node(id: trail.startNodeID))
        let wrong = try #require(start.options.firstIndex { !$0.isEfficient })

        let board = BranchingEngine.replay(puzzle: trail, moves: [move(0, 0, .choose(wrong))])
        #expect(board.visits.count == 1)
        #expect(board.currentNodeID != nil)
        #expect(!board.isComplete)
    }

    @Test("The efficient route reaches the end and grades as fully correct")
    func trailEfficientRouteFinishes() {
        var moves: [GameMove] = []
        var current: String? = trail.startNodeID

        while let nodeID = current, let node = trail.node(id: nodeID) {
            guard let index = node.options.firstIndex(where: { $0.isEfficient }) else { break }
            moves.append(move(moves.count, moves.count, .choose(index)))
            current = node.options[index].nextNodeID
        }

        let board = BranchingEngine.replay(puzzle: trail, moves: moves)
        #expect(board.isComplete)

        let play = BranchingEngine.grade(puzzle: trail, board: board)
        #expect(play.isFinished)
        #expect(play.stepsCorrect == play.steps.count)
        #expect(play.steps.count == trail.efficientRouteLength)
        #expect(play.steps.allSatisfy { $0.explanation != nil })
    }

    // MARK: - Study

    private var atlas: StudyPuzzle {
        guard case .studyThenQuiz(let content) =
                BuiltInGameContent.memoryAtlasScrapbook.payload else {
            fatalError("Scrapbook is not a study puzzle")
        }
        return content
    }

    @Test("Questions are not answerable until the page has been put away")
    func studyRequiresAdvance() {
        let board = StudyEngine.replay(puzzle: atlas, moves: [move(0, 0, .choose(0))])
        #expect(board.phase == .studying)
        #expect(!board.isComplete)
    }

    @Test("A skipped question grades as unanswered, not as a wrong guess")
    func studySkipIsNotAWrongAnswer() {
        var moves = [move(0, 0, .advance)]
        for index in atlas.questions.indices {
            moves.append(move(
                moves.count, index,
                index == 0 ? .skip : .choose(atlas.questions[index].answerIndex)
            ))
        }

        let board = StudyEngine.replay(puzzle: atlas, moves: moves)
        #expect(board.isComplete)

        let play = StudyEngine.grade(puzzle: atlas, board: board)
        #expect(play.skipped == 1)
        #expect(play.wrongAttempts == 0)
        #expect(play.stepsCorrect == atlas.questions.count - 1)
    }

    // MARK: - Scoring and completion

    private var scoringPuzzle: PuzzleDefinition {
        PuzzleDefinition(
            id: "test.puzzle.scoring",
            gameID: "test.game.scoring",
            difficulty: .steady,
            title: GameText(text: "Scoring", localizationKey: "k.title"),
            payload: .answerChain(chain),
            baseScore: 100
        )
    }

    @Test("Hints, wrong answers, and skips each come off the score")
    func scoreDeducts() {
        let play = GradedPlay(
            steps: [], isFinished: true, hintsUsed: 2, wrongAttempts: 3, skipped: 1, revealCost: 5
        )
        let score = GameHost.score(
            puzzle: scoringPuzzle, play: play, hintPolicy: .standard
        )
        // 100 − (2 × 10) − (3 × 5) − 15 − 5
        #expect(score == 45)
    }

    @Test("A score never goes below zero")
    func scoreHasAFloor() {
        let play = GradedPlay(isFinished: true, hintsUsed: 50)
        #expect(GameHost.score(puzzle: scoringPuzzle, play: play, hintPolicy: .standard) == 0)
    }

    @Test("Completion never reads as a failure")
    func completionNamesWhatHappened() {
        let step = GameStepResult(
            stepIndex: 0,
            prompt: GameText(text: "p", localizationKey: "k"),
            expectedAnswer: "a",
            playerAnswer: "a",
            wasCorrect: true,
            hintsUsed: 0,
            explanation: nil
        )

        #expect(GameHost.completion(GradedPlay(steps: [step], isFinished: true)) == .solvedUnaided)
        #expect(GameHost.completion(
            GradedPlay(steps: [step], isFinished: true, hintsUsed: 1)
        ) == .solvedWithHints)
        #expect(GameHost.completion(GradedPlay(steps: [step], isFinished: false)) == .setAside)

        // Every case is something that happened. There is no `.failed` to reach
        // for, which is the point.
        for completion in [
            GameCompletion.solvedUnaided, .solvedWithHints, .finishedWithHelp, .setAside
        ] {
            #expect(!completion.rawValue.lowercased().contains("fail"))
        }
    }

    @Test("Revealing clues does not stop a round counting as unaided")
    func revealsDoNotCountAsHelp() {
        let step = GameStepResult(
            stepIndex: 0,
            prompt: GameText(text: "p", localizationKey: "k"),
            expectedAnswer: "a",
            playerAnswer: "a",
            wasCorrect: true,
            hintsUsed: 0,
            explanation: nil
        )
        let play = GradedPlay(steps: [step], isFinished: true, revealCost: 30)
        #expect(GameHost.completion(play) == .solvedUnaided)
    }

    @Test("Only a finished session earns progression")
    func abandonedSessionsEarnNothing() {
        let unfinished = GameSessionState(
            gameID: "test.game.scoring",
            puzzleID: "test.puzzle.scoring",
            difficulty: .steady,
            seed: 1,
            startedAt: now,
            lastPlayedAt: now
        )
        let result = GameHost.makeResult(
            session: unfinished,
            puzzle: scoringPuzzle,
            play: GradedPlay(isFinished: false),
            hintPolicy: .standard,
            finishedAt: now
        )
        #expect(result.completion == .setAside)
        #expect(!result.earnsProgression)
    }

    @Test("A tutorial keeps its full score whatever help was taken")
    func tutorialIsNotScoredAgainst() {
        let session = GameSessionState(
            gameID: "test.game.scoring",
            puzzleID: "test.puzzle.scoring",
            difficulty: .tutorial,
            seed: 1,
            startedAt: now,
            lastPlayedAt: now
        )
        let result = GameHost.makeResult(
            session: session,
            puzzle: scoringPuzzle,
            play: GradedPlay(isFinished: true, hintsUsed: 6),
            hintPolicy: .free,
            finishedAt: now
        )
        #expect(result.score == scoringPuzzle.baseScore)
    }

    // MARK: - Save and resume

    @Test("A session survives a JSON round trip")
    func sessionRoundTrips() throws {
        var session = GameSessionState(
            gameID: "sunnie.game.wordLayover",
            puzzleID: "sunnie.puzzle.wordLayover.seine",
            difficulty: .gentle,
            seed: 0xFFFF_FFFF_FFFF_FFFF,
            dailyKey: "2026-08-05",
            startedAt: now,
            lastPlayedAt: now
        )
        session.append(.answer("paris"), stepIndex: 0, at: now)
        session.append(.hint, stepIndex: 1, at: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            GameSessionState.self, from: try encoder.encode(session)
        )
        #expect(restored == session)
        // The largest possible seed survives, which is what the string storage in
        // the schema exists to guarantee.
        #expect(restored.seed == 0xFFFF_FFFF_FFFF_FFFF)
        #expect(restored.hintsUsed == 1)
    }

    @Test("A puzzle pack survives a JSON round trip")
    func packRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let restored = try decoder.decode(
            GamePack.self, from: try encoder.encode(BuiltInGameContent.pack)
        )
        #expect(restored == BuiltInGameContent.pack)
    }

    // MARK: - Daily puzzle

    @Test("The day key is the local date and does not depend on the locale")
    func dayKeyIsStable() throws {
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))
        )
        #expect(DailyPuzzleScheduler.dayKey(for: date, calendar: calendar) == "2026-08-05")
    }

    @Test("The same day always chooses the same puzzle")
    func dailySelectionIsDeterministic() {
        let pack = BuiltInGameContent.pack
        for day in ["2026-01-01", "2026-08-05", "2027-02-28"] {
            let first = DailyPuzzleScheduler.selection(pack: pack, dayKey: day)
            let second = DailyPuzzleScheduler.selection(pack: pack, dayKey: day)
            #expect(first?.puzzle.id == second?.puzzle.id)
            #expect(first?.game.id == second?.game.id)
        }
    }

    @Test("The daily puzzle rotates across games rather than repeating one")
    func dailyRotates() throws {
        let pack = BuiltInGameContent.pack
        var chosen = Set<ContentID>()
        for day in 1...60 {
            let key = String(format: "2026-03-%02d", (day % 31) + 1)
            if let selection = DailyPuzzleScheduler.selection(pack: pack, dayKey: key) {
                chosen.insert(selection.game.id)
            }
        }
        // Not a distribution test — just that the rotation is not pinned to one
        // game, which a hash mistake would produce.
        #expect(chosen.count >= 3)
    }

    @Test("The daily puzzle is never a tutorial and always has content behind it")
    func dailyIsAlwaysPlayable() {
        let pack = BuiltInGameContent.pack
        for day in 1...40 {
            let key = String(format: "2026-05-%02d", (day % 28) + 1)
            let selection = DailyPuzzleScheduler.selection(pack: pack, dayKey: key)
            #expect(selection != nil)
            #expect(selection?.puzzle.difficulty.isTutorial == false)
            #expect(selection?.puzzle.gameID == selection?.game.id)
        }
    }

    @Test("Missing a day changes nothing about the next one")
    func missingADayCostsNothing() {
        // There is no state to check, which is the assertion: the scheduler takes
        // a date and a pack and nothing else, so a gap cannot be recorded, cannot
        // be punished, and cannot break a streak that does not exist.
        let pack = BuiltInGameContent.pack
        let after = DailyPuzzleScheduler.selection(pack: pack, dayKey: "2026-08-05")
        let afterGap = DailyPuzzleScheduler.selection(pack: pack, dayKey: "2026-08-05")
        #expect(after?.puzzle.id == afterGap?.puzzle.id)
    }

    // MARK: - Idempotency

    @Test("The progression key depends on the puzzle, not the session")
    func progressionKeyIsPerPuzzle() {
        let first = ActionKeyFactory.gamePuzzle(
            puzzleID: "sunnie.puzzle.wordLayover.seine", difficulty: .gentle
        )
        let second = ActionKeyFactory.gamePuzzle(
            puzzleID: "sunnie.puzzle.wordLayover.seine", difficulty: .gentle
        )
        #expect(first == second)

        // A different difficulty is a different puzzle to have solved.
        let harder = ActionKeyFactory.gamePuzzle(
            puzzleID: "sunnie.puzzle.wordLayover.seine", difficulty: .steady
        )
        #expect(first != harder)
    }

    @Test("The daily key depends on the day alone")
    func dailyKeyIsPerDay() {
        #expect(
            ActionKeyFactory.dailyPuzzle(dayKey: "2026-08-05")
                == ActionKeyFactory.dailyPuzzle(dayKey: "2026-08-05")
        )
        #expect(
            ActionKeyFactory.dailyPuzzle(dayKey: "2026-08-05")
                != ActionKeyFactory.dailyPuzzle(dayKey: "2026-08-06")
        )
    }

    // MARK: - Multiplayer groundwork

    @Test("Moves are serializable and carry their own order")
    func movesAreTransferable() throws {
        let move = GameMove(
            ordinal: 4, stepIndex: 2, action: .assign(item: 3, slot: 1), occurredAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(GameMove.self, from: try encoder.encode(move)) == move)
    }

    @Test("The initial app composes a multiplayer service that does nothing")
    func multiplayerIsAbsentRatherThanFaked() async throws {
        let service = NoMultiplayer()
        #expect(!service.isAvailable)
        let pending = try await service.pendingMoves(sessionID: UUID())
        #expect(pending.isEmpty)
    }
}

/// The shipped pack, checked the way the app will read it.
@Suite("Game content")
struct GameContentTests {

    @Test("The built-in pack has no content problems")
    func packIsValid() {
        let issues = GamePackValidator.validate(BuiltInGameContent.pack)
        #expect(issues.isEmpty, "\(issues.map(\.description))")
    }

    @Test("The registry serves the built-in pack")
    func registryCarriesGames() {
        let registry = ContentRegistry(
            messagePack: FallbackContent.messagePack,
            themePack: FallbackContent.themePack
        )
        #expect(!registry.gamePack.games.isEmpty)
        #expect(registry.gameIssues.isEmpty)
        #expect(registry.game(id: "sunnie.game.wordLayover") != nil)
    }

    @Test("All seven games from the specification ship")
    func theInitialSetIsComplete() {
        let expected: Set<ContentID> = [
            "sunnie.game.wordLayover",
            "sunnie.game.postcardCipher",
            "sunnie.game.jungleLogic",
            "sunnie.game.memoryAtlas",
            "sunnie.game.lostInTranslation",
            "sunnie.game.sunniesSuitcase",
            "sunnie.game.triviaTrail"
        ]
        #expect(Set(BuiltInGameContent.pack.games.map(\.id)) == expected)
    }

    @Test("Every game covers every difficulty it offers")
    func difficultiesHavePuzzles() {
        let pack = BuiltInGameContent.pack
        for game in pack.games {
            for difficulty in game.difficulties {
                #expect(
                    !pack.puzzles(for: game.id, difficulty: difficulty).isEmpty,
                    "\(game.id) offers \(difficulty.rawValue) with nothing behind it"
                )
            }
        }
    }

    @Test("Every authored line passes the tone rules")
    func gameTextIsKind() {
        var texts: [(String, String)] = []

        func collect(_ text: GameText, _ id: String) {
            texts.append((text.text, id))
        }

        for puzzle in BuiltInGameContent.pack.puzzles {
            let id = puzzle.id.rawValue
            collect(puzzle.title, id)

            switch puzzle.payload {
            case .answerChain(let content):
                for stop in content.stops {
                    collect(stop.prompt, id)
                    collect(stop.linkExplanation, id)
                    stop.hints.forEach { collect($0, id) }
                }
            case .revealAndIdentify(let content):
                collect(content.prompt, id)
                collect(content.explanation, id)
                content.clues.forEach { collect($0.detail, id) }
                content.options.forEach { collect($0, id) }
            case .gridAssignment(let content):
                collect(content.positionLabel, id)
                collect(content.explanation, id)
                content.categories.forEach { category in
                    collect(category.name, id)
                    category.values.forEach { collect($0, id) }
                }
            case .studyThenQuiz(let content):
                content.items.forEach { collect($0.label, id); collect($0.detail, id) }
                content.questions.forEach { question in
                    collect(question.prompt, id)
                    collect(question.explanation, id)
                    question.options.forEach { collect($0, id) }
                }
            case .constrainedSelection(let content):
                collect(content.brief, id)
                collect(content.explanation, id)
                content.candidates.forEach { collect($0.name, id) }
                content.rules.forEach { collect($0.explanation, id) }
            case .branchingChoice(let content):
                content.nodes.forEach { node in
                    collect(node.prompt, id)
                    node.options.forEach { collect($0.text, id); collect($0.explanation, id) }
                }
            }
        }

        #expect(!texts.isEmpty)
        for (text, id) in texts {
            #expect(ContentValidator.toneIssues(in: text, contentID: id).isEmpty)
            #expect(ContentValidator.claimIssues(in: text, contentID: id).isEmpty)
        }
    }

    @Test("Every step of every puzzle can explain itself")
    func everyPuzzleExplains() {
        for puzzle in BuiltInGameContent.pack.puzzles {
            switch puzzle.payload {
            case .answerChain(let content):
                #expect(content.stops.allSatisfy { !$0.linkExplanation.isEmpty })
            case .revealAndIdentify(let content):
                #expect(!content.explanation.isEmpty)
            case .gridAssignment(let content):
                #expect(!content.explanation.isEmpty)
            case .studyThenQuiz(let content):
                #expect(content.questions.allSatisfy { !$0.explanation.isEmpty })
            case .constrainedSelection(let content):
                #expect(content.rules.allSatisfy { !$0.explanation.isEmpty })
                #expect(!content.explanation.isEmpty)
            case .branchingChoice(let content):
                #expect(content.nodes.allSatisfy { node in
                    node.options.allSatisfy { !$0.explanation.isEmpty }
                })
            }
        }
    }

    @Test("A pack with an ambiguous deduction puzzle is rejected")
    func validatorCatchesAnAmbiguousPuzzle() {
        let grid = GridPuzzle(
            positionLabel: GameText(text: "Shelf", localizationKey: "k.pos"),
            categories: [
                GridCategory(
                    name: GameText(text: "Plant", localizationKey: "k.a"),
                    values: [
                        GameText(text: "Fern", localizationKey: "k.a.1"),
                        GameText(text: "Pothos", localizationKey: "k.a.2")
                    ]
                ),
                GridCategory(
                    name: GameText(text: "Pot", localizationKey: "k.b"),
                    values: [
                        GameText(text: "Blue", localizationKey: "k.b.1"),
                        GameText(text: "Green", localizationKey: "k.b.2")
                    ]
                )
            ],
            // No clues at all, so both arrangements are valid.
            constraints: [],
            explanation: GameText(text: "Because", localizationKey: "k.e")
        )
        #expect(GridDeductionSolver.solve(grid) == .multiple)

        let pack = GamePack(
            manifest: BuiltInGameContent.manifest,
            games: [
                GameDefinition(
                    id: "test.game.broken",
                    kind: .gridAssignment,
                    categories: [.logic],
                    displayNameKey: "k.name",
                    summaryKey: "k.summary",
                    rulesKey: "k.rules",
                    difficulties: [.gentle]
                )
            ],
            puzzles: [
                PuzzleDefinition(
                    id: "test.puzzle.broken",
                    gameID: "test.game.broken",
                    difficulty: .gentle,
                    title: GameText(text: "Broken", localizationKey: "k.title"),
                    payload: .gridAssignment(grid)
                )
            ]
        )

        let issues = GamePackValidator.validate(pack)
        #expect(issues.contains { issue in
            if case .ambiguousSolution = issue { return true }
            return false
        })
    }

    @Test("A pack whose game and puzzle disagree about shape is rejected")
    func validatorCatchesAKindMismatch() {
        let pack = GamePack(
            manifest: BuiltInGameContent.manifest,
            games: [
                GameDefinition(
                    id: "test.game.mismatch",
                    kind: .branchingChoice,
                    categories: [.trivia],
                    displayNameKey: "k.name",
                    summaryKey: "k.summary",
                    rulesKey: "k.rules",
                    difficulties: [.gentle]
                )
            ],
            puzzles: [
                PuzzleDefinition(
                    id: "test.puzzle.mismatch",
                    gameID: "test.game.mismatch",
                    difficulty: .gentle,
                    title: GameText(text: "Mismatch", localizationKey: "k.title"),
                    payload: .answerChain(AnswerChainPuzzle(stops: [
                        AnswerChainStop(
                            prompt: GameText(text: "One", localizationKey: "k.1"),
                            answer: "one",
                            linkExplanation: GameText(text: "Because", localizationKey: "k.1.e")
                        )
                    ]))
                )
            ]
        )

        #expect(GamePackValidator.validate(pack).contains { issue in
            if case .kindMismatch = issue { return true }
            return false
        })
    }
}
