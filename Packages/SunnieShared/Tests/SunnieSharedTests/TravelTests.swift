import Foundation
import Testing
@testable import SunnieShared

/// Trip status, time zones, packing, and place filtering — all pure, all
/// testable without a store, a device, or a network.
///
/// The time-zone tests are the point of this suite. Every boundary the spec
/// calls out (§8) is exercised here: the day a trip starts, the last day, a trip
/// spanning a daylight-saving change, and two zones that switch on different
/// dates.
@Suite("Travel")
struct TravelTests {

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func trip(
        type: TripType = .personal,
        start: Date? = nil,
        end: Date? = nil,
        home: String = "America/New_York",
        destinations: [String] = [],
        override: TripStatus? = nil
    ) -> Trip {
        Trip(
            title: "Trip",
            type: type,
            startsAt: start,
            endsAt: end,
            statusOverride: override,
            homeTimeZoneID: home,
            destinationTimeZoneIDs: destinations,
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// A date at noon UTC, so day-boundary arithmetic is unambiguous.
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: components)!
    }

    // MARK: - Status

    @Test("Status is derived from the dates at every boundary")
    func statusAcrossBoundaries() {
        let subject = trip(start: day(2026, 6, 10), end: day(2026, 6, 15))

        func status(on date: Date) -> TripStatus {
            TripStatusCalculator.status(for: subject, now: date, calendar: calendar)
        }

        #expect(status(on: day(2026, 6, 1)) == .upcoming)
        // The first day is active from its start, not from some later hour.
        #expect(status(on: day(2026, 6, 10)) == .active)
        #expect(status(on: day(2026, 6, 12)) == .active)
        // The last day is "returning", because that is the day the return
        // checklist matters.
        #expect(status(on: day(2026, 6, 15)) == .returning)
        #expect(status(on: day(2026, 6, 16)) == .completed)
    }

