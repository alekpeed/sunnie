import SwiftUI
import SunnieShared

/// Create or edit a trip.
///
/// **Placeholder presentation** using native form sections. Only a title is
/// required — the same rule as the plant editor. A trip with no dates is in
/// `planning`, which is a real state rather than an incomplete one.
struct TripEditorScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let existing: Trip?
    let type: TripType
    let onSaved: (Trip) -> Void

    @State private var trip: Trip?
    @State private var places: [Place] = []
    @State private var hasDates = false
    @State private var newPlaceName = ""
    @State private var errorMessage: String?
    @State private var calendarStatus: CalendarAuthorization = .notDetermined
    @State private var wantsCalendarEvent = false

    var body: some View {
        NavigationStack {
            Form {
                if let binding = tripBinding {
                    basicsSection(binding)
                    datesSection(binding)
                    placesSection(binding)
                    if binding.wrappedValue.type.isPlannable { calendarSection }
                    notesSection(binding)
                    if existing != nil { dangerSection }
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
                existing == nil ? "trip.editor.new" : "trip.editor.edit",
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
                    .disabled(!hasTitle)
                }
            }
            .task { await load() }
        }
    }

    // MARK: - Sections

    private func basicsSection(_ trip: Binding<Trip>) -> some View {
        Section {
            TextField(
                String(
                    localized: "trip.field.title",
                    defaultValue: "What to call it",
                    comment: "The trip's title"
                ),
                text: trip.title
            )
            .textInputAutocapitalization(.words)

            Picker(selection: trip.type) {
                ForEach(TripType.allCases, id: \.self) { type in
                    Text(LocalizedStringKey(type.localizationKey)).tag(type)
                }
            } label: {
                Text("trip.field.type", bundle: .main)
            }
        } footer: {
            Text("trip.field.title.footer", bundle: .main)
        }
    }

    private func datesSection(_ trip: Binding<Trip>) -> some View {
        Section {
            Toggle(isOn: $hasDates) {
                Text("trip.field.hasDates", bundle: .main)
            }

            if hasDates {
                DatePicker(
                    selection: Binding(
                        get: { trip.wrappedValue.startsAt ?? Date() },
                        set: { trip.wrappedValue.startsAt = $0 }
                    ),
                    displayedComponents: .date
                ) {
                    Text("trip.field.starts", bundle: .main)
                }

                DatePicker(
                    selection: Binding(
                        get: { trip.wrappedValue.endsAt ?? trip.wrappedValue.startsAt ?? Date() },
                        set: { trip.wrappedValue.endsAt = $0 }
                    ),
                    displayedComponents: .date
                ) {
                    Text("trip.field.ends", bundle: .main)
                }
            }
        } footer: {
            Text("trip.field.dates.footer", bundle: .main)
        }
    }

    private func placesSection(_ trip: Binding<Trip>) -> some View {
        Section {
            ForEach(places.filter { trip.wrappedValue.placeIDs.contains($0.id) }) { place in
                HStack {
                    Text(place.name)
                    Spacer()
                    Button {
                        trip.wrappedValue.placeIDs.removeAll { $0 == place.id }
                        syncDestinationZones(trip)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .accessibilityLabel(Text("trip.place.remove", bundle: .main))
                }
            }

            Menu {
                ForEach(places.filter { !trip.wrappedValue.placeIDs.contains($0.id) }) { place in
                    Button(place.name) {
                        trip.wrappedValue.placeIDs.append(place.id)
                        syncDestinationZones(trip)
                    }
                }
            } label: {
                Text("trip.place.addExisting", bundle: .main)
            }
            .disabled(places.allSatisfy { trip.wrappedValue.placeIDs.contains($0.id) })

            HStack {
                TextField(
                    String(
                        localized: "trip.place.new",
                        defaultValue: "Somewhere new",
                        comment: "Creates a place"
                    ),
                    text: $newPlaceName
                )
                Button {
                    Task { await addPlace(trip) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newPlaceName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("trip.place.newAction", bundle: .main))
            }
        } header: {
            Text("trip.section.places", bundle: .main)
        }
    }

    /// Calendar linking. Permission is requested here, from an explicit toggle —
    /// never at launch, and the trip saves fine without it.
    @ViewBuilder
    private var calendarSection: some View {
        if existing?.calendarEventID == nil {
            Section {
                Toggle(isOn: $wantsCalendarEvent) {
                    Text("trip.field.calendar", bundle: .main)
                }
                .disabled(calendarStatus == .denied || !hasDates)

                if calendarStatus == .denied {
                    Text("trip.calendar.denied", bundle: .main)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            } footer: {
                Text("trip.field.calendar.footer", bundle: .main)
            }
        }
    }

    private func notesSection(_ trip: Binding<Trip>) -> some View {
        Section {
            TextField(
                String(
                    localized: "trip.field.notes",
                    defaultValue: "Anything worth remembering",
                    comment: "Trip notes"
                ),
                text: Binding(
                    get: { trip.wrappedValue.notes ?? "" },
                    set: { trip.wrappedValue.notes = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...10)
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await deleteTrip() }
            } label: {
                Text("trip.delete", bundle: .main)
            }
        } footer: {
            // States plainly what goes and what stays, so it can never be
            // mistaken for archiving.
            Text("trip.delete.footer", bundle: .main)
        }
    }

    // MARK: - State

    private var tripBinding: Binding<Trip>? {
        guard trip != nil else { return nil }
        return Binding(
            get: { trip ?? dependencies.manageTrip.newDraft(type: type) },
            set: { trip = $0 }
        )
    }

    private var hasTitle: Bool {
        !(trip?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Keeps the destination zones in step with the chosen places.
    ///
    /// Only places that carry a zone contribute. A place typed from memory has
    /// none, and the trip falls back to showing home time alone rather than
    /// guessing a zone from a name.
    private func syncDestinationZones(_ trip: Binding<Trip>) {
        let zones = trip.wrappedValue.placeIDs.compactMap { id in
            places.first { $0.id == id }?.timeZoneID
        }
        trip.wrappedValue.destinationTimeZoneIDs = Array(NSOrderedSet(array: zones)) as? [String] ?? zones
    }

    private func load() async {
        places = (try? await dependencies.manageTrip.places()) ?? []
        calendarStatus = await dependencies.calendarProvider.authorizationStatus()

        if trip == nil {
            let draft = existing ?? dependencies.manageTrip.newDraft(type: type)
            trip = draft
            hasDates = draft.startsAt != nil
        }
    }

    private func addPlace(_ trip: Binding<Trip>) async {
        let name = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var place = dependencies.manageTrip.newPlace(name: name)
        // The device's zone is a reasonable default for somewhere just typed; it
        // is editable on the place itself.
        place.timeZoneID = nil

        guard let saved = try? await dependencies.manageTrip.save(place) else { return }
        places = (try? await dependencies.manageTrip.places()) ?? places
        trip.wrappedValue.placeIDs.append(saved.id)
        newPlaceName = ""
    }

    private func save() async {
        guard var toSave = trip else { return }
        if !hasDates {
            toSave.startsAt = nil
            toSave.endsAt = nil
        }

        do {
            var saved = try await dependencies.manageTrip.save(toSave)

            if wantsCalendarEvent, saved.calendarEventID == nil, let start = saved.startsAt {
                await linkCalendar(&saved, start: start)
            }

            onSaved(saved)
            dismiss()
        } catch DomainError.validationFailed {
            errorMessage = String(
                localized: "trip.error.needsTitle",
                defaultValue: "A name is all that's needed. Everything else can wait.",
                comment: "Shown when a trip has no title"
            )
        } catch {
            errorMessage = String(
                localized: "trip.error.save",
                defaultValue: "That didn't save just now. Nothing has changed, and you can try again.",
                comment: "Shown when a trip cannot be saved"
            )
        }
    }

    /// Creates the calendar event and stores its identifier.
    ///
    /// The trip is already saved by the time this runs, so a refused permission
    /// or a failed write costs a calendar entry and nothing else.
    private func linkCalendar(_ trip: inout Trip, start: Date) async {
        var status = calendarStatus
        if status == .notDetermined {
            status = await dependencies.calendarProvider.requestAccess()
            calendarStatus = status
        }
        guard status == .authorized || status == .writeOnly else { return }

        let identifier = await dependencies.calendarProvider.createEvent(
            title: trip.title,
            startsAt: start,
            endsAt: trip.endsAt ?? start,
            notes: trip.notes
        )
        guard let identifier else { return }

        trip.calendarEventID = identifier
        _ = try? await dependencies.manageTrip.save(trip)
    }

    private func deleteTrip() async {
        guard let id = trip?.id else { return }
        try? await dependencies.manageTrip.delete(tripID: id)
        dismiss()
    }
}

/// The packing list (S-08).
///
/// **Placeholder presentation.** Work, personal, and food are separate sections
/// as the spec requires — three different questions, and mixing them makes the
/// list harder to work through.
///
/// Nothing here is enforced. An unpacked "required" item is not a failure and
/// nothing blocks on it.
struct PackingScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let tripID: UUID

    @State private var items: [PackingItem] = []
    @State private var templates: [PackingTemplate] = []
    @State private var duplicates: [[PackingItem]] = []
    @State private var searchText = ""
    @State private var newItemName = ""
    @State private var newItemCategory: PackingCategory = .personal
    @State private var addedCount: Int?
    @State private var isNamingTemplate = false
    @State private var templateName = ""

    var body: some View {
        List {
            if let addedCount {
                Section {
                    Text(
                        "packing.added \(addedCount)",
                        bundle: .main,
                        comment: "How many items a template added"
                    )
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                }
            }

            if !duplicates.isEmpty {
                duplicatesSection
            }

            addSection

            ForEach(PackingCategory.Section.allCases, id: \.self) { section in
                let sectionItems = visibleItems.filter { $0.category.section == section }
                if !sectionItems.isEmpty {
                    Section {
                        ForEach(sectionItems) { item in
                            row(item)
                        }
                    } header: {
                        HStack {
                            Text(LocalizedStringKey(section.localizationKey))
                            Spacer()
                            let counts = PackingListBuilder.progress(for: items, in: section)
                            Text(
                                "trip.progress.counts \(counts.packed) \(counts.total)",
                                bundle: .main,
                                comment: "How many of a list are done"
                            )
                        }
                    }
                }
            }

            if items.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "packing.empty.title",
                            defaultValue: "Nothing on the list",
                            comment: "Empty packing list"
                        ),
                        message: String(
                            localized: "packing.empty.message",
                            defaultValue: "Start from a saved list, or add things as you think of them.",
                            comment: "Body of the empty packing state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .traveling, pose: .pullingSuitcase, presence: .medium
                        )
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("trip.progress.packing", bundle: .main))
        .searchable(text: $searchText)
        .toolbar { toolbarContent }
        .task { await load() }
        .alert(
            Text("packing.template.name", bundle: .main),
            isPresented: $isNamingTemplate
        ) {
            TextField(
                String(
                    localized: "packing.template.namePlaceholder",
                    defaultValue: "Name it",
                    comment: "Template name field"
                ),
                text: $templateName
            )
            Button(String(
                localized: "common.save",
                defaultValue: "Save",
                comment: "Save"
            )) {
                Task { await saveAsTemplate() }
            }
            Button(String(
                localized: "common.cancel",
                defaultValue: "Cancel",
                comment: "Cancel"
            ), role: .cancel) {}
        }
    }

    private var visibleItems: [PackingItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Duplicates are surfaced, never merged — two things called "charger" might
    /// genuinely be two chargers.
    private var duplicatesSection: some View {
        Section {
            ForEach(Array(duplicates.enumerated()), id: \.offset) { _, group in
                Text(
                    "packing.duplicate \(group.first?.name ?? "") \(group.count)",
                    bundle: .main,
                    comment: "Names a duplicated packing item and how many there are"
                )
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
            }
        } header: {
            Text("packing.duplicates", bundle: .main)
        } footer: {
            Text("packing.duplicates.footer", bundle: .main)
        }
    }

    private var addSection: some View {
        Section {
            HStack {
                TextField(
                    String(
                        localized: "packing.add",
                        defaultValue: "Add something",
                        comment: "Adds a packing item"
                    ),
                    text: $newItemName
                )
                .onSubmit { Task { await addItem() } }

                Picker("", selection: $newItemCategory) {
                    ForEach(PackingCategory.allCases, id: \.self) { category in
                        Text(LocalizedStringKey(category.localizationKey)).tag(category)
                    }
                }
                .labelsHidden()

                Button {
                    Task { await addItem() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("packing.addAction", bundle: .main))
            }
        }
    }

    private func row(_ item: PackingItem) -> some View {
        HStack(spacing: Space.s) {
            Button {
                Task { await togglePacked(item) }
            } label: {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isPacked ? theme.color.success : theme.color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(
                item.isPacked ? "packing.unpack" : "packing.pack",
                bundle: .main
            ))

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(item.name)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .strikethrough(item.isPacked, color: theme.color.textSecondary)

                if let reason = item.suggestionReason {
                    Text(reason)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Spacer()

            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if item.isRequired {
                // A soft label, not a red asterisk. Nothing is enforced.
                Text("packing.required", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.managePacking.delete(itemID: item.id)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(templates) { template in
                    Button(template.name) {
                        Task { await apply(template) }
                    }
                }

                if !templates.isEmpty { Divider() }

                Button {
                    templateName = ""
                    isNamingTemplate = true
                } label: {
                    Label(
                        String(
                            localized: "packing.saveAsTemplate",
                            defaultValue: "Save this as a list",
                            comment: "Creates a template from the trip's packing list"
                        ),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .disabled(items.isEmpty)
            } label: {
                Label(
                    String(
                        localized: "packing.templates",
                        defaultValue: "Saved lists",
                        comment: "Packing template menu"
                    ),
                    systemImage: "list.bullet.rectangle"
                )
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        items = (try? await dependencies.managePacking.items(forTripID: tripID)) ?? []
        duplicates = (try? await dependencies.managePacking.duplicates(forTripID: tripID)) ?? []

        let type = (try? await dependencies.travelRepository.trip(id: tripID))?.type
        templates = (try? await dependencies.managePacking.templates(for: type ?? .personal)) ?? []
    }

    private func addItem() async {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        _ = try? await dependencies.managePacking.save(PackingItem(
            tripID: tripID,
            name: name,
            category: newItemCategory,
            sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1
        ))
        newItemName = ""
        await load()
    }

    private func togglePacked(_ item: PackingItem) async {
        await MainActor.run { dependencies.haptics.selection() }
        try? await dependencies.managePacking.setPacked(!item.isPacked, item: item)
        await load()
    }

    private func apply(_ template: PackingTemplate) async {
        addedCount = try? await dependencies.managePacking.apply(
            template: template, toTripID: tripID
        )
        await load()
    }

    private func saveAsTemplate() async {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let type = (try? await dependencies.travelRepository.trip(id: tripID))?.type
        _ = try? await dependencies.managePacking.makeTemplate(
            named: name, fromTripID: tripID, tripType: type
        )
        await load()
    }
}
