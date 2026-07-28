import Foundation

/// The universal time engine (THEMES_AND_TIME_OF_DAY.md §2).
///
/// It affects every theme, not just the branded Day-Cycle theme, and it emits
/// semantic modifiers rather than view code.
public struct TimePhaseEngine: TimePhaseResolving {

    /// Clock fallback used when sunrise/sunset is unavailable — which is the
    /// default, since solar times require location permission the app does not
    /// demand. Ranges are inclusive of the start hour.
    public struct PhaseSchedule: Hashable, Sendable {
        public var morningStart: Int
        public var dayStart: Int
        public var afternoonStart: Int
        public var eveningStart: Int
        public var nightStart: Int
        public var lateNightStart: Int

        /// Morning 05:00, day 11:00, afternoon 14:00, evening 18:00,
        /// night 21:00, late night 00:00.
        public static let `default` = PhaseSchedule(
            morningStart: 5,
            dayStart: 11,
            afternoonStart: 14,
            eveningStart: 18,
            nightStart: 21,
            lateNightStart: 0
        )

        public init(
            morningStart: Int,
            dayStart: Int,
            afternoonStart: Int,
            eveningStart: Int,
            nightStart: Int,
            lateNightStart: Int
        ) {
            self.morningStart = morningStart
            self.dayStart = dayStart
            self.afternoonStart = afternoonStart
            self.eveningStart = eveningStart
            self.nightStart = nightStart
            self.lateNightStart = lateNightStart
        }

        public func phase(forHour hour: Int) -> TimePhase {
            switch hour {
            case lateNightStart..<morningStart: .lateNight
            case morningStart..<dayStart: .morning
            case dayStart..<afternoonStart: .day
            case afternoonStart..<eveningStart: .afternoon
            case eveningStart..<nightStart: .evening
            default: .night
            }
        }
    }

    private let schedule: PhaseSchedule
    private let calendar: Calendar

    public init(schedule: PhaseSchedule = .default, calendar: Calendar = .current) {
        self.schedule = schedule
        self.calendar = calendar
    }

    public func resolve(
        at date: Date,
        preferences: UserPreferences,
        timeZone: TimeZone,
        reduceMotion: Bool
    ) -> TimeContext {
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone
        let hour = zonedCalendar.component(.hour, from: date)

        // A manual override pins the presentation but does not disable the
        // engine — quiet hours still follow the real clock.
        let phase: TimePhase
        if preferences.automaticDayCycle {
            phase = schedule.phase(forHour: hour)
        } else {
            phase = preferences.dayCycleOverride ?? schedule.phase(forHour: hour)
        }

        let isQuiet = preferences.quietHours.contains(hour: hour)
        let motion = reduceMotion || preferences.accessibility.forceReducedMotion
            ? 0
            : Self.animationIntensity(for: phase)

        return TimeContext(
            phase: phase,
            presentation: phase.brandedPresentation,
            lightingLevel: Self.lightingLevel(
                for: phase,
                nightReduction: preferences.accessibility.nightBrightnessReduction
            ),
            warmth: Self.warmth(for: phase),
            greeting: Self.greeting(for: phase),
            sunnieExpression: Self.expression(for: phase),
            suggestedActivity: Self.activity(for: phase),
            ambientAudioCategory: isQuiet ? .silence : Self.ambience(for: phase),
            animationIntensity: motion,
            isQuietHours: isQuiet
        )
    }

    // MARK: - Semantic mapping

    /// Decorative lighting only. Text contrast is the palette's job, so a dark
    /// value here never makes content harder to read.
    static func lightingLevel(for phase: TimePhase, nightReduction: Double) -> Double {
        let base: Double = switch phase {
        case .morning: 0.75
        case .day: 1.0
        case .afternoon: 0.85
        case .evening: 0.5
        case .night: 0.3
        case .lateNight: 0.15
        }
        let isDark = phase == .evening || phase == .night || phase == .lateNight
        guard isDark else { return base }
        let clampedReduction = min(max(nightReduction, 0), 1)
        return max(0.05, base * (1 - clampedReduction))
    }

    static func warmth(for phase: TimePhase) -> Double {
        switch phase {
        case .morning: 0.4
        case .day: 0.1
        case .afternoon: 0.8
        case .evening: 0.5
        case .night: -0.3
        case .lateNight: -0.5
        }
    }

    static func greeting(for phase: TimePhase) -> GreetingCategory {
        switch phase {
        case .morning: .morningWelcome
        case .day: .daytime
        case .afternoon: .afternoon
        case .evening: .eveningWindDown
        case .night: .nightRest
        case .lateNight: .lateNightGentle
        }
    }

    /// Sunnie gets sleepier as the day ends. He is never unhappy — only calmer.
    static func expression(for phase: TimePhase) -> SunnieExpression {
        switch phase {
        case .morning: .gentleWave
        case .day: .happyOpenEyed
        case .afternoon: .happyClosedEyed
        case .evening: .calmBreathing
        case .night: .sleepyHalfLidded
        case .lateNight: .sleeping
        }
    }

    static func activity(for phase: TimePhase) -> ActivityCategory {
        switch phase {
        case .morning: .plantCare
        case .day: .travelPrep
        case .afternoon: .mealPrep
        case .evening: .wellnessCheckIn
        case .night, .lateNight: .restAndCalm
        }
    }

    static func ambience(for phase: TimePhase) -> AmbientAudioCategory {
        switch phase {
        case .morning: .brightMorning
        case .day: .openDay
        case .afternoon: .warmAfternoon
        case .evening: .softEvening
        case .night: .quietNight
        case .lateNight: .silence
        }
    }

    /// Motion calms down at night rather than stopping outright, so the app does
    /// not feel broken in the evening.
    static func animationIntensity(for phase: TimePhase) -> Double {
        switch phase {
        case .morning, .day: 1.0
        case .afternoon: 0.8
        case .evening: 0.5
        case .night: 0.3
        case .lateNight: 0.15
        }
    }
}
