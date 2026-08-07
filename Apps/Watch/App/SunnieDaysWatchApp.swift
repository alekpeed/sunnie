import SwiftUI

@main
struct SunnieDaysWatchApp: App {

    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { model.activate() }
        }
    }
}

/// The five destinations (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §5), in the order
/// the specification lists them.
///
/// A vertical page TabView rather than a list of links: on a wrist, a crown turn
/// between five pages is faster than a tap into a menu and a tap back out, and
/// every destination is one someone reaches repeatedly.
struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WatchTodayScreen()
                WatchCheckInScreen()
                WatchPlantsScreen()
                WatchCalmScreen()
                WatchTravelScreen()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
