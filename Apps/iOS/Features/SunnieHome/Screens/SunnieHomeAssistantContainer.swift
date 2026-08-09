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
            // The shared world can now change Sunnie's actual semantic pose in
            // Home, not merely the labels around him. Other app surfaces do not
            // receive this value and therefore keep their own visual contracts.
            .environment(\.sunnieWorldEnvironment, appState.worldContext.environment)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    worldBar
                    if let ambient = ambientLine {
                        ambientBar(ambient)
                    }
                }
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
            Image(systemName: appState.worldContext.environment.symbol)
                .foregroundStyle(theme.color.accentSunnie)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.worldContext.environment.title)
                    .font(SunnieFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color.textPrimary)

                Text(worldDetail)
                    .font(.caption2)
                    .foregroundStyle(theme.color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            if let pack = appState.worldContext.activePresentationPack {
                Image(systemName: pack.symbol)
                    .foregroundStyle(theme.color.textSecondary)
                    .accessibilityLabel("Active Sunnie presentation: \(pack.title)")
            }

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

    private func ambientBar(_ ambient: AmbientLine) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: ambient.symbol)
                .font(.caption)
                .foregroundStyle(theme.color.accentSunnie)
                .accessibilityHidden(true)
            Text(ambient.text)
                .font(.caption2)
                .foregroundStyle(theme.color.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xxs)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
    }

    private var ambientLine: AmbientLine? {
        if let language = appState.worldContext.languageMoment {
            return AmbientLine(
                symbol: "character.bubble.fill",
                text: "\(language.phrase) · \(language.translation)"
            )
        }

        if let surprise = appState.worldContext.surprise {
            return AmbientLine(symbol: surprise.symbol, text: surprise.detail)
        }

        return nil
    }

    private var worldDetail: String {
        let memories = appState.worldContext.memories.count
        let curios = appState.worldContext.curios.count

        if appState.worldContext.environment != .ordinary {
            return appState.worldContext.environment.detail
        }

        switch (memories, curios) {
        case (0, 0): return "Your world will collect memories and keepsakes here."
        case (0, _): return "\(curios) permanent keepsake\(curios == 1 ? "" : "s") unlocked."
        case (_, 0): return "\(memories) memory chapter\(memories == 1 ? "" : "s") in your world."
        default:
            return "\(memories) memory chapter\(memories == 1 ? "" : "s") · \(curios) keepsake\(curios == 1 ? "" : "s")"
        }
    }
}

private struct AmbientLine {
    let symbol: String
    let text: String
}
