import SwiftUI
import SunnieShared

/// Adds OS-level assistant and world affordances to Sunnie's Home without
/// making them part of the home feature's persistence or decoration logic.
struct SunnieHomeAssistantContainer<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var isTellingSunnie = false

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top) {
                worldBar
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                HStack(spacing: Space.s) {
                    if let flight = appState.currentContext.flightMode {
                        Button {
                            router.handle(.trip(flight.tripID))
                        } label: {
                            Label(
                                flight.destinationName.map { "Flight Mode · \($0)" } ?? "Flight Mode",
                                systemImage: "airplane"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        isTellingSunnie = true
                    } label: {
                        Label("Tell Sunnie", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(SunnieFont.caption)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $isTellingSunnie) {
                TellSunnieScreen()
            }
            .task {
                await appState.refreshCurrentContext()
            }
    }

    private var worldBar: some View {
        HStack(spacing: Space.s) {
            Image(systemName: environmentSymbol)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.worldContext.environment.title)
                    .font(SunnieFont.caption)
                    .fontWeight(.semibold)

                Text(worldDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            Button {
                router.handle(.collections)
            } label: {
                Label(
                    "\(appState.worldContext.curios.count)",
                    systemImage: "cabinet.fill"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open collection. \(appState.worldContext.curios.count) curios unlocked.")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .background(.ultraThinMaterial)
    }

    private var worldDetail: String {
        let memories = appState.worldContext.memories.count
        let curios = appState.worldContext.curios.count

        switch (memories, curios) {
        case (0, 0): return "Your world will collect memories and keepsakes here."
        case (0, _): return "\(curios) permanent keepsake\(curios == 1 ? "" : "s") unlocked."
        case (_, 0): return "\(memories) memory chapter\(memories == 1 ? "" : "s") in your world."
        default:
            return "\(memories) memory chapter\(memories == 1 ? "" : "s") · \(curios) keepsake\(curios == 1 ? "" : "s")"
        }
    }

    private var environmentSymbol: String {
        switch appState.worldContext.environment {
        case .ordinary: return "house.fill"
        case .plantDay: return "leaf.fill"
        case .tripPreparing: return "suitcase.fill"
        case .tripAway: return "airplane"
        case .tripReturning: return "house.and.flag.fill"
        }
    }
}
