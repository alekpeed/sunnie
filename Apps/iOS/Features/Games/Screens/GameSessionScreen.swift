import SwiftUI
import Observation
import SunnieShared

/// Feature model for a game session (S-19).
///
/// Holds the session, the puzzle, and — for the deduction game — the one solve.
/// The board is derived from the moves on every read rather than stored, which
/// is what keeps the screen and the save file from disagreeing.
@MainActor
@Observable
final class GameSessionModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var session: GameSessionState?
    private(set) var game: GameDefinition?
    private(set) var puzzle: PuzzleDefinition?
    private(set) var gridSolution: GridSolution?
    private(set) var finish: PlayGame.Finish?

    /// The hint currently on screen, if the player asked for one.
    private(set) var visibleHint: GameText?
    /// Set when a typed answer was one letter away, so the screen can say so
    /// instead of rejecting silently.
    private(set) var lastAnswerWasNearMiss = false

    /// Study phase countdown for Memory Atlas, in seconds remaining.
    var studySecondsRemaining: Int = 0
    /// The player has chosen to study without a countdown. Costs nothing — an
    /// untimed option is an accessibility requirement, not a hint (§10).
    var studyUntimed = false

    private let dependencies: AppDependencies
    private let sessionID: UUID
    /// Seconds played since the last save, flushed on exit and on finish.
    private var unsavedElapsed = 0

    init(dependencies: AppDependencies, sessionID: UUID) {
        self.dependencies = dependencies
        self.sessionID = sessionID
    }

    var board: GameBoard? {
        guard let puzzle, let session else { return nil }
        return GameHost.board(puzzle: puzzle, moves: session.moves)
    }

    var hintPolicy: HintPolicy {
        guard let game, let session else { return .standard }
        return game.hintPolicy(for: session.difficulty)
    }

    /// Only two shapes have a hint to give: the answer chain has authored ones,
    /// and the grid can place a correct value. The others charge for revealing
    /// clues instead, and a hint on top would be paying twice for the same help.
    var canAskForHint: Bool {
        if let maximum = hintPolicy.maximumPerStep, maximum == 0 { return false }
        guard let kind = puzzle?.payload.kind else { return false }
        return kind == .answerChain || kind == .gridAssignment
    }

    func load() async {
        state = .loading
        let play = dependencies.playGame

        guard
            let session = try? await play.session(id: sessionID),
            let game = play.game(id: session.gameID),
            let puzzle = play.puzzle(id: session.puzzleID)
        else {
            state = .failed(String(
                localized: "games.session.missing",
                defaultValue: "I couldn't find that puzzle. It may have been finished on another device — the games list will still have it.",
                comment: "Shown when a game session cannot be loaded"
            ))
            return
        }

        self.session = session
        self.game = game
        self.puzzle = puzzle
        self.gridSolution = await play.gridSolution(for: puzzle)

        if case .studyThenQuiz(let content) = puzzle.payload {
            studySecondsRemaining = content.defaultStudySeconds
        }

        state = .ready
    }

    // MARK: - Moves

    func apply(_ action: GameMove.Action, stepIndex: Int? = nil) async {
        guard let session, let puzzle, let board else { return }
        visibleHint = nil

        let index = stepIndex ?? board.currentStepIndex
        guard let updated = try? await dependencies.playGame.apply(
            action, stepIndex: index, to: session
        ) else { return }
        self.session = updated

        // Recompute the near-miss flag from the rebuilt board, so the nudge
        // reflects what the engine actually decided rather than a guess made
        // here.
        if case .answerChain(let chain) = GameHost.board(
            puzzle: puzzle, moves: updated.moves
        ) {
            lastAnswerWasNearMiss = chain.stops.indices.contains(index)
                && chain.stops[index].lastAnswerWasNearMiss
        }
    }

    /// Asks for a hint and records it, so the cost survives a resume.
    func requestHint() async {
        guard let puzzle, let board else { return }

        switch (puzzle.payload, board) {
        case (.answerChain(let content), .answerChain(let chainBoard)):
            let index = chainBoard.currentStop
            guard content.stops.indices.contains(index) else { return }
            guard let hint = AnswerChainEngine.hint(
                for: content.stops[index],
                alreadyRevealed: chainBoard.stops[index].hintsRevealed,
                policy: hintPolicy
            ) else { return }
            await apply(.hint, stepIndex: index)
            visibleHint = hint

        case (.gridAssignment(let content), .gridAssignment(let gridBoard)):
            guard
                let solution = gridSolution,
                let placement = GridEngine.hintPlacement(
                    puzzle: content, board: gridBoard, solution: solution
                )
            else { return }
            await apply(.hint, stepIndex: 0)
            await apply(
                .assign(
                    item: GridEngine.encode(
                        category: placement.category,
                        value: placement.value,
                        positions: content.positionCount
                    ),
                    slot: placement.position
                ),
                stepIndex: 0
            )

        default:
            return
        }
    }

    // MARK: - Time

    func tick() {
        unsavedElapsed += 1
        if studyUntimed { return }
        if studySecondsRemaining > 0 { studySecondsRemaining -= 1 }
    }

    /// Writes accumulated play time. Called on exit and before finishing.
    func flushElapsed() async {
        guard let session, unsavedElapsed > 0 else { return }
        let seconds = unsavedElapsed
        unsavedElapsed = 0
        self.session = try? await dependencies.playGame.addElapsed(seconds, to: session)
    }

    // MARK: - Ending

    /// Leaves the session for later.
    ///
    /// No-ops once the session has been finished. `onDisappear` also calls this,
    /// and without the guard, closing the result screen would reopen a completed
    /// puzzle as unfinished.
    func setAside() async {
        guard finish == nil else { return }
        await flushElapsed()
        guard let session else { return }
        self.session = try? await dependencies.playGame.setAside(session)
    }

    func finishSession() async {
        await flushElapsed()
        guard let session, let puzzle else { return }
        let outcome = try? await dependencies.playGame.finish(
            session, puzzle: puzzle, gridSolution: gridSolution
        )
        finish = outcome
        // Mirror the stored status locally so nothing downstream — the exit
        // handler in particular — treats a finished session as still open.
        if outcome != nil { self.session?.status = .completed }
    }

    /// Whether the board is far enough along to be worth finishing.
    var canFinish: Bool {
        board?.isComplete ?? false
    }
}

