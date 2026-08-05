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
    @State private var isExporting = false
    @State private var exportedFiles: [URL] = []

    var body: some View {
        Form {
            dayCycleSection
            audioSection
            accessibilitySection
            notificationsSection
            reminderCadenceSection
            quietHoursSection
            dietarySection
            exportSection
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

    /// Export (PLANT_CARE.md §12).
    ///
    /// The user's data is theirs, and this is how they take a copy the app cannot
    /// lose. Both formats are offered because they answer different questions:
    /// JSON keeps the structure, CSV opens in a spreadsheet.
    private var exportSection: some View {
        Section {
            ForEach(JungleExportWriter.Format.allCases, id: \.self) { format in
                Button {
                    Task { await export(format) }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(format.localizationKey))
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)
            }
        } header: {
            Text("settings.section.export", bundle: .main)
        } footer: {
            Text("settings.export.footer", bundle: .main)
        }
        .sheet(isPresented: exportSheetBinding) {
            if !exportedFiles.isEmpty {
                ShareSheet(items: exportedFiles)
            }
        }
    }

    private var exportSheetBinding: Binding<Bool> {
        Binding(
            get: { !exportedFiles.isEmpty },
            set: { if !$0 { exportedFiles = [] } }
        )
    }

    /// Writes the export to a temporary directory and hands it to the share
    /// sheet. Nothing is written into the app's own storage on the way out, and
    /// the directory is unique per export so two in a row cannot mix.
    private func export(_ format: JungleExportWriter.Format) async {
        isExporting = true
        defer { isExporting = false }

        do {
            let export = try await dependencies.exportJungle.build()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SunnieExport-\(UUID().uuidString)", isDirectory: true)
            exportedFiles = try dependencies.exportJungle.write(
                export, format: format, to: directory
            )
        } catch {
            exportedFiles = []
        }
    }

    /// Dietary rules (MEALS_AND_PREP.md §2).
    ///
    /// No eggs is on by default and stays available to turn off — it is
    /// Vanessa's rule, not a setting the app imposes. The footer states exactly
    /// what the filtering does and does not do, because the alternative is a
    /// user assuming an allergen guarantee this app cannot give.
    private var dietarySection: some View {
        Section {
            ForEach(DietaryExclusionCatalog.all) { exclusion in
                Toggle(isOn: binding(
                    get: { $0.dietaryRuleIDs.contains(exclusion.id) },
                    set: { preferences, isOn in
                        if isOn {
                            if !preferences.dietaryRuleIDs.contains(exclusion.id) {
                                preferences.dietaryRuleIDs.append(exclusion.id)
                            }
                        } else {
                            preferences.dietaryRuleIDs.removeAll { $0 == exclusion.id }
                        }
                    }
                )) {
                    Text(LocalizedStringKey(exclusion.displayNameKey))
                }
            }
        } header: {
            Text("settings.section.food", bundle: .main)
        } footer: {
            Text("settings.food.footer", bundle: .main)
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
