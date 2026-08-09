import Foundation
import WidgetKit
import SunnieShared

/// Builds the widget snapshot and leaves it where the extension can find it
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §8).
///
/// This is the only place that decides what a widget may show. Flight Mode does
/// not add a second widget data path: the existing trip panel simply prefers the
/// same explicitly marked work-trip context as the rest of Sunnie Days.
@MainActor
struct WidgetSnapshotPublisher {

    private let dependencies: AppDependencies
    private var log: SunnieLog { SunnieLog(category: .integrations) }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    static let minimumInterval: TimeInterval = 60
    private static var lastPublishedAt: Date?

    func publish(force: Bool = false) async {
        let now = dependencies.clock.now
        if !force, let last = Self.lastPublishedAt,
           now.timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        Self.lastPublishedAt = now

        let store = WidgetSnapshotStore()
        guard store.isAvailable else { return }

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

        let selected: (Trip, TripStatus)?
        if let flight = FlightModeSelector.select(from: trips, now: now, calendar: calendar) {
            selected = (
                flight.trip,
                TripStatusCalculator.status(for: flight.trip, now: now, calendar: calendar)
            )
        } else {
            selected = trips
                .map { ($0, TripStatusCalculator.status(for: $0, now: now, calendar: calendar)) }
                .filter { $0.1.isCurrent || $0.1 == .upcoming }
                .sorted { left, right in
                    if left.1.isCurrent != right.1.isCurrent { return left.1.isCurrent }
                    return (left.0.startsAt ?? .distantFuture) < (right.0.startsAt ?? .distantFuture)
                }
                .first
        }

        guard let (trip, status) = selected else { return nil }
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

    private func affirmation(phase: TimePhase) -> String? {
        dependencies.affirmationService.affirmation(
            for: AffirmationService.Request(phase: phase)
        )?.text
    }
}
