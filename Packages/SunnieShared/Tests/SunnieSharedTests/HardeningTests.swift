import Foundation
import Testing
@testable import SunnieShared

/// Regression cover for defects found by inspection during the hardening pass.
///
/// Each test names the failure it prevents rather than just the behaviour it
/// asserts, so a future change that reintroduces one fails with an explanation.
@Suite("Hardening regressions")
struct HardeningTests {

    // MARK: - Preferences survive schema growth

    @Test("A preferences blob missing a newer field keeps every other setting")
    func decodingToleratesMissingFields() throws {
        // Preferences persist as one encoded blob. Before the lenient decoder,
        // adding a field made the *whole* record fail to decode, and the
        // repository's catch handed back defaults — silently resetting every
        // setting the user had chosen.
        let legacy = """
        {
          "activeThemeID": "sunnie.theme.travelScrapbook",
          "automaticDayCycle": false,
          "dayCycleOverride": "night",
          "hapticsEnabled": false,
          "nicknameProbability": 0.25
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)

        // Present fields survive.
        #expect(decoded.activeThemeID == ThemeCatalog.travelScrapbookID)
        #expect(decoded.automaticDayCycle == false)
        #expect(decoded.dayCycleOverride == .night)
        #expect(decoded.hapticsEnabled == false)
        #expect(decoded.nicknameProbability == 0.25)

        // Absent ones fall back rather than taking the whole record down.
        #expect(decoded.quietHours == UserPreferences.default.quietHours)
        #expect(decoded.audio == UserPreferences.default.audio)
        #expect(decoded.dietaryRuleIDs.contains(DietaryRule.noEggs))
        #expect(decoded.useSolarTimes == UserPreferences.default.useSolarTimes)
    }

    @Test("An unreadable field falls back without discarding the rest")
    func decodingToleratesCorruptedFields() throws {
        // `automaticDayCycle` is the wrong type and `dayCycleOverride` is not a
        // real phase — both should degrade to defaults, not throw.
        let damaged = """
        {
          "activeThemeID": "sunnie.theme.dayCycle",
          "automaticDayCycle": "yes please",
          "dayCycleOverride": "brunch",
          "hapticsEnabled": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: damaged)

        #expect(decoded.activeThemeID == ThemeCatalog.dayCycleID)
        #expect(decoded.hapticsEnabled == false)
        #expect(decoded.automaticDayCycle == UserPreferences.default.automaticDayCycle)
        #expect(decoded.dayCycleOverride == nil)
    }

