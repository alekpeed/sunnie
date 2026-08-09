import SwiftUI
import SunnieShared

/// The daily operational centre and primary contextual surface of Sunnie Days.
///
/// Today is intentionally not a mirror of the navigation hierarchy. It brings
/// together the parts of the user's world that are useful now and provides
/// direct routes into already-built systems. Richer cross-feature prioritisation
/// belongs in summary/context providers rather than in this view.
struct TodayScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var model: TodayModel?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                greetingCard

                if dependencies.isEphemeralStorage {
                    ephemeralStorageNotice
                }

                plantSection
                wellnessSection

                if let reaction = model?.lastReaction {
                    SunnieCard {
                        SunnieMessageView(message: reaction, presence: .small)
                    }
                    .transition(.opacity)
                }

                worldSection
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
        }
        .onDisappear {
            Task { await model?.onDisappear() }
        }
    }

    // MARK: - Cards

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

        case .loaded(let summary):
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

    /// The wellness slice of Today.
    ///
    /// Reads from the summary provider, so Today stays independent of the
    /// Wellness feature. Phrased as an offer in both states — having checked in
    /// is stated as fact, not as a reason to be pleased or to do it again.
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

    /// Direct access to systems that are already part of Sunnie Days.
    ///
    /// This replaces the old "Coming soon" placeholders. It is deliberately a
    /// temporary, non-prioritised bridge: the next integration slice will feed
    /// these systems through a shared context summary so Today can show what is
    /// relevant rather than presenting every module equally.
    private var worldSection: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "today.world.title",
                    defaultValue: "Your world",
                    comment: "Integrated Sunnie Days actions on Today"
                ),
                subtitle: String(
                    localized: "today.world.subtitle",
                    defaultValue: "Everything here is part of the same Sunnie Days world.",
                    comment: "Explains integrated shortcuts without implying required activity"
                )
            )

            VStack(spacing: Space.s) {
                HStack(spacing: Space.s) {
                    SunnieSecondaryButton(
                        title: String(
                            localized: "today.world.travel",
                            defaultValue: "Travel",
                            comment: "Opens travel"
                        ),
                        systemImage: "airplane",
                        action: { router.handle(.travel) }
                    )
                    SunnieSecondaryButton(
                        title: String(
                            localized: "today.world.meals",
                            defaultValue: "Meals",
                            comment: "Opens meals"
                        ),
                        systemImage: "fork.knife",
                        action: { router.handle(.meals) }
                    )
                }

                HStack(spacing: Space.s) {
                    SunnieSecondaryButton(
                        title: String(
                            localized: "today.world.games",
                            defaultValue: "Play",
                            comment: "Opens games without streak framing"
                        ),
                        systemImage: "puzzlepiece",
                        action: { router.handle(.games) }
                    )
                    SunnieSecondaryButton(
                        title: String(
                            localized: "today.world.home",
                            defaultValue: "Sunnie's Home",
                            comment: "Opens Sunnie's Home"
                        ),
                        systemImage: "house",
                        action: { router.handle(.sunnieHome) }
                    )
                }

                SunnieSecondaryButton(
                    title: String(
                        localized: "today.world.collection",
                        defaultValue: "Rewards & Collection",
                        comment: "Opens permanently earned rewards and collectibles"
                    ),
                    systemImage: "sparkles",
                    action: { router.handle(.collections) }
                )
            }
        }
    }
}
