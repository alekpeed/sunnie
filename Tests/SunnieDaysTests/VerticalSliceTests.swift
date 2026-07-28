import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// End-to-end coverage of the first vertical slice.
///
/// These exercise the real composition root against an in-memory store: the same
/// use case, repositories, progression engine, summary provider, and message
/// service the app runs, with only storage and the clock substituted.
@MainActor
@Suite("First vertical slice")
struct VerticalSliceTests {

    private static let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = 10
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()

    private func makeDependencies(
        now: Date = referenceDate
    ) throws -> AppDependencies {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        return AppDependencies(
            modelContainer: container,
            clock: FixedClock(now: now, timeZone: TimeZone(identifier: "UTC")!),
            enableWatchConnectivity: false
        )
    }

    /// One plant with a watering schedule that came due two days ago.
    @discardableResult
    private func seedWaitingPlant(
        _ dependencies: AppDependencies,
        intervalDays: Int = 7
    ) async throws -> (plant: Plant, schedule: PlantCareSchedule) {
        let now = dependencies.clock.now
        let plant = Plant(
            name: "Monstera",
            speciesName: "Monstera deliciosa",
            status: .active,
            qrToken: UUID().uuidString,
            createdAt: now,
            modifiedAt: now
        )
        try await dependencies.plantRepository.save(plant)

        let schedule = PlantCareSchedule(
            plantID: plant.id,
            careType: .water,
            recurrence: .everyDays(intervalDays),
            preferredHour: 9,
            isEnabled: true,
            nextDueDate: now.addingTimeInterval(-2 * 86_400)
        )
        try await dependencies.plantRepository.save(schedule)
        await dependencies.summaryProvider.invalidate()

        return (plant, schedule)
    }

    // MARK: - The documented flow

    @Test("Today surfaces a waiting plant, and logging care clears it")
    func completeFlowFromTodayToUpdatedSummary() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        // 1–4: the summary carries the due task through to the card.
        let before = try await dependencies.summaryProvider.summary()
        #expect(before.actionableTasks.count == 1)
        let task = try #require(before.actionableTasks.first)
        #expect(task.plantDisplayName == "Monstera")
        #expect(task.urgency == .waiting)
        #expect(task.daysWaiting == 2)