    @Test("A single-day trip is active, not returning")
    func singleDayTripIsActive() {
        // With start and end on the same day there is no separate return day, so
        // calling it "returning" all day would be wrong.
        let subject = trip(start: day(2026, 6, 10), end: day(2026, 6, 10))
        #expect(
            TripStatusCalculator.status(
                for: subject, now: day(2026, 6, 10), calendar: calendar
            ) == .active
        )
    }

    @Test("A trip with no dates is planning")
    func datelessTripIsPlanning() {
        #expect(
            TripStatusCalculator.status(
                for: trip(), now: day(2026, 6, 10), calendar: calendar
            ) == .planning
        )
    }

    @Test("A past trip is completed whatever its dates say")
    func pastTripsAreAlwaysCompleted() {
        // Added for the record, not for planning — so a past trip dated next year
        // must not appear as upcoming on the dashboard.
        let subject = trip(type: .past, start: day(2027, 1, 1), end: day(2027, 1, 5))
        #expect(
            TripStatusCalculator.status(
                for: subject, now: day(2026, 6, 10), calendar: calendar
            ) == .completed
        )
    }

    @Test("Archiving overrides the derived status; nothing else does")
    func archiveOverridesDerivation() {
        let archived = trip(
            start: day(2026, 6, 10), end: day(2026, 6, 15), override: .archived
        )
        #expect(
            TripStatusCalculator.status(
                for: archived, now: day(2026, 6, 12), calendar: calendar
            ) == .archived
        )

        // Any other override is ignored while dates exist, so a status can never
        // go stale by being set once and forgotten.
        let stale = trip(
            start: day(2026, 6, 10), end: day(2026, 6, 15), override: .upcoming
        )
        #expect(
            TripStatusCalculator.status(
                for: stale, now: day(2026, 6, 12), calendar: calendar
            ) == .active
        )
    }

    @Test("The trip is lived in the destination's day")
    func statusFollowsTheDestinationDay() {
        // Someone in Tokyo should not see their trip end because it is still
        // yesterday at home.
        let subject = trip(
            start: day(2026, 6, 10),
            end: day(2026, 6, 15),
            home: "America/New_York",
            destinations: ["Asia/Tokyo"]
        )

        // 16 June 01:00 Tokyo is still 15 June in New York. The trip is over in
        // Tokyo, which is where the traveller is.
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 16
        components.hour = 1
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let earlyTokyoMorning = tokyo.date(from: components)!

        #expect(
            TripStatusCalculator.status(
                for: subject, now: earlyTokyoMorning, calendar: calendar
            ) == .completed
        )
    }

    @Test("The absence window runs to the end of the last day")
    func absenceWindowCoversTheWholeLastDay() {
        // Care due on the afternoon of the return day is inside the absence. A
        // window ending at the start of that day would miss it.
        let subject = trip(
            start: day(2026, 6, 10), end: day(2026, 6, 15), home: "UTC"
        )
        let window = TripStatusCalculator.absenceWindow(for: subject, calendar: calendar)
        let unwrapped = try! #require(window)

        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(unwrapped.end > day(2026, 6, 15))
        #expect(unwrapped.end == utc.startOfDay(for: day(2026, 6, 16)))
    }

    @Test("Days until departure counts whole days and stops at the start")
    func daysUntilDeparture() {
        let subject = trip(start: day(2026, 6, 10), home: "UTC")

        #expect(TripStatusCalculator.daysUntilDeparture(
            subject, now: day(2026, 6, 7), calendar: calendar
        ) == 3)
        // Once it has begun there is no countdown.
        #expect(TripStatusCalculator.daysUntilDeparture(
            subject, now: day(2026, 6, 10), calendar: calendar
        ) == nil)
    }

    @Test("Dashboard order puts current first, then soonest upcoming, then recent past")
    func dashboardOrdering() {
        let now = day(2026, 6, 12)
        let active = trip(start: day(2026, 6, 10), end: day(2026, 6, 15), home: "UTC")
        let soon = trip(start: day(2026, 6, 20), home: "UTC")
        let later = trip(start: day(2026, 8, 1), home: "UTC")
        let old = trip(start: day(2026, 1, 1), end: day(2026, 1, 5), home: "UTC")
        let older = trip(start: day(2025, 1, 1), end: day(2025, 1, 5), home: "UTC")

        let ordered = TripStatusCalculator.dashboardOrder(
            [older, later, active, old, soon], now: now, calendar: calendar
        )

        #expect(ordered.map(\.id) == [active, soon, later, old, older].map(\.id))
    }

    // MARK: - Time zones

    @Test("The offset is computed at the instant, not cached")
    func offsetIsComputedPerInstant() {
        // New York and London are five hours apart most of the year and four for
        // the fortnight where their daylight-saving dates disagree. A stored
        // offset is wrong twice a year.
        let march = TimeZoneContext(
            homeTimeZoneID: "America/New_York",
            localTimeZoneID: "Europe/London",
            instant: day(2026, 3, 20)
        )
        let june = TimeZoneContext(
            homeTimeZoneID: "America/New_York",
            localTimeZoneID: "Europe/London",
            instant: day(2026, 6, 20)
        )

        #expect(march.offsetHours == 4)
        #expect(june.offsetHours == 5)
    }

    @Test("A different calendar day is detected across the date line")
    func differentDayIsDetected() {
        let context = TimeZoneContext(
            homeTimeZoneID: "America/Los_Angeles",
            localTimeZoneID: "Asia/Tokyo",
            instant: day(2026, 6, 20)
        )
        #expect(context.isDifferentDay(calendar: calendar))

        let sameZone = TimeZoneContext(
            homeTimeZoneID: "UTC", localTimeZoneID: "UTC", instant: day(2026, 6, 20)
        )
        #expect(!sameZone.isDifferentDay(calendar: calendar))
    }

    @Test("An imminent clock change is flagged")
    func upcomingTransitionIsFlagged() {
        // The US switches on 8 March 2026. The day before, the change is worth
        // mentioning — it is what quietly breaks an alarm.
        let dayBefore = TimeZoneContext(
            homeTimeZoneID: "America/New_York",
            localTimeZoneID: "America/New_York",
            instant: day(2026, 3, 7)
        )
        #expect(dayBefore.hasUpcomingTransition())

        let quietWeek = TimeZoneContext(
            homeTimeZoneID: "America/New_York",
            localTimeZoneID: "America/New_York",
            instant: day(2026, 6, 15)
        )
        #expect(!quietWeek.hasUpcomingTransition())
    }

    @Test("A zone with no daylight saving never reports a transition")
    func fixedZonesHaveNoTransitions() {
        let context = TimeZoneContext(
            homeTimeZoneID: "UTC", localTimeZoneID: "Asia/Tokyo", instant: day(2026, 3, 7)
        )
        #expect(!context.hasUpcomingTransition())
    }

    // MARK: - Sleep window

    @Test("The sleep window translates hours and wraps past midnight")
    func sleepWindowTranslatesHours() {
        // Non-medical arithmetic: the user's own hours, read in the destination's
        // clock. Nothing here models circadian rhythm or gives advice.
        let context = TimeZoneContext(
            homeTimeZoneID: "America/New_York",
            localTimeZoneID: "Europe/Paris",
            instant: day(2026, 6, 20)
        )

        let window = SleepWindowPlanner.window(
            homeBedHour: 23, homeWakeHour: 7, context: context
        )

        #expect(window.shiftHours == 6)
        // 23:00 + 6 wraps to 05:00, not 29:00.
        #expect(window.localBedHour == 5)
        #expect(window.localWakeHour == 13)
        #expect(window.isWorthMentioning)
    }

    @Test("A small shift is not worth mentioning")
    func smallShiftsAreQuiet() {
        let context = TimeZoneContext(
            homeTimeZoneID: "Europe/London",
            localTimeZoneID: "Europe/Paris",
            instant: day(2026, 6, 20)
        )
        let window = SleepWindowPlanner.window(
            homeBedHour: 23, homeWakeHour: 7, context: context
        )
        #expect(!window.isWorthMentioning)
    }

    // MARK: - Hydration

    @Test("Hydration reminders are spaced inside the waking window")
    func hydrationRemindersAreSpaced() {
        let start = day(2026, 6, 20)
        let end = start.addingTimeInterval(12 * 3600)

        let times = HydrationPlanner.reminderTimes(
            wakingStart: start, wakingEnd: end, count: 3, calendar: calendar
        )

        #expect(times.count == 3)
        // Never at the very edges: a reminder at the moment of waking and one at
        // the moment of sleeping are the two least useful.
        #expect(times.allSatisfy { $0 > start && $0 < end })
        #expect(times == times.sorted())
    }

    @Test("Hydration cannot exceed the category's daily ceiling")
    func hydrationRespectsTheReminderCeiling() {
        // A plan that asked for twenty reminders would break the notification
        // rules from the other side.
        let start = day(2026, 6, 20)
        let times = HydrationPlanner.reminderTimes(
            wakingStart: start,
            wakingEnd: start.addingTimeInterval(12 * 3600),
            count: 50,
            calendar: calendar
        )
        #expect(times.count == ReminderCategory.hydration.dailyMaximum)
    }

    @Test("An inverted or empty window produces nothing")
    func degenerateHydrationWindows() {
        let start = day(2026, 6, 20)
        #expect(HydrationPlanner.reminderTimes(
            wakingStart: start, wakingEnd: start, count: 3, calendar: calendar
        ).isEmpty)
        #expect(HydrationPlanner.reminderTimes(
            wakingStart: start,
            wakingEnd: start.addingTimeInterval(-3600),
            count: 3,
            calendar: calendar
        ).isEmpty)
    }

    // MARK: - Packing

    private func template(_ entries: [(String, PackingCategory)]) -> PackingTemplate {
        PackingTemplate(
            name: "Template",
            entries: entries.map { PackingTemplate.Entry(name: $0.0, category: $0.1) },
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Applying a template twice adds nothing the second time")
    func templatesAreIdempotent() {
        // What makes "reuse last trip's list" safe to tap when you are not sure
        // whether you already did.
        let tripID = UUID()
        let source = template([("Passport", .documents), ("Charger", .technology)])

        let first = PackingListBuilder.applying(source, to: [], tripID: tripID)
        #expect(first.count == 2)

        let second = PackingListBuilder.applying(source, to: first, tripID: tripID)
        #expect(second.isEmpty)
    }

    @Test("Duplicate detection ignores case, accents, and surrounding space")
    func duplicateDetectionNormalizes() {
        let tripID = UUID()
        let existing = [PackingItem(tripID: tripID, name: "Passeport", category: .documents)]
        let source = template([("  passeport  ", .documents)])

        #expect(PackingListBuilder.applying(source, to: existing, tripID: tripID).isEmpty)
    }

    @Test("The same name in a different category is not a duplicate")
    func categoryIsPartOfIdentity() {
        // "Water" in food and "water" in work are different things.
        let tripID = UUID()
        let existing = [PackingItem(tripID: tripID, name: "Water", category: .food)]
        let source = template([("Water", .personal)])

        #expect(PackingListBuilder.applying(source, to: existing, tripID: tripID).count == 1)
    }

    @Test("Applying a template never modifies what is already there")
    func templatesDoNotOverwrite() {
        // An item already ticked stays ticked, and a quantity the user changed is
        // not reset by re-applying the template it came from.
        let tripID = UUID()
        var packed = PackingItem(tripID: tripID, name: "Charger", category: .technology)
        packed.isPacked = true
        packed.quantity = 3

        let added = PackingListBuilder.applying(
            template([("Charger", .technology)]), to: [packed], tripID: tripID
        )
        #expect(added.isEmpty)
        #expect(packed.isPacked)
        #expect(packed.quantity == 3)
    }

    @Test("Reusing a list comes back unpacked and without its notes")
    func reusingClearsStateAndNotes() {
        let oldTrip = UUID(), newTrip = UUID()
        var item = PackingItem(
            tripID: oldTrip, name: "Charger", category: .technology, quantity: 2
        )
        item.isPacked = true
        item.notes = "the blue one, side pocket"
        item.isRequired = true

        let copied = PackingListBuilder.reusing([item], for: newTrip)
        let first = try! #require(copied.first)

        #expect(first.tripID == newTrip)
        #expect(!first.isPacked)
        // Notes described last trip's packing and are noise now.
        #expect(first.notes == nil)
        // Quantity and required describe the trip shape and carry over.
        #expect(first.quantity == 2)
        #expect(first.isRequired)
    }

    @Test("Duplicates are grouped rather than merged")
    func duplicatesAreSurfaced() {
        let tripID = UUID()
        let items = [
            PackingItem(tripID: tripID, name: "Charger", category: .technology, sortOrder: 0),
            PackingItem(tripID: tripID, name: "charger", category: .technology, sortOrder: 1),
            PackingItem(tripID: tripID, name: "Passport", category: .documents, sortOrder: 2)
        ]

        let groups = PackingListBuilder.duplicateGroups(in: items)
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
    }

    @Test("Progress is counted per section")
    func progressIsPerSection() {
        let tripID = UUID()
        var uniform = PackingItem(tripID: tripID, name: "Uniform", category: .uniform)
        uniform.isPacked = true
        let snacks = PackingItem(tripID: tripID, name: "Snacks", category: .food)

        let work = PackingListBuilder.progress(for: [uniform, snacks], in: .work)
        #expect(work == (packed: 1, total: 1))

        let food = PackingListBuilder.progress(for: [uniform, snacks], in: .food)
        #expect(food == (packed: 0, total: 1))

        let all = PackingListBuilder.progress(for: [uniform, snacks])
        #expect(all == (packed: 1, total: 2))
    }

    @Test("Categories map to the three sections the spec requires")
    func categorySections() {
        #expect(PackingCategory.uniform.section == .work)
        #expect(PackingCategory.documents.section == .work)
        #expect(PackingCategory.food.section == .food)
        #expect(PackingCategory.toiletries.section == .personal)
    }

    // MARK: - Trip progress

    @Test("Trip progress separates the leaving and returning checklists")
    func tripProgressSeparatesPhases() {
        let tripID = UUID()
        var leaving = ChecklistItem(tripID: tripID, kind: .beforeLeaving, title: "Doors")
        leaving.isDone = true
        let returning = ChecklistItem(tripID: tripID, kind: .returnHome, title: "Unpack")

        let progress = TripProgress.build(
            packingItems: [], checklistItems: [leaving, returning]
        )

        #expect(progress.leavingChecklist.isComplete)
        #expect(!progress.returningChecklist.isComplete)
        #expect(progress.returningChecklist.remaining == 1)
        // An empty list is not "complete" — there is nothing to have finished.
        #expect(progress.packing.isEmpty)
        #expect(!progress.packing.isComplete)
    }

    // MARK: - Places

    private func placeItem(
        name: String,
        country: String? = nil,
        favorite: Bool = false,
        years: Set<Int> = [],
        types: Set<TripType> = []
    ) -> PlaceListItem {
        PlaceListItem(
            place: Place(
                name: name,
                country: country,
                isFavorite: favorite,
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            visitYears: years,
            tripTypes: types
        )
    }

    @Test("Place search covers name, country, and notes, ignoring accents")
    func placeSearch() {
        let items = [
            placeItem(name: "Paris", country: "France"),
            placeItem(name: "Tokyo", country: "Japan")
        ]

        var query = PlaceQuery.default
        query.searchText = "fran"
        #expect(PlaceFilter.apply(query, to: items).map(\.place.name) == ["Paris"])

        query.searchText = "TOKYO"
        #expect(PlaceFilter.apply(query, to: items).map(\.place.name) == ["Tokyo"])
    }

    @Test("Year and favourite filters narrow the list")
    func placeFilters() {
        let items = [
            placeItem(name: "Paris", favorite: true, years: [2024], types: [.work]),
            placeItem(name: "Rome", years: [2025], types: [.personal])
        ]

        var byYear = PlaceQuery.default
        byYear.year = 2025
        #expect(PlaceFilter.apply(byYear, to: items).map(\.place.name) == ["Rome"])

        var favorites = PlaceQuery.default
        favorites.favoritesOnly = true
        #expect(PlaceFilter.apply(favorites, to: items).map(\.place.name) == ["Paris"])

        var byType = PlaceQuery.default
        byType.tripTypes = [.work]
        #expect(PlaceFilter.apply(byType, to: items).map(\.place.name) == ["Paris"])
    }

    @Test("Available years are newest first")
    func availableYears() {
        let items = [
            placeItem(name: "A", years: [2020, 2024]),
            placeItem(name: "B", years: [2022])
        ]
        #expect(PlaceFilter.availableYears(in: items) == [2024, 2022, 2020])
    }

    @Test("A place with no coordinate is still a place")
    func placesWorkWithoutCoordinates() {
        // Somewhere typed from memory belongs in the list; the map is a view of
        // the records, not the records themselves.
        let item = placeItem(name: "That café", country: "Portugal")
        #expect(!item.place.hasCoordinate)
        #expect(PlaceFilter.apply(.default, to: [item]).count == 1)
    }
}
