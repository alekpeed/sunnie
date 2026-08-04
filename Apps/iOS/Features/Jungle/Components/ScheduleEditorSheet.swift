import SwiftUI
import SunnieShared

/// Editor for one care schedule (PLANT_CARE.md §3, §4).
///
/// **Placeholder presentation** using native controls.
///
/// The tone constraint that matters here is the footer: the app schedules
/// reminders and makes no claim of biological certainty. An interval is a
/// reminder cadence the user chose, not a prescription, and nothing on this
/// screen may suggest otherwise.
struct ScheduleEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var schedule: PlantCareSchedule
    let isNew: Bool
    let onSaved: () -> Void

    @State private var repeats: Bool = true
    @State private var intervalDays: Int = 7

    /// Seasonal modifiers offered as three coarse choices rather than four free
    /// multipliers. "Water less in winter" is the real request; a 0.85 spring
    /// coefficient is not.
    private enum SeasonalChoice: String, CaseIterable, Identifiable {
        case none
        case lessInWinter
        case muchLessInWinter

        var id: String { rawValue }
        var localizationKey: String { "schedule.seasonal.\(rawValue)" }

        var modifier: SeasonalModifier {
            switch self {
            case .none:
                SeasonalModifier.none
            case .lessInWinter:
                // Longer gaps in autumn and winter, unchanged in the growing
                // season — the pattern almost every houseplant guide describes.
                SeasonalModifier(
                    springMultiplier: 1, summerMultiplier: 1,
                    autumnMultiplier: 1.3, winterMultiplier: 1.6
                )
            case .muchLessInWinter:
                SeasonalModifier(
                    springMultiplier: 1, summerMultiplier: 0.9,
                    autumnMultiplier: 1.5, winterMultiplier: 2.2
                )
            }
        }
    }

    @State private var seasonalChoice: SeasonalChoice = .none

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $schedule.careType) {
                        ForEach(CareType.builtIn, id: \.self) { type in
                            Text(LocalizationKeys.careType(type)).tag(type)
                        }
                    } label: {
                        Text("schedule.field.careType", bundle: .main)
                    }

                    Toggle(isOn: $schedule.isEnabled) {
                        Text("schedule.field.enabled", bundle: .main)
                    }
                } footer: {
                    Text("schedule.field.enabled.footer", bundle: .main)
                }

                Section {
                    Toggle(isOn: $repeats) {
                        Text("schedule.field.repeats", bundle: .main)
                    }

                    if repeats {
                        Stepper(value: $intervalDays, in: 1...365) {
                            Text(
                                "schedule.field.every \(intervalDays)",
                                bundle: .main,
                                comment: "The repeat interval in days"
                            )
                        }

                        Picker(selection: $schedule.preferredHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        } label: {
                            Text("schedule.field.hour", bundle: .main)
                        }
                    }
                } footer: {
                    // States plainly that this is a reminder cadence, not a rule
                    // about the plant.
                    Text("schedule.field.repeats.footer", bundle: .main)
                }

                if repeats {
                    Section {
                        Picker(selection: $seasonalChoice) {
                            ForEach(SeasonalChoice.allCases) { choice in
                                Text(LocalizedStringKey(choice.localizationKey)).tag(choice)
                            }
                        } label: {
                            Text("schedule.field.seasonal", bundle: .main)
                        }
                    } footer: {
                        Text("schedule.field.seasonal.footer", bundle: .main)
                    }
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            Task { await delete() }
                        } label: {
                            Text("schedule.delete", bundle: .main)
                        }
                    } footer: {
                        Text("schedule.delete.footer", bundle: .main)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text(
                isNew ? "schedule.editor.new" : "schedule.editor.edit",
                bundle: .main
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.save",
                        defaultValue: "Save",
                        comment: "Save"
                    )) {
                        Task { await save() }
                    }
                }
            }
            .task { loadFromSchedule() }
        }
    }

    /// Formats an hour in the user's locale, so a 24-hour region does not see
    /// "9 AM".
    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    private func loadFromSchedule() {
        if let days = schedule.recurrence.intervalDays {
            repeats = true
            intervalDays = days
        } else {
            repeats = false
        }

        // Map the stored multipliers back onto the offered choices. Anything that
        // does not match reads as "no adjustment" rather than silently rewriting
        // a modifier the user set some other way.
        let winter = schedule.seasonalModifier.winterMultiplier
        seasonalChoice = switch winter {
        case 2.2: .muchLessInWinter
        case 1.6: .lessInWinter
        default: .none
        }
    }

    private func save() async {
        var updated = schedule
        updated.recurrence = repeats ? .everyDays(intervalDays) : .manual
        updated.seasonalModifier = repeats ? seasonalChoice.modifier : SeasonalModifier.none

        _ = try? await dependencies.managePlant.save(updated)
        onSaved()
        dismiss()
    }

    private func delete() async {
        try? await dependencies.managePlant.deleteSchedule(
            id: schedule.id, plantID: schedule.plantID
        )
        onSaved()
        dismiss()
    }
}
