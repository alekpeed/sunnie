import SwiftUI
import SwiftData
import SunnieShared

@main
struct SunnieDaysApp: App {

    @State private var dependencies: AppDependencies
    @State private var appState: AppState
    @State private var router = AppRouter()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let storage = Self.makeStorage()
        let dependencies = AppDependencies(
            modelContainer: storage.container,
            isEphemeralStorage: storage.isEphemeral
        )
        _dependencies = State(initialValue: dependencies)
        _appState = State(initialValue: AppState(dependencies: dependencies))
    }

    /// Chooses the store for this launch.
    ///
    /// UI tests run against a fresh in-memory store so a run never depends on
    /// what the previous one left behind. `isEphemeral` stays false in that case:
    /// it is deliberate, not a storage failure, so the warning banner must not
    /// appear. Otherwise storage falls back to memory rather than crashing if the
    /// on-disk store cannot be opened, and the UI surfaces that.
    private static func makeStorage() -> (container: ModelContainer, isEphemeral: Bool) {
        let isUITesting = ProcessInfo.processInfo
            .arguments.contains("-SunnieUITesting")

        if isUITesting,
           let testContainer = try? ModelContainerFactory.make(storage: .inMemory) {
            return (testContainer, false)
        }
        return ModelContainerFactory.makeWithFallback()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .environment(router)
                .environment(dependencies)
                .environment(\.sunnieTheme, appState.theme)
                .modelContainer(dependencies.modelContainer)
                .task {
                    dependencies.configureNotifications { route in
                        router.handle(route)
                    }
                    await appState.load()
                    await SampleData.seedIfNeeded(dependencies: dependencies)
                    await dependencies.processPendingWatchActions()
                    await dependencies.performLaunchHousekeeping()
                    // A shortcut that launched the app left its destination
                    // behind; the app navigates rather than the intent, because
                    // they are separate processes.
                    if let route = IntentRouteBox.take() { router.handle(route) }
                }
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Returning to the foreground may cross a phase boundary or bring
            // actions the Watch queued while the app was away.
            appState.refreshTimeContext()
            if let route = IntentRouteBox.take() { router.handle(route) }
            Task {
                await dependencies.processPendingWatchActions()
                await dependencies.publishWatchContext()
                await dependencies.publishWidgetSnapshot()
            }
        }
    }
}

/// Root shell: five tabs, each with its own preserved navigation stack.
struct RootTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: router.tabSelection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: router.path(for: tab)) {
                    root(for: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                .tabItem {
                    Label(
                        LocalizedStringKey(tab.titleKey),
                        systemImage: tab.symbolName
                    )
                }
                .tag(tab)
            }
        }
        .tint(appState.theme.color.accentPlant)
        .background(appState.theme.color.canvas)
        .environment(\.sunnieTheme, appState.theme)
        .onAppear {
            appState.systemReduceMotion = reduceMotion
        }
        .onChange(of: reduceMotion) { _, newValue in
            appState.systemReduceMotion = newValue
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayScreen()
        case .jungle: JungleScreen()
        case .travel: TravelScreen()
        case .wellness: WellnessScreen()
        case .more: MoreScreen()
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .jungleDue: JungleScreen(showsDueOnly: true)
        case .collection: CollectionScreen()
        case .plant(let id): PlantDetailScreen(plantID: id)
        case .plantHealth(let id): PlantHealthScreen(plantID: id)
        case .plantGrowth(let id): GrowthTimelineScreen(plantID: id)
        case .themes: ThemesScreen()
        case .settings: SettingsScreen()
        case .checkIn: WellnessScreen()
        case .meals: MealsScreen()
        case .mealPlanner: MealsScreen()
        case .recipes: RecipeListScreen()
        case .grocery: GroceryScreen()
        case .pantry: PantryScreen()
        case .games: GamesHomeScreen()
        case .game(let id):
            // The identifier comes from a route this app built, so a value that
            // does not parse means a stale saved navigation path rather than user
            // input. Falling back to the games home beats a blank screen.
            if let sessionID = UUID(uuidString: id) {
                GameSessionScreen(sessionID: sessionID)
            } else {
                GamesHomeScreen()
            }
        case .journal: JournalScreen()
        case .collections: CollectionsScreen()
        case .sunnieHome: SunnieHomeScreen()
        case .trip(let id): TripOverviewScreen(tripID: id)
        case .packing(let id): PackingScreen(tripID: id)
        case .tripChecklist(let id, let phase):
            // An unrecognised phase falls back to the leaving checklist rather
            // than failing: the route is only ever built from the enum, so this
            // is a guard against a stale saved navigation path, not user input.
            TripChecklistScreen(
                tripID: id,
                phase: ChecklistKind.Phase(rawValue: phase) ?? .leaving
            )
        case .itinerary(let id): ItineraryScreen(tripID: id)
        case .plantCoverage(let id): PlantCoverageScreen(tripID: id)
        case .worldMap: WorldMapScreen()
        case .today, .jungle, .travel, .wellness:
            // Tab roots are never pushed; `AppRouter.handle` selects the tab
            // instead. Reaching here would be a routing bug, so show the root
            // rather than an empty screen.
            root(for: route.tab)
        }
    }
}