        // 5–13: log the care.
        let result = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            scheduleID: seeded.schedule.id
        )

        #expect(result.wasNewlyRecorded)
        #expect(result.event.careType == .water)
        #expect(result.progression.event != nil)
        #expect(result.message != nil)

        // 9: the schedule moved forward to the interval, at the preferred hour.
        let updatedSchedule = try #require(result.updatedSchedule)
        let nextDue = try #require(updatedSchedule.nextDueDate)
        #expect(nextDue > dependencies.clock.now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.hour, from: nextDue) == 9)

        // 12: Today no longer shows it.
        let after = try await dependencies.summaryProvider.summary()
        #expect(after.actionableTasks.isEmpty)
        #expect(after.totalActivePlants == 1)
    }

    @Test("The care event survives and is readable afterwards")
    func careEventIsPersisted() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        _ = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            note: "A good long drink"
        )

        let history = try await dependencies.careEventRepository
            .events(forPlantID: seeded.plant.id, limit: 10)

        #expect(history.count == 1)
        #expect(history.first?.note == "A good long drink")
    }

    @Test("Progression is awarded once and never taken away")
    func progressionAwardedOnce() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        _ = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .water
        )
        let afterFirst = try await dependencies.progressionRepository.profile()

        // Same minute, same plant, same care: the same real action.
        _ = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .water
        )
        let afterSecond = try await dependencies.progressionRepository.profile()

        #expect(afterFirst.experience == 10)
        #expect(afterSecond.experience == 10)
    }

    @Test("A duplicated Watch action creates exactly one care event")
    func duplicateWatchActionCreatesOneEvent() async throws {
        // The scenario FIRST_VERTICAL_SLICE.md requires: the Watch's transfer is
        // delivered twice. Both carry the same key, generated on the wrist.
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        let performedAt = dependencies.clock.now
        let watchKey = ActionKeyFactory.plantCare(
            plantID: seeded.plant.id, careType: .water, performedAt: performedAt
        )

        let first = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            performedAt: performedAt,
            scheduleID: seeded.schedule.id,
            actionKey: watchKey,
            sourceDeviceID: DeviceID(rawValue: "watch")
        )
        let redelivered = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            performedAt: performedAt,
            scheduleID: seeded.schedule.id,
            actionKey: watchKey,
            sourceDeviceID: DeviceID(rawValue: "watch")
        )

        #expect(first.wasNewlyRecorded)
        #expect(!redelivered.wasNewlyRecorded)
        #expect(first.event.id == redelivered.event.id)

        let history = try await dependencies.careEventRepository
            .events(forPlantID: seeded.plant.id, limit: 10)
        #expect(history.count == 1)
    }

    @Test("A redelivered action does not advance the schedule a second time")
    func redeliveryDoesNotDoubleAdvanceSchedule() async throws {
        // Advancing twice would push the next watering a full extra interval into
        // the future — a silent way for a plant to be forgotten.
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies, intervalDays: 7)

        let performedAt = dependencies.clock.now
        let key = ActionKeyFactory.plantCare(
            plantID: seeded.plant.id, careType: .water, performedAt: performedAt
        )

        let first = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            performedAt: performedAt,
            scheduleID: seeded.schedule.id,
            actionKey: key
        )
        let firstDue = try #require(first.updatedSchedule?.nextDueDate)

        _ = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            performedAt: performedAt,
            scheduleID: seeded.schedule.id,
            actionKey: key
        )

        let stored = try #require(
            try await dependencies.plantRepository.schedule(id: seeded.schedule.id)
        )
        #expect(stored.nextDueDate == firstDue)
    }

    @Test("The whole flow completes with no Watch and no network")
    func offlineCompletionWorks() async throws {
        // Nothing in this test can reach a network or a paired device, which is
        // the point: an ordinary record must never depend on either.
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        #expect(!dependencies.watchSync.isSupported)

        let result = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .water
        )

        #expect(result.wasNewlyRecorded)
        #expect(result.progression.event != nil)
        let summary = try await dependencies.summaryProvider.summary()
        #expect(summary.actionableTasks.isEmpty)
    }

    @Test("Logging care for a plant that no longer exists reports not-found")
    func missingPlantIsReported() async throws {
        let dependencies = try makeDependencies()

        await #expect(throws: DomainError.self) {
            try await dependencies.logPlantCare(plantID: UUID(), careType: .water)
        }
    }

    @Test("A timestamp far in the future is refused")
    func futureTimestampIsRefused() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        await #expect(throws: DomainError.self) {
            try await dependencies.logPlantCare(
                plantID: seeded.plant.id,
                careType: .water,
                performedAt: dependencies.clock.now.addingTimeInterval(60 * 60)
            )
        }
    }

    @Test("Small clock skew between devices is tolerated")
    func smallClockSkewIsAccepted() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        let result = try await dependencies.logPlantCare(
            plantID: seeded.plant.id,
            careType: .water,
            performedAt: dependencies.clock.now.addingTimeInterval(60)
        )

        #expect(result.wasNewlyRecorded)
    }

    @Test("Care with no matching schedule is still recorded")
    func careWithoutScheduleIsRecorded() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        // Pruning has no schedule on this plant.
        let result = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .prune
        )

        #expect(result.wasNewlyRecorded)
        #expect(result.updatedSchedule == nil)
        // The watering task is untouched by an unrelated care action.
        let summary = try await dependencies.summaryProvider.summary()
        #expect(summary.actionableTasks.count == 1)
    }

    @Test("Sunnie's reaction to completed care is warm and complete")
    func sunnieReactionIsUsable() async throws {
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        let result = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .water
        )

        let message = try #require(result.message)
        #expect(message.category == .careCompleted)
        #expect(!message.text.isEmpty)
        #expect(!message.text.contains("{name}"))
        #expect(ContentValidator.toneIssues(
            in: message.text, contentID: message.id.rawValue
        ).isEmpty)
    }

    @Test("Logging care publishes a typed domain event")
    func domainEventIsPublished() async throws {
        // This is how Today learns to refresh without importing the Jungle
        // feature.
        let dependencies = try makeDependencies()
        let seeded = try await seedWaitingPlant(dependencies)

        let recorder = EventRecorder()
        await dependencies.eventBus.subscribe { event in
            await recorder.record(event)
        }

        _ = try await dependencies.logPlantCare(
            plantID: seeded.plant.id, careType: .water
        )

        let events = await recorder.events
        #expect(events.contains { $0.type == .plantCareLogged })
        #expect(events.first?.sourceEntityID == seeded.plant.id)
    }

    @Test("Sample data seeds once and never overwrites existing plants")
    func sampleDataSeedsOnce() async throws {
        let dependencies = try makeDependencies()

        await SampleData.seedIfNeeded(dependencies: dependencies)
        let afterFirst = try await dependencies.plantRepository
            .allPlants(includingArchived: true)

        await SampleData.seedIfNeeded(dependencies: dependencies)
        let afterSecond = try await dependencies.plantRepository
            .allPlants(includingArchived: true)

        #expect(!afterFirst.isEmpty)
        #expect(afterFirst.count == afterSecond.count)
    }

    @Test("Every seeded plant has a unique QR token")
    func seededQRTokensAreUnique() async throws {
        let dependencies = try makeDependencies()
        await SampleData.seedIfNeeded(dependencies: dependencies)

        let plants = try await dependencies.plantRepository
            .allPlants(includingArchived: true)
        let tokens = Set(plants.map(\.qrToken))

        #expect(tokens.count == plants.count)
        // The token must not be the plant's own identifier, or a printed code
        // would leak record IDs (PLANT_CARE.md §11).
        #expect(plants.allSatisfy { $0.qrToken != $0.id.uuidString })
    }
}

/// Collects published events for assertion.
actor EventRecorder {
    private(set) var events: [DomainEvent] = []

    func record(_ event: DomainEvent) {
        events.append(event)
    }
}
