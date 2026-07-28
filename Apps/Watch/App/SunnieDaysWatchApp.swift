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

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WatchTodayScreen()
                WatchPlantsScreen()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
