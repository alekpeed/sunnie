import Foundation
import Observation
import SunnieShared

/// Feature model for Today.
///
/// Holds screen state, invokes use cases, and maps results to display values. It
/// contains no persistence calls of its own — the plant slice arrives from
/// `PlantSummaryProvider`, which is what keeps Today independent of the Jungle
/// feature (TECHNICAL_ARCHITECTURE.md §4).
@MainActor
@Observable
final class TodayModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(PlantTodaySummary)
        /// Carries copy that is already user-safe: what happened and what is
        /// still fine. Never a raw framework error.
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var greeting: SunnieMessage?
    /// Sunnie's reaction to the most recent completion, shown briefly.
    private(set) var lastReaction: SunnieMessage?

    private let dependencies: AppDependencies
    private let appState: AppState
    private var eventToken: UUID?

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    func onAppear() async {
        greeting = appState.greeting()
        await load()
        await subscribeToChanges()
    }

    func onDisappear() async {
        guard let eventToken else { return }
        await dependencies.eventBus.unsubscribe(eventToken)
        self.eventToken = nil
    }

    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }

        do {
            let summary = try await dependencies.summaryProvider.summary()
            state = .loaded(summary)
        } catch {
            state = .failed(String(
                localized: "today.error.summary",
                defaultValue: "I couldn't put today's list together just now. Everything you've saved is still here.",
                comment: "Shown when the Today summary cannot be built"
            ))
        }
    }

    /// Refreshes when another feature reports something that changes Today.
    ///
    /// Today learns that care was logged without ever importing the Jungle
    /// feature — it hears about a typed event and re-reads its own summary.
    private func subscribeToChanges() async {
        guard eventToken == nil else { return }

        eventToken = await dependencies.eventBus.subscribe { [weak self] event in
            guard event.type == .plantCareLogged else { return }
            await self?.reload()
        }
    }

    private func reload() async {
        do {
            let summary = try await dependencies.summaryProvider.summary()
            state = .loaded(summary)
        } catch {
            // A refresh failing leaves the previous summary on screen, which is
            // better than replacing good data with an error.
            SunnieLog(category: .ui).debug("Today summary refresh failed; keeping the previous list.")
        }
    }

    /// Logs care straight from the Today card.
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
