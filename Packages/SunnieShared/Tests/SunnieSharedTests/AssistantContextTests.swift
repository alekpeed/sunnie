import Foundation
import Testing
@testable import SunnieShared

struct AssistantContextTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test("Flight Mode never infers work from a personal trip")
    func personalTripDoesNotActivateFlightMode() {
        let trip = makeTrip(type: .personal, startsInDays: 0, endsInDays: 2)
        let selected = FlightModeSelector.select(from: [trip], now: now, calendar: calendar)
        #expect(selected == nil)
    }

    @Test("A current explicit work trip activates Flight Mode")
    func currentWorkTripActivates() {
        let trip = makeTrip(type: .work, startsInDays: -1, endsInDays: 2)
        let selected = FlightModeSelector.select(from: [trip], now: now, calendar: calendar)
        #expect(selected?.trip.id == trip.id)
        #expect(selected?.phase == .away)
    }

    @Test("An imminent work trip enters preparation mode")
    func imminentWorkTripPrepares() {
        let trip = makeTrip(type: .work, startsInDays: 2, endsInDays: 4)
        let selected = FlightModeSelector.select(from: [trip], now: now, calendar: calendar)
        #expect(selected?.trip.id == trip.id)
        #expect(selected?.phase == .preparing)
    }

    @Test("A distant work trip stays ordinary travel")
    func distantWorkTripDoesNotActivate() {
        let trip = makeTrip(type: .work, startsInDays: 5, endsInDays: 7)
        let selected = FlightModeSelector.select(from: [trip], now: now, calendar: calendar)
        #expect(selected == nil)
    }

    @Test("Returning work trip uses returning state")
    func returningWorkTrip() {
        let trip = makeTrip(type: .work, startsInDays: -2, endsInDays: 0)
        let selected = FlightModeSelector.select(from: [trip], now: now, calendar: calendar)
        #expect(selected?.phase == .returning)
    }

    @Test("Tell Sunnie parses a common plant care statement")
    func parsesPlantCare() {
        let intent = TellSunnieParser.parse("Watered the monstera this morning")
        #expect(intent == .recordPlantCare(careType: .water, plantQuery: "monstera"))
    }

    @Test("Tell Sunnie parses packing capture")
    func parsesPacking() {
        let intent = TellSunnieParser.parse("Remind me to pack my charger")
        #expect(intent == .addPackingItem(name: "my charger", category: .technology))
    }

    @Test("Tell Sunnie parses trip context questions")
    func parsesTripPreparation() {
        #expect(
            TellSunnieParser.parse("What do I still need to do before my flight?")
                == .askTripPreparation
        )
    }

    @Test("Tell Sunnie routes ordinary navigation")
    func parsesNavigation() {
        #expect(TellSunnieParser.parse("Open my plants") == .open(.plants))
        #expect(TellSunnieParser.parse("Show me travel") == .open(.travel))
        #expect(TellSunnieParser.parse("Go to Sunnie's Home") == .open(.home))
    }

    @Test("CurrentContext ranks higher priority items first")
    func contextRanking() {
        let low = ContextItem(
            id: "low",
            kind: .ambient,
            priority: 10,
            title: "Low"
        )
        let high = ContextItem(
            id: "high",
            kind: .informational,
            priority: 100,
            title: "High"
        )
        let context = CurrentContext(generatedAt: now, items: [low, high])
        #expect(context.items.map(\.id) == ["high", "low"])
    }

    private func makeTrip(
        type: TripType,
        startsInDays: Int,
        endsInDays: Int
    ) -> Trip {
        let start = calendar.date(byAdding: .day, value: startsInDays, to: now)!
        let end = calendar.date(byAdding: .day, value: endsInDays, to: now)!
        return Trip(
            title: "Test trip",
            type: type,
            startsAt: start,
            endsAt: end,
            homeTimeZoneID: "America/New_York",
            destinationTimeZoneIDs: ["Asia/Tokyo"],
            createdAt: now,
            modifiedAt: now
        )
    }
}
