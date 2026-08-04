import SwiftUI
import SunnieShared

/// Add or edit a plant (S-05).
///
/// **Placeholder presentation** using native form sections with progressive
/// disclosure, which is what the spec asks for anyway.
///
/// The rule that shapes the whole screen: **saving is never blocked because
/// reference content is missing.** Only a name is required. Everything else is
/// collapsed, optional, and can be filled in later or never.
struct PlantEditorScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let existing: Plant?
    let onSaved: (Plant) -> Void

    @State private var plant: Plant?
    @State private var locations: [PlantLocation] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showsDetails = false
    @State private var showsNotes = false
    @State private var newLocationName = ""

    var body: some View {
        NavigationStack {
            Form {
                if let binding = plantBinding {
                    essentialsSection(binding)
                    detailsSection(binding)
                    notesSection(binding)
                    if existing != nil { attachmentsSection(binding.wrappedValue) }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text(
                existing == nil ? "plant.editor.new" : "plant.editor.edit",
                bundle: .main
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Leaves the editor without saving"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.save",
                        defaultValue: "Save",
                        comment: "Saves the plant"
                    )) {
                        Task { await save() }
                    }
                    // The only thing that can disable Save is a missing name.
                    // Nothing else — not a failed lookup, not a missing photo.
                    .disabled(isSaving || !hasName)
                }
            }
            .task { await load() }
        }
    }

    // MARK: - Sections

    private func essentialsSection(_ plant: Binding<Plant>) -> some View {
        Section {
            TextField(
                String(
                    localized: "plant.field.name",
                    defaultValue: "Name",
                    comment: "The plant's name"
                ),
                text: plant.name
            )
            .textInputAutocapitalization(.words)

            TextField(
                String(
                    localized: "plant.field.nickname",
                    defaultValue: "Nickname (optional)",
                    comment: "An affectionate name for the plant"
                ),
                text: optional(plant.nickname)
            )

            Picker(selection: plant.locationID) {
                Text("plant.location.none", bundle: .main).tag(UUID?.none)
                ForEach(locations) { location in
                    Text(location.name).tag(UUID?.some(location.id))
                }
            } label: {
                Text("plant.field.location", bundle: .main)
            }

            HStack {
                TextField(
                    String(
                        localized: "plant.location.new",
                        defaultValue: "Add a room",
                        comment: "Creates a new location"
                    ),
                    text: $newLocationName
                )
                Button {
                    Task { await addLocation() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("plant.location.newAction", bundle: .main))
            }
        } header: {
            Text("plant.section.essentials", bundle: .main)
        } footer: {
            Text("plant.section.essentials.footer", bundle: .main)
        }
    }

    /// Everything here is optional and collapsed by default, so adding a plant is
    /// a name and a tap rather than a form to work through.
    private func detailsSection(_ plant: Binding<Plant>) -> some View {
        Section(isExpanded: $showsDetails) {
            TextField(
                String(
                    localized: "plant.field.species",
                    defaultValue: "Species",
                    comment: "The plant's species"
                ),
                text: optional(plant.speciesName)
            )
            TextField(
                String(
                    localized: "plant.field.variety",
                    defaultValue: "Variety",
                    comment: "The plant's cultivar or variety"
                ),
                text: optional(plant.variety)
            )

            Picker(selection: plant.lightProfile) {
                ForEach(LightProfile.allCases, id: \.self) { profile in
                    Text(LocalizationKeys.lightProfile(profile)).tag(profile)
                }
            } label: {
                Text("plant.field.light", bundle: .main)
            }

            Picker(selection: plant.difficulty) {
                ForEach(CareDifficulty.allCases, id: \.self) { difficulty in
                    Text(LocalizationKeys.difficulty(difficulty)).tag(difficulty)
                }
            } label: {
                Text("plant.field.difficulty", bundle: .main)
            }

            DatePicker(
                selection: dateBinding(plant.acquiredDate),
                displayedComponents: .date
            ) {
                Text("plant.field.acquired", bundle: .main)
            }

            TextField(
                String(
                    localized: "plant.field.source",
                    defaultValue: "Where it came from",
                    comment: "Where the plant was acquired"
                ),
                text: optional(plant.source)
            )
            TextField(
                String(
                    localized: "plant.field.pot",
                    defaultValue: "Pot",
                    comment: "The plant's pot"
                ),
                text: optional(plant.pot)
            )
            TextField(
                String(
                    localized: "plant.field.soil",
                    defaultValue: "Soil",
                    comment: "The plant's soil or substrate"
                ),
                text: optional(plant.soil)
            )
        } header: {
            Text("plant.section.details", bundle: .main)
        }
    }

    private func notesSection(_ plant: Binding<Plant>) -> some View {
        Section(isExpanded: $showsNotes) {
            TextField(
                String(
                    localized: "plant.field.notes",
                    defaultValue: "Anything worth remembering",
                    comment: "Free notes about the plant"
                ),
                text: optional(plant.notes),
                axis: .vertical
            )
            .lineLimit(3...10)

            Picker(selection: plant.status) {
                ForEach(PlantStatus.allCases, id: \.self) { status in
                    Text(LocalizationKeys.plantStatus(status)).tag(status)
                }
            } label: {
                Text("plant.field.status", bundle: .main)
            }
        } header: {
            Text("plant.section.notes", bundle: .main)
        }
    }

    /// Photos attach to the saved plant, so this only appears when editing —
    /// a new plant has no ID for media to belong to until it is saved once.
    private func attachmentsSection(_ plant: Plant) -> some View {
        Section {
            AttachmentsSection(owner: .plant(plant.id))
        } header: {
            Text("plant.section.photos", bundle: .main)
        }
    }

    // MARK: - Bindings

    private var plantBinding: Binding<Plant>? {
        guard plant != nil else { return nil }
        return Binding(
            get: { plant ?? dependencies.managePlant.newDraft() },
            set: { plant = $0 }
        )
    }

    private var hasName: Bool {
        !(plant?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Bridges an optional string field to a `TextField`, which needs a
    /// non-optional. An emptied field becomes nil on save rather than an empty
    /// string that would later render as a blank line.
    private func optional(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    /// `DatePicker` cannot represent "no date". Unknown acquisition dates are
    /// common — most plants arrive without a receipt — so an untouched picker
    /// shows today but only commits a date once the user changes it.
    private func dateBinding(_ source: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: { source.wrappedValue ?? Date() },
            set: { source.wrappedValue = $0 }
        )
    }

    // MARK: - Actions

    private func load() async {
        locations = (try? await dependencies.plantRepository.locations()) ?? []
        if plant == nil {
            plant = existing ?? dependencies.managePlant.newDraft()
        }
    }

    private func addLocation() async {
        let name = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let location = PlantLocation(name: name, sortOrder: locations.count)
        guard let saved = try? await dependencies.managePlant.save(location) else { return }

        locations = (try? await dependencies.plantRepository.locations()) ?? locations
        plant?.locationID = saved.id
        newLocationName = ""
    }

    private func save() async {
        guard let plant else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let saved = try await dependencies.managePlant.save(plant)
            onSaved(saved)
            dismiss()
        } catch DomainError.validationFailed {
            errorMessage = String(
                localized: "plant.error.needsName",
                defaultValue: "A name is all that's needed to save. Everything else can wait.",
                comment: "Shown when the plant has no name"
            )
        } catch {
            errorMessage = String(
                localized: "plant.error.save",
                defaultValue: "That didn't save just now. Nothing has changed, and you can try again.",
                comment: "Shown when saving a plant fails"
            )
        }
    }
}
