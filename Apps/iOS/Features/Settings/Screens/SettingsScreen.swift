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
            reminderCadenceSection
            quietHoursSection
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

    /// Per-category cadence.
    ///
    /// Every category starts at "None" and stays there until the user chooses
    /// otherwise: reminders are opt-in one kind at a time, and granting
    /// notification permission does not by itself turn any of them on
    /// (NOTIFICATIONS_AND_REMINDERS.md §5).
    ///
    /// Only the categories whose features exist are listed. Offering a switch for
    /// travel reminders before travel is built would be a setting that does
    /// nothing.
    @ViewBuilder
    private var reminderCadenceSection: some View {
        if notificationStatus == .authorized || notificationStatus == .provisional {
            Section {
                ForEach(Self.availableReminderCategories, id: \.self) { category in
                    Picker(
                        selection: cadenceBinding(for: category)
                    ) {
                        ForEach(AdaptiveCadenceLevel.allCases, id: \.self) { level in
                            Text(LocalizationKeys.cadenceLevel(level)).tag(level)
                        }
                    } label: {
                        Text(LocalizationKeys.reminderCategory(category))
                    }
                }
            } header: {
                Text("settings.section.cadence", bundle: .main)
            } footer: {
                Text("settings.cadence.footer", bundle: .main)
            }
        }
    }

    /// Categories with a feature behind them today. Extended as features land.
    private static let availableReminderCategories: [ReminderCategory] = [.plantCare]

    /// Quiet hours.
    ///
    /// Nothing is cancelled by quiet hours — a reminder due inside the window is
    /// moved to the edge of it, so the task is not lost, it just doesn't wake
    /// anyone (NOTIFICATIONS_AND_REMINDERS.md §7).
    private var quietHoursSection: some View {
        Section {
            Toggle(isOn: binding(
                get: { $0.quietHours.isEnabled },
                set: { $0.quietHours.isEnabled = $1 }
            )) {
                Text("settings.quietHours.enabled", bundle: .main)
            }

            if appState.preferences.quietHours.isEnabled {
                Picker(selection: binding(
                    get: { $0.quietHours.startHour },
                    set: { $0.quietHours.startHour = $1 }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                } label: {
                    Text("settings.quietHours.start", bundle: .main)
                }

                Picker(selection: binding(
                    get: { $0.quietHours.endHour },
                    set: { $0.quietHours.endHour = $1 }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                } label: {
                    Text("settings.quietHours.end", bundle: .main)
                }
            }
        } header: {
            Text("settings.section.quietHours", bundle: .main)
        } footer: {
            Text("settings.quietHours.footer", bundle: .main)
        }
    }

    /// Formats an hour in the user's locale, so a 24-hour region does not see
    /// "10 PM".
    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    private func cadenceBinding(
        for category: ReminderCategory
    ) -> Binding<AdaptiveCadenceLevel> {
        binding(
            get: { $0.reminderLevel(for: category) },
            set: { $0.setReminderLevel($1, for: category) }
        )
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
