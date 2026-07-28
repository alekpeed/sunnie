import Foundation
import Testing
@testable import SunnieShared

@Suite("Universal time engine")
struct TimePhaseEngineTests {

    private let engine = TimePhaseEngine(calendar: TestFixtures.calendar)

    @Test(
        "Clock fallback matches the documented ranges",
        arguments: [
            (0, TimePhase.lateNight), (4, TimePhase.lateNight),
            (5, TimePhase.morning), (10, TimePhase.morning),
            (11, TimePhase.day), (13, TimePhase.day),
            (14, TimePhase.afternoon), (17, TimePhase.afternoon),
            (18, TimePhase.evening), (20, TimePhase.evening),
            (21, TimePhase.night), (23, TimePhase.night)
        ]
    )
    func clockFallbackRanges(hour: Int, expected: TimePhase) {
        #expect(TimePhaseEngine.PhaseSchedule.default.phase(forHour: hour) == expected)
    }

    @Test(
        "Only the three branded presentations exist",
        arguments: TimePhase.allCases
    )
    func brandedPresentationMapping(phase: TimePhase) {
        let presentation = phase.brandedPresentation

        switch phase {
        case .morning, .day:
            #expect(presentation == .sunnieDays)
        case .afternoon:
            #expect(presentation == .sunnieAfternoonies)
        case .evening, .night, .lateNight:
            #expect(presentation == .sunnieNights)
        }
    }

    @Test("Branded names are exactly the three approved strings")
    func brandedNamesAreCanonical() {
        let names = DayCyclePresentation.allCases.map(\.canonicalDisplayName)

        #expect(names == ["Sunnie Days", "Sunnie Afternoonies", "Sunnie Nights"])
        #expect(!names.contains("Sunnie Mornings"))
        #expect(!names.contains("Sunnie Evenings"))
    }

    @Test("A manual override pins the phase")
    func manualOverrideWins() {
        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 12),
            preferences: TestFixtures.preferences(
                automaticDayCycle: false, override: .night
            ),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.phase == .night)
        #expect(context.presentation == .sunnieNights)
    }

    @Test("Automatic mode ignores a stale override")
    func automaticIgnoresOverride() {
        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 12),
            preferences: TestFixtures.preferences(
                automaticDayCycle: true, override: .night
            ),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.phase == .day)
    }

    @Test("Reduce Motion pins animation intensity to zero in every phase")
    func reduceMotionStopsAnimation() {
        for phase in TimePhase.allCases {
            let context = engine.resolve(
                at: TestFixtures.date(2026, 7, 15, 12),
                preferences: TestFixtures.preferences(
                    automaticDayCycle: false, override: phase
                ),
                timeZone: TestFixtures.utc,
                reduceMotion: true
            )
            #expect(context.animationIntensity == 0)
        }
    }

    @Test("The preference alone is enough to reduce motion")
    func preferenceReducesMotionWithoutSystemFlag() {
        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 12),
            preferences: TestFixtures.preferences(reduceMotion: true),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.animationIntensity == 0)
    }

    @Test("Quiet hours silence ambience but do not change the phase")
    func quietHoursSilenceAmbience() {
        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)

        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 23),
            preferences: TestFixtures.preferences(quietHours: quiet),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.isQuietHours)
        #expect(context.ambientAudioCategory == .silence)
        #expect(context.phase == .night)
    }

    @Test("Quiet hours wrap correctly past midnight")
    func quietHoursWrapMidnight() {
        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)

        #expect(quiet.contains(hour: 23))
        #expect(quiet.contains(hour: 2))
        #expect(quiet.contains(hour: 6))
        #expect(!quiet.contains(hour: 7))
        #expect(!quiet.contains(hour: 12))
        #expect(!quiet.contains(hour: 21))
    }

    @Test("Disabled quiet hours never match")
    func disabledQuietHoursNeverMatch() {
        let quiet = QuietHours(isEnabled: false, startHour: 22, endHour: 7)
        #expect(!quiet.contains(hour: 23))
    }

    @Test("Time zone decides the phase, not the absolute instant")
    func timeZoneChangesPhase() throws {
        // 20:00 UTC on 15 July is evening in London and afternoon in New York.
        let instant = TestFixtures.date(2026, 7, 15, 20)
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))

        let londonContext = engine.resolve(
            at: instant,
            preferences: TestFixtures.preferences(),
            timeZone: london,
            reduceMotion: false
        )
        let newYorkContext = engine.resolve(
            at: instant,
            preferences: TestFixtures.preferences(),
            timeZone: newYork,
            reduceMotion: false
        )

        #expect(londonContext.phase == .night)
        #expect(newYorkContext.phase == .afternoon)
        #expect(newYorkContext.presentation == .sunnieAfternoonies)
    }

    @Test("Night brightness reduction dims lighting but never reaches zero")
    func nightBrightnessReductionClamps() {
        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 23),
            preferences: TestFixtures.preferences(nightReduction: 1.0),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.lightingLevel > 0)
        #expect(context.lightingLevel <= 0.3)
    }

    @Test("Daytime lighting ignores the night reduction setting")
    func nightReductionDoesNotAffectDay() {
        let context = engine.resolve(
            at: TestFixtures.date(2026, 7, 15, 12),
            preferences: TestFixtures.preferences(nightReduction: 1.0),
            timeZone: TestFixtures.utc,
            reduceMotion: false
        )

        #expect(context.lightingLevel == 1.0)
    }

    @Test("Sunnie is never assigned a negative expression at any hour")
    func expressionsStayPositive() {
        // The character bible permits no angry, disappointed, or distressed
        // states. Guard the mapping so a future phase cannot introduce one.
        let permitted: Set<SunnieExpression> = [
            .gentleWave, .happyOpenEyed, .happyClosedEyed,
            .calmBreathing, .sleepyHalfLidded, .sleeping
        ]

        for phase in TimePhase.allCases {
            #expect(permitted.contains(TimePhaseEngine.expression(for: phase)))
        }
    }
}
