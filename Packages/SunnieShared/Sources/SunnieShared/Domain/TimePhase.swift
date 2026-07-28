import Foundation

/// Internal time phases used by the universal time engine
/// (THEMES_AND_TIME_OF_DAY.md §2).
///
/// These are engine detail. They never appear as user-visible names — only the
/// three branded presentations below do.
public enum TimePhase: String, Hashable, Sendable, Codable, CaseIterable {
    case morning
    case day
    case afternoon
    case evening
    case night
    case lateNight

    public var brandedPresentation: DayCyclePresentation {
        switch self {
        case .morning, .day: .sunnieDays
        case .afternoon: .sunnieAfternoonies
        case .evening, .night, .lateNight: .sunnieNights
        }
    }
}

/// The only three public day-cycle labels permitted (ADR-008).
///
/// "Sunnie Mornings" and "Sunnie Evenings" do not exist and must never be added.
/// The app title stays "Sunnie Days" in every state.
public enum DayCyclePresentation: String, Hashable, Sendable, Codable, CaseIterable {
    case sunnieDays
    case sunnieAfternoonies
    case sunnieNights

    /// Not localized here: user-facing strings live in the app's localization
    /// resources. This is the canonical English source text.
    public var canonicalDisplayName: String {
        switch self {
        case .sunnieDays: "Sunnie Days"
        case .sunnieAfternoonies: "Sunnie Afternoonies"
        case .sunnieNights: "Sunnie Nights"
        }
    }

    public var localizationKey: String {
        switch self {
        case .sunnieDays: "dayCycle.sunnieDays"
        case .sunnieAfternoonies: "dayCycle.sunnieAfternoonies"
        case .sunnieNights: "dayCycle.sunnieNights"
        }
    }
}

/// Semantic modifiers the time engine hands to the theme layer.
///
/// The engine emits meaning, not view code — no colours, asset names, or
/// animation curves (TECHNICAL_ARCHITECTURE.md §4, THEMES_AND_TIME_OF_DAY.md §4).
public struct TimeContext: Hashable, Sendable {
    public let phase: TimePhase
    public let presentation: DayCyclePresentation
    /// 0 = darkest, 1 = brightest. Drives decorative lighting only; it must
    /// never reduce text contrast.
    public let lightingLevel: Double
    /// -1 = cool, 0 = neutral, 1 = warm.
    public let warmth: Double
    public let greeting: GreetingCategory
    public let sunnieExpression: SunnieExpression
    public let suggestedActivity: ActivityCategory
    public let ambientAudioCategory: AmbientAudioCategory
    /// 0 = static, 1 = full motion. Forced to 0 under Reduce Motion.
    public let animationIntensity: Double
    public let isQuietHours: Bool

    public init(
        phase: TimePhase,
        presentation: DayCyclePresentation,
        lightingLevel: Double,
        warmth: Double,
        greeting: GreetingCategory,
        sunnieExpression: SunnieExpression,
        suggestedActivity: ActivityCategory,
        ambientAudioCategory: AmbientAudioCategory,
        animationIntensity: Double,
        isQuietHours: Bool
    ) {
        self.phase = phase
        self.presentation = presentation
        self.lightingLevel = lightingLevel
        self.warmth = warmth
        self.greeting = greeting
        self.sunnieExpression = sunnieExpression
        self.suggestedActivity = suggestedActivity
        self.ambientAudioCategory = ambientAudioCategory
        self.animationIntensity = animationIntensity
        self.isQuietHours = isQuietHours
    }
}

public enum GreetingCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case morningWelcome
    case daytime
    case afternoon
    case eveningWindDown
    case nightRest
    case lateNightGentle
}

public enum ActivityCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case plantCare
    case travelPrep
    case wellnessCheckIn
    case mealPrep
    case gentlePlay
    case restAndCalm
}

public enum AmbientAudioCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case brightMorning
    case openDay
    case warmAfternoon
    case softEvening
    case quietNight
    case silence
}
