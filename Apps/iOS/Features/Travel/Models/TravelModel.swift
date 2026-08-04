import Foundation
import Observation
import SunnieShared

/// Feature model for the travel dashboard (S-06).
@MainActor
@Observable
final class TravelModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var trips: [Trip] = []
    private(set) var recentMemories: [TravelMemory] = []
    private(set) var placeCount = 0

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() async {
        if state != .loaded { state = .loading }

        do {
            async let trips = dependencies.manageTrip.dashboardTrips()
            async let memories = dependencies.manageTrip.recentMemories(limit: 6)
            async let places = dependencies.manageTrip.places()

            self.trips = try await trips
            self.recentMemories = try await memories
            self.placeCount = try await places.count
            state = .loaded

            // Built-in templates arrive on first visit rather than at launch, so
            // an install that never opens Travel never creates them.
            try? await dependencies.managePacking.seedBuiltInTemplatesIfNeeded()
        } catch {
            state = .failed(String(
                localized: "travel.error.load",
                defaultValue: "I couldn't open your travel just now. Nothing has been lost, and you can try again.",
                comment: "Shown when travel data cannot be loaded"
            ))
        }
    }

    func status(of trip: Trip) -> TripStatus {
        dependencies.manageTrip.status(of: trip)
    }

    /// The trip that leads the screen: active or returning, if there is one.
    var currentTrip: Trip? {
        trips.first { status(of: $0).isCurrent }
    }

    var upcomingTrips: [Trip] {
        trips.filter { status(of: $0) == .upcoming }
    }

    var pastTrips: [Trip] {
        trips.filter { status(of: $0) == .completed }
    }

    func daysUntil(_ trip: Trip) -> Int? {
        TripStatusCalculator.daysUntilDeparture(
            trip, now: dependencies.clock.now, calendar: dependencies.clock.calendar
        )
    }
}

