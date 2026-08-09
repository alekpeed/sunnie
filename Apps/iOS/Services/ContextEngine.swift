import Foundation
import SunnieShared

/// Builds the shared read-only picture of Sunnie Days used across product
/// surfaces. No method here writes user data.
@MainActor
final class ContextEngine {

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func currentContext() async -> CurrentContext {
        let now = dependencies.clock.now

        let plantSummary = try? await dependencies.summaryProvider.summary()
        let wellnessSummary = try? await dependencies.wellnessSummaryProvider.summary()
        let progression = (try? await dependencies.progressionRepository.profile())
            ?? ProgressionProfile()
        let trips = (try? await dependencies.manageTrip.dashboardTrips()) ?? []
        let flightMode = await buildFlightContext(from: trips, now: now)
        let mealsToday = await mealCountToday(now: now)

        let items = buildItems(
            plantSummary: plantSummary,
            trips: trips,
            flightMode: flightMode,
            progression: progression,
            mealsToday: mealsToday,
            now: now
        )

        return CurrentContext(
            generatedAt: now,
            plantSummary: plantSummary,
            wellnessSummary: wellnessSummary,
            progression: progression,
            flightMode: flightMode,
            items: items
        )
    }

    private func buildFlightContext(from trips: [Trip], now: Date) async -> FlightContext? {
        guard let selection = FlightModeSelector.select(
            from: trips,
            now: now,
            calendar: dependencies.clock.calendar
        ) else { return nil }

        let trip = selection.trip
        let packing = (try? await dependencies.managePacking.items(forTripID: trip.id)) ?? []
        let checklist = (try? await dependencies.manageChecklists.items(forTripID: trip.id)) ?? []
        let places = (try? await dependencies.manageTrip.places()) ?? []
        let destination = places.first { trip.placeIDs.contains($0.id) }
        let weather = await weather(for: destination)

        var coverageRows: [PlanTravelCoverage.CoverageRow] = []
        if let window = TripStatusCalculator.absenceWindow(
            for: trip,
            calendar: dependencies.clock.calendar
        ) {
            coverageRows = (try? await dependencies.planTravelCoverage.rows(
                tripID: trip.id,
                absenceStart: window.start,
                absenceEnd: window.end
            )) ?? []
        }

        let mealCount = await mealCountToday(now: now)

        return FlightContext(
            tripID: trip.id,
            tripTitle: trip.title,
            phase: selection.phase,
            destinationName: destination?.name,
            destinationTimeZoneID: trip.destinationTimeZoneIDs.first,
            startsAt: trip.startsAt,
            endsAt: trip.endsAt,
            daysUntilDeparture: TripStatusCalculator.daysUntilDeparture(
                trip,
                now: now,
                calendar: dependencies.clock.calendar
            ),
            packedCount: packing.filter(\.isPacked).count,
            packingCount: packing.count,
            checklistDoneCount: checklist.filter(\.isDone).count,
            checklistCount: checklist.count,
            plantCoverageUndecidedCount: coverageRows.filter(\.isUndecided).count,
            plantsNeedingTripCareCount: coverageRows.filter { $0.need.needsAnything }.count,
            plannedMealsTodayCount: mealCount,
            weather: weather
        )
    }

    private func weather(for place: Place?) async -> WeatherSummary? {
        guard
            let place,
            let latitude = place.latitude,
            let longitude = place.longitude
        else { return nil }

        return await dependencies.weatherProvider.summary(
            latitude: latitude,
            longitude: longitude
        )
    }

    private func mealCountToday(now: Date) async -> Int {
        var calendar = dependencies.clock.calendar
        calendar.timeZone = dependencies.clock.timeZone
        let day = calendar.startOfDay(for: now)
        return ((try? await dependencies.mealRepository.entries(forDay: day)) ?? []).count
    }

