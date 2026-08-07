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

/// The user's sound controls (AUDIO_MIDI_AND_SOUNDSCAPES.md §9).
///
/// Every layer in §4 has an enable state and a gain here, because that is what
/// §4 asks for and because one master volume is not enough: someone who wants
/// the meditation bell but no bed needs two controls, not one.
///
/// Two of these default to *off* on purpose. `autoPlayAmbience` is off because
/// §6 says so — nothing may make a sound on launch that the user did not ask
/// for. `backgroundPlaybackEnabled` is off because turning it on changes the
/// audio session category, and with it whether the ring/silent switch still
/// works; that is a decision to be offered, not assumed.
public struct AudioPreferences: Hashable, Sendable, Codable {
    public var musicEnabled: Bool
    public var ambienceEnabled: Bool
    public var effectsEnabled: Bool
    /// Reserved for voice. Off until there is something to narrate (§4).
    public var narrationEnabled: Bool
    public var masterGain: Double
    /// Per-layer gain, 0…1, keyed by `AudioLayer.rawValue`.
    ///
    /// A dictionary rather than four fields so a new layer needs no migration —
    /// the same reasoning `reminderLevels` uses. An absent key means 1, which is
    /// "this layer does not attenuate", not "this layer is silent".
    public var layerGains: [String: Double]
    /// Whether music and ambience may start on their own when a screen appears.
    /// Off by default (§6). A sound the user taps always plays regardless.
    public var autoPlayAmbience: Bool
    /// Whether a practice keeps sounding once the screen locks (§7, §10).
    public var backgroundPlaybackEnabled: Bool
    /// The ambience chosen for a given theme, keyed by theme id raw value (§9,
    /// "per-theme ambience setting"). Absent means "let the context decide".
    public var themeAmbienceIDs: [String: String]

    public init(
        musicEnabled: Bool = true,
        ambienceEnabled: Bool = true,
        effectsEnabled: Bool = true,
        narrationEnabled: Bool = false,
        masterGain: Double = 0.8,
        layerGains: [String: Double] = [:],
        autoPlayAmbience: Bool = false,
        backgroundPlaybackEnabled: Bool = false,
        themeAmbienceIDs: [String: String] = [:]
    ) {
        self.musicEnabled = musicEnabled
        self.ambienceEnabled = ambienceEnabled
        self.effectsEnabled = effectsEnabled
        self.narrationEnabled = narrationEnabled
        self.masterGain = masterGain
        self.layerGains = layerGains
        self.autoPlayAmbience = autoPlayAmbience
        self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
        self.themeAmbienceIDs = themeAmbienceIDs
    }

    /// Whether anything on this layer may sound.
    public func isEnabled(_ layer: AudioLayer) -> Bool {
        switch layer {
        case .music: musicEnabled
        case .ambience: ambienceEnabled
        case .effects: effectsEnabled
        case .narration: narrationEnabled
        // Bells follow the effects switch rather than having their own toggle.
        // A "meditation bells" control on the settings screen beside "effects"
        // is a distinction only the mixer cares about.
        case .meditationBell: effectsEnabled
        }
    }

    public func gain(for layer: AudioLayer) -> Double {
        min(max(layerGains[layer.rawValue] ?? 1, 0), 1)
    }

    public mutating func setGain(_ gain: Double, for layer: AudioLayer) {
        layerGains[layer.rawValue] = min(max(gain, 0), 1)
    }

    /// Track gain × layer gain × master gain, clamped.
    ///
    /// One multiplication chain in one place, so a level can never be computed
    /// two different ways in two features.
    public func effectiveGain(for layer: AudioLayer, trackGain: Double) -> Double {
        guard isEnabled(layer) else { return 0 }
        let combined = min(max(trackGain, 0), 1) * gain(for: layer) * min(max(masterGain, 0), 1)
        return min(max(combined, 0), 1)
    }

    public func ambienceID(forTheme themeID: ContentID) -> ContentID? {
        themeAmbienceIDs[themeID.rawValue].map(ContentID.init(rawValue:))
    }

    public mutating func setAmbienceID(_ id: ContentID?, forTheme themeID: ContentID) {
        if let id {
            themeAmbienceIDs[themeID.rawValue] = id.rawValue
        } else {
            themeAmbienceIDs.removeValue(forKey: themeID.rawValue)
        }
    }

    /// Decodes field by field, for the reason `UserPreferences` documents at
    /// length: this is stored inside that one encoded blob, so a synthesized
    /// initializer would throw on the whole record the first time a field was
    /// added here — and the enclosing lenient decoder would then quietly hand
    /// back default audio settings, resetting a volume the user had chosen.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AudioPreferences()

