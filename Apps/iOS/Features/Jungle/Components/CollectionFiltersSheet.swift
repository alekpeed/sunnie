import SwiftUI
import SunnieShared

/// The collection filter sheet (S-03).
///
/// **Placeholder presentation** — native toggles and pickers. Every filter is
/// multi-select except the due window, and "Show all" is always one tap away, so
/// a filtered collection is never something the user has to puzzle their way out
/// of.
struct CollectionFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @Bindable var model: CollectionModel

    /// Offered due windows. Fixed rather than free entry — the useful questions
    /// are "today", "this week", "this fortnight", not "in 13 days".
    private static let dueWindows: [Int] = [1, 7, 14, 30]

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                dueSection
                if !model.locations.isEmpty { locationSection }
                if !model.availableSpecies.isEmpty { speciesSection }
                careTypeSection
                if !model.caretakers.isEmpty { caretakerSection }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("collection.filters", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "collection.clearFilters",
                        defaultValue: "Show all",
                        comment: "Clears every filter"
                    )) {
                        model.clearFilters()
                    }
                    .disabled(!model.query.isFiltering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.done",
                        defaultValue: "Done",
                        comment: "Closes the sheet"
                    )) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            ForEach(PlantStatus.allCases, id: \.self) { status in
                toggleRow(
                    label: Text(LocalizationKeys.plantStatus(status)),
                    isOn: model.query.statuses.contains(status)
                ) { isOn in
                    // An empty status set would match nothing and read as a
                    // broken screen, so the last one cannot be turned off.
                    if isOn {
                        model.query.statuses.insert(status)
                    } else if model.query.statuses.count > 1 {
                        model.query.statuses.remove(status)
                    }
                }
            }
        } header: {
            Text("collection.filter.status", bundle: .main)
        }
    }

    private var dueSection: some View {
        Section {
            Picker(selection: $model.query.dueWithinDays) {
                Text("collection.filter.due.any", bundle: .main).tag(Int?.none)
                ForEach(Self.dueWindows, id: \.self) { days in
                    Text(
                        "collection.filter.due.days \(days)",
                        bundle: .main,
                        comment: "A due-within window in days"
                    )
                    .tag(Int?.some(days))
                }
            } label: {
                Text("collection.filter.due", bundle: .main)
            }
        } footer: {
            Text("collection.filter.due.footer", bundle: .main)
        }
    }

    private var locationSection: some View {
        Section {
            ForEach(model.locations) { location in
                toggleRow(
                    label: Text(location.name),
                    isOn: model.query.locationIDs.contains(location.id)
                ) { isOn in
                    if isOn {
                        model.query.locationIDs.insert(location.id)
                    } else {
                        model.query.locationIDs.remove(location.id)
                    }
                }
            }
        } header: {
            Text("collection.filter.location", bundle: .main)
        }
    }

    private var speciesSection: some View {
        Section {
            ForEach(model.availableSpecies, id: \.self) { species in
                toggleRow(
                    label: Text(species),
                    isOn: model.query.species.contains(species)
                ) { isOn in
                    if isOn {
                        model.query.species.insert(species)
                    } else {
                        model.query.species.remove(species)
                    }
                }
            }
        } header: {
            Text("collection.filter.species", bundle: .main)
        }
    }

    /// Only the built-in care types. Custom types belong to individual plants and
    /// listing every one a user has ever invented would make this unusable.
    private var careTypeSection: some View {
        Section {
            ForEach(CareType.builtIn, id: \.self) { careType in
                toggleRow(
                    label: Text(LocalizationKeys.careType(careType)),
                    isOn: model.query.careTypes.contains(careType)
                ) { isOn in
                    if isOn {
                        model.query.careTypes.insert(careType)
                    } else {
                        model.query.careTypes.remove(careType)
                    }
                }
            }
        } header: {
            Text("collection.filter.careType", bundle: .main)
        }
    }

    private var caretakerSection: some View {
        Section {
            ForEach(model.caretakers) { caretaker in
                toggleRow(
                    label: Text(caretaker.name),
                    isOn: model.query.caretakerIDs.contains(caretaker.id)
                ) { isOn in
                    if isOn {
                        model.query.caretakerIDs.insert(caretaker.id)
                    } else {
                        model.query.caretakerIDs.remove(caretaker.id)
                    }
                }
            }
        } header: {
            Text("collection.filter.caretaker", bundle: .main)
        }
    }

    private func toggleRow(
        label: Text,
        isOn: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) { label }
    }
}
