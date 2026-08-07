import Foundation
import Testing
@testable import SunnieShared

/// Health phrasing, widget snapshots, and the Watch payloads. All pure.
///
/// The phrasing tests carry the weight here. §4 forbids diagnosis, ratings, and
/// prescriptive advice, and the way that is guaranteed is structural: a
/// `Descriptor` is a number, a unit, and an optional caveat, with nowhere to put
/// an adjective. These tests check the other half — that a value the app does not
/// have never becomes a zero, and that a partial day never reads as a whole one.
@Suite("Health and integrations")
struct HealthAndIntegrationTests {

    private let now = Date(timeIntervalSince1970: 1_770_033_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    // MARK: - Health types

    @Test("Only the two types the app writes are writable")
    func writeSurfaceIsMinimal() {
        let writable = HealthDataType.allCases.filter(\.isWritten)
        #expect(Set(writable) == [.mindfulSession, .dietaryWater])
        #expect(Set(HealthDataType.writeOnlyDefaults) == Set(writable))
    }

    @Test("Absent data is nil, never zero")
    func absenceIsNotZero() {
        let reading = HealthReading.absent(.stepCount, start: now, end: now)
        #expect(reading.value == nil)
        #expect(reading.coverage == .none)
        #expect(!reading.hasValue)

        // And the snapshot refuses to hand it back as a value.
        let snapshot = HealthSnapshot(generatedAt: now, readings: [.stepCount: reading])
        #expect(snapshot.reading(.stepCount) == nil)
        #expect(snapshot.isEmpty)
    }

    @Test("A reading with no value produces no phrase at all")
    func absentReadingsSaySilent() {
        // Not "no data" — a row that says that every day is the app nagging
        // about a permission the user already declined (§12).
        #expect(HealthPhrasing.descriptor(
            for: .absent(.sleepAnalysis, start: now, end: now)
        ) == nil)
    }

    @Test("An unfinished window is marked as such")
    func inProgressReadingsCarryACaveat() throws {
        let partial = HealthReading(
            type: .stepCount, value: 3_200, coverage: .inProgress, start: now, end: now
        )
        let descriptor = try #require(HealthPhrasing.descriptor(for: partial))
        #expect(descriptor.formattedValue == "3200")
        #expect(descriptor.caveatKey == "health.caveat.inProgress")

        let whole = HealthReading(
            type: .stepCount, value: 9_000, coverage: .complete, start: now, end: now
        )
        #expect(HealthPhrasing.descriptor(for: whole)?.caveatKey == nil)
    }

    @Test("Values are rounded to a precision that does not imply measurement")
    func valuesAreRoundedSensibly() throws {
        let sleep = try #require(HealthPhrasing.descriptor(for: HealthReading(
            type: .sleepAnalysis, value: 7.4213, coverage: .complete, start: now, end: now
        )))
        #expect(sleep.formattedValue == "7.4")

        let steps = try #require(HealthPhrasing.descriptor(for: HealthReading(
            type: .stepCount, value: 8_412.7, coverage: .complete, start: now, end: now
        )))
        #expect(steps.formattedValue == "8413")
    }

    @Test("A phrase is a number and a noun, with nowhere for a verdict")
    func phrasesCannotJudge() throws {
        // Structural: `Descriptor` has four fields and none of them is free text.
        // This walks every type and checks the two key fields resolve to keys
        // rather than to sentences someone could have written a judgement into.
        for type in HealthDataType.allCases {
            let descriptor = try #require(HealthPhrasing.descriptor(for: HealthReading(
                type: type, value: 42, coverage: .complete, start: now, end: now
            )))
            #expect(descriptor.unitKey.hasPrefix("health.unit."))
            #expect(descriptor.caveatKey == nil)
        }
    }

    @Test("Negative values never reach the screen")
    func negativeValuesAreClamped() throws {
        // A negative step count is nonsense from a bad sample rather than a real
        // reading. Shown as zero rather than as a minus sign, which would look
        // like the app is claiming something.
        let descriptor = try #require(HealthPhrasing.descriptor(for: HealthReading(
            type: .stepCount, value: -12, coverage: .complete, start: now, end: now
        )))
        #expect(descriptor.formattedValue == "0")
    }

    @Test("The unavailable service behaves exactly like a refusal")
    func unavailableServiceIsHonest() async {
        let service = UnavailableHealthService()
        #expect(!service.isAvailable)
        #expect(await service.authorization(for: .mindfulSession) == .unavailable)
        #expect(await service.writeMindfulSession(from: now, to: now) == nil)
        #expect(await service.writeWater(millilitres: 250, at: now) == nil)

        let snapshot = await service.snapshot(
            types: Set(HealthDataType.allCases), day: now, calendar: calendar
        )
        #expect(snapshot.isEmpty)
    }

    // MARK: - Hydration

    @Test("Hydration keys collapse a double tap but keep two real entries")
    func hydrationKeysAreBucketed() {
        let first = ActionKeyFactory.hydration(millilitres: 250, loggedAt: now)
        let doubleTap = ActionKeyFactory.hydration(
            millilitres: 250, loggedAt: now.addingTimeInterval(3)
        )
        #expect(first == doubleTap)

        // A different amount in the same minute is a second, deliberate entry.
        let different = ActionKeyFactory.hydration(millilitres: 500, loggedAt: now)
        #expect(first != different)

        // And the same amount a minute later is a second glass.
        let later = ActionKeyFactory.hydration(
            millilitres: 250, loggedAt: now.addingTimeInterval(120)
        )
        #expect(first != later)
    }

    @Test("A checklist key depends on the item alone")
    func checklistKeysArePerItem() {
        let id = UUID()
        #expect(
            ActionKeyFactory.checklistItem(itemID: id)
                == ActionKeyFactory.checklistItem(itemID: id)
        )
        #expect(
            ActionKeyFactory.checklistItem(itemID: id)
                != ActionKeyFactory.checklistItem(itemID: UUID())
        )
    }

    // MARK: - Watch payloads

    @Test("Every Watch action carries the five things the specification requires")
    func envelopesCarryTheRequiredFields() throws {
        // §7: stable action ID, type, timestamp, source device, payload version.
        let payload = WatchCheckInPayload(
            recordedAt: now,
            timeZoneID: "Europe/Lisbon",
            moodRawValue: 4,
            energyRawValue: nil,
            sourceDeviceID: "watch",
            actionKeyRawValue: "test|key"
        )
        let envelope = try #require(
            WatchActionEnvelope.wrap(
                payload,
                kind: .wellnessCheckIn,
                occurredAt: now,
                deviceID: DeviceID(rawValue: "watch"),
                actionKey: ActionKey(rawValue: "test|key")
            )
        )

        #expect(envelope.actionKey.rawValue == "test|key")
        #expect(envelope.kind == .wellnessCheckIn)
        #expect(envelope.occurredAt == now)
        #expect(envelope.deviceID.rawValue == "watch")
        #expect(envelope.payloadVersion == WatchPayloadVersion.current)
    }

    @Test("An envelope round-trips through its own coder")
    func envelopesRoundTrip() throws {
        let payload = WatchHydrationPayload(
            millilitres: 500,
            loggedAt: now,
            sourceDeviceID: "watch",
            actionKeyRawValue: "hydration|1"
        )
        let envelope = try #require(
            WatchActionEnvelope.wrap(
                payload,
                kind: .hydration,
                occurredAt: now,
                deviceID: DeviceID(rawValue: "watch"),
                actionKey: ActionKey(rawValue: "hydration|1")
            )
        )

        let coder = WatchActionEnvelope.coder
        let restored = try coder.decoder.decode(
            WatchActionEnvelope.self, from: try coder.encoder.encode(envelope)
        )
        #expect(restored == envelope)

        let body = try #require(restored.unwrap(WatchHydrationPayload.self))
        #expect(body.millilitres == 500)
        #expect(body.loggedAt == now)
    }

    @Test("An action of an unknown kind is recognisably unknown, not corrupt")
    func unknownKindsAreIdentifiable() {
        let envelope = WatchActionEnvelope(
            kindRawValue: "somethingFromANewerBuild",
            occurredAt: now,
            sourceDeviceID: "watch",
            actionKeyRawValue: "k",
            body: Data()
        )
        #expect(envelope.kind == nil)
        // Still readable as an envelope — which is what lets the phone log it
        // rather than treating the transfer as damaged.
        #expect(envelope.isReadable)
    }

    @Test("A payload from a newer build is refused rather than guessed at")
    func futurePayloadsAreRefused() {
        let envelope = WatchActionEnvelope(
            payloadVersion: WatchPayloadVersion.current + 1,
            kindRawValue: WatchActionKind.hydration.rawValue,
            occurredAt: now,
            sourceDeviceID: "watch",
            actionKeyRawValue: "k",
            body: Data()
        )
        #expect(!envelope.isReadable)
    }

    @Test("An old Watch context still decodes when the phone adds fields")
    func contextDecodesLeniently() throws {
        // Exactly the shape the Phase 2 build wrote: no `features` key at all.
        let json = """
        {
          "payloadVersion": 1,
          "generatedAt": "2026-02-02T12:00:00Z",
          "dueTasks": [],
          "totalActivePlants": 3,
          "dayCyclePresentationKey": "sunnieAfternoonies"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let context = try decoder.decode(
            WatchApplicationContext.self, from: Data(json.utf8)
        )
        #expect(context.totalActivePlants == 3)
        #expect(context.dayCyclePresentationKey == "sunnieAfternoonies")
        #expect(context.features == nil)
    }

    @Test("A context with the new fields round-trips whole")
    func contextRoundTripsWithFeatures() throws {
        let context = WatchApplicationContext(
            generatedAt: now,
            dueTasks: [],
            totalActivePlants: 1,
            dayCyclePresentationKey: DayCyclePresentation.sunnieNights.rawValue,
            sunnieGreeting: "Evening.",
            features: WatchFeatureContext(
                affirmation: "One thing at a time.",
                nextTaskDescription: "Monstera",
                checkIn: .init(offersEnergy: true, recordedToday: true),
                calm: .init(
                    practices: [
                        .init(
                            id: "sunnie.breathing.longerExhale",
                            displayName: "Longer exhale",
                            typeRawValue: WellnessSessionType.breathing.rawValue,
                            inhaleSeconds: 4,
                            holdAfterInhaleSeconds: 0,
                            exhaleSeconds: 6,
                            holdAfterExhaleSeconds: 0,
                            defaultDuration: 120
                        )
                    ],
                    usesHapticPacing: true
                ),
                travel: .init(
                    tripTitle: "Lisbon",
                    startsAt: now.addingTimeInterval(86_400 * 3),
                    endsAt: nil,
                    homeTimeZoneID: "Europe/London",
                    destinationTimeZoneID: "Europe/Lisbon",
                    statusKey: "trip.status.upcoming",
                    checklistItems: [.init(id: UUID(), title: "Passport")]
                )
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            WatchApplicationContext.self, from: try encoder.encode(context)
        )
        #expect(restored == context)
        #expect(restored.features?.calm.practices.first?.cycleDuration == 10)
    }

    @Test("A breathing practice keeps its shape when it crosses to the wrist")
    func practicesCarryTheirPattern() {
        let pattern = BreathingPattern(
            id: "sunnie.breathing.box",
            displayNameKey: "k.name",
            descriptionKey: "k.description",
            inhaleSeconds: 4,
            holdAfterInhaleSeconds: 4,
            exhaleSeconds: 4,
            holdAfterExhaleSeconds: 4,
            defaultCycles: 5
        )
        let practice = WatchFeatureContext.CalmPanel.Practice(
            pattern: pattern, displayName: "Box breathing"
        )

        #expect(practice.cycleDuration == pattern.cycleDuration)
        #expect(practice.defaultDuration == pattern.totalDuration(cycles: 5))
        #expect(practice.sessionType == .breathing)
    }

    // MARK: - Widget snapshots

    @Test("A trip countdown is whole days and stops once the trip starts")
    func tripCountdownCountsWholeDays() throws {
        let departure = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 5, hour: 6))
        )
        let panel = WidgetSnapshot.TripPanel(
            title: "Lisbon",
            startsAt: departure,
            destinationTimeZoneID: "Europe/Lisbon",
            statusKey: "trip.status.upcoming"
        )

        // Noon on the 2nd to a 6am departure on the 5th is three days, because a
        // countdown is read in whole days rather than in hours.
        #expect(panel.daysUntilDeparture(now: now, calendar: calendar) == 3)
        // Once it has started there is nothing to count down to.
        #expect(panel.daysUntilDeparture(
            now: departure.addingTimeInterval(3600), calendar: calendar
        ) == nil)
    }

    @Test("A snapshot round-trips through the store")
    func snapshotRoundTripsThroughAStore() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sunnie-widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.isAvailable)
        // Nothing written yet reads as nothing, not as an empty snapshot.
        #expect(store.read() == nil)

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            today: .init(dayCyclePresentationKey: DayCyclePresentation.sunnieDays.rawValue),
            plants: .init(dueCount: 2, overdueCount: 1, nextTaskName: "Monstera"),
            trip: nil,
            affirmation: "One thing at a time.",
            dailyPuzzle: .init(
                gameNameKey: "game.jungleLogic.name",
                puzzleTitle: "Four shelves",
                isFinishedToday: false
            )
        )

        #expect(store.write(snapshot))
        #expect(store.read() == snapshot)
    }

    @Test("With no shared container the store is a no-op rather than a failure")
    func storeWithoutAContainerIsHarmless() {
        // The default when no App Group is configured (ADR-012).
        let store = WidgetSnapshotStore(directory: nil)
        #expect(!store.isAvailable)
        #expect(!store.write(.empty(at: now)))
        #expect(store.read() == nil)
    }

    @Test("A snapshot from a newer app is ignored rather than half-read")
    func newerSnapshotsAreIgnored() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sunnie-widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let future = WidgetSnapshot(
            payloadVersion: WidgetSnapshot.currentVersion + 1,
            generatedAt: now,
            today: .init(dayCyclePresentationKey: DayCyclePresentation.sunnieDays.rawValue),
            plants: .init(dueCount: 0, overdueCount: 0, nextTaskName: nil)
        )
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.write(future))
        #expect(store.read() == nil)
    }

    @Test("An empty snapshot is a valid thing to show")
    func emptySnapshotIsCoherent() {
        let snapshot = WidgetSnapshot.empty(at: now)
        #expect(snapshot.today.presentation == .sunnieDays)
        #expect(snapshot.plants.dueCount == 0)
        #expect(snapshot.trip == nil)
        #expect(snapshot.affirmation == nil)
    }
}