/// Feature model for one trip (S-07).
///
/// Loads everything the overview needs in parallel, and treats each optional
/// integration as best-effort: no weather, no calendar, and no plant coverage
/// are all normal states that must not stop the screen rendering.
@MainActor
@Observable
final class TripDetailModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var trip: Trip?
    private(set) var segments: [TripSegment] = []
    private(set) var packingItems: [PackingItem] = []
    private(set) var checklistItems: [ChecklistItem] = []
    private(set) var memories: [TravelMemory] = []
    private(set) var places: [Place] = []
    private(set) var weather: WeatherSummary?
    private(set) var coverageRows: [PlanTravelCoverage.CoverageRow] = []
    /// Set when a linked calendar event has moved or been deleted since the trip
    /// was saved. Surfaced as information, never as an error the user caused.
    private(set) var calendarDrift: CalendarDrift?

    enum CalendarDrift: Equatable {
        case movedTo(start: Date, end: Date)
        case deleted
    }

    let tripID: UUID
    private let dependencies: AppDependencies

    init(tripID: UUID, dependencies: AppDependencies) {
        self.tripID = tripID
        self.dependencies = dependencies
    }

    var status: TripStatus {
        guard let trip else { return .planning }
        return dependencies.manageTrip.status(of: trip)
    }

    var timeZoneContext: TimeZoneContext? {
        trip.map { dependencies.manageTrip.timeZoneContext(for: $0) }
    }

    var progress: TripProgress {
        TripProgress.build(
            packingItems: packingItems,
            checklistItems: checklistItems,
            undecidedPlantCoverage: coverageRows.filter(\.isUndecided).count,
            totalPlantsNeedingCare: coverageRows.filter(\.need.needsAnything).count
        )
    }

    func load() async {
        if state != .loaded { state = .loading }

        do {
            guard let trip = try await dependencies.travelRepository.trip(id: tripID) else {
                state = .failed(String(
                    localized: "trip.error.missing",
                    defaultValue: "I can't find that trip anymore.",
                    comment: "Shown when a trip no longer exists"
                ))
                return
            }
            self.trip = trip

            async let segments = dependencies.manageTrip.segments(forTripID: tripID)
            async let packing = dependencies.managePacking.items(forTripID: tripID)
            async let checklists = dependencies.manageChecklists.items(forTripID: tripID)
            async let memories = dependencies.manageTrip.memories(forTripID: tripID)
            async let places = dependencies.manageTrip.places()

            self.segments = try await segments
            self.packingItems = try await packing
            self.checklistItems = try await checklists
            self.memories = try await memories
            self.places = try await places

            state = .loaded

            // Everything below is optional and must not block the screen.
            if trip.type.isPlannable {
                _ = try? await dependencies.manageChecklists.seedDefaultsIfNeeded(
                    tripID: tripID, tripType: trip.type
                )
                self.checklistItems = (try? await dependencies.manageChecklists
                    .items(forTripID: tripID)) ?? self.checklistItems
            }

            await loadCoverage(for: trip)
            await loadWeather(for: trip)
            await checkCalendarDrift(for: trip)
        } catch {
            state = .failed(String(
                localized: "trip.error.load",
                defaultValue: "I couldn't open that trip just now. Nothing has been lost, and you can try again.",
                comment: "Shown when a trip cannot be loaded"
            ))
        }
    }

    /// Plant coverage for the absence window, if the trip has dates.
    private func loadCoverage(for trip: Trip) async {
        guard trip.type.isPlannable,
              let window = TripStatusCalculator.absenceWindow(
                  for: trip, calendar: dependencies.clock.calendar
              )
        else {
            coverageRows = []
            return
        }

        coverageRows = (try? await dependencies.planTravelCoverage.rows(
            tripID: trip.id,
            absenceStart: window.start,
            absenceEnd: window.end
        )) ?? []
    }

    /// Weather for the first destination place that has a coordinate.
    ///
    /// Nil is a normal outcome — offline, no coordinate, no entitlement — and the
    /// screen leaves the weather line out rather than showing an error.
    private func loadWeather(for trip: Trip) async {
        guard let place = places.first(where: {
            trip.placeIDs.contains($0.id) && $0.hasCoordinate
        }), let latitude = place.latitude, let longitude = place.longitude else {
            weather = nil
            return
        }
        weather = await dependencies.weatherProvider.summary(
            latitude: latitude, longitude: longitude
        )
    }

    /// Notices a linked calendar event moving or being deleted.
    ///
    /// Reported, never applied. The trip is the source of truth for Sunnie
    /// Days-specific content, and silently rewriting the user's dates because a
    /// calendar entry changed would be exactly the kind of unrequested edit the
    /// spec rules out (TRAVEL_AND_FLIGHT_ATTENDANT.md §9, §10).
    private func checkCalendarDrift(for trip: Trip) async {
        guard let identifier = trip.calendarEventID else {
            calendarDrift = nil
            return
        }
        guard await dependencies.calendarProvider.authorizationStatus() == .authorized else {
            calendarDrift = nil
            return
        }

        guard let event = await dependencies.calendarProvider
            .event(withIdentifier: identifier) else {
            calendarDrift = .deleted
            return
        }

        let startMatches = trip.startsAt.map { abs($0.timeIntervalSince(event.startsAt)) < 60 } ?? false
        let endMatches = trip.endsAt.map { abs($0.timeIntervalSince(event.endsAt)) < 60 } ?? false

        calendarDrift = (startMatches && endMatches)
            ? nil
            : .movedTo(start: event.startsAt, end: event.endsAt)
    }

    /// Applies the calendar's dates to the trip. Only ever from an explicit tap.
    func acceptCalendarDates() async {
        guard case .movedTo(let start, let end) = calendarDrift,
              var trip = self.trip else { return }
        trip.startsAt = start
        trip.endsAt = end
        _ = try? await dependencies.manageTrip.save(trip)
        calendarDrift = nil
        await load()
    }

    func placeName(_ id: UUID) -> String? {
        places.first { $0.id == id }?.name
    }

    func setPacked(_ isPacked: Bool, item: PackingItem) async {
        try? await dependencies.managePacking.setPacked(isPacked, item: item)
        packingItems = (try? await dependencies.managePacking
            .items(forTripID: tripID)) ?? packingItems
    }

    func setDone(_ isDone: Bool, item: ChecklistItem) async {
        try? await dependencies.manageChecklists.setDone(isDone, item: item)
        checklistItems = (try? await dependencies.manageChecklists
            .items(forTripID: tripID)) ?? checklistItems
    }
}