    private func buildItems(
        plantSummary: PlantTodaySummary?,
        trips: [Trip],
        flightMode: FlightContext?,
        progression: ProgressionProfile,
        mealsToday: Int,
        now: Date
    ) -> [ContextItem] {
        var items: [ContextItem] = []

        if let flightMode {
            items.append(flightItem(flightMode))
        } else if let nextTrip = nextRelevantTrip(in: trips, now: now) {
            items.append(ContextItem(
                id: "travel.\(nextTrip.id.uuidString)",
                kind: .informational,
                priority: 75,
                title: nextTrip.title,
                detail: tripDetail(nextTrip, now: now),
                primaryAction: .openTrip(nextTrip.id)
            ))
        }

        if let plantSummary {
            let count = plantSummary.actionableTasks.count
            if count > 0 {
                items.append(ContextItem(
                    id: "plants.actionable",
                    kind: .actionable,
                    priority: flightMode?.plantCoverageUndecidedCount ?? 0 > 0 ? 88 : 70,
                    title: "Plant care",
                    detail: count == 1
                        ? "1 care item is ready in your jungle."
                        : "\(count) care items are ready in your jungle.",
                    primaryAction: .openJungleDue
                ))
            }
        }

        if mealsToday > 0 {
            items.append(ContextItem(
                id: "meals.today",
                kind: .informational,
                priority: flightMode == nil ? 45 : 64,
                title: "Meals",
                detail: mealsToday == 1
                    ? "1 meal is planned for today."
                    : "\(mealsToday) meals are planned for today.",
                primaryAction: .openMeals
            ))
        }

        items.append(ContextItem(
            id: "progression.current",
            kind: .ambient,
            priority: 20,
            title: "Your Sunnie world",
            detail: "Level \(progression.level) · \(progression.experience) points",
            primaryAction: .openCollections,
            secondaryAction: .openSunnieHome
        ))

        return items.filter { $0.isRelevant(at: now) }
    }

    private func flightItem(_ flight: FlightContext) -> ContextItem {
        var facts: [String] = []

        if flight.packingCount > 0 {
            facts.append("\(flight.packedCount) of \(flight.packingCount) packed")
        }
        if flight.checklistCount > 0 {
            facts.append("\(flight.checklistDoneCount) of \(flight.checklistCount) personal checklist items checked")
        }
        if flight.plantCoverageUndecidedCount > 0 {
            let count = flight.plantCoverageUndecidedCount
            facts.append(count == 1
                ? "1 plant coverage decision is still undecided"
                : "\(count) plant coverage decisions are still undecided")
        }

        let place = flight.destinationName.map { " · \($0)" } ?? ""
        let detail = facts.isEmpty ? flightPhaseDetail(flight) : facts.joined(separator: " · ")

        return ContextItem(
            id: "flightMode.\(flight.tripID.uuidString)",
            kind: .informational,
            priority: 100,
            title: "Flight Mode\(place)",
            detail: detail,
            primaryAction: .openTrip(flight.tripID),
            secondaryAction: .openPacking(flight.tripID),
            expiresAt: flight.endsAt
        )
    }

    private func flightPhaseDetail(_ flight: FlightContext) -> String {
        switch flight.phase {
        case .preparing:
            if let days = flight.daysUntilDeparture {
                if days == 0 { return "Your work trip starts today." }
                if days == 1 { return "Your work trip starts tomorrow." }
                return "Your work trip starts in \(days) days."
            }
            return "Your upcoming work trip is in context."
        case .away:
            return "Your work trip is active."
        case .returning:
            return "This is the return part of your work trip."
        }
    }

    private func nextRelevantTrip(in trips: [Trip], now: Date) -> Trip? {
        trips.first { trip in
            let status = TripStatusCalculator.status(
                for: trip,
                now: now,
                calendar: dependencies.clock.calendar
            )
            return status.isCurrent || status == .upcoming
        }
    }

    private func tripDetail(_ trip: Trip, now: Date) -> String? {
        let status = TripStatusCalculator.status(
            for: trip,
            now: now,
            calendar: dependencies.clock.calendar
        )
        if status.isCurrent { return "This trip is active." }
        guard let days = TripStatusCalculator.daysUntilDeparture(
            trip,
            now: now,
            calendar: dependencies.clock.calendar
        ) else { return nil }
        if days == 0 { return "Starts today." }
        if days == 1 { return "Starts tomorrow." }
        return "Starts in \(days) days."
    }
}
