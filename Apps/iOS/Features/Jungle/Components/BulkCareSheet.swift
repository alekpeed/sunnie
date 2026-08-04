import SwiftUI
import SunnieShared

/// Log the same care for several plants, with per-plant overrides (S-03).
///
/// **Placeholder presentation.** The behaviour that matters is the result: each
/// plant is recorded independently, so a partial failure keeps everything that
/// did work and says plainly which plants to try again — it never rolls the
/// others back (PLANT_CARE.md §15).
struct BulkCareSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let items: [PlantCollectionItem]
    /// Called with whether anything was recorded, so the caller knows whether to
    /// reload.
    let onFinish: (Bool) -> Void

    @State private var careType: CareType = .water
    @State private var entries: [UUID: BulkCareItem] = [:]
    @State private var isSaving = false
    @State private var result: BulkCareResult?

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSection(result)
                } else {
                    careTypeSection
                    plantsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("bulkCare.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { prepareEntries() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var careTypeSection: some View {
        Section {
            Picker(selection: $careType) {
                ForEach(CareType.builtIn, id: \.self) { type in
                    Text(LocalizationKeys.careType(type)).tag(type)
                }
            } label: {
                Text("bulkCare.type", bundle: .main)
            }
        } footer: {
            Text("bulkCare.footer", bundle: .main)
        }
    }

    private var plantsSection: some View {
        Section {
            ForEach(items) { item in
                plantRow(item)
            }
        } header: {
            Text(
                "bulkCare.plants \(includedCount)",
                bundle: .main,
                comment: "How many plants the action will apply to"
            )
        }
    }

    private func plantRow(_ item: PlantCollectionItem) -> some View {
        let entry = entries[item.id] ?? BulkCareItem(plantID: item.id)

        return VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(isOn: Binding(
                get: { entry.isIncluded },
                set: { entries[item.id]?.isIncluded = $0 }
            )) {
                Text(item.plant.displayName)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
            }

            if entry.isIncluded {
                // Per-plant override. Nearly always left alone, which is why it
                // is a compact picker rather than a second screen.
                Picker(selection: Binding(
                    get: { entries[item.id]?.careTypeOverride ?? careType },
                    set: { newValue in
                        entries[item.id]?.careTypeOverride =
                            newValue == careType ? nil : newValue
                    }
                )) {
                    ForEach(CareType.builtIn, id: \.self) { type in
                        Text(LocalizationKeys.careType(type)).tag(type)
                    }
                } label: {
                    Text("bulkCare.override", bundle: .main)
                }
                .pickerStyle(.menu)

                TextField(
                    String(
                        localized: "bulkCare.note",
                        defaultValue: "Note (optional)",
                        comment: "A per-plant note"
                    ),
                    text: Binding(
                        get: { entries[item.id]?.note ?? "" },
                        set: { entries[item.id]?.note = $0.isEmpty ? nil : $0 }
                    )
                )
                .font(SunnieFont.secondary)
            }
        }
    }

    /// What actually happened, per plant.
    ///
    /// Successes are stated first and plainly. A failure is offered as a retry,
    /// never as a reprimand, and the plants that worked stay worked.
    private func resultSection(_ result: BulkCareResult) -> some View {
        Section {
            Text(
                "bulkCare.result \(result.recordedCount)",
                bundle: .main,
                comment: "How many plants were recorded"
            )
            .font(SunnieFont.body)
            .foregroundStyle(theme.color.textPrimary)

            if result.hasFailures {
                Text("bulkCare.result.partial", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)

                ForEach(failedItems(result), id: \.id) { item in
                    Text(item.plant.displayName)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }

                SunnieSecondaryButton(
                    title: String(
                        localized: "bulkCare.retry",
                        defaultValue: "Try those again",
                        comment: "Retries the plants that failed"
                    )
                ) {
                    retryFailures(result)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(
                localized: result == nil ? "common.cancel" : "common.done",
                defaultValue: result == nil ? "Cancel" : "Done",
                comment: "Closes the bulk care sheet"
            )) {
                onFinish(result != nil)
                dismiss()
            }
        }

        if result == nil {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(
                    localized: "bulkCare.save",
                    defaultValue: "Log it",
                    comment: "Records the bulk care action"
                )) {
                    Task { await save() }
                }
                .disabled(isSaving || includedCount == 0)
            }
        }
    }

    // MARK: - Actions

    private var includedCount: Int {
        entries.values.filter(\.isIncluded).count
    }

    private func prepareEntries() {
        guard entries.isEmpty else { return }
        entries = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, BulkCareItem(plantID: $0.id)) }
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Ordered by the list rather than by dictionary order, so the history
        // reads in the order the user saw the plants.
        let ordered = items.compactMap { entries[$0.id] }
        result = await dependencies.logBulkCare(careType: careType, items: ordered)
    }

    private func retryFailures(_ previous: BulkCareResult) {
        let failed = Set(previous.failedPlantIDs)
        for id in entries.keys {
            entries[id]?.isIncluded = failed.contains(id)
        }
        result = nil
    }

    private func failedItems(_ result: BulkCareResult) -> [PlantCollectionItem] {
        let failed = Set(result.failedPlantIDs)
        return items.filter { failed.contains($0.id) }
    }
}