    @Test("An unknown future field is ignored rather than rejected")
    func decodingIgnoresUnknownFields() throws {
        let future = """
        {
          "activeThemeID": "sunnie.theme.lushTropicalJungle",
          "somethingAddedLater": { "nested": true },
          "hapticsEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: future)
        #expect(decoded.hapticsEnabled)
    }

    @Test("A full round trip is lossless")
    func encodingRoundTripsExactly() throws {
        var original = UserPreferences.default
        original.activeThemeID = ThemeCatalog.travelScrapbookID
        original.automaticDayCycle = false
        original.dayCycleOverride = .lateNight
        original.quietHours = QuietHours(isEnabled: true, startHour: 21, endHour: 6)
        original.audio = AudioPreferences(
            musicEnabled: false, ambienceEnabled: true,
            effectsEnabled: false, masterGain: 0.42
        )
        original.accessibility = AccessibilityOverrides(
            forceHighContrast: true,
            forceReducedMotion: true,
            nightBrightnessReduction: 0.7
        )
        original.nicknameProbability = 0.11
        original.useSolarTimes = true

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(UserPreferences.self, from: data)

        #expect(restored == original)
    }

    @Test("An empty object decodes to the defaults")
    func emptyObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(
            UserPreferences.self, from: "{}".data(using: .utf8)!
        )
        #expect(decoded == UserPreferences.default)
    }

    // MARK: - The phase schedule cannot trap

    @Test("An out-of-order phase schedule resolves without trapping")
    func misconfiguredScheduleDoesNotTrap() {
        // The bounds are public and documented as user-adjustable. Built from
        // `Range` patterns, an out-of-order pair crashed at runtime; ordered
        // comparisons return a wrong-but-harmless phase instead.
        let broken = TimePhaseEngine.PhaseSchedule(
            morningStart: 14,
            dayStart: 5,
            afternoonStart: 22,
            eveningStart: 3,
            nightStart: 9,
            lateNightStart: 0
        )

        #expect(!broken.isOrdered)
        for hour in 0...23 {
            // The assertion is simply that this returns at all.
            _ = broken.phase(forHour: hour)
        }
    }

    @Test("The shipped schedule is well ordered")
    func defaultScheduleIsOrdered() {
        #expect(TimePhaseEngine.PhaseSchedule.default.isOrdered)
    }

    @Test("Every hour of the day resolves to some phase")
    func everyHourResolves() {
        let schedule = TimePhaseEngine.PhaseSchedule.default
        let phases = (0...23).map { schedule.phase(forHour: $0) }

        #expect(phases.count == 24)
        // All six phases appear across a full day.
        #expect(Set(phases).count == TimePhase.allCases.count)
    }

    // MARK: - The name Sunnie uses is not frozen at launch

    @Test("Sunnie uses the name from the moment, not one captured at startup")
    func displayNameComesFromTheContext() throws {
        // The service used to capture a display name at composition time, so
        // renaming yourself in Settings would never change what Sunnie called
        // you for the rest of the session.
        let service = SunnieMessageService(
            registry: ContentRegistry.builtIn(),
            random: SeededRandomSource(seed: 3)
        )

        func greeting(named name: String) throws -> String {
            let message = try #require(service.message(for: SunnieMessageContext(
                category: .greeting,
                timeContext: TestFixtures.timeContext(phase: .morning),
                displayName: name,
                nickname: nil,
                nicknameProbability: 0
            )))
            return message.text
        }

        #expect(try greeting(named: "Vanessa").contains("Vanessa"))
        #expect(try greeting(named: "Ness").contains("Ness"))
        #expect(!(try greeting(named: "Ness").contains("Vanessa")))
    }

    // MARK: - Both sides of the Watch bridge agree

    @Test("The Watch message keys are declared once and shared")
    func watchMessageKeysAreShared() {
        // Two separate constants would let a rename on one side break delivery
        // silently: no compiler error, no failing test, just actions that never
        // arrive.
        #expect(WatchMessageKeys.careAction == "sunnie.watch.careAction")
        #expect(WatchMessageKeys.applicationContext == "sunnie.watch.applicationContext")
        #expect(WatchMessageKeys.careAction != WatchMessageKeys.applicationContext)
    }

    // MARK: - Branded naming cannot drift

    @Test("No shipped or fallback content introduces a forbidden day-cycle name")
    func noForbiddenDayCycleNamesAnywhere() {
        let registry = ContentRegistry.builtIn()
        let texts = registry.messagePack.messages.map(\.template)
            + FallbackContent.messagePack.messages.map(\.template)
            + DayCyclePresentation.allCases.map(\.canonicalDisplayName)

        for text in texts {
            let lowered = text.lowercased()
            #expect(!lowered.contains("sunnie mornings"))
            #expect(!lowered.contains("sunnie evenings"))
        }
    }

    @Test("Every content ID in the shipped packs is well formed")
    func shippedContentIDsAreWellFormed() {
        let registry = ContentRegistry.builtIn()

        for message in registry.messagePack.messages {
            #expect(message.id.isWellFormed, "malformed: \(message.id.rawValue)")
        }
        for theme in registry.themePack.themes {
            #expect(theme.id.isWellFormed, "malformed: \(theme.id.rawValue)")
        }
    }
}
