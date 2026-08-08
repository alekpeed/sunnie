import SwiftUI
import SunnieShared

/// The travel dashboard (S-06).
///
/// **Placeholder presentation.** The scrapbook treatment — taped photos, stamps,
/// map fragments — comes with the visual pass. The structure is real: an active
/// trip leads, upcoming follow, then memories, places, and past travel.
struct TravelScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var model: TravelModel?
    @State private var isCreatingTrip = false
    @State private var newTripType: TripType = .personal

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "travel.loading",
                            defaultValue: "Looking at your travel…",
                            comment: "Loading state for travel"
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
                    content
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("tab.travel", bundle: .main))
        .audioContext(.travelScrapbook)
        .refreshable { await model?.load() }
        .toolbar { toolbarContent }
        .task {
            if model == nil { model = TravelModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(isPresented: $isCreatingTrip) {
            TripEditorScreen(existing: nil, type: newTripType) { trip in
                Task { await model?.load() }
                router.push(.trip(trip.id))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let current = model?.currentTrip {
            currentTripCard(current)
        }

        let upcoming = model?.upcomingTrips ?? []
        if !upcoming.isEmpty {
            upcomingCard(upcoming)
        }

        if model?.currentTrip == nil, upcoming.isEmpty {
            emptyState
        }

        memoriesCard
        placesCard

        let past = model?.pastTrips ?? []
        if !past.isEmpty {
            pastCard(past)
        }
    }

    // MARK: - Cards

    private func currentTripCard(_ trip: Trip) -> some View {
        SunnieCard {
            SectionHeader(
                title: trip.title,
                subtitle: String(localized: .init(
                    (model?.status(of: trip) ?? .active).localizationKey
                ))
            )

            if let context = clockContext(for: trip) {
                DualClockView(context: context)
            }

            SunniePrimaryButton(
                title: String(
                    localized: "trip.open",
                    defaultValue: "Open this trip",
                    comment: "Opens the trip overview"
                ),
                systemImage: "airplane",
                action: { router.push(.trip(trip.id)) }
            )
        }
    }

    private func upcomingCard(_ trips: [Trip]) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "travel.section.upcoming",
                    defaultValue: "Coming up",
                    comment: "Upcoming trips section"
                ),
                subtitle: nil
            )

            ForEach(trips) { trip in
                Button {
                    router.push(.trip(trip.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(trip.title)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            if let start = trip.startsAt {
                                Text(start, format: .dateTime.day().month().year())
                                    .font(SunnieFont.caption)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                        Spacer()
                        if let days = model?.daysUntil(trip) {
                            // Neutral information, never a countdown that reads
                            // as pressure.
                            StatusChip(
                                text: String(
                                    localized: "trip.inDays",
                                    defaultValue: "In \(days) days",
                                    comment: "Days until a trip starts"
                                ),
                                style: .neutral
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var memoriesCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "travel.section.memories",
                    defaultValue: "Worth remembering",
                    comment: "Recent memories section"
                ),
                subtitle: nil
            )

            let memories = model?.recentMemories ?? []
            if memories.isEmpty {
                Text("travel.memories.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(memories) { memory in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(memory.title ?? String(
                            localized: "memory.untitled",
                            defaultValue: "A moment",
                            comment: "A memory with no title"
                        ))
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                        Text(memory.occurredAt, format: .dateTime.month().year())
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var placesCard: some View {
        SunnieCard {
            NavigationLink(value: AppRoute.worldMap) {
                HStack {
                    Label(
                        String(
                            localized: "travel.section.places",
                            defaultValue: "Everywhere you've been",
                            comment: "Places and map section"
                        ),
                        systemImage: "map"
                    )
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    Text(
                        "travel.places.count \(model?.placeCount ?? 0)",
                        bundle: .main,
                        comment: "How many places are recorded"
                    )
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
    }

    private func pastCard(_ trips: [Trip]) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "travel.section.past",
                    defaultValue: "Where you've been",
                    comment: "Past trips section"
                ),
                subtitle: nil
            )
            ForEach(trips.prefix(5)) { trip in
                Button {
                    router.push(.trip(trip.id))
                } label: {
                    HStack {
                        Text(trip.title)
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                        Spacer()
                        if let start = trip.startsAt {
                            Text(start, format: .dateTime.month().year())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var emptyState: some View {
        SunnieCard {
            EmptyStateView(
                title: String(
                    localized: "travel.empty.title",
                    defaultValue: "Nothing planned",
                    comment: "Empty travel state"
                ),
                message: String(
                    localized: "travel.empty.message",
                    defaultValue: "When there's a trip coming, Sunnie will help you get ready. You can also add somewhere you've already been.",
                    comment: "Body of the empty travel state"
                ),
                actionTitle: String(
                    localized: "travel.newTrip",
                    defaultValue: "Plan a trip",
                    comment: "Creates a trip"
                ),
                action: {
                    newTripType = .personal
                    isCreatingTrip = true
                },
                visualState: SunnieVisualState(
                    expression: .traveling, pose: .pullingSuitcase, presence: .prominent
                )
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // Work first: this is the trip type Vanessa creates most, and it
                // should be the shortest path.
                Button {
                    newTripType = .work
                    isCreatingTrip = true
                } label: {
                    Label(
                        String(
                            localized: "travel.newWorkTrip",
                            defaultValue: "New work trip",
                            comment: "Creates a work trip"
                        ),
                        systemImage: "briefcase"
                    )
                }

                Button {
                    newTripType = .personal
                    isCreatingTrip = true
                } label: {
                    Label(
                        String(
                            localized: "travel.newTrip",
                            defaultValue: "Plan a trip",
                            comment: "Creates a trip"
                        ),
                        systemImage: "airplane"
                    )
                }

                Button {
                    newTripType = .past
                    isCreatingTrip = true
                } label: {
                    Label(
                        String(
                            localized: "travel.addPastTrip",
                            defaultValue: "Add somewhere you've been",
                            comment: "Creates a past trip for the record"
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )
                }

                Divider()

                Button {
                    router.push(.worldMap)
                } label: {
                    Label(
                        String(
                            localized: "travel.map",
                            defaultValue: "Map",
                            comment: "Opens the world map"
                        ),
                        systemImage: "map"
                    )
                }
            } label: {
                Label(
                    String(
                        localized: "travel.options",
                        defaultValue: "Options",
                        comment: "Travel options menu"
                    ),
                    systemImage: "plus.circle"
                )
            }
        }
    }

    private func clockContext(for trip: Trip) -> TimeZoneContext? {
        let context = dependencies.manageTrip.timeZoneContext(for: trip)
        // Identical zones would show the same time twice, which looks broken.
        return context.homeTimeZoneID == context.localTimeZoneID ? nil : context
    }
}

/// Home time and local time, side by side.
///
/// The signature element of the trip screens. Both are read from the same
/// instant through different zones, so a daylight-saving change on either side
/// needs no special handling — the offset is computed, never stored.
struct DualClockView: View {
    @Environment(\.sunnieTheme) private var theme

    let context: TimeZoneContext

    var body: some View {
        HStack(spacing: Space.l) {
            clock(
                zone: context.homeTimeZone,
                labelKey: "trip.clock.home"
            )
            clock(
                zone: context.localTimeZone,
                labelKey: "trip.clock.there"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func clock(zone: TimeZone, labelKey: String) -> some View {
        VStack(spacing: Space.xxs) {
            Text(LocalizedStringKey(labelKey))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)

            Text(Self.time(context.instant, in: zone))
                .font(SunnieFont.numeric)
                .foregroundStyle(theme.color.textPrimary)

            // The day matters more than the hour when it differs — "tomorrow
            // there" is the thing that catches people out.
            Text(Self.weekday(context.instant, in: zone))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Formats *in* a zone.
    ///
    /// The style's `timeZone` initializer parameter is what does this. The
    /// `.timeZone(_:)` modifier looks like it should and does not — it adds the
    /// zone's *name* to the output while still formatting in the current zone,
    /// which would show the right label beside the wrong time.
    private static func time(_ instant: Date, in zone: TimeZone) -> String {
        instant.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        )
    }

    private static func weekday(_ instant: Date, in zone: TimeZone) -> String {
        instant.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, timeZone: zone)
                .weekday(.abbreviated)
        )
    }
}
