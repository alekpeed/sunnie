import Foundation
import SunnieShared

/// Assembles the snapshot the Watch renders
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §6, §7).
///
/// One place builds the context, so the five Watch destinations cannot disagree
/// about what "now" is, and so the resolution work happens on the phone exactly
/// once. Flight Mode uses the same conservative selector as Today: an explicitly
/// marked work trip in its active/preparation window leads the Watch travel panel.
@MainActor
struct WatchContextPublisher {

    private let dependencies: AppDependencies
    private var log: SunnieLog { SunnieLog(category: .integrations) }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    /// Builds and sends. Failures are logged and dropped — the Watch being one
    /// refresh behind is not worth telling anyone about, and the next publish
    /// carries the change anyway.
    func publish() async {
        guard let context = await build() else { return }
        await dependencies.watchSync.updateApplicationContext(context)
    }

    func build() async -> WatchApplicationContext? {
        let now = dependencies.clock.now
        guard
            let summary = try? await dependencies.summaryProvider.summary(),
            let preferences = try? await dependencies.preferencesRepository.preferences()
        else {
            log.debug("Could not assemble the Watch context.")
            return nil
        }

        let timeContext = dependencies.timeEngine.resolve(
            at: now,
            preferences: preferences,
            timeZone: dependencies.clock.timeZone,
            reduceMotion: false
        )

        return WatchApplicationContext(
            generatedAt: now,
            dueTasks: summary.actionableTasks
                .prefix(WatchApplicationContext.maximumDueTasks)
                .map(WatchDueTask.init(task:)),
            totalActivePlants: summary.totalActivePlants,
            dayCyclePresentationKey: timeContext.presentation.rawValue,
            sunnieGreeting: nil,
            features: await features(
                phase: timeContext.phase, preferences: preferences, summary: summary, now: now
            )
        )
    }

    private func features(
        phase: TimePhase,
        preferences: UserPreferences,
        summary: PlantTodaySummary,
        now: Date
    ) async -> WatchFeatureContext {
        WatchFeatureContext(
            affirmation: dependencies.affirmationService.affirmation(
                for: AffirmationService.Request(
                    phase: phase,
                    preferences: .init(
                        favoriteIDs: Set(preferences.favoriteCalmSoundIDs), hiddenIDs: []
                    )
                )
            )?.text,
            nextTaskDescription: summary.actionableTasks.first?.plantDisplayName,
            checkIn: await checkInPanel(now: now),
            calm: calmPanel(preferences: preferences),
            travel: await travelPanel(now: now)
        )
    }

    private func checkInPanel(now: Date) async -> WatchFeatureContext.CheckInPanel {
        let start = dependencies.clock.calendar.startOfDay(for: now)
        let today = (try? await dependencies.wellnessRepository.checkIns(
            from: start, to: now, limit: 1
        )) ?? []
        return WatchFeatureContext.CheckInPanel(
            offersEnergy: true,
            recordedToday: !today.isEmpty
        )
    }

    private func calmPanel(preferences: UserPreferences) -> WatchFeatureContext.CalmPanel {
        let patterns = dependencies.contentRegistry.wellnessPack.breathingPatterns
            .filter(\.isWellFormed)
            .prefix(WatchFeatureContext.CalmPanel.maximumPractices)

        return WatchFeatureContext.CalmPanel(
            practices: patterns.map { pattern in
                WatchFeatureContext.CalmPanel.Practice(
                    pattern: pattern,
                    displayName: String(localized: .init(pattern.displayNameKey))
                )
            },
            usesHapticPacing: preferences.hapticsEnabled
        )
    }

    private func travelPanel(now: Date) async -> WatchFeatureContext.TravelPanel? {
        let calendar = dependencies.clock.calendar
        let trips = (try? await dependencies.travelRepository.trips(includingArchived: false)) ?? []

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

        let items = (try? await dependencies.travelRepository.checklistItems(
            forTripID: trip.id
        )) ?? []
        let outstanding = items
            .filter { !$0.isDone }
            .prefix(WatchFeatureContext.TravelPanel.maximumChecklistItems)
            .map { WatchFeatureContext.TravelPanel.ChecklistEntry(id: $0.id, title: $0.title) }

        return WatchFeatureContext.TravelPanel(
            tripTitle: trip.title,
            startsAt: trip.startsAt,
            endsAt: trip.endsAt,
            homeTimeZoneID: trip.homeTimeZoneID,
            destinationTimeZoneID: trip.destinationTimeZoneIDs.first,
            statusKey: status.localizationKey,
            checklistItems: Array(outstanding),
            nextRefreshment: nil
        )
    }
}
