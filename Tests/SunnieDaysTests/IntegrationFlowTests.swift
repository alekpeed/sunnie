import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Phase 9 behaviour against a real in-memory store: hydration, mindful minutes,
/// Watch actions arriving from the wrist, and the widget snapshot.
///
/// Health itself is not exercised here — there is no HealthKit store in a test
/// process, and `UnavailableHealthService` is what a device with Health turned
/// off behaves like anyway. That is deliberate: every path below is the path a
/// user who declined the permission takes, and it must work.
@Suite("Integration flows")
struct IntegrationFlowTests {

    /// 2026-02-02T12:00:00Z. Noon UTC keeps a day's worth of activity inside one
    /// local day whatever zone the test machine is set to.
    private static let referenceDate = Date(timeIntervalSince1970: 1_770_033_600)

    @Test("Intent handoff is durable, expiring, and consumed once")
    func intentHandoffIsOneShot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IntentHandoffStore(directory: directory)
        let route = try #require(URL(string: "sunniedays://today"))

        try store.save(routeURL: route, tellSunnieText: "Watered Fern", now: Self.referenceDate)
        let handoff = try #require(store.take(now: Self.referenceDate.addingTimeInterval(1)))
        #expect(handoff.routeURL == route)
        #expect(handoff.tellSunnieText == "Watered Fern")
        #expect(store.take(now: Self.referenceDate.addingTimeInterval(2)) == nil)
    }

    @MainActor
    private func makeDependencies(
        now: Date = IntegrationFlowTests.referenceDate
    ) throws -> AppDependencies {
        AppDependencies(
            modelContainer: try ModelContainerFactory.make(storage: .inMemory),
            clock: FixedClock(now: now),
            enableWatchConnectivity: false
        )
    }

    // MARK: - Hydration

    @Test("Water is recorded locally whether or not Health is available")
    @MainActor
    func hydrationWorksWithoutHealth() async throws {
        let dependencies = try makeDependencies()
        // Deliberately asserts nothing about whether Health exists here.
        //
        // This used to require `!isAvailable`, on the reasoning that a test
        // process has no Health store. It does: `isAvailable` is true on an
        // iPhone simulator and on a device alike, so the assertion was false
        // wherever this test could actually run, and it contradicted the
        // sentence in its own name — the claim is that water is recorded
        // locally *whether or not* Health is available, which is a claim about
        // both branches and must not be pinned to one.
        //
        // What follows holds either way: the entry is written locally, carries
        // no HealthKit sample id while no type is enabled, and counts towards
        // today's total.

        let entry = try await dependencies.manageHealth.logWater(millilitres: 250)
        #expect(entry.millilitres == 250)
        #expect(entry.healthKitSampleID == nil)
        #expect(await dependencies.manageHealth.todayHydration() == 250)
    }

    @Test("Two taps in the same minute at the same amount are one glass")
    @MainActor
    func hydrationDoubleTapIsOneEntry() async throws {
        let dependencies = try makeDependencies()

        _ = try await dependencies.manageHealth.logWater(millilitres: 250)
        _ = try await dependencies.manageHealth.logWater(millilitres: 250)

        #expect(await dependencies.manageHealth.todayHydration() == 250)
    }

    @Test("Two different amounts in the same minute are two entries")
    @MainActor
    func differentAmountsAreDistinct() async throws {
        let dependencies = try makeDependencies()

        _ = try await dependencies.manageHealth.logWater(millilitres: 250)
        _ = try await dependencies.manageHealth.logWater(millilitres: 500)

        #expect(await dependencies.manageHealth.todayHydration() == 750)
    }

    @Test("An absurd amount is bounded rather than stored")
    @MainActor
    func hydrationIsBounded() async throws {
        let dependencies = try makeDependencies()
        let entry = try await dependencies.manageHealth.logWater(millilitres: 50_000)
        #expect(entry.millilitres == HydrationLog.maximumSingleEntry)
    }

    @Test("Nothing is written to Health until the type is turned on")
    @MainActor
    func healthWritesNeedThePreference() async throws {
        let dependencies = try makeDependencies()
        #expect(await dependencies.manageHealth.enabledTypes().isEmpty)

        let entry = try await dependencies.manageHealth.logWater(millilitres: 250)
        #expect(entry.healthKitSampleID == nil)

        // And the catch-up pass is a no-op rather than an attempt.
        await dependencies.manageHealth.catchUpHealthWrites()
        let pending = try await dependencies.hydrationRepository.unwrittenLogs(limit: 10)
        #expect(pending.contains { $0.id == entry.id })
    }

    @Test("Turning a type off leaves the entries alone")
    @MainActor
    func disablingAHealthTypeKeepsTheData() async throws {
        let dependencies = try makeDependencies()

        await dependencies.manageHealth.enable(.dietaryWater)
        #expect(await dependencies.manageHealth.enabledTypes().contains(.dietaryWater))

        _ = try await dependencies.manageHealth.logWater(millilitres: 500)
        await dependencies.manageHealth.disable(.dietaryWater)

        #expect(!(await dependencies.manageHealth.enabledTypes().contains(.dietaryWater)))
        // The record is the user's; the permission was only ever about mirroring.
        #expect(await dependencies.manageHealth.todayHydration() == 500)
    }

    // MARK: - Mindful minutes

    @Test("A practice that was stopped early is never written as a mindful session")
    @MainActor
    func onlyCompletedPracticesCount() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageHealth.enable(.mindfulSession)

        let session = try await dependencies.manageWellnessSession.start(
            type: .breathing,
            practiceID: "sunnie.breathing.longerExhale",
            plannedDuration: 120
        )
        let finished = try await dependencies.manageWellnessSession.finish(
            session, completion: .endedEarly
        )

        #expect(finished.healthKitSampleID == nil)
        #expect(await dependencies.manageHealth.recordMindfulSession(finished) == nil)
    }

    @Test("Calm sounds are not a mindful session")
    @MainActor
    func onlyBreathingAndMeditationCount() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageHealth.enable(.mindfulSession)

        let session = try await dependencies.manageWellnessSession.start(
            type: .calmSounds, practiceID: nil, plannedDuration: 600
        )
        let finished = try await dependencies.manageWellnessSession.finish(
            session, completion: .completed
        )
        // Sound playing in the background is not a claim the user made about
        // their own attention, and writing it as one would put that claim into
        // their Health record.
        #expect(await dependencies.manageHealth.recordMindfulSession(finished) == nil)
    }

    @Test("A session already written is never written again")
    @MainActor
    func mindfulWritesAreOnce() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageHealth.enable(.mindfulSession)

        var session = try await dependencies.manageWellnessSession.start(
            type: .meditation, practiceID: nil, plannedDuration: 300
        )
        session.endedAt = Self.referenceDate.addingTimeInterval(300)
        session.completion = .completed
        session.healthKitSampleID = "already-written"

        #expect(await dependencies.manageHealth.recordMindfulSession(session) == nil)
    }

    // MARK: - Watch actions

    @MainActor
    private func envelope<Payload: Encodable>(
        _ payload: Payload, kind: WatchActionKind, key: ActionKey
    ) throws -> WatchActionEnvelope {
        try #require(
            WatchActionEnvelope.wrap(
                payload,
                kind: kind,
                occurredAt: Self.referenceDate,
                deviceID: DeviceID(rawValue: "watch"),
                actionKey: key
            )
        )
    }

    @Test("A check-in from the wrist is recorded once, however often it arrives")
    @MainActor
    func watchCheckInIsIdempotent() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        let key = ActionKeyFactory.wellnessCheckIn(recordedAt: Self.referenceDate)
        let payload = WatchCheckInPayload(
            recordedAt: Self.referenceDate,
            timeZoneID: "Europe/Lisbon",
            moodRawValue: 4,
            energyRawValue: 3,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        let wrapped = try envelope(payload, kind: .wellnessCheckIn, key: key)

        await processor.receive(wrapped)
        await processor.receive(wrapped)

        let start = dependencies.clock.calendar.startOfDay(for: Self.referenceDate)
        let recorded = try await dependencies.wellnessRepository.checkIns(
            from: start,
            to: Self.referenceDate.addingTimeInterval(60),
            limit: 20
        )
        #expect(recorded.count == 1)
        #expect(recorded.first?.mood == .four)
        // And the record says where it was actually made.
        #expect(recorded.first?.sourceDeviceID.rawValue == "watch")
    }

    @Test("An empty check-in from the wrist is not stored")
    @MainActor
    func emptyWatchCheckInIsRejected() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        let key = ActionKeyFactory.wellnessCheckIn(recordedAt: Self.referenceDate)
        let payload = WatchCheckInPayload(
            recordedAt: Self.referenceDate,
            timeZoneID: "Europe/Lisbon",
            moodRawValue: nil,
            energyRawValue: nil,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        await processor.receive(try envelope(payload, kind: .wellnessCheckIn, key: key))

        let start = dependencies.clock.calendar.startOfDay(for: Self.referenceDate)
        #expect(try await dependencies.wellnessRepository.checkIns(
            from: start, to: Self.referenceDate.addingTimeInterval(60), limit: 20
        ).isEmpty)
    }

    @Test("A practice finished on the wrist is stored once")
    @MainActor
    func watchSessionIsIdempotent() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        let sessionID = UUID()
        let key = ActionKeyFactory.wellnessSession(sessionID: sessionID)
        let payload = WatchSessionPayload(
            id: sessionID,
            practiceID: "sunnie.breathing.longerExhale",
            typeRawValue: WellnessSessionType.breathing.rawValue,
            startedAt: Self.referenceDate,
            endedAt: Self.referenceDate.addingTimeInterval(120),
            plannedDuration: 120,
            completionRawValue: WellnessSessionCompletion.completed.rawValue,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        let wrapped = try envelope(payload, kind: .wellnessSession, key: key)

        await processor.receive(wrapped)
        await processor.receive(wrapped)

        let sessions = try await dependencies.wellnessRepository.sessions(
            from: Self.referenceDate.addingTimeInterval(-60),
            to: Self.referenceDate.addingTimeInterval(600),
            limit: 20
        )
        #expect(sessions.count == 1)
        #expect(sessions.first?.completion == .completed)
    }

    @Test("Water logged on the wrist keeps the wrist's own key")
    @MainActor
    func watchHydrationIsIdempotent() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        // Logged a minute before "now", so a key regenerated from the phone's
        // clock would differ from the wrist's — which is the bug this guards.
        let loggedAt = Self.referenceDate.addingTimeInterval(-120)
        let key = ActionKeyFactory.hydration(millilitres: 500, loggedAt: loggedAt)
        let payload = WatchHydrationPayload(
            millilitres: 500,
            loggedAt: loggedAt,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        let wrapped = try envelope(payload, kind: .hydration, key: key)

        await processor.receive(wrapped)
        await processor.receive(wrapped)

        #expect(await dependencies.manageHealth.todayHydration() == 500)

        let start = dependencies.clock.calendar.startOfDay(for: Self.referenceDate)
        let end = start.addingTimeInterval(86_400)
        let logs = try await dependencies.hydrationRepository.logs(from: start, to: end)
        #expect(logs.count == 1)
        #expect(logs.first?.sourceDeviceID.rawValue == "watch")
    }

    @Test("A checklist item ticked on the wrist is ticked on the phone")
    @MainActor
    func watchChecklistTickApplies() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        var trip = dependencies.manageTrip.newDraft()
        trip.title = "Lisbon"
        trip = try await dependencies.manageTrip.save(trip)

        let item = ChecklistItem(
            tripID: trip.id, kind: .beforeLeaving, title: "Passport", sortOrder: 0
        )
        try await dependencies.travelRepository.save(item)

        let key = ActionKeyFactory.checklistItem(itemID: item.id)
        let payload = WatchChecklistPayload(
            itemID: item.id,
            completedAt: Self.referenceDate,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        await processor.receive(try envelope(payload, kind: .checklistItem, key: key))

        let stored = try await dependencies.travelRepository.checklistItem(id: item.id)
        #expect(stored?.isDone == true)
    }

    @Test("A tick for an item that no longer exists is dropped quietly")
    @MainActor
    func watchChecklistTickForMissingItem() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        let missing = UUID()
        let key = ActionKeyFactory.checklistItem(itemID: missing)
        let payload = WatchChecklistPayload(
            itemID: missing,
            completedAt: Self.referenceDate,
            sourceDeviceID: "watch",
            actionKeyRawValue: key.rawValue
        )
        // The trip was deleted after the wrist queued this. Nothing to apply and
        // nothing to report — the assertion is that it does not throw.
        await processor.receive(try envelope(payload, kind: .checklistItem, key: key))
    }

    @Test("An action of an unrecognised kind is ignored rather than misapplied")
    @MainActor
    func unknownWatchKindsAreIgnored() async throws {
        let dependencies = try makeDependencies()
        let processor = WatchEnvelopeProcessor(
            recordCheckIn: dependencies.recordWellnessCheckIn,
            wellnessRepository: dependencies.wellnessRepository,
            travelRepository: dependencies.travelRepository,
            health: dependencies.manageHealth,
            clock: dependencies.clock
        )

        await processor.receive(WatchActionEnvelope(
            kindRawValue: "somethingFromANewerWatch",
            occurredAt: Self.referenceDate,
            sourceDeviceID: "watch",
            actionKeyRawValue: "k",
            body: Data()
        ))
        #expect(await dependencies.manageHealth.todayHydration() == 0)
    }

    // MARK: - Watch context

    @Test("The Watch context carries all five destinations' data")
    @MainActor
    func watchContextIsComplete() async throws {
        let dependencies = try makeDependencies()

        var trip = dependencies.manageTrip.newDraft()
        trip.title = "Lisbon"
        trip.startsAt = Self.referenceDate.addingTimeInterval(86_400 * 4)
        trip.endsAt = Self.referenceDate.addingTimeInterval(86_400 * 8)
        trip.destinationTimeZoneIDs = ["Europe/Lisbon"]
        trip = try await dependencies.manageTrip.save(trip)

        try await dependencies.travelRepository.save(
            ChecklistItem(tripID: trip.id, kind: .beforeLeaving, title: "Passport", sortOrder: 0)
        )

        let context = try #require(
            await WatchContextPublisher(dependencies: dependencies).build()
        )
        let features = try #require(context.features)

        #expect(features.affirmation != nil)
        #expect(!features.calm.practices.isEmpty)
        #expect(features.travel?.tripTitle == "Lisbon")
        #expect(features.travel?.destinationTimeZoneID == "Europe/Lisbon")
        #expect(features.travel?.checklistItems.count == 1)
        #expect(features.checkIn.recordedToday == false)
    }

    @Test("The context stays small enough for a transfer")
    @MainActor
    func watchContextIsBounded() async throws {
        let dependencies = try makeDependencies()

        var trip = dependencies.manageTrip.newDraft()
        trip.title = "Lisbon"
        trip.startsAt = Self.referenceDate.addingTimeInterval(86_400)
        trip = try await dependencies.manageTrip.save(trip)

        // Twelve outstanding items; the wrist should get five.
        for index in 0..<12 {
            try await dependencies.travelRepository.save(
                ChecklistItem(
                    tripID: trip.id, kind: .beforeLeaving, title: "Item \(index)", sortOrder: index
                )
            )
        }

        let context = try #require(
            await WatchContextPublisher(dependencies: dependencies).build()
        )
        let travel = try #require(context.features?.travel)
        #expect(
            travel.checklistItems.count
                == WatchFeatureContext.TravelPanel.maximumChecklistItems
        )
        #expect(
            (context.features?.calm.practices.count ?? 0)
                <= WatchFeatureContext.CalmPanel.maximumPractices
        )
    }

    @Test("A check-in today shows on the wrist as already noted")
    @MainActor
    func watchContextKnowsAboutTodaysCheckIn() async throws {
        let dependencies = try makeDependencies()
        _ = try await dependencies.recordWellnessCheckIn(mood: .four)

        let context = try #require(
            await WatchContextPublisher(dependencies: dependencies).build()
        )
        #expect(context.features?.checkIn.recordedToday == true)
    }

    // MARK: - Widget snapshot

    @Test("The snapshot carries what the widgets show and nothing private")
    @MainActor
    func widgetSnapshotIsBuiltAndFiltered() async throws {
        let dependencies = try makeDependencies()

        var draft = dependencies.managePlant.newDraft()
        draft.name = "Monstera"
        draft.notes = "The private note that must never reach a lock screen"
        _ = try await dependencies.managePlant.save(draft)

        let snapshot = await WidgetSnapshotPublisher(dependencies: dependencies)
            .build(at: Self.referenceDate)

        #expect(snapshot.payloadVersion == WidgetSnapshot.currentVersion)
        // The daily puzzle always resolves — the game pack guarantees one for
        // every day, offline.
        #expect(snapshot.dailyPuzzle != nil)

        // The one privacy assertion that matters: whatever else is in there, the
        // note is not. A widget lives where other people can see it.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        #expect(!json.contains("private note"))
    }

    @Test("A trip appears in the snapshot with a countdown")
    @MainActor
    func widgetSnapshotCarriesTheTrip() async throws {
        let dependencies = try makeDependencies()

        var trip = dependencies.manageTrip.newDraft()
        trip.title = "Lisbon"
        trip.startsAt = Self.referenceDate.addingTimeInterval(86_400 * 3)
        trip.endsAt = Self.referenceDate.addingTimeInterval(86_400 * 7)
        _ = try await dependencies.manageTrip.save(trip)

        let snapshot = await WidgetSnapshotPublisher(dependencies: dependencies)
            .build(at: Self.referenceDate)
        let panel = try #require(snapshot.trip)
        #expect(panel.title == "Lisbon")
        #expect(panel.daysUntilDeparture(
            now: Self.referenceDate, calendar: dependencies.clock.calendar
        ) == 3)
    }

    @Test("Publishing without an App Group changes nothing and does not fail")
    @MainActor
    func publishingWithoutAnAppGroupIsSafe() async throws {
        let dependencies = try makeDependencies()
        // No entitlement in a test process, which is also the shipped default
        // (ADR-012). The assertion is that this is a no-op rather than a crash.
        await dependencies.publishWidgetSnapshot(force: true)
        #expect(!WidgetSnapshotStore().isAvailable)
    }

    // MARK: - Intents

    @Test("The intent care types resolve to the domain's own kinds")
    @MainActor
    func intentCareTypesResolve() {
        for value in [
            CareTypeAppValue.water, .mist, .fertilize, .rotate, .repot, .prune
        ] {
            #expect(value.careType != nil, "\(value.rawValue) does not resolve")
            #expect(value.careType?.storageKey == value.rawValue)
        }
    }
}
