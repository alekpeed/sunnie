import SwiftUI
import SunnieShared

/// The More tab.
///
/// **Placeholder presentation.** Destinations are clearly labelled and in the
/// documented order (INFORMATION_ARCHITECTURE.md §6). Everything except Themes
/// and Settings routes to a stub until its phase lands.
struct MoreScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    var body: some View {
        List {
            Section {
                ForEach(MoreDestination.allCases) { destination in
                    Button {
                        router.handle(destination.route)
                    } label: {
                        HStack {
                            Label(
                                String(localized: destination.titleKey),
                                systemImage: destination.symbolName
                            )
                            .foregroundStyle(theme.color.textPrimary)

                            Spacer()

                            if !destination.isImplemented {
                                StatusChip(
                                    text: String(
                                        localized: "common.comingSoon",
                                        defaultValue: "Coming soon",
                                        comment: "Marks an unbuilt feature"
                                    ),
                                    style: .neutral
                                )
                            }
                            Image(systemName: "chevron.right")
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("tab.more", bundle: .main))
    }
}

enum MoreDestination: String, CaseIterable, Identifiable {
    case meals
    case games
    case journal
    case collections
    case sunnieHome
    case themes
    case settings

    var id: String { rawValue }

    var route: AppRoute {
        switch self {
        case .meals: .meals
        case .games: .games
        case .journal: .journal
        case .collections: .collections
        case .sunnieHome: .sunnieHome
        case .themes: .themes
        case .settings: .settings
        }
    }

    /// Every More destination now leads somewhere real.
    var isImplemented: Bool { true }

    var titleKey: String.LocalizationValue {
        switch self {
        case .meals: "more.meals"
        case .games: "more.games"
        case .journal: "more.journal"
        case .collections: "more.collections"
        case .sunnieHome: "more.sunnieHome"
        case .themes: "more.themes"
        case .settings: "more.settings"
        }
    }

    var symbolName: String {
        switch self {
        case .meals: "fork.knife"
        case .games: "puzzlepiece"
        case .journal: "book"
        case .collections: "sparkles"
        case .sunnieHome: "house"
        case .themes: "paintpalette"
        case .settings: "gearshape"
        }
    }
}

/// Stand-in for a feature that has not been built yet.
///
/// Says plainly that it is coming rather than presenting an empty screen that
/// looks broken.
struct PlaceholderFeatureScreen: View {
    @Environment(\.sunnieTheme) private var theme

    enum Feature: String {
        case travel
        case wellness
        case meals
        case games
        case journal
        case collections
        case sunnieHome

        var titleKey: String.LocalizationValue {
            switch self {
            case .travel: "placeholder.travel.title"
            case .wellness: "placeholder.wellness.title"
            case .meals: "placeholder.meals.title"
            case .games: "placeholder.games.title"
            case .journal: "placeholder.journal.title"
            case .collections: "placeholder.collections.title"
            case .sunnieHome: "placeholder.sunnieHome.title"
            }
        }

        var messageKey: String.LocalizationValue {
            switch self {
            case .travel: "placeholder.travel.message"
            case .wellness: "placeholder.wellness.message"
            case .meals: "placeholder.meals.message"
            case .games: "placeholder.games.message"
            case .journal: "placeholder.journal.message"
            case .collections: "placeholder.collections.message"
            case .sunnieHome: "placeholder.sunnieHome.message"
            }
        }

        var visualState: SunnieVisualState {
            switch self {
            case .travel:
                SunnieVisualState(expression: .traveling, pose: .pullingSuitcase, presence: .medium)
            case .wellness:
                SunnieVisualState(expression: .calmBreathing, pose: .meditating, presence: .medium)
            case .meals:
                SunnieVisualState(expression: .happyOpenEyed, pose: .holdingMug, presence: .medium)
            case .games:
                SunnieVisualState(expression: .curious, pose: .playingGame, presence: .medium)
            case .journal:
                SunnieVisualState(expression: .thinking, pose: .reading, presence: .medium)
            case .collections:
                SunnieVisualState(expression: .excitedDiscovery, pose: .standingNeutral, presence: .medium)
            case .sunnieHome:
                SunnieVisualState(expression: .happyClosedEyed, pose: .decoratingHome, presence: .medium)
            }
        }
    }

    private let feature: Feature

    init(feature: Feature) {
        self.feature = feature
    }

    var body: some View {
        ScrollView {
            SunnieCard {
                EmptyStateView(
                    title: String(localized: feature.titleKey),
                    message: String(localized: feature.messageKey),
                    visualState: feature.visualState
                )
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text(String(localized: feature.titleKey)))
    }
}
