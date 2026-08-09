import SwiftUI
import SunnieShared

/// Adds the two OS-level assistant affordances to Sunnie's Home without making
/// them part of the home feature's persistence or decoration logic.
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
}
