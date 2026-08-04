import Foundation
import Testing
@testable import SunnieShared

/// Collection filtering and sorting (PLANT_CARE.md §6).
///
/// All pure: arrays in, arrays out. Every filter, every sort order, and the
/// search rules are exercised here without a store, a screen, or a device.
@Suite("Plant collection filter")
struct PlantCollectionFilterTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private var timeZone: TimeZone { TimeZone(identifier: "UTC")! }

    private func plant(
        name: String,
        nickname: String? = nil,
        species: String? = nil,
        variety: String? = nil,
        notes: String? = nil,
        locationID: UUID? = nil,
        status: PlantStatus = .active,
        acquired: Date? = nil,
        difficulty: CareDifficulty = .moderate
    ) -> Plant {
        Plant(
            name: name,
            nickname: nickname,
            speciesName: species,
            variety: variety,
            locationID: locationID,
            difficulty: difficulty,
            acquiredDate: acquired,
            notes: notes,
            status: status,
            qrToken: PlantQRIdentity.makeToken(),
            createdAt: now,
            modifiedAt: now
        )
    }

    private func item(
        _ plant: Plant,
        locationName: String? = nil,
        nextDue: Date? = nil,
        lastCare: Date? = nil,
        careTypes: Set<CareType> = [],
        caretakers: Set<UUID> = [],
        openObservations: Int = 0
    ) -> PlantCollectionItem {
        PlantCollectionItem(
            plant: plant,
            locationName: locationName,
            nextDueDate: nextDue,
            lastCareAt: lastCare,
            scheduledCareTypes: careTypes,
            caretakerIDs: caretakers,
            openObservationCount: openObservations
        )
    }

    private func apply(
        _ query: PlantCollectionQuery,
        _ items: [PlantCollectionItem]
    ) -> [String] {
        PlantCollectionFilter.apply(
            query, to: items, now: now, calendar: calendar, timeZone: timeZone
        ).map(\.plant.displayName)
    }

    // MARK: - Search

    @Test("Search covers name, nickname, species, variety, room, and notes")
    func searchCoversEveryTypedField() {
        let base = item(plant(name: "Monstera", species: "Monstera deliciosa"))

        for term in ["Monstera", "monstera", "deliciosa"] {
            #expect(PlantCollectionFilter.matchesSearch(term, item: base), "\(term)")
        }

        let nicknamed = item(plant(name: "Plant", nickname: "Gerald"))
        #expect(PlantCollectionFilter.matchesSearch("gerald", item: nicknamed))

        let located = item(plant(name: "Plant"), locationName: "Kitchen")
        #expect(PlantCollectionFilter.matchesSearch("kitch", item: located))

        let noted = item(plant(name: "Plant", notes: "From the market on Ossington"))
        #expect(PlantCollectionFilter.matchesSearch("ossington", item: noted))

        #expect(!PlantCollectionFilter.matchesSearch("fern", item: base))
    }

    @Test("Search ignores diacritics")
    func searchIgnoresDiacritics() {
        // Someone typing quickly will not reach for the accented character, and
        // failing to find their own plant because of it would be maddening.
        let accented = item(plant(name: "Sansevieriá"))
        #expect(PlantCollectionFilter.matchesSearch("sansevieria", item: accented))
    }

    @Test("An empty search matches everything")
    func emptySearchMatchesEverything() {
        let base = item(plant(name: "Monstera"))
        #expect(PlantCollectionFilter.matchesSearch("", item: base))
        #expect(PlantCollectionFilter.matchesSearch("   ", item: base))
    }

    // MARK: - Filters

    @Test("Archived plants are hidden by default and shown on request")
    func archivedPlantsAreHiddenByDefault() {
        let items = [
            item(plant(name: "Here")),
            item(plant(name: "Gone", status: .archived))
        ]

        #expect(apply(.default, items) == ["Here"])

        var showingArchived = PlantCollectionQuery.default
        showingArchived.statuses = [.active, .archived]
        #expect(apply(showingArchived, items) == ["Gone", "Here"])
    }

    @Test("An empty status set shows everything rather than nothing")
    func emptyStatusSetIsTreatedAsUnfiltered() {
        // A screen that has gone blank because every status was switched off
        // reads as broken, not as filtered.
        var query = PlantCollectionQuery.default
        query.statuses = []

        let items = [item(plant(name: "A")), item(plant(name: "B", status: .archived))]
        #expect(apply(query, items).count == 2)
    }

    @Test("Location, species, care type, and caretaker filters all narrow")
    func eachFilterNarrows() {
        let kitchen = UUID()
        let sitter = UUID()

        let items = [
            item(
                plant(name: "Kitchen fern", species: "Nephrolepis", locationID: kitchen),
                careTypes: [.water, .mist],
                caretakers: [sitter]
            ),
            item(
                plant(name: "Hall palm", species: "Chamaedorea"),
                careTypes: [.water]
            )
        ]

        var byLocation = PlantCollectionQuery.default
        byLocation.locationIDs = [kitchen]
        #expect(apply(byLocation, items) == ["Kitchen fern"])

        var bySpecies = PlantCollectionQuery.default
        bySpecies.species = ["Chamaedorea"]
        #expect(apply(bySpecies, items) == ["Hall palm"])

        var byCareType = PlantCollectionQuery.default
        byCareType.careTypes = [.mist]
        #expect(apply(byCareType, items) == ["Kitchen fern"])

        var byCaretaker = PlantCollectionQuery.default
        byCaretaker.caretakerIDs = [sitter]
        #expect(apply(byCaretaker, items) == ["Kitchen fern"])
    }

    @Test("The species filter is case-insensitive")
    func speciesFilterIgnoresCase() {
        let items = [item(plant(name: "Fern", species: "Nephrolepis"))]
        var query = PlantCollectionQuery.default
        query.species = ["nephrolepis"]
        #expect(apply(query, items) == ["Fern"])
    }

    @Test("Anything already waiting falls inside every due window")
    func waitingTasksAreInsideEveryDueWindow() {
        // A plant that needed water yesterday certainly needs it in the next
        // seven days; excluding it would hide exactly the plant the user is
        // looking for.
        let items = [
            item(plant(name: "Waiting"), nextDue: now.addingTimeInterval(-86_400 * 3)),
            item(plant(name: "Tomorrow"), nextDue: now.addingTimeInterval(86_400)),
            item(plant(name: "Next month"), nextDue: now.addingTimeInterval(86_400 * 40)),
            item(plant(name: "Nothing scheduled"))
        ]

        var query = PlantCollectionQuery.default
        query.dueWithinDays = 7
        #expect(apply(query, items) == ["Tomorrow", "Waiting"])
    }

    // MARK: - isFiltering

    @Test("isFiltering reflects only things that hide plants")
    func isFilteringIgnoresSortAndMode() {
        #expect(!PlantCollectionQuery.default.isFiltering)

        var sorted = PlantCollectionQuery.default
        sorted.sortOrder = .nextDue
        sorted.mode = .grid
        // Neither hides a plant, so neither should raise the "filters are on"
        // banner.
        #expect(!sorted.isFiltering)

        var searched = PlantCollectionQuery.default
        searched.searchText = "fern"
        #expect(searched.isFiltering)

        var byRoom = PlantCollectionQuery.default
        byRoom.locationIDs = [UUID()]
        #expect(byRoom.isFiltering)
        #expect(byRoom.activeFilterCount == 1)
    }

    @Test("Clearing filters keeps sort order and presentation mode")
    func clearingFiltersKeepsPreferences() {
        var query = PlantCollectionQuery.default
        query.sortOrder = .lastCare
        query.mode = .grid
        query.locationIDs = [UUID()]
        query.searchText = "fern"

        let cleared = query.clearingFilters()
        #expect(!cleared.isFiltering)
        // Sort order and grid/list are how the user likes to look at their
        // collection, not filters, and resetting them would be an unasked-for
        // change.
        #expect(cleared.sortOrder == .lastCare)
        #expect(cleared.mode == .grid)
    }

    // MARK: - Sorting

    @Test("Sorting by next due puts unscheduled plants last")
    func unscheduledPlantsSortLastByDueDate() {
        let items = [
            item(plant(name: "Nothing scheduled")),
            item(plant(name: "Later"), nextDue: now.addingTimeInterval(86_400 * 5)),
            item(plant(name: "Sooner"), nextDue: now.addingTimeInterval(86_400))
        ]

        var query = PlantCollectionQuery.default
        query.sortOrder = .nextDue
        #expect(apply(query, items) == ["Sooner", "Later", "Nothing scheduled"])
    }

    @Test("Sorting by last care puts the longest-ago first")
    func longestSinceCareSortsFirst() {
        let items = [
            item(plant(name: "Yesterday"), lastCare: now.addingTimeInterval(-86_400)),
            item(plant(name: "Never")),
            item(plant(name: "Last month"), lastCare: now.addingTimeInterval(-86_400 * 30))
        ]

        var query = PlantCollectionQuery.default
        query.sortOrder = .lastCare
        #expect(apply(query, items) == ["Never", "Last month", "Yesterday"])
    }

    @Test("Sorting by acquired date puts the newest first")
    func newestAcquiredSortsFirst() {
        let items = [
            item(plant(name: "Old", acquired: now.addingTimeInterval(-86_400 * 400))),
            item(plant(name: "Unknown")),
            item(plant(name: "New", acquired: now.addingTimeInterval(-86_400 * 3)))
        ]

        var query = PlantCollectionQuery.default
        query.sortOrder = .acquiredDate
        #expect(apply(query, items) == ["New", "Old", "Unknown"])
    }

    @Test("Duplicate names still have a stable order")
    func duplicateNamesAreStable() {
        // Two plants genuinely called the same thing is normal, and a list that
        // reshuffles them between refreshes looks broken (PLANT_CARE.md §15).
        let first = item(plant(name: "Fern"))
        let second = item(plant(name: "Fern"))

        let forwards = PlantCollectionFilter.sort([first, second], by: .name)
        let backwards = PlantCollectionFilter.sort([second, first], by: .name)
        #expect(forwards.map(\.id) == backwards.map(\.id))
    }

    @Test("A nickname is what the collection sorts and searches by")
    func nicknameIsTheDisplayName() {
        let items = [
            item(plant(name: "Zebra plant", nickname: "Alfie")),
            item(plant(name: "Aloe"))
        ]
        #expect(apply(.default, items) == ["Alfie", "Aloe"])
    }
}