/// A game session (S-19).
///
/// **Placeholder presentation.** The host frame is the spec's — exit and save,
/// rules, hint, progress, and the accessibility alternative — with the board
/// swapped in per interaction shape.
///
/// On §10: no board here is drag-driven. Every one is tap- or field-driven,
/// which is the alternative interaction rather than a substitute for it, and
/// nothing is solvable only by sound or only by colour.
struct GameSessionScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let sessionID: UUID

    @State private var model: GameSessionModel?
    @State private var showsRules = false

    /// Static so the publisher survives the view struct being rebuilt; a fresh
    /// one on every body evaluation would resubscribe on every keystroke.
    private static let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let finish = model?.finish {
                GameResultView(
                    finish: finish,
                    puzzle: model?.puzzle,
                    game: model?.game,
                    onDone: { dismiss() }
                )
            } else {
                sessionBody
            }
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .task {
            if model == nil {
                model = GameSessionModel(dependencies: dependencies, sessionID: sessionID)
            }
            await model?.load()
        }
        .onReceive(Self.ticker) { _ in
            guard model?.finish == nil else { return }
            model?.tick()
        }
        .onDisappear {
            // Leaving is a legitimate way to play. The session is saved as set
            // aside — never discarded, and never described as abandoned.
            Task { [model] in await model?.setAside() }
        }
    }

    @ViewBuilder
    private var sessionBody: some View {
        switch model?.state ?? .idle {
        case .idle, .loading:
            LoadingStateView(message: String(
                localized: "games.session.loading",
                defaultValue: "Setting out the pieces…",
                comment: "Loading a game session"
            ))

        case .failed(let message):
            ErrorStateView(message: message)

        case .ready:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.m) {
                    headerCard
                    if let hint = model?.visibleHint { hintCard(hint) }
                    boardSection
                    footerCard
                }
                .padding(Space.m)
            }
            .navigationTitle(Text(model?.puzzle?.title.text ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsRules = true
                    } label: {
                        Label(
                            String(
                                localized: "games.rules.open",
                                defaultValue: "Rules",
                                comment: "Opens the rules sheet"
                            ),
                            systemImage: "questionmark.circle"
                        )
                    }
                }
            }
            .sheet(isPresented: $showsRules) {
                RulesSheet(game: model?.game)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        SunnieCard {
            if let game = model?.game {
                Text(LocalizedStringKey(game.displayNameKey))
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
            }

            HStack(spacing: Space.xs) {
                if let difficulty = model?.session?.difficulty {
                    StatusChip(
                        text: String(localized: .init(difficulty.localizationKey)),
                        style: .neutral
                    )
                }
                if let hints = model?.session?.hintsUsed, hints > 0 {
                    StatusChip(
                        text: String(
                            format: String(
                                localized: "games.hints.count",
                                defaultValue: "%d hints",
                                comment: "Number of hints taken"
                            ),
                            hints
                        ),
                        style: .neutral
                    )
                }
            }

            if let progress = progressText {
                Text(progress)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                    .accessibilityLabel(Text(progress))
            }
        }
    }

    private var progressText: String? {
        guard let board = model?.board, let puzzle = model?.puzzle else { return nil }
        let total = puzzle.payload.stepCount
        guard total > 0 else { return nil }

        let done: Int
        switch board {
        case .answerChain(let chain): done = min(chain.currentStop, total)
        case .studyThenQuiz(let study):
            done = study.answers.filter { $0 != nil }.count
        case .branchingChoice(let trail): done = trail.visits.count
        case .gridAssignment(let grid):
            done = grid.assignment.filter { row in row.allSatisfy { $0 != nil } }.count
        case .revealAndIdentify, .constrainedSelection:
            return nil
        }

        return String(
            format: String(
                localized: "games.progress",
                defaultValue: "Step %1$d of %2$d",
                comment: "Progress through a puzzle"
            ),
            min(done + 1, total), total
        )
    }

    private func hintCard(_ hint: GameText) -> some View {
        SunnieCard {
            Label {
                Text(hint.text)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textPrimary)
            } icon: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(theme.color.attention)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Board

    @ViewBuilder
    private var boardSection: some View {
        if let model, let puzzle = model.puzzle, let board = model.board {
            switch (puzzle.payload, board) {
            case (.answerChain(let content), .answerChain(let state)):
                AnswerChainBoardView(
                    puzzle: content,
                    board: state,
                    wasNearMiss: model.lastAnswerWasNearMiss,
                    onMove: { action, index in
                        Task { await model.apply(action, stepIndex: index) }
                    }
                )

            case (.revealAndIdentify(let content), .revealAndIdentify(let state)):
                IdentifyBoardView(puzzle: content, board: state, onMove: { action in
                    Task { await model.apply(action, stepIndex: 0) }
                })

            case (.gridAssignment(let content), .gridAssignment(let state)):
                GridBoardView(puzzle: content, board: state, onMove: { action in
                    Task { await model.apply(action, stepIndex: 0) }
                })

            case (.studyThenQuiz(let content), .studyThenQuiz(let state)):
                StudyBoardView(
                    puzzle: content,
                    board: state,
                    secondsRemaining: model.studySecondsRemaining,
                    isUntimed: model.studyUntimed,
                    onUntimed: { model.studyUntimed = true },
                    onMove: { action, index in
                        Task { await model.apply(action, stepIndex: index) }
                    }
                )

            case (.constrainedSelection(let content), .constrainedSelection(let state)):
                SelectionBoardView(puzzle: content, board: state, onMove: { action in
                    Task { await model.apply(action, stepIndex: 0) }
                })

            case (.branchingChoice(let content), .branchingChoice(let state)):
                BranchingBoardView(puzzle: content, board: state, onMove: { action, index in
                    Task { await model.apply(action, stepIndex: index) }
                })

            default:
                // A saved session whose puzzle no longer matches its board shape.
                // Says so plainly rather than showing a blank card.
                ErrorStateView(message: String(
                    localized: "games.session.mismatch",
                    defaultValue: "This saved game doesn't match the puzzle it came from. Starting it fresh will work.",
                    comment: "Shown when a saved session cannot be replayed"
                ))
            }
        }
    }

    // MARK: - Footer

    private var footerCard: some View {
        SunnieCard {
            if model?.canAskForHint == true {
                SunnieSecondaryButton(
                    title: String(
                        localized: "games.hint",
                        defaultValue: "Give me a nudge",
                        comment: "Requests a hint"
                    )
                ) {
                    Task { await model?.requestHint() }
                }
                Text("games.hint.note", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if model?.canFinish == true {
                SunniePrimaryButton(
                    title: String(
                        localized: "games.finish",
                        defaultValue: "See how it went",
                        comment: "Finishes a session and shows the result"
                    )
                ) {
                    Task { await model?.finishSession() }
                }
            }

            SunnieSecondaryButton(
                title: String(
                    localized: "games.setAside",
                    defaultValue: "Save and come back later",
                    comment: "Leaves a session for later"
                )
            ) {
                Task {
                    await model?.setAside()
                    dismiss()
                }
            }
        }
    }
}

/// The rules, always reachable mid-session (§2).
private struct RulesSheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let game: GameDefinition?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let game {
                        Text(LocalizedStringKey(game.rulesKey))
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)

                        Text("games.rules.hints", bundle: .main)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("games.rules.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.done",
                        defaultValue: "Done",
                        comment: "Dismisses a sheet"
                    )) { dismiss() }
                }
            }
        }
    }
}
