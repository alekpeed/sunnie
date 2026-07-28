import Foundation
import Observation
import SwiftUI

/// Owns navigation state for the whole app.
///
/// Each tab keeps its own stack, so switching away and back returns to where the
/// user was — a plant filter or a half-read detail screen is not reset by a trip
/// to another tab (INFORMATION_ARCHITECTURE.md §14).
@MainActor
@Observable
final class AppRouter {

    private(set) var selectedTab: AppTab = .today
    private var stacks: [AppTab: [AppRoute]] = [:]

    /// Binding for `TabView`. Re-selecting the current tab pops it to its root,
    /// matching the platform convention.
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { newValue in
                if newValue == self.selectedTab {
                    self.popToRoot(newValue)
                } else {
                    self.selectedTab = newValue
                }
            }
        )
    }

    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { self.stacks[tab] ?? [] },
            set: { self.stacks[tab] = $0 }
        )
    }

    func push(_ route: AppRoute) {
        var stack = stacks[selectedTab] ?? []
        // Guard against a double-tap pushing the same detail screen twice.
        guard stack.last != route else { return }
        stack.append(route)
        stacks[selectedTab] = stack
    }

    func popToRoot(_ tab: AppTab) {
        stacks[tab] = []
    }

    /// Resolves a route from anywhere — a deep link, a notification, a widget, a
    /// Watch handoff — into tab selection plus a push.
    func handle(_ route: AppRoute) {
        selectedTab = route.tab

        guard !route.isTabRoot else {
            popToRoot(route.tab)
            return
        }

        var stack = stacks[route.tab] ?? []
        if stack.last != route {
            stack.append(route)
        }
        stacks[route.tab] = stack
    }

    func handle(url: URL) {
        guard let route = DeepLinkParser.route(from: url) else { return }
        handle(route)
    }
}
