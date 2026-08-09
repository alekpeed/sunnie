import SwiftUI
import SunnieShared

/// The daily operating layer for Sunnie Days.
///
/// Today consumes one `CurrentContext`, so Travel, Jungle, Meals, Wellness,
/// progression and Flight Mode are ranked as one situation rather than rendered
/// as equally important mini-apps. Tell Sunnie is the universal capture path.
struct TodayScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var model: TodayModel?
    @State private var isTellingSunnie = false
    @State private var pendingTellText = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                greetingCard
                tellSunnieCard

                if dependencies.isEphemeralStorage {
                    ephemeralStorageNotice
                }

                if let flight = model?.flightMode {
                    flightModeCard(flight)
                }

                plantSection
                wellnessSection

                if let reaction = model?.lastReaction {
                    SunnieCard {
                        SunnieMessageView(message: reaction, presence: .small)
                    }
                    .transition(.opacity)
                }

                contextSection
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("app.name", bundle: .main))
        .audioContext(.today)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model?.load() }
        .task {
            if model == nil {
                model = TodayModel(dependencies: dependencies, appState: appState)
            }
            await model?.onAppear()
            if let text = TellSunnieCaptureBox.take() {
                pendingTellText = text
                isTellingSunnie = true
            }
        }
        .onDisappear {
            Task { await model?.onDisappear() }
        }
        .sheet(isPresented: $isTellingSunnie) {
            TellSunnieScreen(initialText: pendingTellText)
        }
    }

    // MARK: - Primary OS surfaces

    private var greetingCard: some View {
        SunnieCard {
            if let greeting = model?.greeting {
                SunnieMessageView(message: greeting, presence: .prominent)
            } else {
                SunnieAvatarView(
                    state: SunnieVisualState(
                        expression: appState.timeContext.sunnieExpression,
                        pose: .standingNeutral,
                        presence: .prominent,
                        animationIntensity: appState.timeContext.animationIntensity
                    )
                )
            }

            Text(LocalizationKeys.dayCycle(appState.timeContext.presentation))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
                .accessibilityLabel(Text(
                    "today.presentation.accessibility \(appState.timeContext.presentation.canonicalDisplayName)"
                ))
        }
    }

    private var tellSunnieCard: some View {
        Button {
            isTellingSunnie = true
        } label: {
            SunnieCard {
                HStack(spacing: Space.s) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Tell Sunnie")
                            .font(SunnieFont.sectionTitle)
                            .foregroundStyle(theme.color.textPrimary)
                        Text("Type it or say it. Sunnie Days will work out where it belongs.")
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(theme.color.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tell Sunnie")
        .accessibilityHint("Opens text and voice capture")
    }

    private func flightModeCard(_ flight: FlightContext) -> some View {
        SunnieCard {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "Flight Mode",
                    subtitle: flight.destinationName ?? flight.tripTitle
                )
                Spacer()
                Image(systemName: "airplane")
                    .accessibilityHidden(true)
            }

            Text(flightModeSummary(flight))
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let localTime = destinationLocalTime(flight) {
                Label(localTime, systemImage: "clock")
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if let weather = flight.weather {
                Label(
                    weatherSummary(weather),
                    systemImage: weather.condition.symbolName
                )
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)

                if let url = weather.attributionURL {
                    Link(weather.attributionText, destination: url)
                        .font(SunnieFont.caption)
                } else {
                    Text(weather.attributionText)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            HStack(spacing: Space.s) {
                SunnieSecondaryButton(
                    title: "Open Trip",
                    systemImage: "airplane",
                    action: { router.handle(.trip(flight.tripID)) }
                )
                SunnieSecondaryButton(
                    title: "Packing",
                    systemImage: "suitcase",
                    action: { router.handle(.packing(flight.tripID)) }
                )
            }

            if flight.plantCoverageUndecidedCount > 0 {
                SunnieSecondaryButton(
                    title: "Plant Coverage",
                    systemImage: "leaf",
                    action: { router.handle(.plantCoverage(flight.tripID)) }
                )
            }
        }
    }

    /// Shown only when the on-disk store could not be opened. The user must know
    /// their work is not being kept.
    private var ephemeralStorageNotice: some View {
        ErrorStateView(
            message: String(
                localized: "today.storage.ephemeral",
                defaultValue: "I can't reach your saved information right now, so anything you add today won't be kept. Restarting the app usually sorts it out.",
                comment: "Shown when persistent storage is unavailable"
            )
        )
    }

    // MARK: - Existing feature actions, fed by CurrentContext

    @ViewBuilder
    private var plantSection: some View {
        switch model?.state ?? .idle {
        case .idle, .loading:
            SunnieCard {
                LoadingStateView(message: String(
                    localized: "today.plants.loading",
                    defaultValue: "Looking at your jungle…",
                    comment: "Loading state for the plant card"
                ))
            }

        case .failed(let message):
            ErrorStateView(
                message: message,
                retryTitle: String(
                    localized: "common.tryAgain",
                    defaultValue: "Try again",
                    comment: "Retry button"
                ),
                retry: { Task { await model?.load() } }
            )

        case .loaded:
            if let summary = model?.plantSummary {
                PlantTaskCard(
                    summary: summary,
                    onOpenDueList: { router.handle(.jungleDue) },
                    onComplete: { task in
                        Task { await model?.completeCare(task: task) }
                    },
                    onOpenPlant: { plantID in router.handle(.plant(plantID)) }
                )
            }
        }
    }

    private var wellnessSection: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "today.card.wellness.title",
                    defaultValue: "Wellness",
                    comment: "Wellness card on Today"
                ),
                subtitle: wellnessSubtitle
            )

            if let affirmation = model?.affirmation {
                Text(affirmation.text)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Space.s) {
                SunnieSecondaryButton(
                    title: String(
                        localized: "wellness.checkIn.action",
                        defaultValue: "Check in",
                        comment: "Opens the check-in"
                    ),
                    systemImage: "heart",
                    action: { router.handle(.checkIn) }
                )
                SunnieSecondaryButton(
                    title: String(
                        localized: "today.journal.action",
                        defaultValue: "Write",
                        comment: "Opens the journal"
                    ),
                    systemImage: "square.and.pencil",
                    action: { router.handle(.journal) }
                )
            }
        }
    }

    private var wellnessSubtitle: String? {
        guard let summary = model?.wellnessSummary else { return nil }
        if summary.hasCheckedInToday {
            return String(
                localized: "today.wellness.checkedIn",
                defaultValue: "You checked in today.",
                comment: "Stated as fact, never as praise or a nudge"
            )
        }
        return nil
    }

    /// Lower-priority context that remains after Flight Mode and the dedicated
    /// plant/wellness actions have been shown. There is intentionally no fixed
    /// row for every module.
    @ViewBuilder
    private var contextSection: some View {
        let visible = (model?.contextItems ?? []).filter {
            !$0.id.hasPrefix("flightMode.") && $0.id != "plants.actionable"
        }

        ForEach(visible) { item in
            SunnieCard {
                SectionHeader(title: item.title, subtitle: item.detail)

                HStack(spacing: Space.s) {
                    if let action = item.primaryAction {
                        contextButton(action, fallbackTitle: "Open")
                    }
                    if let action = item.secondaryAction {
                        contextButton(action, fallbackTitle: "More")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextButton(_ action: ContextAction, fallbackTitle: String) -> some View {
        if action == .tellSunnie {
            SunnieSecondaryButton(
                title: "Tell Sunnie",
                systemImage: "bubble.left",
                action: { isTellingSunnie = true }
            )
        } else if let route = action.appRoute {
            SunnieSecondaryButton(
                title: contextActionTitle(action, fallback: fallbackTitle),
                systemImage: contextActionSymbol(action),
                action: { router.handle(route) }
            )
        }
    }

    private func contextActionTitle(_ action: ContextAction, fallback: String) -> String {
        switch action {
        case .openTravel, .openTrip: "Travel"
        case .openPacking: "Packing"
        case .openChecklist: "Checklist"
        case .openPlantCoverage: "Plant Coverage"
        case .openJungle, .openJungleDue: "Jungle"
        case .openMeals: "Meals"
        case .openGames: "Play"
        case .openWellness: "Wellness"
        case .openJournal: "Journal"
        case .openSunnieHome: "Sunnie's Home"
        case .openCollections: "Collection"
        case .tellSunnie: "Tell Sunnie"
        }
    }

    private func contextActionSymbol(_ action: ContextAction) -> String {
        switch action {
        case .openTravel, .openTrip: "airplane"
        case .openPacking: "suitcase"
        case .openChecklist: "checklist"
        case .openPlantCoverage, .openJungle, .openJungleDue: "leaf"
        case .openMeals: "fork.knife"
        case .openGames: "puzzlepiece"
        case .openWellness: "heart"
        case .openJournal: "square.and.pencil"
        case .openSunnieHome: "house"
        case .openCollections: "sparkles"
        case .tellSunnie: "bubble.left"
        }
    }

    private func flightModeSummary(_ flight: FlightContext) -> String {
        var facts: [String] = []
        switch flight.phase {
        case .preparing:
            if let days = flight.daysUntilDeparture {
                if days == 0 { facts.append("Work trip starts today") }
                else if days == 1 { facts.append("Work trip starts tomorrow") }
                else { facts.append("Work trip starts in \(days) days") }
            }
        case .away:
            facts.append("Work trip active")
        case .returning:
            facts.append("Return part of the work trip")
        }

        if flight.packingCount > 0 {
            facts.append("\(flight.packedCount) of \(flight.packingCount) packed")
        }
        if flight.checklistCount > 0 {
            facts.append("\(flight.checklistDoneCount) of \(flight.checklistCount) personal checklist items checked")
        }
        if flight.plantCoverageUndecidedCount > 0 {
            let count = flight.plantCoverageUndecidedCount
            facts.append(count == 1
                ? "1 plant coverage decision undecided"
                : "\(count) plant coverage decisions undecided")
        }

        return facts.isEmpty ? "Your work trip is in context." : facts.joined(separator: " · ")
    }

    private func destinationLocalTime(_ flight: FlightContext) -> String? {
        guard
            let zoneID = flight.destinationTimeZoneID,
            let zone = TimeZone(identifier: zoneID)
        else { return nil }

        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let place = flight.destinationName ?? "Destination"
        return "\(place) · \(formatter.string(from: dependencies.clock.now))"
    }

    private func weatherSummary(_ weather: WeatherSummary) -> String {
        let condition = String(localized: .init(weather.condition.localizationKey))
        let temperature = "\(Int(weather.temperatureCelsius.rounded()))°C"
        if weather.isStale(now: dependencies.clock.now) {
            return "\(condition) · \(temperature) · Earlier"
        }
        return "\(condition) · \(temperature)"
    }
}