        func value<T: Decodable>(_ key: CodingKeys, _ fallbackValue: T) -> T {
            guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else {
                return fallbackValue
            }
            return decoded
        }

        musicEnabled = value(.musicEnabled, fallback.musicEnabled)
        ambienceEnabled = value(.ambienceEnabled, fallback.ambienceEnabled)
        effectsEnabled = value(.effectsEnabled, fallback.effectsEnabled)
        narrationEnabled = value(.narrationEnabled, fallback.narrationEnabled)
        masterGain = value(.masterGain, fallback.masterGain)
        layerGains = value(.layerGains, fallback.layerGains)
        autoPlayAmbience = value(.autoPlayAmbience, fallback.autoPlayAmbience)
        backgroundPlaybackEnabled = value(
            .backgroundPlaybackEnabled, fallback.backgroundPlaybackEnabled
        )
        themeAmbienceIDs = value(.themeAmbienceIDs, fallback.themeAmbienceIDs)
    }

    enum CodingKeys: String, CodingKey {
        case musicEnabled
        case ambienceEnabled
        case effectsEnabled
        case narrationEnabled
        case masterGain
        case layerGains
        case autoPlayAmbience
        case backgroundPlaybackEnabled
        case themeAmbienceIDs
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
    /// Cadence level per reminder category, keyed by the category's raw value.
    ///
    /// A dictionary rather than fixed fields so a new category needs no schema
    /// change. Absent means disabled — reminders are opt-in, one category at a
    /// time (NOTIFICATIONS_AND_REMINDERS.md §5).
    public var reminderLevels: [String: Int]
    /// Calm sounds the user marked as favourites.
    public var favoriteCalmSoundIDs: [ContentID]
    /// Minutes before calm sounds fade out on their own. Nil means play until stopped.
    public var calmSoundTimerMinutes: Int?
    /// Whether to show the caring-days count at all
    /// (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §5, "user may hide rhythm
    /// metrics"). On by default because it is a warm number, and turn-off-able
    /// because for some people any number becomes a target.
    public var showsRhythm: Bool
    /// Health types the user has asked the app to use, as
    /// `HealthDataType` raw values.
    ///
    /// Stored as strings rather than a typed set so a future type needs no
    /// migration, and empty by default: every integration is optional and
    /// nothing is requested until someone asks for it
    /// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §1).
    ///
    /// This records what the app *asked for*, not what it was granted. HealthKit
    /// does not report read denial, so the granted set is unknowable and any
    /// field claiming to hold it would be wrong (§12).
    public var healthTypeKeys: [String]

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
        useSolarTimes: false,
        reminderLevels: [:],
        favoriteCalmSoundIDs: [],
        calmSoundTimerMinutes: nil,
        showsRhythm: true,
        healthTypeKeys: []
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
        useSolarTimes: Bool,
        reminderLevels: [String: Int] = [:],
        favoriteCalmSoundIDs: [ContentID] = [],
        calmSoundTimerMinutes: Int? = nil,
        showsRhythm: Bool = true,
        healthTypeKeys: [String] = []
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
        self.reminderLevels = reminderLevels
        self.favoriteCalmSoundIDs = favoriteCalmSoundIDs
        self.calmSoundTimerMinutes = calmSoundTimerMinutes
        self.showsRhythm = showsRhythm
        self.healthTypeKeys = healthTypeKeys
    }

    /// The cadence the user chose for a category. Disabled unless they said otherwise.
    public func reminderLevel(for category: ReminderCategory) -> AdaptiveCadenceLevel {
        guard let raw = reminderLevels[category.rawValue] else { return .disabled }
        return AdaptiveCadenceLevel(rawValue: raw) ?? .disabled
    }

    public mutating func setReminderLevel(
        _ level: AdaptiveCadenceLevel,
        for category: ReminderCategory
    ) {
        reminderLevels[category.rawValue] = level.rawValue
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
        reminderLevels = value(.reminderLevels, fallback.reminderLevels)
        favoriteCalmSoundIDs = value(.favoriteCalmSoundIDs, fallback.favoriteCalmSoundIDs)
        calmSoundTimerMinutes = try? container.decodeIfPresent(
            Int.self, forKey: .calmSoundTimerMinutes
        )
        showsRhythm = value(.showsRhythm, fallback.showsRhythm)
        healthTypeKeys = value(.healthTypeKeys, fallback.healthTypeKeys)
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
        case reminderLevels
        case favoriteCalmSoundIDs
        case showsRhythm
        case healthTypeKeys
        case calmSoundTimerMinutes
    }
}

/// Dietary rules are content IDs rather than booleans so Phase 6 can add rules
/// without a schema change. Vanessa's locked rule is no eggs.
public enum DietaryRule {
    public static let noEggs: ContentID = "sunnie.diet.noEggs"
}
