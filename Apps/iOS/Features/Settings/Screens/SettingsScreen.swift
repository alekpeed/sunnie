import SwiftUI
import SunnieShared

/// Settings.
///
/// **Placeholder presentation** using standard native controls, which is what
/// this screen should use anyway (VISUAL_DESIGN_SYSTEM.md §12). Present controls
/// all work; export, deletion, and the full permission matrix are Phase 11.
struct SettingsScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var notificationStatus: NotificationAuthorization = .notDetermined

    var body: some View {
        Form {
            dayCycleSection
            audioSection
            accessibilitySection
            notificationsSection
            privacySection
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.settings", bundle: .main))
        .task {
            notificationStatus = await dependencies.notificationService.authorizationStatus()
        }
    }

    // MARK: - Sections

    private var dayCycleSection: some View {
        Section {
            Toggle(
                String(
                    localized: "settings.dayCycle.automatic",
                    defaultValue: "Follow the time of day",
                    comment: "Automatic day cycle toggle"
                ),
                isOn: binding(
                    get: { $0.automaticDayCycle },
                    set: { $0.automaticDayCycle = $1 }
                )
            )

            if !appState.preferences.automaticDayCycle {
                Picker(
                    String(
                        localized: "settings.dayCycle.fixed",
                        defaultValue: "Stay at",
                        comment: "Fixed phase picker"
                    ),
                    selection: binding(
                        get: { $0.dayCycleOverride ?? .day },
                        set: { $0.dayCycleOverride = $1 }
                    )
                ) {
                    ForEach(TimePhase.allCases, id: \.self) { phase in
                        Text(LocalizationKeys.timePhase(phase)).tag(phase)
                    }
                }
            }
        } header: {
            Text("settings.section.dayCycle", bundle: .main)
        } footer: {
            Text("settings.dayCycle.footer", bundle: .main)
        }
    }

    private var audioSection: some View {
        Section {
            Toggle(
                String(localized: "settings.audio.music", defaultValue: "Music", comment: "Music toggle"),
                isOn: binding(get: { $0.audio.musicEnabled }, set: { $0.audio.musicEnabled = $1 })
            )
            Toggle(
                String(localized: "settings.audio.ambience", defaultValue: "Ambience", comment: "Ambience toggle"),
                isOn: binding(get: { $0.audio.ambienceEnabled }, set: { $0.audio.ambienceEnabled = $1 })
            )
            Toggle(
                String(localized: "settings.haptics", defaultValue: "Haptics", comment: "Haptics toggle"),
                isOn: binding(get: { $0.hapticsEnabled }, set: { $0.hapticsEnabled = $1 })
            )

            Toggle(
                String(
                    localized: "settings.quietHours",
                    defaultValue: "Quiet hours",
                    comment: "Quiet hours toggle"
                ),
                isOn: binding(
                    get: { $0.quietHours.isEnabled },
                    set: { $0.quietHours.isEnabled = $1 }
                )
            )
        } header: {
            Text("settings.section.sound", bundle: .main)
        } footer: {
            Text("settings.sound.footer", bundle: .main)
        }
    }

    private var accessibilitySection: some View {
        Section {
            Toggle(
                String(
                    localized: "settings.accessibility.contrast",
                    defaultValue: "Increase contrast",
                    comment: "High contrast toggle"
                ),
                isOn: binding(
                    get: { $0.accessibility.forceHighContrast },
                    set: { $0.accessibility.forceHighContrast = $1 }
                )
            )
            Toggle(
                String(
                    localized: "settings.accessibility.motion",
                    defaultValue: "Reduce motion",
                    comment: "Reduce motion toggle"
                ),
                isOn: binding(
                    get: { $0.accessibility.forceReducedMotion },
                    set: { $0.accessibility.forceReducedMotion = $1 }
                )
            )
        } header: {
            Text("settings.section.accessibility", bundle: .main)
        } footer: {
            Text("settings.accessibility.footer", bundle: .main)
        }
    }

    /// Permission is requested only when the user asks for it here — never at
    /// launch, and never with pressure.
    private var notificationsSection: some View {
        Section {
            LabeledContent {
                Text(LocalizationKeys.notificationStatus(notificationStatus))
                    .foregroundStyle(theme.color.textSecondary)
            } label: {
                Text("settings.notifications.status", bundle: .main)
            }

            if notificationStatus == .notDetermined {
                Button(String(
                    localized: "settings.notifications.enable",
                    defaultValue: "Turn on gentle reminders",
                    comment: "Requests notification permission"
                )) {
                    Task {
                        notificationStatus = await dependencies
                            .notificationService.requestAuthorization()
                    }
                }
            }
        } header: {
            Text("settings.section.reminders", bundle: .main)
        } footer: {
            Text("settings.reminders.footer", bundle: .main)
        }
    }

    private var privacySection: some View {
        Section {
            Text("settings.privacy.body", bundle: .main)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)

            if dependencies.isEphemeralStorage {
                Text("settings.storage.ephemeral", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.error)
            }
        } header: {
            Text("settings.section.privacy", bundle: .main)
        }
    }

    // MARK: - Binding helper

    /// Writes go through `AppState.update`, which persists and republishes, so
    /// no view mutates preferences directly.
    private func binding<Value>(
        get: @escaping (UserPreferences) -> Value,
        set: @escaping (inout UserPreferences, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(appState.preferences) },
            set: { newValue in
                var preferences = appState.preferences
                set(&preferences, newValue)
                Task { await appState.update(preferences: preferences) }
            }
        )
    }
}
