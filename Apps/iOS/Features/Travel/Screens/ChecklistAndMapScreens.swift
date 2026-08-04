import SwiftUI
import SunnieShared
#if canImport(MapKit)
import MapKit
#endif

/// A trip checklist (TRAVEL_AND_FLIGHT_ATTENDANT.md §7).
///
/// **Placeholder presentation.**
///
/// **Nothing here is an official procedure, and the copy never implies it is**
/// (§1, §7). These are personal reminders — lock the door, water the plants —
/// and an unticked line is not a failure.
struct TripChecklistScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    let tripID: UUID
    let phase: ChecklistKind.Phase

    @State private var items: [ChecklistItem] = []
    @State private var newTitle = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField(
                        String(
                            localized: "checklist.add",
                            defaultValue: "Add a reminder",
                            comment: "Adds a checklist item"
                        ),
                        text: $newTitle
                    )
                    .onSubmit { Task { await add() } }

                    Button {
                        Task { await add() }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(Text("checklist.addAction", bundle: .main))
                }
            }

            ForEach(kinds, id: \.self) { kind in
                let kindItems = items.filter { $0.kind == kind }
                if !kindItems.isEmpty {
                    Section {
                        ForEach(kindItems) { item in
                            row(item)
                        }
                    } header: {
                        Text(LocalizedStringKey(kind.localizationKey))
                    }
                }
            }

            if items.isEmpty {
                Section {
                    Text("checklist.empty", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text(LocalizedStringKey("checklist.phase.\(phase.rawValue)")))
        .task { await load() }
    }

    private var kinds: [ChecklistKind] {
        ChecklistKind.allCases.filter { $0.phase == phase }
    }

    private func row(_ item: ChecklistItem) -> some View {
        HStack(spacing: Space.s) {
            Button {
                Task { await toggle(item) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? theme.color.success : theme.color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(
                item.isDone ? "checklist.undo" : "checklist.done",
                bundle: .main
            ))

            Text(item.title)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
                .strikethrough(item.isDone, color: theme.color.textSecondary)

            Spacer()

            // A line that refers to something the app knows about opens it,
            // rather than leaving the user to remember what it meant.
            if let route = item.linkedRoute,
               let url = URL(string: route),
               let destination = DeepLinkParser.route(from: url) {
                Button {
                    router.handle(destination)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .foregroundStyle(theme.color.accentTravel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("checklist.open", bundle: .main))
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.manageChecklists.delete(itemID: item.id)
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

    private func load() async {
        items = (try? await dependencies.manageChecklists
            .items(forTripID: tripID, phase: phase)) ?? []
    }

    private func add() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        _ = try? await dependencies.manageChecklists.save(ChecklistItem(
            tripID: tripID,
            kind: kinds.first ?? .beforeLeaving,
            title: title,
            sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1
        ))
        newTitle = ""
        await load()
    }

    private func toggle(_ item: ChecklistItem) async {
        dependencies.haptics.selection()
        try? await dependencies.manageChecklists.setDone(!item.isDone, item: item)
        await load()
    }
}

/// Plant coverage for a trip (PLANT_CARE.md §10).
///
/// **Placeholder presentation.** Every plant is listed, including the ones
/// needing nothing — leaving them out would make this read as a list of
/// problems, when most of the answer is usually "these are fine".
///
/// A plant with no decision is *undecided*, never *at risk*. Nothing here tells
/// someone their plants are in danger.
struct PlantCoverageScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let tripID: UUID

    @State private var rows: [PlanTravelCoverage.CoverageRow] = []
    @State private var caretakers: [Caretaker] = []
    @State private var isLoaded = false
    @State private var newCaretakerName = ""

    var body: some View {
        List {
            if !isLoaded {
                Section {
                    LoadingStateView(message: String(
                        localized: "coverage.loading",
                        defaultValue: "Working out what's due…",
                        comment: "Loading state for plant coverage"
                    ))
                }
            } else if rows.isEmpty {
                Section {
                    Text("coverage.noPlants", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }
            } else {
                caretakerSection

                let needing = rows.filter(\.need.needsAnything)
                let fine = rows.filter { !$0.need.needsAnything }

                if !needing.isEmpty {
                    Section {
                        ForEach(needing) { row in
                            coverageRow(row)
                        }
                    } header: {
                        Text("coverage.section.needing", bundle: .main)
                    }
                }

                if !fine.isEmpty {
                    Section {
                        ForEach(fine) { row in
                            Text(row.plant.displayName)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    } header: {
                        Text("coverage.section.fine", bundle: .main)
                    } footer: {
                        Text("coverage.section.fine.footer", bundle: .main)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("coverage.title", bundle: .main))
        .task { await load() }
    }

    private var caretakerSection: some View {
        Section {
            HStack {
                TextField(
                    String(
                        localized: "coverage.caretaker.new",
                        defaultValue: "Someone who can help",
                        comment: "Adds a caretaker"
                    ),
                    text: $newCaretakerName
                )
                Button {
                    Task { await addCaretaker() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newCaretakerName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("coverage.caretaker.newAction", bundle: .main))
            }
        } header: {
            Text("coverage.section.caretakers", bundle: .main)
        }
    }

    private func coverageRow(_ row: PlanTravelCoverage.CoverageRow) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(row.plant.displayName)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                Spacer()

                if row.isUndecided {
                    StatusChip(
                        text: String(
                            localized: "coverage.undecided",
                            defaultValue: "Not decided",
                            comment: "A plant with no coverage decision"
                        ),
                        style: .neutral
                    )
                }
            }

            Text(
                "coverage.timesDue \(row.need.dueDuringAbsence.count)",
                bundle: .main,
                comment: "How many times a plant needs care during the trip"
            )
            .font(SunnieFont.caption)
            .foregroundStyle(theme.color.textSecondary)

            Picker(selection: assignmentBinding(row)) {
                Text("coverage.assignment.unresolved", bundle: .main)
                    .tag(CoverageAssignment.unresolved)
                Text("coverage.assignment.selfManaged", bundle: .main)
                    .tag(CoverageAssignment.selfManaged)
                ForEach(caretakers) { caretaker in
                    Text(caretaker.name).tag(CoverageAssignment.caretaker(caretaker.id))
                }
            } label: {
                Text("coverage.assignment", bundle: .main)
            }
            .pickerStyle(.menu)
        }
        .accessibilityElement(children: .contain)
    }

    private func assignmentBinding(
        _ row: PlanTravelCoverage.CoverageRow
    ) -> Binding<CoverageAssignment> {
        Binding(
            get: { row.assignment },
            set: { newValue in
                Task { await assign(newValue, to: row) }
            }
        )
    }

    private func load() async {
        defer { isLoaded = true }

        guard let trip = try? await dependencies.travelRepository.trip(id: tripID),
              let window = TripStatusCalculator.absenceWindow(
                  for: trip, calendar: dependencies.clock.calendar
              )
        else {
            rows = []
            return
        }

        rows = (try? await dependencies.planTravelCoverage.rows(
            tripID: tripID, absenceStart: window.start, absenceEnd: window.end
        )) ?? []
        caretakers = (try? await dependencies.plantHealthRepository
            .caretakers(includingInactive: false)) ?? []
    }

    private func assign(
        _ assignment: CoverageAssignment,
        to row: PlanTravelCoverage.CoverageRow
    ) async {
        _ = try? await dependencies.planTravelCoverage.assign(
            assignment,
            plantID: row.plant.id,
            tripID: tripID,
            need: row.need,
            plantName: row.plant.displayName
        )
        await load()
    }

    private func addCaretaker() async {
        let name = newCaretakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        try? await dependencies.plantHealthRepository.save(
            Caretaker(name: name, createdAt: dependencies.clock.now)
        )
        newCaretakerName = ""
        await load()
    }
}

/// The world map (S-09).
///
/// **Placeholder presentation.**
///
/// The offline rule is the design constraint: when map tiles are unavailable the
/// screen must still be useful and must not show an empty grey rectangle that
/// looks broken. The list is always present and always complete; the map is a
/// view *of* the records, not the records themselves
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §12, §16).
struct WorldMapScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var items: [PlaceListItem] = []
    @State private var query = PlaceQuery.default
    @State private var showsMap = true
    @State private var editingPlace: Place?

    var body: some View {
        VStack(spacing: 0) {
            #if canImport(MapKit)
            if showsMap, !mappable.isEmpty {
                Map {
                    ForEach(mappable) { item in
                        if let latitude = item.place.latitude,
                           let longitude = item.place.longitude {
                            Marker(
                                item.place.name,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: latitude, longitude: longitude
                                )
                            )
                            .tint(item.place.isFavorite
                                ? theme.color.accentWarm : theme.color.accentTravel)
                        }
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous))
                .padding(Space.m)
            }
            #endif

            list
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("travel.map.title", bundle: .main))
        .searchable(text: $query.searchText)
        .toolbar { toolbarContent }
        .task { await load() }
        .sheet(item: $editingPlace) { place in
            PlaceEditorSheet(place: place) { Task { await load() } }
        }
    }

    private var visible: [PlaceListItem] {
        PlaceFilter.apply(query, to: items)
    }

    private var mappable: [PlaceListItem] {
        visible.filter(\.place.hasCoordinate)
    }

    private var list: some View {
        List {
            if query.isFiltering {
                Section {
                    HStack {
                        Text(
                            "travel.map.filtered \(visible.count) \(items.count)",
                            bundle: .main,
                            comment: "How many places are visible out of the total"
                        )
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)

                        Spacer()

                        Button(String(
                            localized: "collection.clearFilters",
                            defaultValue: "Show all",
                            comment: "Clears every filter"
                        )) {
                            query = .default
                        }
                        .font(SunnieFont.caption)
                    }
                }
            }

            if visible.isEmpty {
                Section {
                    Text(
                        query.isFiltering ? "travel.map.noMatches" : "travel.map.empty",
                        bundle: .main
                    )
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                }
            } else {
                ForEach(visible) { item in
                    Button {
                        editingPlace = item.place
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(item.place.name)
                                    .font(SunnieFont.body)
                                    .foregroundStyle(theme.color.textPrimary)
                                if let country = item.place.country {
                                    Text(country)
                                        .font(SunnieFont.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }
                            }
                            Spacer()
                            if item.place.isFavorite {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(theme.color.accentWarm)
                                    .accessibilityHidden(true)
                            }
                            if item.memoryCount > 0 {
                                Text("\(item.memoryCount)")
                                    .font(SunnieFont.numeric)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(isOn: $query.favoritesOnly) {
                    Text("travel.map.favoritesOnly", bundle: .main)
                }

                Picker(selection: $query.year) {
                    Text("travel.map.anyYear", bundle: .main).tag(Int?.none)
                    ForEach(PlaceFilter.availableYears(in: items), id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                } label: {
                    Text("travel.map.year", bundle: .main)
                }

                Divider()

                Button {
                    showsMap.toggle()
                } label: {
                    Label(
                        String(
                            localized: showsMap ? "travel.map.hideMap" : "travel.map.showMap",
                            defaultValue: showsMap ? "Just the list" : "Show the map",
                            comment: "Toggles the map"
                        ),
                        systemImage: showsMap ? "list.bullet" : "map"
                    )
                }

                Button {
                    editingPlace = dependencies.manageTrip.newPlace()
                } label: {
                    Label(
                        String(
                            localized: "travel.map.addPlace",
                            defaultValue: "Add a place",
                            comment: "Creates a place"
                        ),
                        systemImage: "plus"
                    )
                }
            } label: {
                Label(
                    String(
                        localized: "collection.options",
                        defaultValue: "Options",
                        comment: "Options menu"
                    ),
                    systemImage: "ellipsis.circle"
                )
            }
        }
    }

    private func load() async {
        items = (try? await dependencies.manageTrip.placeListItems()) ?? []
    }
}

/// Editor for one place.
struct PlaceEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var place: Place
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(
                            localized: "place.field.name",
                            defaultValue: "Name",
                            comment: "The place's name"
                        ),
                        text: $place.name
                    )
                    TextField(
                        String(
                            localized: "place.field.country",
                            defaultValue: "Country",
                            comment: "The place's country"
                        ),
                        text: Binding(
                            get: { place.country ?? "" },
                            set: { place.country = $0.isEmpty ? nil : $0 }
                        )
                    )
                    Toggle(isOn: $place.isFavorite) {
                        Text("place.field.favorite", bundle: .main)
                    }
                }

                Section {
                    Picker(selection: Binding(
                        get: { place.timeZoneID ?? "" },
                        set: { place.timeZoneID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("place.timeZone.none", bundle: .main).tag("")
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    } label: {
                        Text("place.field.timeZone", bundle: .main)
                    }
                } footer: {
                    // The zone is what makes the two clocks work, and it is
                    // stored rather than looked up so it works offline.
                    Text("place.field.timeZone.footer", bundle: .main)
                }

                Section {
                    TextField(
                        String(
                            localized: "place.field.notes",
                            defaultValue: "Notes",
                            comment: "Notes about a place"
                        ),
                        text: Binding(
                            get: { place.notes ?? "" },
                            set: { place.notes = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("place.editor.title", bundle: .main))
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
                        Task {
                            _ = try? await dependencies.manageTrip.save(place)
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(place.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Editor for one travel memory.
///
/// A memory needs a title, some text, a place, or a photo — any one. A
/// photograph of somewhere is a complete memory on its own.
struct MemoryEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var memory: TravelMemory
    let places: [Place]
    let onSaved: () -> Void

    @State private var attachmentCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        selection: $memory.occurredAt,
                        displayedComponents: .date
                    ) {
                        Text("memory.field.date", bundle: .main)
                    }

                    TextField(
                        String(
                            localized: "memory.field.title",
                            defaultValue: "Title (optional)",
                            comment: "A memory's title"
                        ),
                        text: Binding(
                            get: { memory.title ?? "" },
                            set: { memory.title = $0.isEmpty ? nil : $0 }
                        )
                    )

                    TextField(
                        String(
                            localized: "memory.field.text",
                            defaultValue: "What happened",
                            comment: "A memory's text"
                        ),
                        text: Binding(
                            get: { memory.text ?? "" },
                            set: { memory.text = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...12)

                    Picker(selection: $memory.placeID) {
                        Text("memory.place.none", bundle: .main).tag(UUID?.none)
                        ForEach(places) { place in
                            Text(place.name).tag(UUID?.some(place.id))
                        }
                    } label: {
                        Text("memory.field.place", bundle: .main)
                    }

                    Toggle(isOn: $memory.isFavorite) {
                        Text("memory.field.favorite", bundle: .main)
                    }
                }

                if let owner = memory.mediaOwner {
                    Section {
                        AttachmentsSection(owner: owner) { count in
                            attachmentCount = count
                        }
                    } header: {
                        Text("memory.section.photos", bundle: .main)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("memory.editor.title", bundle: .main))
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
                        Task {
                            _ = try? await dependencies.manageTrip.save(
                                memory, hasAttachments: attachmentCount > 0
                            )
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

/// The itinerary: a trip's segments in order.
///
/// **Placeholder presentation.** The rule that matters is that every time is
/// shown in *its own* zone — a flight leaving Tokyo leaves at Tokyo time,
/// whatever the phone thinks. Absolute instants are stored; the local reading is
/// computed here (TRAVEL_AND_FLIGHT_ATTENDANT.md §8).
struct ItineraryScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let tripID: UUID

    @State private var segments: [TripSegment] = []
    @State private var places: [Place] = []
    @State private var editing: TripSegment?

    var body: some View {
        List {
            if segments.isEmpty {
                Section {
                    Text("trip.itinerary.none", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }
            } else {
                ForEach(segments) { segment in
                    Button {
                        editing = segment
                    } label: {
                        row(segment)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                try? await dependencies.manageTrip.deleteSegment(id: segment.id)
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
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("trip.section.itinerary", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = TripSegment(
                        tripID: tripID,
                        title: "",
                        sortOrder: (segments.map(\.sortOrder).max() ?? -1) + 1
                    )
                } label: {
                    Label(
                        String(
                            localized: "segment.add",
                            defaultValue: "Add a leg",
                            comment: "Adds an itinerary segment"
                        ),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { segment in
            SegmentEditorSheet(segment: segment, places: places) {
                Task { await load() }
            }
        }
    }

    private func row(_ segment: TripSegment) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(segment.title)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)

            if let start = segment.startsAt {
                let zone = segment.originTimeZoneID
                    .flatMap(TimeZone.init(identifier:)) ?? dependencies.clock.timeZone
                Text(Self.dateTime(start, in: zone))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if let end = segment.endsAt {
                let zone = segment.destinationTimeZoneID
                    .flatMap(TimeZone.init(identifier:)) ?? dependencies.clock.timeZone
                Text(Self.dateTime(end, in: zone))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Formats *in* a zone. The style's initializer parameter does this; the
    /// `.timeZone(_:)` modifier only adds the zone's name to the output.
    private static func dateTime(_ instant: Date, in zone: TimeZone) -> String {
        instant.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
        )
    }

    private func load() async {
        segments = (try? await dependencies.manageTrip.segments(forTripID: tripID)) ?? []
        places = (try? await dependencies.manageTrip.places()) ?? []
    }
}

/// Editor for one itinerary leg.
struct SegmentEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var segment: TripSegment
    let places: [Place]
    let onSaved: () -> Void

    @State private var hasTimes = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(
                            localized: "segment.field.title",
                            defaultValue: "What it is",
                            comment: "The segment's title"
                        ),
                        text: $segment.title
                    )

                    Picker(selection: $segment.kind) {
                        ForEach(TripSegment.SegmentKind.allCases, id: \.self) { kind in
                            Text(LocalizedStringKey(kind.localizationKey)).tag(kind)
                        }
                    } label: {
                        Text("segment.field.kind", bundle: .main)
                    }
                }

                Section {
                    Toggle(isOn: $hasTimes) {
                        Text("segment.field.hasTimes", bundle: .main)
                    }

                    if hasTimes {
                        DatePicker(
                            selection: Binding(
                                get: { segment.startsAt ?? Date() },
                                set: { segment.startsAt = $0 }
                            )
                        ) {
                            Text("segment.field.starts", bundle: .main)
                        }

                        DatePicker(
                            selection: Binding(
                                get: { segment.endsAt ?? segment.startsAt ?? Date() },
                                set: { segment.endsAt = $0 }
                            )
                        ) {
                            Text("segment.field.ends", bundle: .main)
                        }
                    }
                } footer: {
                    // Explains why the zones below matter: the same instant reads
                    // differently at each end, and that is the point.
                    Text("segment.field.times.footer", bundle: .main)
                }

                Section {
                    zonePicker(
                        labelKey: "segment.field.originZone",
                        selection: $segment.originTimeZoneID
                    )
                    zonePicker(
                        labelKey: "segment.field.destinationZone",
                        selection: $segment.destinationTimeZoneID
                    )
                } header: {
                    Text("segment.section.zones", bundle: .main)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("segment.editor.title", bundle: .main))
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
            .task { hasTimes = segment.startsAt != nil }
        }
    }

    private func zonePicker(
        labelKey: String,
        selection: Binding<String?>
    ) -> some View {
        Picker(selection: Binding(
            get: { selection.wrappedValue ?? "" },
            set: { selection.wrappedValue = $0.isEmpty ? nil : $0 }
        )) {
            Text("place.timeZone.none", bundle: .main).tag("")
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                Text(identifier).tag(identifier)
            }
        } label: {
            Text(LocalizedStringKey(labelKey))
        }
    }

    private func save() async {
        var toSave = segment
        if !hasTimes {
            toSave.startsAt = nil
            toSave.endsAt = nil
        }
        _ = try? await dependencies.manageTrip.save(toSave)
        onSaved()
        dismiss()
    }
}
