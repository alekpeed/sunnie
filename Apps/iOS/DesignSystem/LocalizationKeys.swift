import SwiftUI
import SunnieShared

/// Localization keys built from runtime values.
///
/// These exist because `LocalizedStringKey` and `String.LocalizationValue` are
/// `ExpressibleByStringInterpolation`: writing `LocalizedStringKey("phase.\(raw)")`
/// does *not* build the key `"phase.morning"` — it builds `"phase.%@"` with the
/// value as a format argument, and the lookup silently fails.
///
/// Composing the key as a plain `String` first and passing it to
/// `LocalizedStringKey(_:)` avoids that, so every dynamic key goes through here
/// rather than being interpolated at the call site.
enum LocalizationKeys {

    static func timePhase(_ phase: TimePhase) -> LocalizedStringKey {
        LocalizedStringKey("timePhase." + phase.rawValue)
    }

    static func dayCycle(_ presentation: DayCyclePresentation) -> LocalizedStringKey {
        LocalizedStringKey(presentation.localizationKey)
    }

    static func notificationStatus(
        _ status: NotificationAuthorization
    ) -> LocalizedStringKey {
        LocalizedStringKey("settings.notifications." + status.rawValue)
    }

    static func themeName(_ theme: ThemeDefinition) -> LocalizedStringKey {
        LocalizedStringKey(theme.displayNameKey)
    }

    static func lightProfile(_ profile: LightProfile) -> LocalizedStringKey {
        LocalizedStringKey("light." + profile.rawValue)
    }

    static func difficulty(_ difficulty: CareDifficulty) -> LocalizedStringKey {
        LocalizedStringKey("difficulty." + difficulty.rawValue)
    }

    static func plantStatus(_ status: PlantStatus) -> LocalizedStringKey {
        LocalizedStringKey("plantStatus." + status.rawValue)
    }

    static func careType(_ careType: CareType) -> LocalizedStringKey {
        // A custom care type carries its own content ID, which has no entry in
        // the strings file. It falls back to a generic label rather than showing
        // a raw identifier.
        if case .custom = careType {
            return LocalizedStringKey("care.custom")
        }
        return LocalizedStringKey("care." + careType.storageKey)
    }

    static func symptom(_ category: SymptomCategory) -> LocalizedStringKey {
        LocalizedStringKey(category.localizationKey)
    }

    static func severity(_ severity: ObservationSeverity) -> LocalizedStringKey {
        LocalizedStringKey(severity.localizationKey)
    }

    static func growthMetric(_ metric: GrowthMetric) -> LocalizedStringKey {
        LocalizedStringKey(metric.localizationKey)
    }

    static func sortOrder(_ order: PlantSortOrder) -> LocalizedStringKey {
        LocalizedStringKey(order.localizationKey)
    }

    static func reminderCategory(_ category: ReminderCategory) -> LocalizedStringKey {
        LocalizedStringKey("reminder.category." + category.rawValue)
    }

    /// Cadence levels are keyed by name rather than by their raw `Int`, so the
    /// strings stay readable and reordering the enum cannot silently relabel them.
    static func cadenceLevel(_ level: AdaptiveCadenceLevel) -> LocalizedStringKey {
        let name: String
        switch level {
        case .disabled: name = "disabled"
        case .single: name = "single"
        case .singleWithReOffer: name = "singleWithReOffer"
        case .regular: name = "regular"
        }
        return LocalizedStringKey("reminder.cadence." + name)
    }
}
