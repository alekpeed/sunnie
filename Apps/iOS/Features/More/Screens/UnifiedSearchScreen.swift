import SwiftUI
import SunnieShared

struct UnifiedSearchScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme
    @State private var query = ""

    private var results: [SearchEntity] { dependencies.unifiedSearch.results(matching: query) }

    var body: some View {
        List(results) { result in
            Button {
                guard let url = URL(string: result.route) else { return }
                router.handle(url: url)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(result.title).foregroundStyle(theme.color.textPrimary)
                        if let subtitle = result.subtitle {
                            Text(subtitle).font(SunnieFont.caption).foregroundStyle(theme.color.textSecondary)
                        }
                    }
                } icon: {
                    Image(systemName: symbol(for: result.kind))
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Plants, trips, places, recipes and curios")
        .navigationTitle("Search Sunnie Days")
        .task { await dependencies.unifiedSearch.rebuild() }
    }

    private func symbol(for kind: SearchEntityKind) -> String {
        switch kind {
        case .plant: "leaf.fill"
        case .trip: "airplane"
        case .place: "mappin.circle.fill"
        case .memory: "photo.on.rectangle.angled"
        case .recipe: "fork.knife"
        case .game: "puzzlepiece.fill"
        case .curio: "sparkles"
        }
    }
}
