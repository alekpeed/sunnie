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
    /// The wellness slice, from its own provider. Today never queries wellness
    /// storage directly (TECHNICAL_ARCHITECTURE.md §6).
    private(set) var wellnessSummary: WellnessSummary?
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

    func onAppear() async {
        greeting = appState.greeting()
        // Subscribed before the first read, not after it. Loading first leaves a
        // window in which something can change the jungle, publish, and be
        // missed entirely — which is exactly what first-launch seeding does
        // (see SampleData). Subscribing first means the worst case is one
        // redundant rebuild rather than a screen that stays wrong.
        await subscribeToChanges()
        await load()
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

        // The wellness slice is best-effort: a failure there must not take the
        // plant card down with it.
        wellnessSummary = try? await dependencies.wellnessSummaryProvider.summary()
        affirmation = dependencies.affirmationService.affirmation(for: .init(
            phase: appState.timeContext.phase,
            isSensitiveMoment: wellnessSummary?.mostRecentCheckIn?.suggestsSensitiveMoment ?? false
        ))

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
            // The set a plant card can be wrong about: care logged elsewhere,
            // a plant added or archived. `plantAdded` covers first-launch
            // seeding as well as the Phase 4 editor, since both mean the same
            // thing to this screen — the jungle is not what Today last read.
            guard event.type == .plantCareLogged
                || event.type == .plantAdded
                || event.type == .plantArchived
                || event.type == .wellnessCheckInRecorded else { return }
            await self?.reload()
        }
    }

    private func reload() async {
        wellnessSummary = try? await dependencies.wellnessSummaryProvider.summary()
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
