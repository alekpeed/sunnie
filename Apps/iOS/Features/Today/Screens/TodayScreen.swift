import SwiftUI
import SunnieShared

/// The visual home/front page for Sunnie Days.
///
/// This keeps live text, state, accessibility and routing native in SwiftUI while
/// using the illustrated-card composition established by the approved front-screen
/// concept. The app-level five-tab navigation remains the canonical navigation shell.
struct TodayScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var model: TodayModel?
    @State private var isTellingSunnie = false
    @State private var pendingTellText = ""

    private let featureColumns = [
        GridItem(.flexible(), spacing: Space.s),
        GridItem(.flexible(), spacing: Space.s)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                brandHeader
                greetingCard
                sunnieHero
                quickStatusStrip
                featureGrid

                if dependencies.isEphemeralStorage {
                    ephemeralStorageNotice
                }

                todayAtAGlance
                encouragementCard
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.l)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.handle(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .audioContext(.today)
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

    // MARK: - Front-page composition

    private var brandHeader: some View {
        VStack(spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(sunnieButter)
                    .accessibilityHidden(true)

                Text("SUNNIE DAYS")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.color.textPrimary)

                Image(systemName: "leaf.fill")
                    .foregroundStyle(sunnieSage)
                    .accessibilityHidden(true)
            }

            Text("Small joys. Every day.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var greetingCard: some View {
        SunnieCard {
            VStack(spacing: Space.xs) {
                if let greeting = model?.greeting {
                    Text(greeting.text)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.color.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Good morning")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.color.textPrimary)
                }

                Text(LocalizationKeys.dayCycle(appState.timeContext.presentation))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                    .accessibilityLabel(Text(
                        "today.presentation.accessibility \(appState.timeContext.presentation.canonicalDisplayName)"
                    ))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sunnieHero: some View {
        Button {
            router.handle(.sunnieHome)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [sunnieButter.opacity(0.24), sunnieSage.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HStack {
                    Spacer(minLength: 0)
                    SunnieAvatarView(
                        state: SunnieVisualState(
                            expression: appState.timeContext.sunnieExpression,
                            pose: .sittingNeutral,
                            presence: .prominent,
                            animationIntensity: appState.timeContext.animationIntensity
                        )
                    )
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s)

                Label("Visit Sunnie", systemImage: "house.fill")
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textPrimary)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(Space.s)
            }
            .frame(minHeight: 220)
        }
        .buttonStyle(FrontPagePressStyle())
        .accessibilityLabel("Sunnie")
        .accessibilityHint("Opens Sunnie's home")
    }

    private var quickStatusStrip: some View {
        HStack(spacing: Space.xs) {
            statusItem(
                icon: "sun.max.fill",
                // `dayCycle` returns a LocalizedStringKey, which Text takes and
                // String(localized:) does not. `LocalizationKeys.text` is the
                // String-returning form for a key assembled at run time, and it
                // takes a fallback — so a missing translation shows the branded
                // name rather than the raw key.
                title: LocalizationKeys.text(
                    appState.timeContext.presentation.localizationKey,
                    fallback: appState.timeContext.presentation.canonicalDisplayName
                ),
                tint: sunnieButter
            )

            if model?.wellnessSummary?.hasCheckedInToday == true {
                statusItem(icon: "heart.fill", title: "Checked in", tint: sunniePeach)
            } else {
                statusItem(icon: "heart", title: "Wellness", tint: sunniePeach)
            }

            if model?.flightMode != nil {
                statusItem(icon: "airplane", title: "Travel", tint: sunnieSky)
            } else {
                statusItem(icon: "leaf.fill", title: "Jungle", tint: sunnieSage)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(theme.color.surface, in: Capsule())
    }

    private func statusItem(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private var featureGrid: some View {
        LazyVGrid(columns: featureColumns, spacing: Space.s) {
            featureCard(
                title: "Plant Care",
                subtitle: "Happy plants, happy you",
                symbol: "leaf.fill",
                tint: sunnieSage,
                route: .jungle
            )
            featureCard(
                title: "Travel",
                subtitle: "Next adventure awaits",
                symbol: "airplane",
                tint: sunnieSky,
                route: .travel
            )
            featureCard(
                title: "Wellness",
                subtitle: "Feel good, grow strong",
                symbol: "heart.fill",
                tint: sunniePeach,
                route: .wellness
            )
            featureCard(
                title: "Games",
                subtitle: "Play, learn, and shine",
                symbol: "puzzlepiece.fill",
                tint: sunnieLavender,
                route: .games
            )
            featureCard(
                title: "Collections",
                subtitle: "Keep the little joys",
                symbol: "sparkles",
                tint: sunnieButter,
                route: .collections
            )
            featureCard(
                title: "Journal",
                subtitle: "Tiny moments, big joy",
                symbol: "book.closed.fill",
                tint: sunniePeach.opacity(0.86),
                route: .journal
            )
        }
    }

    private func featureCard(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        route: AppRoute
    ) -> some View {
        Button {
            router.handle(route)
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.color.textSecondary)
                        .accessibilityHidden(true)
                }

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.36), tint.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 112)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(tint)
                    }

                Text(subtitle)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, minHeight: 208, alignment: .topLeading)
            .background(theme.color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(FrontPagePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }

    private var todayAtAGlance: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label("Today at a Glance", systemImage: "sun.max.fill")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(theme.color.textPrimary)

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
    }

    private var encouragementCard: some View {
        Button {
            isTellingSunnie = true
        } label: {
            SunnieCard {
                HStack(spacing: Space.s) {
                    SunnieAvatarView(
                        state: SunnieVisualState(
                            expression: .happyOpenEyed,
                            pose: .sittingNeutral,
                            presence: .small,
                            animationIntensity: appState.timeContext.animationIntensity
                        )
                    )

                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("You've got this!")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(theme.color.textPrimary)
                        Text("Tell Sunnie anything you want to capture.")
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(sunniePeach)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(FrontPagePressStyle())
        .accessibilityLabel("Tell Sunnie")
        .accessibilityHint("Opens text and voice capture")
    }

    // MARK: - Existing live Today modules

    private func flightModeCard(_ flight: FlightContext) -> some View {
        SunnieCard {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "Flight Mode",
                    subtitle: flight.destinationName ?? flight.tripTitle
                )
                Spacer()
                Image(systemName: "airplane")
                    .foregroundStyle(sunnieSky)
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

    private var ephemeralStorageNotice: some View {
        ErrorStateView(
            message: String(
                localized: "today.storage.ephemeral",
                defaultValue: "I can't reach your saved information right now, so anything you add today won't be kept. Restarting the app usually sorts it out.",
                comment: "Shown when persistent storage is unavailable"
            )
        )
    }

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

    // MARK: - Visual tokens from the approved front-screen concept

    private var sunnieButter: Color { Color(red: 0.965, green: 0.831, blue: 0.490) }
    private var sunnieSage: Color { Color(red: 0.663, green: 0.773, blue: 0.627) }
    private var sunniePeach: Color { Color(red: 0.953, green: 0.647, blue: 0.553) }
    private var sunnieLavender: Color { Color(red: 0.725, green: 0.651, blue: 0.882) }
    private var sunnieSky: Color { Color(red: 0.659, green: 0.796, blue: 0.894) }
}

private struct FrontPagePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}
