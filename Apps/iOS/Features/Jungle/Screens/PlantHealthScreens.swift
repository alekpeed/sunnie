import SwiftUI
import SunnieShared

/// Health observations for one plant (PLANT_CARE.md §8).
///
/// **Placeholder presentation.** The rule that governs every string here: the app
/// records what the user noticed and does not diagnose. There is no computed
/// assessment, no predicted cause, and no language suggesting the app knows what
/// is wrong with a plant.
struct PlantHealthScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let plantID: UUID

    @State private var observations: [PlantHealthObservation] = []
    @State private var editing: PlantHealthObservation?
    @State private var isEditorPresented = false

    var body: some View {
        List {
            if observations.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "health.empty.title",
                            defaultValue: "Nothing noted",
                            comment: "Empty health history"
                        ),
                        message: String(
                            localized: "health.empty.message",
                            defaultValue: "If you ever notice something about this plant, you can write it down here.",
                            comment: "Body of the empty health state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .curious, pose: .standingNeutral, presence: .medium
                        )
                    )
                }
            } else {
                let open = observations.filter { !$0.isResolved }
                let resolved = observations.filter(\.isResolved)

                if !open.isEmpty {
                    Section {
                        ForEach(open) { observation in
                            row(observation)
                        }
                    } header: {
                        Text("health.section.open", bundle: .main)
                    }
                }

                if !resolved.isEmpty {
                    Section {
                        ForEach(resolved) { observation in
                            row(observation)
                        }
                    } header: {
                        Text("health.section.resolved", bundle: .main)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("health.title", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = dependencies.managePlantHealth.newObservation(plantID: plantID)
                    isEditorPresented = true
                } label: {
                    Label(
                        String(
                            localized: "health.new",
                            defaultValue: "Note something",
                            comment: "Adds a health observation"
                        ),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $isEditorPresented) {
            if let editing {
                ObservationEditorSheet(observation: editing) {
                    Task { await load() }
                }
            }
        }
    }

    private func row(_ observation: PlantHealthObservation) -> some View {
        Button {
            editing = observation
            isEditorPresented = true
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack {
                    Text(LocalizationKeys.symptom(observation.category))
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    StatusChip(
                        text: String(localized: .init(observation.severity.localizationKey)),
                        style: observation.isResolved ? .done : .neutral
                    )
                }
                Text(observation.observedAt, format: .dateTime.day().month().year())
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                if let notes = observation.notes {
                    Text(notes)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            if observation.isResolved {
                Button {
                    Task {
                        _ = try? await dependencies.managePlantHealth
                            .reopen(observationID: observation.id)
                        await load()
                    }
                } label: {
                    Label(
                        String(
                            localized: "health.reopen",
                            defaultValue: "Reopen",
                            comment: "Marks a resolved observation open again"
                        ),
                        systemImage: "arrow.uturn.backward"
                    )
                }
            } else {
                Button {
                    Task {
                        _ = try? await dependencies.managePlantHealth
                            .resolve(observationID: observation.id)
                        await load()
                    }
                } label: {
                    Label(
                        String(
                            localized: "health.resolve",
                            defaultValue: "Better now",
                            comment: "Marks an observation resolved"
                        ),
                        systemImage: "checkmark"
                    )
                }
                .tint(theme.color.success)
            }
        }
    }

    private func load() async {
        observations = (try? await dependencies.managePlantHealth
            .observations(forPlantID: plantID)) ?? []
    }
}

/// Editor for one observation.
///
/// Every field the user fills in is theirs: what they saw, how much it seems to
/// matter, what they think caused it, what they tried. Nothing is prefilled by
/// the app beyond the date.
struct ObservationEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var observation: PlantHealthObservation
    let onSaved: () -> Void

    @State private var wantsFollowUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        selection: $observation.observedAt,
                        displayedComponents: .date
                    ) {
                        Text("health.field.date", bundle: .main)
                    }

                    Picker(selection: $observation.category) {
                        ForEach(SymptomCategory.allCases, id: \.self) { category in
                            Text(LocalizationKeys.symptom(category)).tag(category)
                        }
                    } label: {
                        Text("health.field.category", bundle: .main)
                    }

                    Picker(selection: $observation.severity) {
                        ForEach(ObservationSeverity.allCases, id: \.self) { severity in
                            Text(LocalizationKeys.severity(severity)).tag(severity)
                        }
                    } label: {
                        Text("health.field.severity", bundle: .main)
                    }
                } footer: {
                    // States outright that the app is not assessing anything.
                    Text("health.field.severity.footer", bundle: .main)
                }

                Section {
                    TextField(
                        String(
                            localized: "health.field.notes",
                            defaultValue: "What you noticed",
                            comment: "Observation notes"
                        ),
                        text: optional($observation.notes),
                        axis: .vertical
                    )
                    .lineLimit(2...8)

                    TextField(
                        String(
                            localized: "health.field.cause",
                            defaultValue: "What you think might have caused it (optional)",
                            comment: "The user's own suspected cause"
                        ),
                        text: optional($observation.suspectedCause),
                        axis: .vertical
                    )
                    .lineLimit(1...5)

                    TextField(
                        String(
                            localized: "health.field.treatment",
                            defaultValue: "What you tried (optional)",
                            comment: "What the user did about it"
                        ),
                        text: optional($observation.treatment),
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                }

                Section {
                    Toggle(isOn: $wantsFollowUp) {
                        Text("health.field.followUp", bundle: .main)
                    }
                    if wantsFollowUp {
                        DatePicker(
                            selection: Binding(
                                get: { observation.followUpDate ?? Date() },
                                set: { observation.followUpDate = $0 }
                            ),
                            displayedComponents: .date
                        ) {
                            Text("health.field.followUpDate", bundle: .main)
                        }
                    }
                }

                Section {
                    AttachmentsSection(owner: .plant(observation.plantID))
                } header: {
                    Text("health.section.photos", bundle: .main)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("health.editor.title", bundle: .main))
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
            .task { wantsFollowUp = observation.followUpDate != nil }
        }
    }

    private func save() async {
        var toSave = observation
        // Turning the toggle off must actually clear the date, or a follow-up the
        // user cancelled would still be stored.
        if !wantsFollowUp { toSave.followUpDate = nil }

        _ = try? await dependencies.managePlantHealth.save(toSave)
        onSaved()
        dismiss()
    }

    private func optional(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
