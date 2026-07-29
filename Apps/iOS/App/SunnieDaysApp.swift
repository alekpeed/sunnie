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
                    await appState.load()
                    await SampleData.seedIfNeeded(dependencies: dependencies)
                    await dependencies.processPendingWatchActions()
                    await dependencies.performLaunchHousekeeping()
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
            Task { await dependencies.processPendingWatchActions() }
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
        case .travel: PlaceholderFeatureScreen(feature: .travel)
        case .wellness: WellnessScreen()
        case .more: MoreScreen()
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .jungleDue: JungleScreen(showsDueOnly: true)
        case .plant(let id): PlantDetailScreen(plantID: id)
        case .themes: ThemesScreen()
        case .settings: SettingsScreen()
        case .checkIn: WellnessScreen()
        case .meals: PlaceholderFeatureScreen(feature: .meals)
        case .games, .game: PlaceholderFeatureScreen(feature: .games)
        case .journal: JournalScreen()
        case .collections: PlaceholderFeatureScreen(feature: .collections)
        case .sunnieHome: PlaceholderFeatureScreen(feature: .sunnieHome)
        case .trip: PlaceholderFeatureScreen(feature: .travel)
        case .today, .jungle, .travel, .wellness:
            // Tab roots are never pushed; `AppRouter.handle` selects the tab
            // instead. Reaching here would be a routing bug, so show the root
            // rather than an empty screen.
            root(for: route.tab)
        }
    }
}
