import Foundation
import WidgetKit
import SunnieShared

/// Builds the widget snapshot and leaves it where the extension can find it
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §8).
///
/// This is the only place that decides what a widget may show, which is what
/// keeps the privacy rule in §8 in one reviewable spot rather than spread across
/// six timeline providers.
///
/// What is deliberately *not* in a snapshot: journal text, check-in values,
/// health readings, meal contents, plant notes, and anything a photograph. A
/// widget lives on a lock screen someone else can see over your shoulder.
@MainActor
struct WidgetSnapshotPublisher {

    private let dependencies: AppDependencies
    private var log: SunnieLog { SunnieLog(category: .integrations) }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// How often a refresh is worth doing.
    ///
    /// §10 asks not to waste battery on frequent refreshes. The app publishes on
    /// meaningful changes rather than on a timer, and this floor stops a burst of
    /// changes — logging five plants in a row — becoming five writes and five
    /// timeline reloads.
    static let minimumInterval: TimeInterval = 60

    private static var lastPublishedAt: Date?

    /// Builds and writes a snapshot, then asks WidgetKit to reload.
    ///
    /// Failures are swallowed: there is nobody to tell, and a stale widget is a
    /// small thing next to an error on a screen the user did not ask for.
    func publish(force: Bool = false) async {
        let now = dependencies.clock.now
        if !force, let last = Self.lastPublishedAt,
           now.timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        Self.lastPublishedAt = now

        let store = WidgetSnapshotStore()
        guard store.isAvailable else {
            // No App Group configured, which is the default (ADR-012). The
            // widget shows its "open Sunnie Days" state, which is honest.
            return
        }

        let snapshot = await build(at: now)
        guard store.write(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func build(at now: Date) async -> WidgetSnapshot {
        let preferences = (try? await dependencies.preferencesRepository.preferences())
            ?? .default
        let timeContext = dependencies.timeEngine.resolve(
            at: now,
            preferences: preferences,
            timeZone: dependencies.clock.timeZone,
            reduceMotion: false
        )

        let plants = await plantsPanel()
        let trip = await tripPanel(now: now)
        let puzzle = await puzzlePanel()

        return WidgetSnapshot(
            generatedAt: now,
            today: WidgetSnapshot.TodayPanel(
                dayCyclePresentationKey: timeContext.presentation.rawValue,
                headlineKey: plants.dueCount > 0 ? "widget.headline.plants" : nil,
                headlineValue: plants.dueCount > 0 ? String(plants.dueCount) : nil
            ),
            plants: plants,
            trip: trip,
            affirmation: affirmation(phase: timeContext.phase),
            dailyPuzzle: puzzle
        )
    }

    // MARK: - Panels

    private func plantsPanel() async -> WidgetSnapshot.PlantsPanel {
        guard let summary = try? await dependencies.summaryProvider.summary() else {
            return WidgetSnapshot.PlantsPanel(dueCount: 0, overdueCount: 0, nextTaskName: nil)
        }
        let tasks = summary.actionableTasks
        return WidgetSnapshot.PlantsPanel(
            dueCount: tasks.count,
            overdueCount: summary.waiting.count,
            nextTaskName: tasks.first?.plantDisplayName
        )
    }

    private func tripPanel(now: Date) async -> WidgetSnapshot.TripPanel? {
        let trips = (try? await dependencies.travelRepository.trips(includingArchived: false)) ?? []
        let calendar = dependencies.clock.calendar

        // The trip a countdown is about: the current one if there is one, else
        // the next one to start. A trip three months out is still worth a
        // countdown; a trip that ended last week is not.
        let candidates = trips
            .map { ($0, TripStatusCalculator.status(for: $0, now: now, calendar: calendar)) }
            .filter { $0.1.isCurrent || $0.1 == .upcoming }
            .sorted { left, right in
                if left.1.isCurrent != right.1.isCurrent { return left.1.isCurrent }
                return (left.0.startsAt ?? .distantFuture) < (right.0.startsAt ?? .distantFuture)
            }

        guard let (trip, status) = candidates.first else { return nil }
        return WidgetSnapshot.TripPanel(
            title: trip.title,
            startsAt: trip.startsAt,
            destinationTimeZoneID: trip.destinationTimeZoneIDs.first,
            statusKey: status.localizationKey
        )
    }

    private func puzzlePanel() async -> WidgetSnapshot.PuzzlePanel? {
        guard let daily = await dependencies.playGame.daily() else { return nil }
        return WidgetSnapshot.PuzzlePanel(
            gameNameKey: daily.game.displayNameKey,
            puzzleTitle: daily.puzzle.title.text,
            isFinishedToday: daily.session?.status == .completed
        )
    }

    /// One affirmation, resolved to text here rather than on the widget.
    ///
    /// The extension has no content pack and no nickname rules, and giving it
    /// either would be a second place those rules could drift.
    private func affirmation(phase: TimePhase) -> String? {
        dependencies.affirmationService.affirmation(
            for: AffirmationService.Request(phase: phase)
        )?.text
    }
}
