import SwiftUI
import SunnieShared

/// The growth timeline (PLANT_CARE.md §9).
///
/// **Placeholder presentation** — a chronological list rather than the
/// photo-led timeline the design pass will build. The behaviour is real: photos,
/// measurements, notes, milestones, and a side-by-side comparison of the first
/// and latest comparable entries.
///
/// This is the reward screen of the whole feature. Months of watering pay off as
/// a plant visibly getting bigger, so nothing here is framed as a task.
struct GrowthTimelineScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let plantID: UUID

    @State private var entries: [GrowthEntry] = []
    @State private var comparison: (earliest: GrowthEntry, latest: GrowthEntry)?
    @State private var editing: GrowthEntry?
    @State private var isEditorPresented = false

    var body: some View {
        List {
            if let comparison {
                comparisonSection(comparison)
            }

            if entries.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "growth.empty.title",
                            defaultValue: "No photos yet",
                            comment: "Empty growth timeline"
                        ),
                        message: String(
                            localized: "growth.empty.message",
                            defaultValue: "A photo now gives you something to compare against later. There's no hurry.",
                            comment: "Body of the empty growth state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .happyOpenEyed, pose: .holdingWateringCan, presence: .medium
                        )
                    )
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                } header: {
                    Text("growth.section.timeline", bundle: .main)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("growth.title", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = dependencies.managePlantHealth.newGrowthEntry(plantID: plantID)
                    isEditorPresented = true
                } label: {
                    Label(
                        String(
                            localized: "growth.new",
                            defaultValue: "Add to the timeline",
                            comment: "Adds a growth entry"
                        ),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $isEditorPresented) {
            if let editing {
                GrowthEntryEditorSheet(entry: editing) {
                    Task { await load() }
                }
            }
        }
    }

    /// First and latest, side by side.
    ///
    /// Only shown when there is genuinely something to compare — two comparable
    /// measurements, or two photos. Comparing one entry against itself would be
    /// a control that looks broken.
    private func comparisonSection(
        _ pair: (earliest: GrowthEntry, latest: GrowthEntry)
    ) -> some View {
        Section {
            HStack(alignment: .top, spacing: Space.m) {
                comparisonColumn(pair.earliest, labelKey: "growth.comparison.then")
                comparisonColumn(pair.latest, labelKey: "growth.comparison.now")
            }

            if let delta = deltaDescription(pair) {
                Text(delta)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textPrimary)
            }
        } header: {
            Text("growth.section.comparison", bundle: .main)
        }
    }

    private func comparisonColumn(
        _ entry: GrowthEntry,
        labelKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(LocalizedStringKey(labelKey))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)

            RoundedRectangle(cornerRadius: Radius.image, style: .continuous)
                .fill(theme.color.surface)
                .frame(height: 90)
                .overlay {
                    Image(systemName: entry.photoAttachmentID == nil ? "ruler" : "photo")
                        .foregroundStyle(theme.color.accentPlant)
                }
                .accessibilityHidden(true)

            Text(entry.recordedAt, format: .dateTime.month().year())
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)

            if let measurement = measurementText(entry) {
                Text(measurement)
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Describes the change between two comparable entries.
    ///
    /// Purely descriptive — it states the difference and draws no conclusion
    /// about whether the plant is thriving. Nil unless both entries carry a value
    /// on the same metric in the same unit.
    private func deltaDescription(
        _ pair: (earliest: GrowthEntry, latest: GrowthEntry)
    ) -> String? {
        guard
            pair.earliest.isComparable(with: pair.latest),
            let from = pair.earliest.value,
            let to = pair.latest.value,
            let metric = pair.latest.metric
        else { return nil }

        let difference = to - from
        guard difference != 0 else { return nil }

        let metricName = String(localized: .init(metric.localizationKey))
        let unit = pair.latest.unit.map { " \($0)" } ?? ""
        let formatted = String(format: "%.1f", abs(difference))

        return difference > 0
            ? String(
                localized: "growth.delta.up \(metricName) \(formatted)\(unit)",
                defaultValue: "\(metricName): up \(formatted)\(unit) since then",
                comment: "Describes an increase between two growth entries"
            )
            : String(
                localized: "growth.delta.down \(metricName) \(formatted)\(unit)",
                defaultValue: "\(metricName): down \(formatted)\(unit) since then",
                comment: "Describes a decrease between two growth entries"
            )
    }

    private func row(_ entry: GrowthEntry) -> some View {
        Button {
            editing = entry
            isEditorPresented = true
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: entry.isMilestone
                    ? "star.fill"
                    : (entry.photoAttachmentID == nil ? "ruler" : "photo"))
                    .foregroundStyle(entry.isMilestone
                        ? theme.color.accentSunnie : theme.color.accentPlant)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(entry.recordedAt, format: .dateTime.day().month().year())
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                    if let label = entry.milestoneLabel {
                        Text(label)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textPrimary)
                    }
                    if let measurement = measurementText(entry) {
                        Text(measurement)
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    if let note = entry.note {
                        Text(note)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.managePlantHealth.deleteGrowthEntry(id: entry.id)
                    await load()
                }
            } label: {
                Label(
                    String(localized: "common.delete", defaultValue: "Delete", comment: "Delete"),
                    systemImage: "trash"
                )
            }
        }
    }

    private func measurementText(_ entry: GrowthEntry) -> String? {
        guard let metric = entry.metric, let value = entry.value else { return nil }
        let name = String(localized: .init(metric.localizationKey))
        let formatted = String(format: "%.1f", value)
        let unit = entry.unit.map { " \($0)" } ?? ""
        return "\(name): \(formatted)\(unit)"
    }

    private func load() async {
        entries = (try? await dependencies.managePlantHealth
            .growthEntries(forPlantID: plantID)) ?? []
        comparison = try? await dependencies.managePlantHealth
            .comparisonPair(forPlantID: plantID)
    }
}

