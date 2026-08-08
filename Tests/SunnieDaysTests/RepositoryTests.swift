import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Repository behaviour against a real SwiftData store held in memory.
///
/// These run the same code paths as the on-disk store — same schema, same
/// contexts, same predicates — without touching the file system, so idempotency
/// is proven against SwiftData rather than against a hand-written fake.
@Suite("SwiftData repositories")
struct RepositoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.make(storage: .inMemory)
    }

    private func samplePlant(name: String = "Monstera") -> Plant {
        Plant(
            name: name,
            speciesName: "Monstera deliciosa",
            status: .active,
            qrToken: UUID().uuidString,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    private func careEvent(
        plantID: UUID,
        performedAt: Date,
        device: String = "phone",
        note: String? = nil
    ) -> PlantCareEvent {
        PlantCareEvent(
            plantID: plantID,
            careType: .water,
            performedAt: performedAt,
            sourceDeviceID: DeviceID(rawValue: device),
            note: note,
            actionKey: ActionKeyFactory.plantCare(
                plantID: plantID, careType: .water, performedAt: performedAt
            ),
            createdAt: Date()
        )
    }

    // MARK: - Plants

    @Test("A plant round-trips through storage")
    func plantRoundTrips() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        let plant = samplePlant()

        try await repository.save(plant)
        let loaded = try await repository.plant(id: plant.id)

        #expect(loaded?.name == "Monstera")
        #expect(loaded?.speciesName == "Monstera deliciosa")
        #expect(loaded?.qrToken == plant.qrToken)
    }

    @Test("Saving an existing plant updates rather than duplicating it")
    func savingUpdatesInPlace() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        var plant = samplePlant()
        try await repository.save(plant)

        plant.nickname = "Monty"
        try await repository.save(plant)

        let all = try await repository.allPlants(includingArchived: true)
        #expect(all.count == 1)
        #expect(all.first?.displayName == "Monty")
    }

    @Test("Archived plants are hidden by default but never deleted")
    func archivingHidesWithoutDeleting() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        let plant = samplePlant()
        try await repository.save(plant)

        try await repository.archive(plantID: plant.id, at: Date())

        let active = try await repository.allPlants(includingArchived: false)
        let all = try await repository.allPlants(includingArchived: true)

        #expect(active.isEmpty)
        #expect(all.count == 1)
        #expect(all.first?.status == .archived)
    }

    @Test("Archiving a plant stops its schedules producing tasks")
    func archivingDisablesSchedules() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        let plant = samplePlant()
        try await repository.save(plant)
        try await repository.save(PlantCareSchedule(
            plantID: plant.id,
            careType: .water,
            recurrence: .everyDays(7),
            nextDueDate: Date()
        ))

        try await repository.archive(plantID: plant.id, at: Date())

        let schedules = try await repository.schedules(forPlantID: plant.id)
        #expect(schedules.allSatisfy { !$0.isEnabled })
        #expect(schedules.allSatisfy { $0.nextDueDate == nil })
        #expect(try await repository.enabledSchedules().isEmpty)
    }

    @Test("Archiving a plant that does not exist reports not-found")
    func archivingMissingPlantThrows() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())

        await #expect(throws: DomainError.self) {
            try await repository.archive(plantID: UUID(), at: Date())
        }
    }

    @Test("Schedules round-trip including their seasonal modifier")
    func scheduleRoundTrips() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        let plant = samplePlant()
        try await repository.save(plant)

        let schedule = PlantCareSchedule(
            plantID: plant.id,
            careType: .mist,
            recurrence: .everyDays(3),
            seasonalModifier: SeasonalModifier(
                springMultiplier: 1, summerMultiplier: 0.5,
                autumnMultiplier: 1.2, winterMultiplier: 2
            ),
            preferredHour: 7
        )
        try await repository.save(schedule)

        let loaded = try #require(try await repository.schedule(id: schedule.id))
        #expect(loaded.careType == .mist)
        #expect(loaded.recurrence.intervalDays == 3)
        #expect(loaded.seasonalModifier.winterMultiplier == 2)
        #expect(loaded.preferredHour == 7)
    }

    @Test("A manual schedule survives the round trip as manual")
    func manualScheduleRoundTrips() async throws {
        let repository = SwiftDataPlantRepository(modelContainer: try makeContainer())
        let plant = samplePlant()
        try await repository.save(plant)

        let schedule = PlantCareSchedule(
            plantID: plant.id, careType: .prune, recurrence: .manual
        )
        try await repository.save(schedule)

        let loaded = try #require(try await repository.schedule(id: schedule.id))
        #expect(loaded.recurrence == .manual)
    }

    // MARK: - Care events

    @Test("A care event round-trips through storage")
    func careEventRoundTrips() async throws {
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let event = careEvent(plantID: plantID, performedAt: Date(), note: "Fully soaked")

        let outcome = try await repository.save(event)

        #expect(outcome.wasCreated)
        let loaded = try await repository.event(actionKey: event.actionKey)
        #expect(loaded?.note == "Fully soaked")
        #expect(loaded?.careType == .water)
    }

    @Test("The same action key stores exactly one event")
    func duplicateActionKeyStoresOnce() async throws {
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let performedAt = Date()
        let event = careEvent(plantID: plantID, performedAt: performedAt)

        let first = try await repository.save(event)
        let second = try await repository.save(event)

        #expect(first.wasCreated)
        #expect(!second.wasCreated)
        #expect(second.value.id == first.value.id)

        let all = try await repository.events(forPlantID: plantID, limit: 50)
        #expect(all.count == 1)
    }

    @Test("Watch and phone recording the same watering store one event")
    func watchAndPhoneCollapseToOneEvent() async throws {
        // Same plant, same care, seconds apart, different devices. The action key
        // ignores both the device and the exact second, so this is one watering.
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let watchTime = Date()

        let fromWatch = careEvent(plantID: plantID, performedAt: watchTime, device: "watch")
        let fromPhone = careEvent(
            plantID: plantID,
            performedAt: watchTime.addingTimeInterval(12),
            device: "phone"
        )

        _ = try await repository.save(fromWatch)
        let second = try await repository.save(fromPhone)

        #expect(!second.wasCreated)
        #expect(try await repository.events(forPlantID: plantID, limit: 50).count == 1)
    }

    @Test("Concurrent saves of the same action still store one event")
    func concurrentSavesStoreOnce() async throws {
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let event = careEvent(plantID: plantID, performedAt: Date())

        // The repository actor serializes these, which is what makes
        // check-then-insert safe without a database unique constraint.
        async let first = repository.save(event)
        async let second = repository.save(event)
        let outcomes = try await [first, second]

        #expect(outcomes.filter(\.wasCreated).count == 1)
        #expect(try await repository.events(forPlantID: plantID, limit: 50).count == 1)
    }

    @Test("Most recent event is found per care type, not per plant")
    func mostRecentEventIsPerCareType() async throws {
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let older = Date().addingTimeInterval(-60 * 60 * 24 * 7)
        let newer = Date()

        _ = try await repository.save(careEvent(plantID: plantID, performedAt: older))
        _ = try await repository.save(PlantCareEvent(
            plantID: plantID,
            careType: .mist,
            performedAt: newer,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            actionKey: ActionKeyFactory.plantCare(
                plantID: plantID, careType: .mist, performedAt: newer
            ),
            createdAt: newer
        ))

        let lastWater = try await repository.mostRecentEvent(
            forPlantID: plantID, careType: .water
        )
        let lastMist = try await repository.mostRecentEvent(
            forPlantID: plantID, careType: .mist
        )

        #expect(lastWater?.careType == .water)
        #expect(lastMist?.careType == .mist)
        #expect(lastWater?.performedAt != lastMist?.performedAt)
    }

    @Test("History is returned newest first and respects the limit")
    func historyIsOrderedAndLimited() async throws {
        let repository = SwiftDataPlantCareEventRepository(
            modelContainer: try makeContainer()
        )
        let plantID = UUID()
        let base = Date()

        for day in 0..<5 {
            _ = try await repository.save(careEvent(
                plantID: plantID,
                performedAt: base.addingTimeInterval(-Double(day) * 86_400)
            ))
        }

        let recent = try await repository.events(forPlantID: plantID, limit: 3)

        #expect(recent.count == 3)
        #expect(recent[0].performedAt > recent[1].performedAt)
        #expect(recent[1].performedAt > recent[2].performedAt)
    }

    // MARK: - Progression

    @Test("Progression events are stored once per deterministic key")
    func progressionEventsAreIdempotent() async throws {
        let repository = SwiftDataProgressionRepository(
            modelContainer: try makeContainer()
        )
        let event = ProgressionEvent(
            type: .plantCareCompleted,
            sourceEntityID: UUID(),
            occurredAt: Date(),
            deterministicKey: "progression.v1|plantCareCompleted|test",
            experienceAwarded: 10
        )

        let first = try await repository.save(event)
        let second = try await repository.save(event)

        #expect(first.wasCreated)
        #expect(!second.wasCreated)
    }

    @Test("A progression profile is created on first read")
    func progressionProfileIsCreatedLazily() async throws {
        let repository = SwiftDataProgressionRepository(
            modelContainer: try makeContainer()
        )

        let profile = try await repository.profile()

        #expect(profile.level == 1)
        #expect(profile.experience == 0)
    }

    @Test("Reward grants are stored once per deterministic key")
    func rewardGrantsAreIdempotent() async throws {
        let repository = SwiftDataProgressionRepository(
            modelContainer: try makeContainer()
        )
        let grant = RewardGrant(
            rewardID: "sunnie.reward.collectible.wateringCan",
            grantedAt: Date(),
            sourceEventID: UUID(),
            deterministicKey: "reward.v1|wateringCan|firstTime"
        )

        _ = try await repository.save(grant)
        let second = try await repository.save(grant)

        #expect(!second.wasCreated)
        #expect(try await repository.grants(limit: 10).count == 1)
    }

    // MARK: - Preferences

    @Test("Preferences round-trip and default cleanly when absent")
    func preferencesRoundTrip() async throws {
        let repository = SwiftDataPreferencesRepository(
            modelContainer: try makeContainer()
        )

        let initial = try await repository.preferences()
        #expect(initial.nicknameProbability == 0.05)
        #expect(initial.dietaryRuleIDs.contains(DietaryRule.noEggs))

        var updated = initial
        updated.activeThemeID = ThemeCatalog.travelScrapbookID
        updated.automaticDayCycle = false
        updated.dayCycleOverride = .night
        try await repository.save(updated)

        let loaded = try await repository.preferences()
        #expect(loaded.activeThemeID == ThemeCatalog.travelScrapbookID)
        #expect(loaded.dayCycleOverride == .night)
    }

    @Test("The profile is seeded with a name and nickname on first read")
    func profileIsSeeded() async throws {
        let repository = SwiftDataPreferencesRepository(
            modelContainer: try makeContainer()
        )

        let profile = try await repository.profile()

        #expect(profile.displayName == DefaultProfile.displayName)
        #expect(profile.preferredNickname == DefaultProfile.nickname)
    }

    // MARK: - Pending Watch actions

    @Test("The Watch queue rejects a redelivered action")
    func watchQueueDedupes() async throws {
        let repository = SwiftDataPendingWatchActionRepository(
            modelContainer: try makeContainer()
        )
        let action = PendingWatchAction(
            payloadData: Data([1, 2, 3]),
            createdAt: Date(),
            sourceDeviceID: DeviceID(rawValue: "watch"),
            actionKey: ActionKey(rawValue: "test.key")
        )

        let first = try await repository.enqueue(action)
        let second = try await repository.enqueue(action)

        #expect(first.wasCreated)
        #expect(!second.wasCreated)
        #expect(try await repository.unprocessedActions().count == 1)
    }

    @Test("A processed action leaves the pending list but stays on record")
    func processedActionsLeavePendingList() async throws {
        let repository = SwiftDataPendingWatchActionRepository(
            modelContainer: try makeContainer()
        )
        let action = PendingWatchAction(
            payloadData: Data([1]),
            createdAt: Date(),
            sourceDeviceID: DeviceID(rawValue: "watch"),
            actionKey: ActionKey(rawValue: "test.key")
        )
        _ = try await repository.enqueue(action)

        try await repository.markProcessed(actionID: action.id, at: Date())

        #expect(try await repository.unprocessedActions().isEmpty)
        // Re-enqueueing is still refused: the record is retained, not dropped.
        let again = try await repository.enqueue(action)
        #expect(!again.wasCreated)
    }

    // MARK: - Trips

    /// The unarchived-trips fetch must return a trip that has no status override.
    ///
    /// Which is every ordinary trip: an override is the exception. The predicate
    /// used to read `statusOverrideRaw != archived`, and SQL answers NULL rather
    /// than true when the column is null, so this returned nothing at all for a
    /// store full of trips — emptying the travel list, the Watch context, the
    /// widget snapshot, and Sunnie's Home from one line.
    ///
    /// Tested here, at the repository, because the three integration tests that
    /// caught it could only report a missing panel several layers away.
    @Test("Trips without a status override are not filtered out")
    func unarchivedTripsIncludeTripsWithNoOverride() async throws {
        let repository = SwiftDataTravelRepository(modelContainer: try makeContainer())
        let now = Date()

        let ordinary = Trip(
            title: "Lisbon",
            type: .personal,
            startsAt: now.addingTimeInterval(86_400 * 4),
            endsAt: now.addingTimeInterval(86_400 * 8),
            homeTimeZoneID: "UTC",
            createdAt: now,
            modifiedAt: now
        )
        try await repository.save(ordinary)

        let visible = try await repository.trips(includingArchived: false)
        #expect(visible.contains { $0.id == ordinary.id })
    }

    @Test("An archived trip is still excluded")
    func archivedTripsAreExcluded() async throws {
        let repository = SwiftDataTravelRepository(modelContainer: try makeContainer())
        let now = Date()

        var archived = Trip(
            title: "Last year",
            type: .personal,
            homeTimeZoneID: "UTC",
            createdAt: now,
            modifiedAt: now
        )
        archived.statusOverride = .archived
        try await repository.save(archived)

        // The fix widened the predicate, so this is the half that must not have
        // been widened with it.
        let visible = try await repository.trips(includingArchived: false)
        #expect(!visible.contains { $0.id == archived.id })
        #expect(try await repository.trips(includingArchived: true)
            .contains { $0.id == archived.id })
    }
}
