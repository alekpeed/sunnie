import WidgetKit
import SwiftUI
import SunnieShared

/// The six widgets (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §8) and the accessory
/// families that make four of them Smart Stack and complication surfaces (§10).
///
/// Every one of them:
///
/// - Reads only the snapshot, which the app already privacy-filtered.
/// - Hides user content on the lock screen through `redactionReasons`, because
///   §8 requires respecting lock-screen sensitivity and a plant's name is the
///   one piece of user content these carry.
/// - Deep-links through `sunniedays://`, so a tap resolves into the same typed
///   route as a notification or a Watch handoff.

// MARK: - Today

struct TodaySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sunnie.widget.today", provider: SunnieSnapshotProvider()) {
            entry in
            TodaySummaryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.today.name", bundle: .main))
        .description(Text("widget.today.description", bundle: .main))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodaySummaryView: View {
    @Environment(\.redactionReasons) private var redaction
    let entry: SunnieEntry

    var body: some View {
        WidgetFrame(entry: entry, url: "sunniedays://today") {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(entry.snapshot.today.presentation.localizationKey))
                    .font(.headline)

                if entry.snapshot.plants.dueCount > 0 {
                    Label(
                        "\(entry.snapshot.plants.dueCount)",
                        systemImage: "leaf"
                    )
                    .font(.subheadline)
                } else {
                    Text("widget.today.settled", bundle: .main)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let trip = entry.snapshot.trip,
                   let days = trip.daysUntilDeparture(now: entry.date, calendar: .current) {
                    Label("\(days)", systemImage: "airplane")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Plants

struct PlantTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sunnie.widget.plants", provider: SunnieSnapshotProvider()) {
            entry in
            PlantTasksView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.plants.name", bundle: .main))
        .description(Text("widget.plants.description", bundle: .main))
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryInline
        ])
    }
}

