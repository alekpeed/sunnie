import SwiftUI
import SwiftData
import SunnieShared

@main
struct SunnieDaysApp: App {

    @State private var dependencies: AppDependencies
    @State private var appState: AppState
    @State private var router = AppRouter()
    @State private var backgroundMaintenance: BackgroundMaintenanceCoordinator

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let storage = Self.makeStorage()
        let dependencies = AppDependencies(
            modelContainer: storage.container,
            isEphemeralStorage: storage.isEphemeral
        )
        _dependencies = State(initialValue: dependencies)
        let appState = AppState(dependencies: dependencies)
        _appState = State(initialValue: appState)
        _backgroundMaintenance = State(initialValue: BackgroundMaintenanceCoordinator(
            dependencies: dependencies,
            appState: appState
        ))
    }

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
                    backgroundMaintenance.register()
                    dependencies.configureNotifications { route in
                        router.handle(route)
                    }
                    await appState.load()
                    await SampleData.seedIfNeeded(dependencies: dependencies)
                    await dependencies.processPendingWatchActions()
                    await dependencies.performLaunchHousekeeping()
                    // Seeding and queued Watch actions can change the world after
                    // AppState's initial load, so publish one authoritative
                    // context only after launch housekeeping has settled.
                    await appState.refreshCurrentContext()
                    await dependencies.favorites.rebuild()
                    await dependencies.unifiedSearch.rebuild()
                    backgroundMaintenance.schedule()
                    if let route = IntentRouteBox.take() { router.handle(route) }
                }
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            appState.refreshTimeContext()
            if let route = IntentRouteBox.take() { router.handle(route) }
            Task {
                await dependencies.processPendingWatchActions()
                await appState.refreshCurrentContext()
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
        case .search: UnifiedSearchScreen()
        case .checkIn: WellnessScreen()
        case .meals: MealsScreen()
        case .mealPlanner: MealsScreen()
        case .recipes: RecipeListScreen()
        case .grocery: GroceryScreen()
        case .pantry: PantryScreen()
        case .games: GamesHomeScreen()
        case .game(let id):
            if let sessionID = UUID(uuidString: id) {
                GameSessionScreen(sessionID: sessionID)
            } else {
                GamesHomeScreen()
            }
        case .journal: JournalScreen()
        case .collections:
            SunnieWorldCollectionContainer {
                CollectionsScreen()
            }
        case .sunnieHome:
            SunnieHomeAssistantContainer {
                SunnieHomeScreen()
            }
        case .trip(let id): TripOverviewScreen(tripID: id)
        case .packing(let id): PackingScreen(tripID: id)
        case .tripChecklist(let id, let phase):
            TripChecklistScreen(
                tripID: id,
                phase: ChecklistKind.Phase(rawValue: phase) ?? .leaving
            )
        case .itinerary(let id): ItineraryScreen(tripID: id)
        case .plantCoverage(let id): PlantCoverageScreen(tripID: id)
        case .worldMap: WorldMapScreen()
        case .today, .jungle, .travel, .wellness:
            root(for: route.tab)
        }
    }
}
