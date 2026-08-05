import SwiftUI
import Observation
import SunnieShared

/// Feature model for the games home (S-18).
@MainActor
@Observable
final class GamesModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct DailyEntry: Identifiable {
        let game: GameDefinition
        let puzzle: PuzzleDefinition
        let session: GameSessionState?
        /// True once the day's puzzle has been finished. Shown as a quiet mark,
        /// never as a streak or a count of days in a row.
        let isFinished: Bool

        var id: ContentID { puzzle.id }
    }

    struct ResumeEntry: Identifiable {
        let session: GameSessionState
        let game: GameDefinition?
        let puzzle: PuzzleDefinition?

        var id: UUID { session.id }
    }

    private(set) var state: LoadState = .idle
    private(set) var daily: DailyEntry?
    private(set) var resumable: [ResumeEntry] = []
    private(set) var recent: [GameResult] = []
    private(set) var games: [GameDefinition] = []
    /// Games the player has never finished a puzzle in, surfaced first so the
    /// list is an invitation rather than a scoreboard.
    private(set) var unplayedGameIDs: Set<ContentID> = []

    var selectedCategory: GameCategory?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var filteredGames: [GameDefinition] {
        guard let selectedCategory else { return games }
        return games.filter { $0.categories.contains(selectedCategory) }
    }

    /// Categories with at least one game, so a filter never leads to an empty
    /// list.
    var availableCategories: [GameCategory] {
        GameCategory.allCases.filter { category in
            games.contains { $0.categories.contains(category) }
        }
    }

    func load() async {
        if state != .loaded { state = .loading }
        let play = dependencies.playGame
        games = play.games

        do {
            if let choice = await play.daily() {
                daily = DailyEntry(
                    game: choice.game,
                    puzzle: choice.puzzle,
                    session: choice.session,
                    isFinished: choice.session?.status == .completed
                )
            } else {
                daily = nil
            }

            resumable = try await play.resumableSessions().map { session in
                ResumeEntry(
                    session: session,
                    game: play.game(id: session.gameID),
                    puzzle: play.puzzle(id: session.puzzleID)
                )
            }
            recent = try await play.recentResults()

            var unplayed: Set<ContentID> = []
            for game in games {
                let results = try await play.results(for: game.id, limit: 1)
                if results.isEmpty { unplayed.insert(game.id) }
            }
            unplayedGameIDs = unplayed

            state = .loaded
        } catch {
            state = .failed(String(
                localized: "games.error.load",
                defaultValue: "I couldn't open the games just now. Nothing has been lost, and you can try again.",
                comment: "Shown when the games list cannot be loaded"
            ))
        }
    }

    /// Opens the day's puzzle, resuming if it was already started.
    func openDaily() async -> UUID? {
        (try? await dependencies.playGame.startDaily())??.id
    }

    func start(_ game: GameDefinition, difficulty: GameDifficulty) async -> UUID? {
        (try? await dependencies.playGame.start(
            gameID: game.id, difficulty: difficulty
        ))??.id
    }

    func title(for result: GameResult) -> String {
        dependencies.playGame.puzzle(id: result.puzzleID)?.title.text
            ?? dependencies.playGame.game(id: result.gameID)
                .map { String(localized: .init($0.displayNameKey)) }
            ?? ""
    }
}

