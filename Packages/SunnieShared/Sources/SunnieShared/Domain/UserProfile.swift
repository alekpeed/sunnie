import Foundation

public struct UserProfile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    /// The affectionate nickname. Never part of branding or serious system copy
    /// (MASTER_SOURCE_OF_TRUTH.md §9).
    public var preferredNickname: String?
    public var homeTimeZoneID: String
    public var preferredLocale: String
    public var enabledLanguageIDs: [String]
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        preferredNickname: String? = nil,
        homeTimeZoneID: String,
        preferredLocale: String = "en_US",
        enabledLanguageIDs: [String] = ["en"],
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredNickname = preferredNickname
        self.homeTimeZoneID = homeTimeZoneID
        self.preferredLocale = preferredLocale
        self.enabledLanguageIDs = enabledLanguageIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// A window during which the app does not initiate sound or notifications.
public struct QuietHours: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    public var startHour: Int
    public var endHour: Int

    public init(isEnabled: Bool = false, startHour: Int = 22, endHour: Int = 7) {
        self.isEnabled = isEnabled
        self.startHour = startHour
        self.endHour = endHour
    }

    /// Quiet hours may wrap past midnight, so the comparison is not a simple range.
    public func contains(hour: Int) -> Bool {
        guard isEnabled else { return false }
        if startHour == endHour { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }
}

public struct AudioPreferences: Hashable, Sendable, Codable {
    public var musicEnabled: Bool
    public var ambienceEnabled: Bool
    public var effectsEnabled: Bool
    public var masterGain: Double

    public init(
        musicEnabled: Bool = true,
        ambienceEnabled: Bool = true,
        effectsEnabled: Bool = true,
        masterGain: Double = 0.8
    ) {
        self.musicEnabled = musicEnabled
        self.ambienceEnabled = ambienceEnabled
        self.effectsEnabled = effectsEnabled
        self.masterGain = masterGain
    }
}

public struct AccessibilityOverrides: Hashable, Sendable, Codable {
    public var forceHighContrast: Bool
    public var forceReducedMotion: Bool
    /// Dims decorative lighting further at night without reducing text contrast.
    public var nightBrightnessReduction: Double

    public init(
        forceHighContrast: Bool = false,
        forceReducedMotion: Bool = false,
        nightBrightnessReduction: Double = 0
    ) {
        self.forceHighContrast = forceHighContrast
        self.forceReducedMotion = forceReducedMotion
        self.nightBrightnessReduction = nightBrightnessReduction
    }
}

public struct UserPreferences: Hashable, Sendable, Codable {
    public var activeThemeID: ContentID
    /// When true the time engine follows the clock; when false `dayCycleOverride`
    /// pins the presentation.
    public var automaticDayCycle: Bool
    public var dayCycleOverride: TimePhase?
    public var quietHours: QuietHours
    public var audio: AudioPreferences
    public var hapticsEnabled: Bool
    public var accessibility: AccessibilityOverrides
    /// Probability that an eligible Sunnie message uses the nickname.
    /// Approximately 1 in 20 (MASTER_SOURCE_OF_TRUTH.md §9).
    public var nicknameProbability: Double
    public var dietaryRuleIDs: [ContentID]
    /// Use sunrise/sunset instead of the clock fallback. Requires location
    /// permission, so it is off until the user grants it.
    public var useSolarTimes: Bool

    public static let `default` = UserPreferences(
        activeThemeID: ThemeCatalog.lushTropicalJungleID,
        automaticDayCycle: true,
        dayCycleOverride: nil,
        quietHours: QuietHours(),
        audio: AudioPreferences(),
        hapticsEnabled: true,
        accessibility: AccessibilityOverrides(),
        nicknameProbability: 0.05,
        dietaryRuleIDs: [DietaryRule.noEggs],
        useSolarTimes: false
    )

    public init(
        activeThemeID: ContentID,
        automaticDayCycle: Bool,
        dayCycleOverride: TimePhase?,
        quietHours: QuietHours,
        audio: AudioPreferences,
        hapticsEnabled: Bool,
        accessibility: AccessibilityOverrides,
        nicknameProbability: Double,
        dietaryRuleIDs: [ContentID],
        useSolarTimes: Bool
    ) {
        self.activeThemeID = activeThemeID
        self.automaticDayCycle = automaticDayCycle
        self.dayCycleOverride = dayCycleOverride
        self.quietHours = quietHours
        self.audio = audio
        self.hapticsEnabled = hapticsEnabled
        self.accessibility = accessibility
        self.nicknameProbability = nicknameProbability
        self.dietaryRuleIDs = dietaryRuleIDs
        self.useSolarTimes = useSolarTimes
    }

    /// Decodes field by field, falling back to the default for anything absent.
    ///
    /// Preferences are persisted as one encoded blob, so the synthesized
    /// initializer would throw on the *whole* record the first time a new field
    /// is added — and the repository's catch would then hand back defaults,
    /// silently resetting every setting the user had chosen. Decoding leniently
    /// means a new field takes its default and everything else survives.
    ///
    /// This is the migration story for preferences. Removing or repurposing a
    /// field still needs a real migration and an ADR.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UserPreferences.default

        // `try?` flattens the optional, so a single `T?` covers both "the key was
        // absent" and "the value was there but unreadable". Either way the
        // default stands in.
        func value<T: Decodable>(_ key: CodingKeys, _ fallbackValue: T) -> T {
            guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else {
                return fallbackValue
            }
            return decoded
        }

        activeThemeID = value(.activeThemeID, fallback.activeThemeID)
        automaticDayCycle = value(.automaticDayCycle, fallback.automaticDayCycle)
        dayCycleOverride = try? container.decodeIfPresent(
            TimePhase.self, forKey: .dayCycleOverride
        )
        quietHours = value(.quietHours, fallback.quietHours)
        audio = value(.audio, fallback.audio)
        hapticsEnabled = value(.hapticsEnabled, fallback.hapticsEnabled)
        accessibility = value(.accessibility, fallback.accessibility)
        nicknameProbability = value(.nicknameProbability, fallback.nicknameProbability)
        dietaryRuleIDs = value(.dietaryRuleIDs, fallback.dietaryRuleIDs)
        useSolarTimes = value(.useSolarTimes, fallback.useSolarTimes)
    }

    enum CodingKeys: String, CodingKey {
        case activeThemeID
        case automaticDayCycle
        case dayCycleOverride
        case quietHours
        case audio
        case hapticsEnabled
        case accessibility
        case nicknameProbability
        case dietaryRuleIDs
        case useSolarTimes
    }
}

/// Dietary rules are content IDs rather than booleans so Phase 6 can add rules
/// without a schema change. Vanessa's locked rule is no eggs.
public enum DietaryRule {
    public static let noEggs: ContentID = "sunnie.diet.noEggs"
}
