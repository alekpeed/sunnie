import SwiftUI
import Observation
import SunnieShared

/// Feature model for the meals dashboard (S-15).
@MainActor
@Observable
final class MealsModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var summary: MealDaySummary?
    private(set) var suggestions: [MealSuggestionEngine.Suggestion] = []
    private(set) var useBeforeTrip: [PantryItem] = []
    private(set) var recipeTitles: [UUID: String] = [:]
    private(set) var timers: [KitchenTimer] = []
    private(set) var activeExclusionCount = 0

    var selectedDate: Date = Date()

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() async {
        if state != .loaded { state = .loading }

        do {
            let summary = try await dependencies.manageMeals.daySummary(for: selectedDate)
            self.summary = summary

            let recipes = try await dependencies.manageMeals.recipes()
            recipeTitles = Dictionary(
                uniqueKeysWithValues: recipes.map { ($0.id, $0.title) }
            )

            useBeforeTrip = try await dependencies.manageGrocery.useBeforeTrip()
            activeExclusionCount = await dependencies.manageMeals.activeExclusions().count

            // Elapsed timers become finished on the next look, because the end
            // instant is the truth rather than a countdown held in memory.
            _ = try? await dependencies.managePrep.reconcileTimers()
            timers = (try? await dependencies.managePrep.timers()) ?? []

            suggestions = (try? await dependencies.manageMeals.suggestions(
                for: summary.context
            )) ?? []

            state = .loaded
        } catch {
            state = .failed(String(
                localized: "meals.error.load",
                defaultValue: "I couldn't open your meals just now. Nothing has been lost, and you can try again.",
                comment: "Shown when meals cannot be loaded"
            ))
        }
    }

    func title(for entry: MealPlanEntry) -> String {
        if let recipeID = entry.recipeID, let title = recipeTitles[recipeID] {
            return title
        }
        return entry.customTitle ?? String(
            localized: "meals.slot.empty",
            defaultValue: "Nothing planned",
            comment: "An empty meal slot"
        )
    }

    func plan(_ suggestion: MealSuggestionEngine.Suggestion, slot: MealSlot) async {
        var entry = dependencies.manageMeals.newEntry(
            on: selectedDate,
            slot: slot,
            context: summary?.context ?? .home
        )
        entry.recipeID = suggestion.recipe.id
        _ = try? await dependencies.manageMeals.save(entry)
        await load()
    }
}