/// The games home (S-18).
///
/// **Placeholder presentation.** The structure is the spec's: the day's puzzle,
/// anything to continue, categories, the games themselves, and recent results.
///
/// What is not placeholder is what the screen refuses to show. There is no
/// streak, no daily-target ring, no "you haven't played in 4 days", and no
/// leaderboard. Progress appears only as things that happened
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §7).
struct GamesHomeScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var model: GamesModel?
    @State private var pendingGame: GameDefinition?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "games.loading",
                            defaultValue: "Getting the puzzles out…",
                            comment: "Loading state for games"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(
                        message: message,
                        retryTitle: String(
                            localized: "common.tryAgain",
                            defaultValue: "Try again",
                            comment: "Retry"
                        ),
                        retry: { Task { await model?.load() } }
                    )

                case .loaded:
                    dailyCard
                    if !(model?.resumable.isEmpty ?? true) { continueCard }
                    categoryRow
                    gamesList
                    if !(model?.recent.isEmpty ?? true) { recentCard }
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.games", bundle: .main))
        .task {
            if model == nil { model = GamesModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(item: $pendingGame) { game in
            DifficultySheet(game: game) { difficulty in
                pendingGame = nil
                Task {
                    if let id = await model?.start(game, difficulty: difficulty) {
                        router.push(.game(id.uuidString))
                    }
                }
            }
        }
    }

    // MARK: - Daily

    @ViewBuilder
    private var dailyCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "games.daily.title",
                    defaultValue: "Today's puzzle",
                    comment: "Daily puzzle section"
                ),
                subtitle: String(
                    localized: "games.daily.subtitle",
                    defaultValue: "One a day, and no hurry about it.",
                    comment: "Daily puzzle subtitle"
                )
            )

            if let daily = model?.daily {
                Text(LocalizedStringKey(daily.game.displayNameKey))
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Text(daily.puzzle.title.text)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)

                HStack(spacing: Space.xs) {
                    StatusChip(
                        text: String(localized: .init(daily.puzzle.difficulty.localizationKey)),
                        style: .neutral
                    )
                    if daily.isFinished {
                        StatusChip(
                            text: String(
                                localized: "games.daily.done",
                                defaultValue: "Played today",
                                comment: "The daily puzzle has been finished"
                            ),
                            style: .done
                        )
                    }
                }

                SunniePrimaryButton(
                    title: daily.isFinished
                        ? String(
                            localized: "games.daily.playAgain",
                            defaultValue: "Play it again",
                            comment: "Replay the daily puzzle"
                        )
                        : (daily.session == nil
                            ? String(
                                localized: "games.daily.start",
                                defaultValue: "Start today's puzzle",
                                comment: "Start the daily puzzle"
                            )
                            : String(
                                localized: "games.daily.continue",
                                defaultValue: "Pick it back up",
                                comment: "Resume the daily puzzle"
                            ))
                ) {
                    Task {
                        if let id = await model?.openDaily() {
                            router.push(.game(id.uuidString))
                        }
                    }
                }
            } else {
                Text("games.daily.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    // MARK: - Continue

    private var continueCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "games.continue.title",
                    defaultValue: "Where you left off",
                    comment: "Resumable sessions section"
                )
            )

            ForEach(model?.resumable ?? []) { entry in
                Button {
                    router.push(.game(entry.session.id.uuidString))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(entry.puzzle?.title.text ?? "")
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            if let game = entry.game {
                                Text(LocalizedStringKey(game.displayNameKey))
                                    .font(SunnieFont.caption)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.color.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint(Text("games.continue.hint", bundle: .main))
            }
        }
    }

    // MARK: - Categories

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                categoryChip(nil)
                ForEach(model?.availableCategories ?? [], id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, Space.xxs)
        }
    }

    private func categoryChip(_ category: GameCategory?) -> some View {
        let isSelected = model?.selectedCategory == category
        let title = category.map { String(localized: .init("game.category.\($0.rawValue)")) }
            ?? String(
                localized: "games.category.all",
                defaultValue: "All",
                comment: "No category filter"
            )

        return Button {
            model?.selectedCategory = isSelected ? nil : category
        } label: {
            Text(title)
                .font(SunnieFont.caption)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xxs)
                .background(
                    Capsule().fill(
                        isSelected ? theme.color.accentPlant.opacity(0.2) : theme.color.surface
                    )
                )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Games

    private var gamesList: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "games.all.title",
                    defaultValue: "Games",
                    comment: "Games list section"
                )
            )

            ForEach(model?.filteredGames ?? []) { game in
                Button {
                    pendingGame = game
                } label: {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text(LocalizedStringKey(game.displayNameKey))
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            if model?.unplayedGameIDs.contains(game.id) == true {
                                StatusChip(
                                    text: String(
                                        localized: "games.new",
                                        defaultValue: "Not tried yet",
                                        comment: "A game with no results"
                                    ),
                                    style: .neutral
                                )
                            }
                            Spacer()
                        }
                        Text(LocalizedStringKey(game.summaryKey))
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }

    // MARK: - Recent

    private var recentCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "games.recent.title",
                    defaultValue: "Recently played",
                    comment: "Recent results section"
                )
            )

            ForEach(model?.recent ?? []) { result in
                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(model?.title(for: result) ?? "")
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                        Text(LocalizedStringKey(result.completion.localizationKey))
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    Spacer()
                    Text(result.finishedAt, format: .dateTime.day().month(.abbreviated))
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Difficulty choice, presented when a game is opened.
///
/// Every level a game declares has puzzles behind it — the content validator
/// refuses a pack that offers a difficulty with nothing at it, so this sheet can
/// never lead to an empty screen.
private struct DifficultySheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let game: GameDefinition
    let onChoose: (GameDifficulty) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LocalizedStringKey(game.rulesKey))
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                } header: {
                    Text("games.rules.title", bundle: .main)
                }

                Section {
                    ForEach(game.difficulties.sorted { $0.rank < $1.rank }, id: \.self) { level in
                        Button {
                            onChoose(level)
                        } label: {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(LocalizedStringKey(level.localizationKey))
                                    .foregroundStyle(theme.color.textPrimary)
                                if level.isTutorial {
                                    Text("games.difficulty.tutorial.note", bundle: .main)
                                        .font(SunnieFont.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("games.difficulty.title", bundle: .main)
                }
            }
            .navigationTitle(Text(LocalizedStringKey(game.displayNameKey)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel"
                    )) { dismiss() }
                }
            }
        }
    }
}
