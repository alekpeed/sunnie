import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Regression coverage for what the first simulator run exposed.
///
/// The app seeds a small starter jungle on first launch so there is something to
/// act on. It worked — the plants were written, and the Jungle tab showed them.
/// Today did not, because it had already built its summary from the empty store
/// the seed was about to fill, and nothing told it to look again. A brand-new
/// user was shown "No plants yet" above five plants that existed, until they
/// changed tabs and came back.
///
/// Two things had to be true to fix it, and both are asserted here: seeding has
/// to *say* it changed the jungle, and a summary built against the store as it
/// was must not be able to overwrite one built after the change.
@MainActor
@Suite("First launch")
struct FirstLaunchTests {

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

    private func makeDependencies() throws -> AppDependencies {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        return AppDependencies(
            modelContainer: container,
            clock: FixedClock(
                now: Self.referenceDate,
                timeZone: TimeZone(identifier: "UTC")!
            ),
            enableWatchConnectivity: false
        )
    }

    /// Collects what the bus delivered, from whatever context delivers it.
    private actor EventCollector {
        private(set) var received: [DomainEventType] = []

        func record(_ event: DomainEvent) {
            received.append(event.type)
        }
    }

    @Test("Seeding the sample jungle announces that plants were added")
    func seedingPublishesPlantAdded() async throws {
        let dependencies = try makeDependencies()
        let collector = EventCollector()

        let token = await dependencies.eventBus.subscribe { event in
            await collector.record(event)
        }
        defer { Task { await dependencies.eventBus.unsubscribe(token) } }

        await SampleData.seedIfNeeded(dependencies: dependencies)

        // This is the event Today listens for. Without it, invalidating the
        // summary cache changes nothing on screen, because nothing re-reads.
        let received = await collector.received
        #expect(received.contains(.plantAdded))
    }

    /// The specific sequence that produced the bug, in order.
    @Test("Today's summary reflects the seeded jungle even when read first")
    func summaryIsCorrectAfterSeedingFollowsAnEmptyRead() async throws {
        let dependencies = try makeDependencies()

        // Today's first read, against a store the seed has not filled yet.
        let beforeSeeding = try await dependencies.summaryProvider.summary()
        #expect(beforeSeeding.totalActivePlants == 0)

        await SampleData.seedIfNeeded(dependencies: dependencies)

        // Anyone asking after the seed must be told about the plants, not
        // handed the empty summary cached moments earlier.
        let afterSeeding = try await dependencies.summaryProvider.summary()
        #expect(afterSeeding.totalActivePlants > 0)
        #expect(afterSeeding.actionableTasks.isEmpty == false)
    }

    /// Seeding runs once. A second launch must not double the jungle.
    @Test("Seeding a second time changes nothing")
    func seedingIsIdempotent() async throws {
        let dependencies = try makeDependencies()

        await SampleData.seedIfNeeded(dependencies: dependencies)
        let afterFirst = try await dependencies.summaryProvider.summary()

        await SampleData.seedIfNeeded(dependencies: dependencies)
        await dependencies.summaryProvider.invalidate()
        let afterSecond = try await dependencies.summaryProvider.summary()

        #expect(afterFirst.totalActivePlants == afterSecond.totalActivePlants)
    }

    /// A rebuild racing an invalidation must still leave the cache correct.
    ///
    /// Honest about its own limits: the actor serialises these, so the rebuild
    /// may well finish before the invalidation is ever admitted, and this cannot
    /// *force* the interleaving that caused the bug. What it does hold is the
    /// property that matters — however the two are ordered, what a later reader
    /// gets describes the store as it actually is. Deterministic coverage of the
    /// guard itself would need a repository fixture that blocks mid-read, which
    /// is worth building when there is a second reason to want one.
    @Test("A summary invalidated mid-rebuild is not the one that survives")
    func staleRebuildDoesNotOverwriteFreshData() async throws {
        let dependencies = try makeDependencies()

        async let rebuild = dependencies.summaryProvider.rebuild()
        await dependencies.summaryProvider.invalidate()
        _ = try await rebuild

        await SampleData.seedIfNeeded(dependencies: dependencies)

        let summary = try await dependencies.summaryProvider.summary()
        #expect(summary.totalActivePlants > 0)
    }
}