/// The meals dashboard (S-15).
///
/// **Placeholder presentation.** The structure is the spec's: today's plan,
/// travel context, prep tasks, packed food, grocery, pantry use-before-trip, and
/// suggestions.
///
/// Nothing here counts calories, tracks macros, or scores what was eaten — those
/// are explicit exclusions (MEALS_AND_PREP.md §13).
struct MealsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var model: MealsModel?
    @State private var editingEntry: MealPlanEntry?
    @State private var newTimerName = ""
    @State private var newTimerMinutes = 10

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "meals.loading",
                            defaultValue: "Looking at your food…",
                            comment: "Loading state for meals"
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
                    todayCard
                    if !(model?.timers.isEmpty ?? true) { timersCard }
                    prepCard
                    useBeforeTripCard
                    suggestionsCard
                    linksCard
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.meals", bundle: .main))
        .refreshable { await model?.load() }
        .toolbar { toolbarContent }
        .task {
            if model == nil { model = MealsModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(item: $editingEntry) { entry in
            MealEntryEditorSheet(entry: entry) {
                Task { await model?.load() }
            }
        }
    }

    // MARK: - Cards

    private var todayCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "meals.section.today",
                    defaultValue: "Today",
                    comment: "Today's meals section"
                ),
                subtitle: model.map {
                    String(localized: .init($0.summary?.context.localizationKey ?? "meals.context.home"))
                }
            )

            let planned = model?.summary?.plannedEntries ?? []
            if planned.isEmpty {
                Text("meals.today.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(planned) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HStack(spacing: Space.s) {
                            Text(LocalizedStringKey(entry.slot.localizationKey))
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                                .frame(width: 72, alignment: .leading)

                            Text(model?.title(for: entry) ?? "")
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)

                            Spacer()

                            if entry.isPacked {
                                StatusChip(
                                    text: String(
                                        localized: "meals.packed",
                                        defaultValue: "Packed",
                                        comment: "A meal that travels"
                                    ),
                                    style: .neutral
                                )
                            }
                            if entry.isPrepared {
                                StatusChip(
                                    text: String(
                                        localized: "meals.prepared",
                                        defaultValue: "Ready",
                                        comment: "A meal already prepared"
                                    ),
                                    style: .done
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }

            SunnieSecondaryButton(
                title: String(
                    localized: "meals.plan",
                    defaultValue: "Plan a meal",
                    comment: "Adds a meal to the plan"
                ),
                systemImage: "plus",
                action: {
                    guard let model else { return }
                    editingEntry = dependencies.manageMeals.newEntry(
                        on: model.selectedDate,
                        slot: .dinner,
                        context: model.summary?.context ?? .home
                    )
                }
            )
        }
    }

    private var timersCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "meals.section.timers",
                    defaultValue: "Timers",
                    comment: "Kitchen timers section"
                ),
                subtitle: nil
            )

            ForEach(model?.timers ?? []) { timer in
                HStack {
                    Text(timer.name)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    if timer.isFinished {
                        StatusChip(
                            text: String(
                                localized: "meals.timer.finished",
                                defaultValue: "Done",
                                comment: "A finished timer"
                            ),
                            style: .done
                        )
                    } else {
                        // A live countdown from the stored end instant, so it is
                        // right even after the app was closed.
                        Text(timer.endsAt, style: .timer)
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textSecondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button {
                        Task {
                            try? await dependencies.managePrep.cancelTimer(timer)
                            await model?.load()
                        }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("meals.timer.stop", bundle: .main))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var prepCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "meals.section.prep",
                    defaultValue: "To get ready",
                    comment: "Prep tasks section"
                ),
                subtitle: nil
            )

            let tasks = model?.summary?.prepTasksDue ?? []
            if tasks.isEmpty {
                Text("meals.prep.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(tasks) { task in
                    Button {
                        Task {
                            try? await dependencies.managePrep.setDone(true, task: task)
                            await model?.load()
                        }
                    } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: "circle")
                                .foregroundStyle(theme.color.textSecondary)
                            Text(task.title)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Pantry items marked to eat before going away.
    ///
    /// Ordered by whatever date the user wrote down. That is an ordering and
    /// nothing more — the app is not saying anything has gone off
    /// (MEALS_AND_PREP.md §7).
    @ViewBuilder
    private var useBeforeTripCard: some View {
        let items = model?.useBeforeTrip ?? []
        if !items.isEmpty {
            SunnieCard {
                SectionHeader(
                    title: String(
                        localized: "meals.section.useFirst",
                        defaultValue: "Use before you go",
                        comment: "Pantry use-before-trip section"
                    ),
                    subtitle: nil
                )

                ForEach(items.prefix(6)) { item in
                    HStack {
                        Text(item.name)
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                        Spacer()
                        if let date = item.bestBefore {
                            Text(date, format: .dateTime.day().month())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Text("meals.useFirst.footer", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    /// Suggestions, each with the reasons it was offered.
    ///
    /// Deterministic and rule-based — no generative AI in the initial release
    /// (MEALS_AND_PREP.md §10). Saying *why* is what keeps a suggestion an offer
    /// rather than an oracle.
    @ViewBuilder
    private var suggestionsCard: some View {
        let suggestions = model?.suggestions ?? []
        if !suggestions.isEmpty {
            SunnieCard {
                SectionHeader(
                    title: String(
                        localized: "meals.section.ideas",
                        defaultValue: "Could be nice",
                        comment: "Meal suggestions section"
                    ),
                    subtitle: nil
                )

                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text(suggestion.recipe.title)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Button {
                                Task { await model?.plan(suggestion, slot: .dinner) }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(theme.color.accentWarm)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("meals.plan", bundle: .main))
                        }

                        if let reason = suggestion.reasons.first {
                            Text(LocalizedStringKey(reason.localizationKey))
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var linksCard: some View {
        SunnieCard {
            NavigationLink(value: AppRoute.grocery) {
                HStack {
                    Label(
                        String(
                            localized: "meals.grocery",
                            defaultValue: "Shopping list",
                            comment: "Opens the grocery list"
                        ),
                        systemImage: "cart"
                    )
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    let outstanding = model?.summary?.groceryOutstanding ?? 0
                    if outstanding > 0 {
                        Text("\(outstanding)")
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
            }

            NavigationLink(value: AppRoute.pantry) {
                Label(
                    String(
                        localized: "meals.pantry",
                        defaultValue: "What's in",
                        comment: "Opens the pantry"
                    ),
                    systemImage: "cabinet"
                )
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
            }

            NavigationLink(value: AppRoute.recipes) {
                Label(
                    String(
                        localized: "meals.recipes",
                        defaultValue: "Recipes",
                        comment: "Opens the recipe list"
                    ),
                    systemImage: "book"
                )
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(selection: contextBinding) {
                    ForEach(DayContext.allCases, id: \.self) { context in
                        Text(LocalizedStringKey(context.localizationKey)).tag(context)
                    }
                } label: {
                    Text("meals.dayContext", bundle: .main)
                }

                Divider()

                Button {
                    Task { await startTimer(minutes: 10) }
                } label: {
                    Label(
                        String(
                            localized: "meals.timer.ten",
                            defaultValue: "10-minute timer",
                            comment: "Starts a ten-minute timer"
                        ),
                        systemImage: "timer"
                    )
                }

                Button {
                    Task { await startTimer(minutes: 30) }
                } label: {
                    Label(
                        String(
                            localized: "meals.timer.thirty",
                            defaultValue: "30-minute timer",
                            comment: "Starts a thirty-minute timer"
                        ),
                        systemImage: "timer"
                    )
                }
            } label: {
                Label(
                    String(
                        localized: "collection.options",
                        defaultValue: "Options",
                        comment: "Options menu"
                    ),
                    systemImage: "ellipsis.circle"
                )
            }
        }
    }

    private var contextBinding: Binding<DayContext> {
        Binding(
            get: { model?.summary?.context ?? .home },
            set: { newValue in
                guard let model else { return }
                Task {
                    try? await dependencies.manageMeals.setContext(
                        newValue, forDay: model.selectedDate
                    )
                    await model.load()
                }
            }
        )
    }

    private func startTimer(minutes: Int) async {
        _ = try? await dependencies.managePrep.startTimer(
            name: String(
                localized: "meals.timer.untitled",
                defaultValue: "Timer",
                comment: "A timer with no name"
            ),
            seconds: minutes * 60
        )
        await model?.load()
    }
}