struct PlantTasksView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redaction
    let entry: SunnieEntry

    private var count: Int { entry.snapshot.plants.dueCount }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // A number and a leaf. Nothing identifiable, which is what makes it
            // safe on a lock screen at any sensitivity.
            Gauge(value: Double(min(count, 9)), in: 0...9) {
                Image(systemName: "leaf")
            } currentValueLabel: {
                Text("\(count)")
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryInline:
            Label("\(count)", systemImage: "leaf")

        default:
            WidgetFrame(entry: entry, url: "sunniedays://jungle/due") {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("widget.plants.name", bundle: .main)
                    } icon: {
                        Image(systemName: "leaf")
                    }
                    .font(.headline)

                    if count == 0 {
                        Text("widget.plants.none", bundle: .main)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(count)")
                            .font(.title)
                        // The plant's name is the only user content in the
                        // snapshot, and it is withheld whenever the system says
                        // the widget is redacted — which is what "respect
                        // lock-screen sensitivity" means in practice.
                        if let name = entry.snapshot.plants.nextTaskName,
                           !redaction.contains(.privacy) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Trip

struct TripCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sunnie.widget.trip", provider: SunnieSnapshotProvider()) {
            entry in
            TripCountdownView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.trip.name", bundle: .main))
        .description(Text("widget.trip.description", bundle: .main))
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct TripCountdownView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redaction
    let entry: SunnieEntry

    var body: some View {
        if let trip = entry.snapshot.trip {
            let days = trip.daysUntilDeparture(now: entry.date, calendar: .current)

            switch family {
            case .accessoryInline:
                Label(days.map { "\($0)" } ?? "—", systemImage: "airplane")

            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label(days.map { "\($0)" } ?? "—", systemImage: "airplane")
                        .font(.headline)
                    if !redaction.contains(.privacy) {
                        Text(trip.title).font(.caption).lineLimit(1)
                    }
                }

            default:
                WidgetFrame(entry: entry, url: "sunniedays://travel") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !redaction.contains(.privacy) {
                            Text(trip.title).font(.headline).lineLimit(2)
                        }
                        if let days {
                            Text("\(days)").font(.title)
                            Text("widget.trip.days", bundle: .main)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(LocalizedStringKey(trip.statusKey))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        // The destination clock, when there is one. Two time
                        // zones is the single most useful thing on a wrist or a
                        // lock screen while away.
                        if let zoneID = trip.destinationTimeZoneID,
                           let zone = TimeZone(identifier: zoneID) {
                            // Formats *in* the zone. The initializer parameter
                            // does that; `.timeZone(_:)` only appends the
                            // zone's name, which would show local time under a
                            // destination label — the one reading that makes
                            // this clock worse than not having it.
                            Text(
                                entry.date,
                                format: Date.FormatStyle(
                                    date: .omitted,
                                    time: .shortened,
                                    timeZone: zone
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            WidgetFrame(entry: entry, url: "sunniedays://travel") {
                Text("widget.trip.none", bundle: .main)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Affirmation

struct AffirmationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "sunnie.widget.affirmation", provider: SunnieSnapshotProvider()
        ) { entry in
            AffirmationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.affirmation.name", bundle: .main))
        .description(Text("widget.affirmation.description", bundle: .main))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct AffirmationView: View {
    let entry: SunnieEntry

    var body: some View {
        WidgetFrame(entry: entry, url: "sunniedays://wellness") {
            // An affirmation is content the app wrote, not something about the
            // user, so it is safe at any redaction level.
            Text(entry.snapshot.affirmation ?? "")
                .font(.subheadline)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Daily puzzle

struct DailyPuzzleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sunnie.widget.puzzle", provider: SunnieSnapshotProvider()) {
            entry in
            DailyPuzzleView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.puzzle.name", bundle: .main))
        .description(Text("widget.puzzle.description", bundle: .main))
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

struct DailyPuzzleView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SunnieEntry

    var body: some View {
        if let puzzle = entry.snapshot.dailyPuzzle {
            switch family {
            case .accessoryInline:
                Label(
                    puzzle.isFinishedToday ? "✓" : "·",
                    systemImage: "puzzlepiece"
                )
            default:
                WidgetFrame(entry: entry, url: "sunniedays://games") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(puzzle.gameNameKey))
                            .font(.headline)
                            .lineLimit(2)
                        Text(puzzle.puzzleTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if puzzle.isFinishedToday {
                            Label {
                                Text("widget.puzzle.done", bundle: .main)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            WidgetFrame(entry: entry, url: "sunniedays://games") {
                Text("widget.puzzle.none", bundle: .main)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Calm

/// A shortcut, not a display.
///
/// It shows nothing about the user at all, which is what makes it the right
/// thing for a lock screen: opening a breathing practice should not require
/// unlocking a phone first.
struct CalmShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sunnie.widget.calm", provider: SunnieSnapshotProvider()) {
            entry in
            CalmShortcutView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.calm.name", bundle: .main))
        .description(Text("widget.calm.description", bundle: .main))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct CalmShortcutView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "wind").font(.title2)
        case .accessoryInline:
            Label {
                Text("widget.calm.name", bundle: .main)
            } icon: {
                Image(systemName: "wind")
            }
        default:
            Link(destination: URL(string: "sunniedays://wellness")!) {
                VStack(spacing: 8) {
                    Image(systemName: "wind").font(.title)
                    Text("widget.calm.name", bundle: .main).font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Shared frame

/// The wrapper every home-screen widget uses.
///
/// It exists for one reason: to say plainly when there is no snapshot yet,
/// rather than showing an empty rectangle. A widget with nothing in it looks
/// broken; a widget that says "open Sunnie Days" is a widget waiting for
/// something reasonable.
struct WidgetFrame<Content: View>: View {
    let entry: SunnieEntry
    let url: String
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if entry.hasData || entry.isPlaceholder {
                content
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "sun.max").font(.title3)
                    Text("widget.noData", bundle: .main)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: url))
    }
}
