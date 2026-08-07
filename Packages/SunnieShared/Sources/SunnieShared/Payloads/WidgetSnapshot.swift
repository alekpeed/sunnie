import Foundation

/// What the widgets show (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §8).
///
/// One snapshot, written by the app and read by the extension. A widget never
/// opens the SwiftData store: an extension has a tiny memory budget, migrations
/// must not run in it, and a widget that crashes on launch is a blank rectangle
/// on someone's home screen with no way to report itself.
///
/// **Everything here is already privacy-filtered.** §8 requires widgets to show
/// only privacy-appropriate content and to respect lock-screen sensitivity, so
/// the filtering happens where the data is — at the point the app writes this —
/// rather than in six timeline providers that each have to remember.
public struct WidgetSnapshot: Hashable, Sendable, Codable {
    public let payloadVersion: Int
    public let generatedAt: Date

    public let today: TodayPanel
    public let plants: PlantsPanel
    public let trip: TripPanel?
    public let affirmation: String?
    public let dailyPuzzle: PuzzlePanel?

    public init(
        payloadVersion: Int = WidgetSnapshot.currentVersion,
        generatedAt: Date,
        today: TodayPanel,
        plants: PlantsPanel,
        trip: TripPanel? = nil,
        affirmation: String? = nil,
        dailyPuzzle: PuzzlePanel? = nil
    ) {
        self.payloadVersion = payloadVersion
        self.generatedAt = generatedAt
        self.today = today
        self.plants = plants
        self.trip = trip
        self.affirmation = affirmation
        self.dailyPuzzle = dailyPuzzle
    }

    public static let currentVersion = 1

    /// A snapshot with nothing in it, for a first install and for the extension's
    /// placeholder.
    public static func empty(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: date,
            today: TodayPanel(dayCyclePresentationKey: DayCyclePresentation.sunnieDays.rawValue),
            plants: PlantsPanel(dueCount: 0, overdueCount: 0, nextTaskName: nil)
        )
    }

    public struct TodayPanel: Hashable, Sendable, Codable {
        public let dayCyclePresentationKey: String
        /// The one thing worth surfacing, already chosen by the app's own
        /// prioritisation rules (HOME_AND_COMPANION.md §4).
        public let headlineKey: String?
        public let headlineValue: String?

        public init(
            dayCyclePresentationKey: String,
            headlineKey: String? = nil,
            headlineValue: String? = nil
        ) {
            self.dayCyclePresentationKey = dayCyclePresentationKey
            self.headlineKey = headlineKey
            self.headlineValue = headlineValue
        }

        public var presentation: DayCyclePresentation {
            DayCyclePresentation(rawValue: dayCyclePresentationKey) ?? .sunnieDays
        }
    }

    public struct PlantsPanel: Hashable, Sendable, Codable {
        public let dueCount: Int
        public let overdueCount: Int
        /// The name of the next plant needing something.
        ///
        /// A plant's name is the one piece of user content the widgets carry,
        /// and it is omitted from the lock screen by the view rather than by the
        /// snapshot — the same snapshot serves both, and only the placement knows
        /// which it is.
        public let nextTaskName: String?

        public init(dueCount: Int, overdueCount: Int, nextTaskName: String?) {
            self.dueCount = dueCount
            self.overdueCount = overdueCount
            self.nextTaskName = nextTaskName
        }
    }

    public struct TripPanel: Hashable, Sendable, Codable {
        public let title: String
        public let startsAt: Date?
        public let destinationTimeZoneID: String?
        public let statusKey: String

        public init(
            title: String,
            startsAt: Date?,
            destinationTimeZoneID: String?,
            statusKey: String
        ) {
            self.title = title
            self.startsAt = startsAt
            self.destinationTimeZoneID = destinationTimeZoneID
            self.statusKey = statusKey
        }

        /// Whole days until departure, or nil once it has started.
        ///
        /// Counted in whole days in the *home* calendar, because a countdown is
        /// something a person reads at home while packing.
        public func daysUntilDeparture(now: Date, calendar: Calendar) -> Int? {
            guard let startsAt, startsAt > now else { return nil }
            return calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: startsAt)
            ).day
        }
    }

    public struct PuzzlePanel: Hashable, Sendable, Codable {
        public let gameNameKey: String
        public let puzzleTitle: String
        public let isFinishedToday: Bool

        public init(gameNameKey: String, puzzleTitle: String, isFinishedToday: Bool) {
            self.gameNameKey = gameNameKey
            self.puzzleTitle = puzzleTitle
            self.isFinishedToday = isFinishedToday
        }
    }
}

/// Where the app leaves a snapshot for the widgets to find.
///
/// A file in the App Group container rather than `UserDefaults`: the snapshot is
/// a document, `UserDefaults` is not a database, and a corrupt defaults plist is
/// a much worse failure than a corrupt file that can simply be ignored.
///
/// **The App Group is an entitlement, and entitlements are inactive by default
/// (ADR-012).** With none configured, `containerURL` is nil, the app's write is a
/// no-op, and the widget reads nothing and shows its "open the app" state. That
/// is the honest degraded behaviour rather than a crash or an empty rectangle.
public struct WidgetSnapshotStore: Sendable {

    /// The App Group the app and its extensions share.
    ///
    /// Must match the entitlement on both targets. Declared once here so a typo
    /// cannot make the two halves disagree silently — which would look exactly
    /// like "the widget never updates".
    public static let appGroupIdentifier = "group.com.sunniedays.app"

    public static let fileName = "widget-snapshot.json"

    private let containerURL: URL?

    /// Resolves the shared container, or nil when no App Group is configured.
    public init(appGroupIdentifier: String = WidgetSnapshotStore.appGroupIdentifier) {
        self.containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// For tests: a store rooted at a directory of the caller's choosing.
    public init(directory: URL?) {
        self.containerURL = directory
    }

    /// True when there is somewhere to write. False means no App Group.
    public var isAvailable: Bool { containerURL != nil }

    private var fileURL: URL? {
        containerURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Writes the snapshot, replacing whatever was there.
    ///
    /// Failures are swallowed rather than thrown: a widget that is one refresh
    /// stale is a minor thing, and there is nobody to show an error to at the
    /// moment this runs.
    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        // Atomic, so a widget reading mid-write sees the old file rather than
        // half of the new one.
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    /// Reads the snapshot, or nil when there is none or it cannot be understood.
    ///
    /// A payload from a newer app than this extension is ignored rather than
    /// guessed at — the two are updated together, but not always at the same
    /// instant.
    public func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        guard snapshot.payloadVersion <= WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }
}