/// Editor for one point on the timeline.
///
/// Everything is optional except having *something*: a photo, a measurement, a
/// note, or a milestone. Someone who only ever takes photos never sees a
/// measurement field they have to skip past.
struct GrowthEntryEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var entry: GrowthEntry
    let onSaved: () -> Void

    @State private var recordsMeasurement = false
    @State private var valueText = ""
    @State private var attachmentCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        selection: $entry.recordedAt,
                        displayedComponents: .date
                    ) {
                        Text("growth.field.date", bundle: .main)
                    }
                }

                Section {
                    AttachmentsSection(owner: .plant(entry.plantID)) { count in
                        attachmentCount = count
                    }
                } header: {
                    Text("growth.section.photo", bundle: .main)
                }

                Section {
                    Toggle(isOn: $recordsMeasurement) {
                        Text("growth.field.measure", bundle: .main)
                    }

                    if recordsMeasurement {
                        Picker(selection: Binding(
                            get: { entry.metric ?? .height },
                            set: { entry.metric = $0 }
                        )) {
                            ForEach(GrowthMetric.allCases, id: \.self) { metric in
                                Text(LocalizationKeys.growthMetric(metric)).tag(metric)
                            }
                        } label: {
                            Text("growth.field.metric", bundle: .main)
                        }

                        TextField(
                            String(
                                localized: "growth.field.value",
                                defaultValue: "Measurement",
                                comment: "The measured value"
                            ),
                            text: $valueText
                        )
                        .keyboardType(.decimalPad)

                        if entry.metric?.isCount != true {
                            TextField(
                                String(
                                    localized: "growth.field.unit",
                                    defaultValue: "Unit (cm, in — whatever you use)",
                                    comment: "The unit of measurement"
                                ),
                                text: Binding(
                                    get: { entry.unit ?? "" },
                                    set: { entry.unit = $0.isEmpty ? nil : $0 }
                                )
                            )
                        }
                    }
                } footer: {
                    Text("growth.field.measure.footer", bundle: .main)
                }

                Section {
                    Toggle(isOn: $entry.isMilestone) {
                        Text("growth.field.milestone", bundle: .main)
                    }
                    if entry.isMilestone {
                        TextField(
                            String(
                                localized: "growth.field.milestoneLabel",
                                defaultValue: "What happened (first flower, repotted…)",
                                comment: "A label for the milestone"
                            ),
                            text: Binding(
                                get: { entry.milestoneLabel ?? "" },
                                set: { entry.milestoneLabel = $0.isEmpty ? nil : $0 }
                            )
                        )
                    }

                    TextField(
                        String(
                            localized: "growth.field.note",
                            defaultValue: "Note (optional)",
                            comment: "A note about this point in the timeline"
                        ),
                        text: Binding(
                            get: { entry.note ?? "" },
                            set: { entry.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("growth.editor.title", bundle: .main))
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
                    .disabled(!hasSomething)
                }
            }
            .task {
                recordsMeasurement = entry.value != nil
                valueText = entry.value.map { String(format: "%g", $0) } ?? ""
            }
        }
    }

    /// A photo, a measurement, a note, or a milestone. Any one is enough.
    private var hasSomething: Bool {
        attachmentCount > 0
            || (recordsMeasurement && Double(valueText.replacingOccurrences(of: ",", with: ".")) != nil)
            || entry.isMilestone
            || !(entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        var toSave = entry
        if recordsMeasurement {
            // Accepts a comma decimal separator, because a keyboard in a
            // comma-decimal locale produces one and rejecting it would look like
            // the field is broken.
            toSave.value = Double(valueText.replacingOccurrences(of: ",", with: "."))
            if toSave.metric == nil { toSave.metric = .height }
        } else {
            toSave.value = nil
            toSave.metric = nil
        }

        _ = try? await dependencies.managePlantHealth.save(toSave)
        onSaved()
        dismiss()
    }
}
