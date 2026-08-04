import SwiftUI
import SunnieShared

/// One trip (S-07).
///
/// **Placeholder presentation.** The structure is the spec's: dates and status,
/// the two clocks, weather, four progress readouts, plant coverage, itinerary,
/// notes.
///
/// Progress is stated as counts, never percentages and never a score. "6 of 10
/// packed" says what is left; "60% ready" invites a judgement about the rest.
struct TripOverviewScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    let tripID: UUID

    @State private var model: TripDetailModel?
    @State private var isEditing = false
    @State private var isAddingMemory = false
    @State private var editingMemory: TravelMemory?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "trip.loading",
                            defaultValue: "Opening this trip…",
                            comment: "Loading state for a trip"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(
                        message: message,
                        retryTitle: String(
                            localized: "common.tryAgain",
                            defaultValue: "Try again",
                            comment: "Retry"
                        ),
                        retry: { Task { await model?.load() } }
                    )

                case .loaded:
                    if let trip = model?.trip {
                        headerCard(trip)
                        if let drift = model?.calendarDrift { calendarDriftCard(drift) }
                        if trip.type.isPlannable { progressCard(trip) }
                        if trip.type.isPlannable { coverageCard }
                        itineraryCard
                        memoriesCard
                        if let notes = trip.notes { notesCard(notes) }
                    }
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(model?.trip?.title ?? String(
            localized: "trip.title",
            defaultValue: "Trip",
            comment: "Trip screen title"
        ))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task {
            if model == nil { model = TripDetailModel(tripID: tripID, dependencies: dependencies) }
            await model?.load()
        }
        .sheet(isPresented: $isEditing) {
            if let trip = model?.trip {
                TripEditorScreen(existing: trip, type: trip.type) { _ in
                    Task { await model?.load() }
                }
            }
        }
        .sheet(isPresented: $isAddingMemory) {
            if let memory = editingMemory {
                MemoryEditorSheet(memory: memory, places: model?.places ?? []) {
                    Task { await model?.load() }
                }
            }
        }
    }

    // MARK: - Cards

    private func headerCard(_ trip: Trip) -> some View {
        SunnieCard {
            SectionHeader(
                title: dateRange(trip),
                subtitle: String(localized: .init((model?.status ?? .planning).localizationKey))
            )

            if let context = model?.timeZoneContext,
               context.homeTimeZoneID != context.localTimeZoneID {
                DualClockView(context: context)

                if context.hasUpcomingTransition() {
                    // The clocks are about to move on one side. Worth saying,
                    // because it is the thing that quietly breaks an alarm.
                    Text("trip.clock.transition", bundle: .main)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            if let weather = model?.weather {
                weatherRow(weather)
            }
        }
    }

    /// Weather, with the attribution Apple requires.
    ///
    /// The attribution is carried in the summary rather than added by this view,
    /// so weather cannot be displayed without it.
    private func weatherRow(_ weather: WeatherSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) {
                Image(systemName: weather.condition.symbolName)
                    .foregroundStyle(theme.color.accentTravel)
                    .accessibilityHidden(true)

                Text(LocalizedStringKey(weather.condition.localizationKey))
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                Spacer()

                Text(
                    Measurement(value: weather.temperatureCelsius, unit: UnitTemperature.celsius),
                    format: .measurement(width: .narrow, usage: .weather)
                )
                .font(SunnieFont.numeric)
                .foregroundStyle(theme.color.textPrimary)
            }
            .accessibilityElement(children: .combine)

            HStack {
                if weather.isStale(now: dependencies.clock.now) {
                    // Stale weather presented as current is worse than none.
                    Text("trip.weather.stale", bundle: .main)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
                Spacer()
                if let url = weather.attributionURL {
                    Link(weather.attributionText, destination: url)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                } else {
                    Text(weather.attributionText)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
    }

    /// A linked calendar event moved. Reported, never applied on its own.
    private func calendarDriftCard(_ drift: TripDetailModel.CalendarDrift) -> some View {
        SunnieCard {
            switch drift {
            case .deleted:
                Text("trip.calendar.deleted", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)

            case .movedTo(let start, _):
                Text("trip.calendar.moved", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textPrimary)

                Text(start, format: .dateTime.day().month().year().hour().minute())
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textSecondary)

                SunnieSecondaryButton(
                    title: String(
                        localized: "trip.calendar.accept",
                        defaultValue: "Use those dates",
                        comment: "Applies the calendar event's dates to the trip"
                    ),
                    action: { Task { await model?.acceptCalendarDates() } }
                )
            }
        }
    }

    private func progressCard(_ trip: Trip) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "trip.section.progress",
                    defaultValue: "Getting ready",
                    comment: "Trip progress section"
                ),
                subtitle: nil
            )

            let progress = model?.progress ?? TripProgress.build(
                packingItems: [], checklistItems: []
            )

            NavigationLink(value: AppRoute.packing(tripID)) {
                progressRow(
                    labelKey: "trip.progress.packing",
                    symbol: "suitcase",
                    counts: progress.packing
                )
            }

            NavigationLink(value: AppRoute.tripChecklist(tripID, ChecklistKind.Phase.leaving.rawValue)) {
                progressRow(
                    labelKey: "trip.progress.leaving",
                    symbol: "figure.walk.departure",
                    counts: progress.leavingChecklist
                )
            }

            NavigationLink(value: AppRoute.tripChecklist(tripID, ChecklistKind.Phase.returning.rawValue)) {
                progressRow(
                    labelKey: "trip.progress.returning",
                    symbol: "house",
                    counts: progress.returningChecklist
                )
            }
        }
    }

    private func progressRow(
        labelKey: String,
        symbol: String,
        counts: TripProgress.Counts
    ) -> some View {
        HStack {
            Label {
                Text(LocalizedStringKey(labelKey))
            } icon: {
                Image(systemName: symbol)
            }
            .font(SunnieFont.body)
            .foregroundStyle(theme.color.textPrimary)

            Spacer()

            if counts.isEmpty {
                Text("trip.progress.none", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            } else if counts.isComplete {
                StatusChip(
                    text: String(
                        localized: "trip.progress.allDone",
                        defaultValue: "All done",
                        comment: "Everything on a list is finished"
                    ),
                    style: .done
                )
            } else {
                // Counts, not a percentage: what is left, with no judgement about
                // the rest.
                Text(
                    "trip.progress.counts \(counts.done) \(counts.total)",
                    bundle: .main,
                    comment: "How many of a list are done"
                )
                .font(SunnieFont.numeric)
                .foregroundStyle(theme.color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Plant coverage during the absence.
    ///
    /// Described as undecided, never as endangered. Nothing here tells someone
    /// their plants are at risk (PLANT_CARE.md §10).
    @ViewBuilder
    private var coverageCard: some View {
        let rows = model?.coverageRows ?? []
        if !rows.isEmpty {
            SunnieCard {
                SectionHeader(
                    title: String(
                        localized: "trip.section.plants",
                        defaultValue: "While you're away",
                        comment: "Plant coverage section"
                    ),
                    subtitle: nil
                )

                let needing = rows.filter(\.need.needsAnything)
                let undecided = rows.filter(\.isUndecided)

                if needing.isEmpty {
                    Text("trip.plants.nothingNeeded", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                } else {
                    Text(
                        "trip.plants.needing \(needing.count)",
                        bundle: .main,
                        comment: "How many plants need something during the trip"
                    )
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textPrimary)

                    if !undecided.isEmpty {
                        Text(
                            "trip.plants.undecided \(undecided.count)",
                            bundle: .main,
                            comment: "How many plants have no coverage decision yet"
                        )
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                    }

                    NavigationLink(value: AppRoute.plantCoverage(tripID)) {
                        Text("trip.plants.open", bundle: .main)
                            .font(SunnieFont.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var itineraryCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "trip.section.itinerary",
                    defaultValue: "Itinerary",
                    comment: "Trip itinerary section"
                ),
                subtitle: nil
            )

            let segments = model?.segments ?? []
            if segments.isEmpty {
                Text("trip.itinerary.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(segments) { segment in
                    segmentRow(segment)
                }
            }

            NavigationLink(value: AppRoute.itinerary(tripID)) {
                Text("trip.itinerary.edit", bundle: .main)
                    .font(SunnieFont.secondary)
            }
        }
    }

    private func segmentRow(_ segment: TripSegment) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: Self.symbol(for: segment.kind))
                .foregroundStyle(theme.color.accentTravel)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(segment.title)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                if let start = segment.startsAt {
                    // Shown in the segment's own zone: a flight leaving Tokyo
                    // leaves at Tokyo time, whatever the phone says.
                    let zone = segment.originTimeZoneID
                        .flatMap(TimeZone.init(identifier:)) ?? dependencies.clock.timeZone
                    Text(Self.dateTime(start, in: zone))
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var memoriesCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "trip.section.memories",
                    defaultValue: "Worth remembering",
                    comment: "Trip memories section"
                ),
                subtitle: nil
            )

            let memories = model?.memories ?? []
            if memories.isEmpty {
                Text("trip.memories.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(memories) { memory in
                    Button {
                        editingMemory = memory
                        isAddingMemory = true
                    } label: {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(memory.title ?? String(
                                localized: "memory.untitled",
                                defaultValue: "A moment",
                                comment: "A memory with no title"
                            ))
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)

                            Text(memory.occurredAt, format: .dateTime.day().month().year())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }

            SunnieSecondaryButton(
                title: String(
                    localized: "memory.add",
                    defaultValue: "Add something",
                    comment: "Adds a travel memory"
                ),
                systemImage: "plus",
                action: {
                    editingMemory = dependencies.manageTrip.newMemory(tripID: tripID)
                    isAddingMemory = true
                }
            )
        }
    }

    private func notesCard(_ notes: String) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "trip.section.notes",
                    defaultValue: "Notes",
                    comment: "Trip notes section"
                ),
                subtitle: nil
            )
            Text(notes)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textPrimary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isEditing = true
                } label: {
                    Label(
                        String(localized: "common.edit", defaultValue: "Edit", comment: "Edit"),
                        systemImage: "pencil"
                    )
                }

                if model?.trip?.type.isPlannable == true {
                    Button {
                        router.push(.packing(tripID))
                    } label: {
                        Label(
                            String(
                                localized: "trip.progress.packing",
                                defaultValue: "Packing",
                                comment: "Opens packing"
                            ),
                            systemImage: "suitcase"
                        )
                    }
                }
            } label: {
                Label(
                    String(
                        localized: "trip.options",
                        defaultValue: "Options",
                        comment: "Trip options menu"
                    ),
                    systemImage: "ellipsis.circle"
                )
            }
        }
    }

    // MARK: - Formatting

    private func dateRange(_ trip: Trip) -> String {
        guard let start = trip.startsAt else {
            return String(
                localized: "trip.noDates",
                defaultValue: "No dates yet",
                comment: "A trip without dates"
            )
        }
        guard let end = trip.endsAt, end != start else {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Formats *in* a zone. The style's initializer parameter does this; the
    /// `.timeZone(_:)` modifier only adds the zone's name to the output.
    private static func dateTime(_ instant: Date, in zone: TimeZone) -> String {
        instant.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
        )
    }

    private static func symbol(for kind: TripSegment.SegmentKind) -> String {
        switch kind {
        case .flight: "airplane"
        case .train: "tram"
        case .drive: "car"
        case .stay: "bed.double"
        case .layover: "clock"
        case .other: "mappin.and.ellipse"
        }
    }
}
