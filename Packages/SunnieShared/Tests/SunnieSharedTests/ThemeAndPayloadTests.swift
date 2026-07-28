import Foundation
import Testing
@testable import SunnieShared

@Suite("Theme resolution")
struct ThemeEngineTests {

    private let engine = ThemeEngine(registry: ContentRegistry.builtIn())

    private func context(phase: TimePhase, quietHours: Bool = false) -> TimeContext {
        TimePhaseEngine(calendar: TestFixtures.calendar).resolve(
            at: TestFixtures.date(2026, 7, 15, 12),
            preferences: TestFixtures.preferences(
                automaticDayCycle: false,
                override: phase,
                quietHours: QuietHours(isEnabled: quietHours, startHour: 0, endHour: 23)
            ),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )
    }

    @Test("A phase variant overrides only what it supplies")
    func variantOverridesSelectively() {
        let resolved = engine.resolve(
            themeID: ThemeCatalog.lushTropicalJungleID,
            timeContext: context(phase: .night),
            highContrast: false
        )
        let base = engine.theme(id: ThemeCatalog.lushTropicalJungleID)!

        // Night supplies canvas, surface, and both text colours.
        #expect(resolved.palette.canvas != base.basePalette.canvas)
        #expect(resolved.palette.textPrimary != base.basePalette.textPrimary)
        // It supplies no accents, so those fall through from the base.
        #expect(resolved.palette.accentPlant == base.basePalette.accentPlant)
    }

    @Test("High contrast wins over decorative phase tinting")
    func highContrastBeatsPhaseVariant() {
        let base = engine.theme(id: ThemeCatalog.lushTropicalJungleID)!
        let contrast = base.highContrastPalette!

        let resolved = engine.resolve(
            themeID: ThemeCatalog.lushTropicalJungleID,
            timeContext: context(phase: .lateNight),
            highContrast: true
        )

        #expect(resolved.palette == contrast)
    }

    @Test("An unknown theme ID falls back rather than leaving the app unstyled")
    func unknownThemeFallsBack() {
        let resolved = engine.resolve(
            themeID: "sunnie.theme.doesNotExist",
            timeContext: context(phase: .day),
            highContrast: false
        )

        #expect(engine.theme(id: resolved.themeID) != nil)
    }

    @Test("Quiet hours suppress the ambient cue")
    func quietHoursSuppressAmbience() {
        let resolved = engine.resolve(
            themeID: ThemeCatalog.dayCycleID,
            timeContext: context(phase: .evening, quietHours: true),
            highContrast: false
        )

        #expect(resolved.ambientAudioCueID == nil)
    }

    @Test("Every theme resolves in every phase without a missing colour")
    func allThemesResolveInAllPhases() {
        for theme in engine.availableThemes() {
            for phase in TimePhase.allCases {
                let resolved = engine.resolve(
                    themeID: theme.id,
                    timeContext: context(phase: phase),
                    highContrast: false
                )
                for color in resolved.palette.allValues {
                    #expect(
                        color.isWellFormed,
                        "\(theme.id) \(phase.rawValue) produced unreadable colour \(color.hex)"
                    )
                }
            }
        }
    }

    @Test("The Day-Cycle theme changes Sunnie's outfit across the day")
    func dayCycleThemeChangesOutfit() {
        let morning = engine.resolve(
            themeID: ThemeCatalog.dayCycleID,
            timeContext: context(phase: .morning),
            highContrast: false
        )
        let lateNight = engine.resolve(
            themeID: ThemeCatalog.dayCycleID,
            timeContext: context(phase: .lateNight),
            highContrast: false
        )

        #expect(morning.sunnieOutfitID != nil)
        #expect(lateNight.sunnieOutfitID != nil)
        #expect(morning.sunnieOutfitID != lateNight.sunnieOutfitID)
    }
}

@Suite("Watch payloads")
struct WatchPayloadTests {

    private func payload() -> WatchCareActionPayload {
        WatchCareActionPayload(
            plantID: TestFixtures.plantID,
            scheduleID: TestFixtures.scheduleID,
            careTypeStorageKey: CareType.water.storageKey,
            performedAt: TestFixtures.date(2026, 7, 15, 9, 30),
            sourceDeviceID: TestFixtures.watchDevice.rawValue,
            actionKeyRawValue: ActionKeyFactory.plantCare(
                plantID: TestFixtures.plantID,
                careType: .water,
                performedAt: TestFixtures.date(2026, 7, 15, 9, 30)
            ).rawValue
        )
    }

    @Test("A care action survives an encode/decode round trip")
    func careActionRoundTrips() throws {
        let original = payload()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WatchCareActionPayload.self, from: data)

