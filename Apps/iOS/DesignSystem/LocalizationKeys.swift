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
}
