import SwiftUI
import SunnieShared

/// The daily operational centre.
///
/// **Placeholder presentation.** Card order follows the documented hierarchy
/// (INFORMATION_ARCHITECTURE.md §2), but only the greeting and plant cards carry
/// real behaviour in this slice. The remaining cards arrive in Phases 3 and after.
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

                if let reaction = model?.lastReaction {
                    SunnieCard {
                        SunnieMessageView(message: reaction, presence: .small)
                    }
                    .transition(.opacity)
                }

                comingSoonCards
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("app.name", bundle: .main))
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

    /// Structural stand-ins for the cards that arrive in later phases. They are
    /// present so the hierarchy is visible and so no card silently goes missing
    /// when its feature lands.
    private var comingSoonCards: some View {
        ForEach(UpcomingCard.allCases) { card in
            SunnieCard {
                SectionHeader(
                    title: String(localized: card.titleKey),
                    subtitle: String(localized: card.subtitleKey)
                )
                StatusChip(
                    text: String(
                        localized: "common.comingSoon",
                        defaultValue: "Coming soon",
                        comment: "Marks a feature that is not built yet"
                    ),
                    style: .neutral
                )
            }
        }
    }
}

/// Cards whose features are not implemented yet, in the documented Today order.
private enum UpcomingCard: String, CaseIterable, Identifiable {
    case travel
    case wellness
    case meals
    case dailyPuzzle
    case progression

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .travel: "today.card.travel.title"
        case .wellness: "today.card.wellness.title"
        case .meals: "today.card.meals.title"
        case .dailyPuzzle: "today.card.puzzle.title"
        case .progression: "today.card.progression.title"
        }
    }

    var subtitleKey: String.LocalizationValue {
        switch self {
        case .travel: "today.card.travel.subtitle"
        case .wellness: "today.card.wellness.subtitle"
        case .meals: "today.card.meals.subtitle"
        case .dailyPuzzle: "today.card.puzzle.subtitle"
        case .progression: "today.card.progression.subtitle"
        }
    }
}