        #expect(restored == original)
        #expect(restored.careType == .water)
        #expect(restored.actionKey == original.actionKey)
    }

    @Test("A payload from a newer build is refused rather than guessed at")
    func futureVersionIsNotReadable() {
        let future = WatchCareActionPayload(
            payloadVersion: WatchPayloadVersion.current + 1,
            plantID: TestFixtures.plantID,
            scheduleID: nil,
            careTypeStorageKey: CareType.water.storageKey,
            performedAt: TestFixtures.date(2026, 7, 15, 9),
            sourceDeviceID: TestFixtures.watchDevice.rawValue,
            actionKeyRawValue: "whatever"
        )

        #expect(!future.isReadable)
        #expect(payload().isReadable)
    }

    @Test("An unrecognised care type decodes to nil instead of a wrong action")
    func unknownCareTypeIsNotGuessed() {
        let unknown = WatchCareActionPayload(
            plantID: TestFixtures.plantID,
            scheduleID: nil,
            careTypeStorageKey: "somethingFromTheFuture",
            performedAt: TestFixtures.date(2026, 7, 15, 9),
            sourceDeviceID: TestFixtures.watchDevice.rawValue,
            actionKeyRawValue: "key"
        )

        #expect(unknown.careType == nil)
    }

    @Test("The application context round trips with its due tasks")
    func applicationContextRoundTrips() throws {
        let task = DueCareTask(
            id: TestFixtures.scheduleID,
            plantID: TestFixtures.plantID,
            scheduleID: TestFixtures.scheduleID,
            plantDisplayName: "Monstera",
            careType: .water,
            dueDate: TestFixtures.date(2026, 7, 15, 9),
            urgency: .dueToday,
            daysWaiting: 0
        )
        let original = WatchApplicationContext(
            generatedAt: TestFixtures.date(2026, 7, 15, 12),
            dueTasks: [WatchDueTask(task: task)],
            totalActivePlants: 52,
            dayCyclePresentationKey: DayCyclePresentation.sunnieDays.rawValue,
            sunnieGreeting: "Hello, Vanessa."
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WatchApplicationContext.self, from: data)

        #expect(restored == original)
        #expect(restored.dueTasks.first?.careType == .water)
        #expect(restored.totalActivePlants == 52)
    }

    @Test("Converting a due task to its Watch form preserves identity")
    func dueTaskConversionPreservesIdentity() {
        let task = DueCareTask(
            id: TestFixtures.scheduleID,
            plantID: TestFixtures.plantID,
            scheduleID: TestFixtures.scheduleID,
            plantDisplayName: "Bird of Paradise",
            careType: .mist,
            dueDate: TestFixtures.date(2026, 7, 15, 9),
            urgency: .waiting,
            daysWaiting: 2
        )

        let watchTask = WatchDueTask(task: task)

        #expect(watchTask.plantID == task.plantID)
        #expect(watchTask.scheduleID == task.scheduleID)
        #expect(watchTask.careType == task.careType)
        #expect(watchTask.urgency == task.urgency)
    }
}

@Suite("Today summary shaping")
struct PlantTodaySummaryTests {

    private func task(
        dueDate: Date,
        urgency: DueUrgency,
        name: String
    ) -> DueCareTask {
        DueCareTask(
            id: UUID(),
            plantID: UUID(),
            scheduleID: UUID(),
            plantDisplayName: name,
            careType: .water,
            dueDate: dueDate,
            urgency: urgency,
            daysWaiting: urgency == .waiting ? 2 : 0
        )
    }

    @Test("Actionable tasks lead with what has been waiting longest")
    func actionableTasksAreOrderedByDueDate() {
        let summary = PlantTodaySummary(
            dueToday: [task(
                dueDate: TestFixtures.date(2026, 7, 15, 9),
                urgency: .dueToday, name: "Today"
            )],
            waiting: [task(
                dueDate: TestFixtures.date(2026, 7, 12, 9),
                urgency: .waiting, name: "Waiting"
            )],
            upcoming: [task(
                dueDate: TestFixtures.date(2026, 7, 20, 9),
                urgency: .upcoming, name: "Upcoming"
            )],
            totalActivePlants: 3,
            generatedAt: TestFixtures.date(2026, 7, 15, 12)
        )

        #expect(summary.actionableTasks.map(\.plantDisplayName) == ["Waiting", "Today"])
        #expect(summary.hasAnythingToDo)
    }

    @Test("Upcoming tasks alone do not make the card actionable")
    func upcomingIsNotActionable() {
        let summary = PlantTodaySummary(
            dueToday: [],
            waiting: [],
            upcoming: [task(
                dueDate: TestFixtures.date(2026, 7, 20, 9),
                urgency: .upcoming, name: "Upcoming"
            )],
            totalActivePlants: 1,
            generatedAt: TestFixtures.date(2026, 7, 15, 12)
        )

        #expect(!summary.hasAnythingToDo)
    }

    @Test("An empty summary is a valid state, not an error")
    func emptySummaryIsValid() {
        let summary = PlantTodaySummary.empty(generatedAt: TestFixtures.date(2026, 7, 15, 12))

        #expect(!summary.hasAnythingToDo)
        #expect(summary.actionableTasks.isEmpty)
        #expect(summary.totalActivePlants == 0)
    }
}
