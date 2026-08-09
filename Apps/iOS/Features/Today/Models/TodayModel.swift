import Foundation
import Observation
import SunnieShared

/// Feature model for Today.
///
/// Today no longer assembles plant, wellness, progression and travel state on its
/// own. It consumes the same `CurrentContext` as the rest of the Sunnie OS layer.
/// Mutations still go through the feature use cases that own them.
@MainActor
@Observable
final class TodayModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var greeting: SunnieMessage?
    private(set) var affirmation: AffirmationDefinition?
    /// Sunnie's reaction to the most recent completion, shown briefly.
    private(set) var lastReaction: SunnieMessage?

    private let dependencies: AppDependencies
    private let appState: AppState
    private var eventToken: UUID?

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    var currentContext: CurrentContext { appState.currentContext }
    var plantSummary: PlantTodaySummary? { currentContext.plantSummary }
    var wellnessSummary: WellnessSummary? { currentContext.wellnessSummary }
    var progressionProfile: ProgressionProfile { currentContext.progression }
    var flightMode: FlightContext? { currentContext.flightMode }
    var contextItems: [ContextItem] { currentContext.items }

    func onAppear() async {
        greeting = appState.greeting()
        // Subscribe before the first rebuild so a change during loading causes a
        // second rebuild rather than leaving a stale contextual surface.
        await subscribeToChanges()
        await load()
    }

    func onDisappear() async {
        guard let eventToken else { return }
        await dependencies.eventBus.unsubscribe(eventToken)
        self.eventToken = nil
    }

    func load() async {
        if state != .loaded { state = .loading }
        await appState.refreshCurrentContext()
        refreshPresentationFromContext()
        state = .loaded
    }

    private func refreshPresentationFromContext() {
        affirmation = dependencies.affirmationService.affirmation(for: .init(
            phase: appState.timeContext.phase,
            isSensitiveMoment: wellnessSummary?.mostRecentCheckIn?.suggestsSensitiveMoment ?? false
        ))
    }

    /// Rebuild Today for any event that can change shared context.
    ///
    /// Rebuilding from the context engine is deliberately cheap conceptually:
    /// consumers no longer need their own event-to-feature dependency map.
    private func subscribeToChanges() async {
        guard eventToken == nil else { return }

        eventToken = await dependencies.eventBus.subscribe { [weak self] _ in
            await self?.reload()
        }
    }

    private func reload() async {
        await appState.refreshCurrentContext()
        refreshPresentationFromContext()
        state = .loaded
    }

    /// Logs care straight from the Today card through the Jungle use case.
    func completeCare(task: DueCareTask) async {
        do {
            let result = try await dependencies.logPlantCare(
                plantID: task.plantID,
                careType: task.careType,
                scheduleID: task.scheduleID
            )
            lastReaction = result.message
            if result.wasNewlyRecorded {
                dependencies.haptics.success()
            }
            await load()
        } catch {
            state = .failed(String(
                localized: "today.error.logCare",
                defaultValue: "That didn't save just now. Nothing else has changed, and you can try again.",
                comment: "Shown when logging care from Today fails"
            ))
        }
    }

    func dismissReaction() {
        lastReaction = nil
    }
}
