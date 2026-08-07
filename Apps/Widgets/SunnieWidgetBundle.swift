import WidgetKit
import SwiftUI
import SunnieShared

/// The WidgetKit extension (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §8, §10).
///
/// Six widgets over one snapshot. The extension reads a file the app wrote and
/// renders it — it never opens SwiftData, never runs a migration, and never
/// resolves a content pack. An extension has a small memory budget and no way to
/// report a crash, so the less it does the more reliably it does it.
@main
struct SunnieWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodaySummaryWidget()
        PlantTasksWidget()
        TripCountdownWidget()
        AffirmationWidget()
        DailyPuzzleWidget()
        CalmShortcutWidget()
    }
}

/// One timeline provider, shared by every widget.
///
/// The refresh policy is the same for all six because the snapshot is: the app
/// republishes on meaningful change and asks WidgetKit to reload, so the
/// timeline's own schedule is a safety net rather than the mechanism. An hour is
/// deliberately unhurried — §10 asks not to waste battery on frequent refreshes,
/// and nothing here is urgent enough to justify more.
struct SunnieSnapshotProvider: TimelineProvider {

    static let refreshInterval: TimeInterval = 3600

    func placeholder(in context: Context) -> SunnieEntry {
        SunnieEntry(date: Date(), snapshot: .empty(at: Date()), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SunnieEntry) -> Void) {
        completion(currentEntry(isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunnieEntry>) -> Void) {
        let entry = currentEntry(isPlaceholder: false)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(entry.date.addingTimeInterval(Self.refreshInterval))
            )
        )
    }

    private func currentEntry(isPlaceholder: Bool) -> SunnieEntry {
        let now = Date()
        // Nil means either no App Group configured (the default — ADR-012) or an
        // app that has not run since install. Both show the same "open Sunnie
        // Days" state, which is true in both cases.
        let snapshot = WidgetSnapshotStore().read()
        return SunnieEntry(
            date: now,
            snapshot: snapshot ?? .empty(at: now),
            isPlaceholder: isPlaceholder,
            hasData: snapshot != nil
        )
    }
}

struct SunnieEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var isPlaceholder = false
    var hasData = true
}
