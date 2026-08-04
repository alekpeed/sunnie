import Foundation
import SunnieShared

/// Creating, editing, and running a trip (TRAVEL_AND_FLIGHT_ATTENDANT.md).
///
/// **This is not an airline operations or safety system** (§1). Nothing here
/// models a flight, validates a schedule, or represents an official procedure.
/// It holds what one person needs to leave the house without forgetting things
/// and to remember the trip afterwards.
struct ManageTrip: Sendable {

    private let repository: any TravelRepository
    private let progressionEngine: ProgressionEngine
    private let eventPublisher: any DomainEventPublishing
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        repository: any TravelRepository,
        progressionEngine: ProgressionEngine,
        eventPublisher: any DomainEventPublishing,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.progressionEngine = progressionEngine
        self.eventPublisher = eventPublisher
        self.clock = clock
    }

    // MARK: - Trips

    /// A blank trip.
    ///
    /// The home time zone is the device's, which is right almost always and
    /// editable when it is not — someone who has moved should not have to answer
    /// that question on every trip.
    func newDraft(type: TripType = .personal) -> Trip {
        let now = clock.now
        return Trip(
            title: "",
            type: type,
            homeTimeZoneID: clock.timeZone.identifier,
            createdAt: now,
            modifiedAt: now
        )
    }

    /// Saves a trip.
    ///
    /// Only a title is required — the same rule as the plant editor. A trip with
    /// no dates is in `planning`, which is a real state, not an incomplete one.
    @discardableResult
    func save(_ trip: Trip) async throws -> Trip {
        var cleaned = trip
        cleaned.title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.notes = tidy(trip.notes)
        cleaned.modifiedAt = clock.now

        // An end before a start is a typo, not an intent. Swapping is kinder than
        // refusing, and the user sees the result immediately.
        if let start = cleaned.startsAt, let end = cleaned.endsAt, end < start {
            cleaned.startsAt = end
            cleaned.endsAt = start
        }

        let isNew = try await repository.trip(id: cleaned.id) == nil
        try await repository.save(cleaned)

        if isNew {
            await eventPublisher.publish(DomainEvent(
                type: .tripCreated,
                occurredAt: clock.now,
                sourceEntityID: cleaned.id,
                deterministicKey: "tripCreated.\(cleaned.id.uuidString)"
            ))
        }

        return cleaned
    }

    func status(of trip: Trip) -> TripStatus {
        TripStatusCalculator.status(for: trip, now: clock.now, calendar: clock.calendar)
    }

    /// Trips in dashboard order: current first, then soonest upcoming, then most
    /// recent past.
    func dashboardTrips(includingArchived: Bool = false) async throws -> [Trip] {
        let trips = try await repository.trips(includingArchived: includingArchived)
        return TripStatusCalculator.dashboardOrder(
            trips, now: clock.now, calendar: clock.calendar
        )
    }

    /// Archiving is reversible and keeps everything. Deleting is the other one.
    func archive(tripID: UUID) async throws {
        guard var trip = try await repository.trip(id: tripID) else {
            throw DomainError.notFound(entity: "Trip", id: tripID)
        }
        trip.statusOverride = .archived
        trip.modifiedAt = clock.now
        try await repository.save(trip)
    }

    func unarchive(tripID: UUID) async throws {
        guard var trip = try await repository.trip(id: tripID) else {
            throw DomainError.notFound(entity: "Trip", id: tripID)
        }
        // Cleared rather than set to a guess: the status goes back to being
        // derived from the dates, which is always current.
        trip.statusOverride = nil
        trip.modifiedAt = clock.now
        try await repository.save(trip)
    }

    func delete(tripID: UUID) async throws {
        try await repository.delete(tripID: tripID)
    }

    // MARK: - Segments

    func segments(forTripID tripID: UUID) async throws -> [TripSegment] {
        try await repository.segments(forTripID: tripID)
    }

    @discardableResult
    func save(_ segment: TripSegment) async throws -> TripSegment {
        var cleaned = segment
        cleaned.title = segment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.notes = tidy(segment.notes)

        if cleaned.title.isEmpty {
            // A segment with no title is still useful — it has times and places.
            // Naming it after its kind beats showing a blank row.
            cleaned.title = String(localized: .init(cleaned.kind.localizationKey))
        }

        try await repository.save(cleaned)
        return cleaned
    }

    func deleteSegment(id: UUID) async throws {
        try await repository.deleteSegment(id: id)
    }

    // MARK: - Time zones

    /// Home and local time for a trip, at this moment.
    ///
    /// Falls back to the home zone when the trip has no destination, so the
    /// caller always gets a context and never has to branch on nil.
    func timeZoneContext(for trip: Trip) -> TimeZoneContext {
        TimeZoneContext(
            homeTimeZoneID: trip.homeTimeZoneID,
            localTimeZoneID: trip.destinationTimeZoneIDs.first ?? trip.homeTimeZoneID,
            instant: clock.now
        )
    }

    // MARK: - Places

    func places() async throws -> [Place] {
        try await repository.places()
    }

    func placeListItems() async throws -> [PlaceListItem] {
        try await repository.placeListItems()
    }

    @discardableResult
    func save(_ place: Place) async throws -> Place {
        var cleaned = place
        cleaned.name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.country = tidy(place.country)
        cleaned.notes = tidy(place.notes)
        try await repository.save(cleaned)
        return cleaned
    }

    func newPlace(name: String = "") -> Place {
        Place(name: name, createdAt: clock.now)
    }

    func deletePlace(id: UUID) async throws {
        try await repository.deletePlace(id: id)
    }

    // MARK: - Memories

    func newMemory(tripID: UUID?, placeID: UUID? = nil) -> TravelMemory {
        let now = clock.now
        return TravelMemory(
            tripID: tripID,
            placeID: placeID,
            occurredAt: now,
            createdAt: now,
            modifiedAt: now
        )
    }

    func memories(forTripID tripID: UUID?) async throws -> [TravelMemory] {
        try await repository.memories(forTripID: tripID)
    }

    func recentMemories(limit: Int = 20) async throws -> [TravelMemory] {
        try await repository.allMemories(limit: limit)
    }

    /// A memory needs a title, some text, or a place. Photos count too, which is
    /// why the caller passes whether any are attached — a photograph of somewhere
    /// is a complete memory on its own.
    @discardableResult
    func save(_ memory: TravelMemory, hasAttachments: Bool = false) async throws -> TravelMemory {
        var cleaned = memory
        cleaned.title = tidy(memory.title)
        cleaned.text = tidy(memory.text)
        cleaned.tags = memory.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        cleaned.modifiedAt = clock.now

        guard cleaned.hasContent || hasAttachments else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        try await repository.save(cleaned)
        return cleaned
    }

    func deleteMemory(id: UUID) async throws {
        try await repository.deleteMemory(id: id)
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
