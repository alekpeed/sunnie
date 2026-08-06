import Foundation

/// Injectable clock. Every time-dependent rule reads through this so tests can
/// pin "now" instead of sleeping.
public protocol SunnieClock: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
    var calendar: Calendar { get }
}

/// Injectable randomness, so nickname selection and message choice are
/// deterministic under test.
public protocol RandomSource: Sendable {
    /// Returns a value in `0..<1`.
    func nextUnitValue() -> Double
    func nextIndex(upperBound: Int) -> Int
}

public protocol TimePhaseResolving: Sendable {
    /// Resolves the current phase and its semantic modifiers.
    ///
    /// Honours the user's manual override and quiet hours. `reduceMotion` is
    /// passed in rather than read from the environment here so the shared
    /// package stays free of UIKit.
    func resolve(
        at date: Date,
        preferences: UserPreferences,
        timeZone: TimeZone,
        reduceMotion: Bool
    ) -> TimeContext
}

public protocol ThemeResolving: Sendable {
    func availableThemes() -> [ThemeDefinition]
    func theme(id: ContentID) -> ThemeDefinition?
    /// Combines a theme, the time context, and accessibility settings into the
    /// single value the design system renders.
    func resolve(
        themeID: ContentID,
        timeContext: TimeContext,
        highContrast: Bool
    ) -> ResolvedTheme
}

public protocol SunnieMessageProviding: Sendable {
    /// Selects a message for the moment. Returns nil only when no content exists
    /// for the category, which content validation is designed to prevent.
    func message(for context: SunnieMessageContext) -> SunnieMessage?
}

/// Publishes typed cross-feature events. Deliberately fire-and-forget: a feature
/// announces what happened and does not learn who reacted.
public protocol DomainEventPublishing: Sendable {
    func publish(_ event: DomainEvent) async
}

/// Delivers state to the Watch and receives queued actions back.
///
/// Every method must tolerate an unpaired, unreachable, or unsupported Watch
/// without throwing into the caller's path — the phone app is fully usable with
/// no Watch at all (CLAUDE.md, non-negotiable product facts).
public protocol WatchSyncing: Sendable {
    var isSupported: Bool { get }
    var isReachable: Bool { get }
    /// Replaces the Watch's current application context. Latest-value-wins, so
    /// this is safe to call on every summary change.
    func updateApplicationContext(_ context: WatchApplicationContext) async
}

public protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func schedule(_ reminder: ScheduledReminderRequest) async throws
    func cancel(reminderID: UUID) async
}

public enum NotificationAuthorization: String, Hashable, Sendable {
    case notDetermined
    case authorized
    case provisional
    case denied
}

/// A request to schedule one gentle reminder. Tone rules apply to the resolved
/// copy, not to this transport type.
public struct ScheduledReminderRequest: Hashable, Sendable {
    public let id: UUID
    public let messageID: ContentID
    /// Already-composed title. Resolved before scheduling, because a
    /// notification with no title and no body simply never appears.
    public let title: String
    public let body: String
    public let fireDate: Date
    public let route: String
    public let respectsQuietHours: Bool
    /// Groups related notifications so the system collapses them rather than
    /// stacking five separate plant reminders (NOTIFICATIONS_AND_REMINDERS.md §9).
    public let threadIdentifier: String
    /// What a "Done" tap needs in order to record the real thing.
    ///
    /// Without this the action button could only note that it was pressed, which
    /// would be worse than not offering it: the user would believe the task was
    /// logged when nothing had been. Values are small identifiers, never content
    /// (NOTIFICATIONS_AND_REMINDERS.md §6).
    public let actionPayload: [String: String]

    public init(
        id: UUID,
        messageID: ContentID,
        title: String,
        body: String,
        fireDate: Date,
        route: String,
        respectsQuietHours: Bool = true,
        threadIdentifier: String,
        actionPayload: [String: String] = [:]
    ) {
        self.id = id
        self.messageID = messageID
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.route = route
        self.respectsQuietHours = respectsQuietHours
        self.threadIdentifier = threadIdentifier
        self.actionPayload = actionPayload
    }
}

/// What the user did to a delivered notification, and what is needed to honour it.
public struct DeliveredNotificationAction: Hashable, Sendable {
    public let reminderID: UUID
    public let response: ReminderResponse
    /// The `actionPayload` the reminder was scheduled with.
    public let payload: [String: String]

    public init(
        reminderID: UUID,
        response: ReminderResponse,
        payload: [String: String] = [:]
    ) {
        self.reminderID = reminderID
        self.response = response
        self.payload = payload
    }
}

/// Offering a reminder, as features see it.
///
/// Features ask for a reminder and never learn whether one was actually
/// scheduled or why not — cadence, quiet hours, the daily ceiling, and
/// permission are the scheduler's business. Behind a protocol so a feature
/// depends on the capability rather than on the concrete scheduler
/// (TECHNICAL_ARCHITECTURE.md §8).
public protocol ReminderOffering: Sendable {
    /// Offers one reminder. Returns the plan, which may be a suppression.
    @discardableResult
    func offer(
        category: ReminderCategory,
        sourceEntityID: UUID?,
        route: String,
        desiredFireDate: Date,
        subject: String?,
        actionPayload: [String: String],
        isTaskComplete: Bool,
        timeZonePolicy: ReminderTimeZonePolicy
    ) async -> ReminderPlan

    /// Cancels everything pending for a task, because it is done.
    func cancelAll(for sourceEntityID: UUID) async

    func recordResponse(reminderID: UUID, response: ReminderResponse) async
}

public extension ReminderOffering {
    @discardableResult
    func offer(
        category: ReminderCategory,
        sourceEntityID: UUID?,
        route: String,
        desiredFireDate: Date,
        subject: String? = nil,
        actionPayload: [String: String] = [:]
    ) async -> ReminderPlan {
        await offer(
            category: category,
            sourceEntityID: sourceEntityID,
            route: route,
            desiredFireDate: desiredFireDate,
            subject: subject,
            actionPayload: actionPayload,
            isTaskComplete: false,
            timeZonePolicy: .deviceTimeZone
        )
    }
}

/// Stand-in for tests, previews, and any composition without notifications.
/// Every offer is suppressed, which is exactly what "no reminders" means.
public struct NoReminders: ReminderOffering {
    public init() {}

    @discardableResult
    public func offer(
        category: ReminderCategory,
        sourceEntityID: UUID?,
        route: String,
        desiredFireDate: Date,
        subject: String?,
        actionPayload: [String: String],
        isTaskComplete: Bool,
        timeZonePolicy: ReminderTimeZonePolicy
    ) async -> ReminderPlan {
        .suppress(.cadenceDisabled)
    }


    public func cancelAll(for sourceEntityID: UUID) async {}
    public func recordResponse(reminderID: UUID, response: ReminderResponse) async {}
}

/// Keys used in a notification's payload, shared so the scheduler and the tap
/// handler cannot drift apart.
public enum NotificationPayloadKeys {
    public static let route = "sunnie.notification.route"
    public static let reminderID = "sunnie.notification.reminderID"
    public static let messageID = "sunnie.notification.messageID"
    /// Prefix for everything in `ScheduledReminderRequest.actionPayload`, so the
    /// per-category values cannot collide with the keys above.
    public static let actionPrefix = "sunnie.notification.action."

    /// Well-known `actionPayload` keys.
    public static let plantID = "plantID"
    public static let careType = "careType"
    public static let scheduleID = "scheduleID"
}

public protocol AudioPlaying: Sendable {
    func playCue(_ cueID: ContentID) async
    func startAmbience(_ cueID: ContentID) async
    func stopAmbience() async
    func apply(preferences: AudioPreferences) async
}

/// A weather summary for a place (TRAVEL_AND_FLIGHT_ATTENDANT.md §9).
///
/// Deliberately small. This is not a weather app: one line and an icon on a trip
/// screen is the whole requirement, and modelling more would mean maintaining
/// more.
public struct WeatherSummary: Hashable, Sendable {
    public let condition: Condition
    public let temperatureCelsius: Double
    public let highCelsius: Double?
    public let lowCelsius: Double?
    /// When this was fetched. Shown, because stale weather presented as current
    /// is worse than no weather.
    public let fetchedAt: Date
    /// Apple requires attribution for WeatherKit data. Carried with the data so
    /// it cannot be displayed without it.
    public let attributionText: String
    public let attributionURL: URL?

    public enum Condition: String, Hashable, Sendable, Codable, CaseIterable {
        case clear
        case cloudy
        case rain
        case snow
        case wind
        case fog
        case storm
        case unknown

        public var localizationKey: String { "weather.\(rawValue)" }

        public var symbolName: String {
            switch self {
            case .clear: "sun.max"
            case .cloudy: "cloud"
            case .rain: "cloud.rain"
            case .snow: "cloud.snow"
            case .wind: "wind"
            case .fog: "cloud.fog"
            case .storm: "cloud.bolt.rain"
            case .unknown: "questionmark.circle"
            }
        }
    }

    public init(
        condition: Condition,
        temperatureCelsius: Double,
        highCelsius: Double? = nil,
        lowCelsius: Double? = nil,
        fetchedAt: Date,
        attributionText: String,
        attributionURL: URL? = nil
    ) {
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.fetchedAt = fetchedAt
        self.attributionText = attributionText
        self.attributionURL = attributionURL
    }

    /// Whether this is old enough that the screen should say so.
    public func isStale(now: Date, after seconds: TimeInterval = 3600) -> Bool {
        now.timeIntervalSince(fetchedAt) > seconds
    }
}

/// Weather lookup, when permission and network allow.
///
/// Returns nil rather than throwing for the ordinary cases — offline, no
/// permission, no coordinate. None of those is an error the user needs told
/// about; the screen simply shows no weather (TRAVEL_AND_FLIGHT_ATTENDANT.md §9,
/// §16).
public protocol WeatherProviding: Sendable {
    func summary(latitude: Double, longitude: Double) async -> WeatherSummary?
}

/// Stand-in for previews, tests, and any build without WeatherKit.
public struct UnavailableWeatherProvider: WeatherProviding {
    public init() {}
    public func summary(latitude: Double, longitude: Double) async -> WeatherSummary? { nil }
}

/// A calendar event, as the app needs it (TRAVEL_AND_FLIGHT_ATTENDANT.md §10).
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let isAllDay: Bool
    public let location: String?

    public init(
        id: String,
        title: String,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool = false,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.location = location
    }
}

public enum CalendarAuthorization: String, Hashable, Sendable {
    case notDetermined
    case authorized
    /// iOS 17+ write-only access. Enough to create a trip event, not enough to
    /// read one.
    case writeOnly
    case denied
}

/// Calendar access. Entirely optional — the app is fully usable with it denied,
/// and the trip stays the source of truth for everything Sunnie Days-specific
/// whatever the calendar says (TRAVEL_AND_FLIGHT_ATTENDANT.md §10).
public protocol CalendarProviding: Sendable {
    func authorizationStatus() async -> CalendarAuthorization
    func requestAccess() async -> CalendarAuthorization
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
    /// Creates an event for a trip and returns its identifier, or nil if it could
    /// not be created. A failure here costs a calendar entry, never the trip.
    func createEvent(
        title: String,
        startsAt: Date,
        endsAt: Date,
        notes: String?
    ) async -> String?
    func event(withIdentifier identifier: String) async -> CalendarEvent?
}

public struct UnavailableCalendarProvider: CalendarProviding {
    public init() {}
    public func authorizationStatus() async -> CalendarAuthorization { .denied }
    public func requestAccess() async -> CalendarAuthorization { .denied }
    public func events(from start: Date, to end: Date) async -> [CalendarEvent] { [] }
    public func createEvent(
        title: String, startsAt: Date, endsAt: Date, notes: String?
    ) async -> String? { nil }
    public func event(withIdentifier identifier: String) async -> CalendarEvent? { nil }
}

/// Generated noise (NOISE_IMPLEMENTATION.md).
///
/// Separate from `AudioPlaying` because it is a different kind of thing: nothing
/// is loaded, decoded, or looped — samples are computed as they are needed. It
/// also needs a different audio-session policy from the rest of the app's sound
/// (ADR-018), and keeping the two behind different protocols is what stops a
/// caller reaching for the wrong one by accident.
public protocol NoiseGenerating: Sendable {
    var currentColor: NoiseColor? { get async }
    func start(_ color: NoiseColor) async
    func stop() async
    /// 0…1, applied before the limiter.
    func setVolume(_ volume: Double) async
    /// Fades to silence over the given duration, then stops.
    ///
    /// Fading rather than cutting, because the usual reason for stopping a sleep
    /// sound is that someone is asleep and a hard stop would wake them.
    func fadeOutAndStop(over seconds: Double) async
}

/// Stand-in for previews, tests, and any composition without audio.
public struct SilentNoiseGenerator: NoiseGenerating {
    public init() {}
    public var currentColor: NoiseColor? { get async { nil } }
    public func start(_ color: NoiseColor) async {}
    public func stop() async {}
    public func setVolume(_ volume: Double) async {}
    public func fadeOutAndStop(over seconds: Double) async {}
}

/// Grants the stamp and postcard a saved travel memory earns
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §11, PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §6).
///
/// A protocol rather than a direct call, because Travel and Collections are
/// separate features and neither may import the other to mutate its state
/// (TECHNICAL_ARCHITECTURE.md §6). The composition root supplies the
/// implementation.
///
/// Deliberately *not* routed through the domain event bus: that bus is
/// best-effort and unordered by design, and a stamp that sometimes does not
/// arrive is worse than one that arrives synchronously with the save.
public protocol TravelKeepsakeAwarding: Sendable {
    /// Idempotent per destination — editing and re-saving the same memory adds
    /// nothing.
    func awardKeepsakes(for memory: TravelMemory) async
}

/// Awards nothing. The composition for previews and for tests that are not
/// about collectibles.
public struct NoKeepsakes: TravelKeepsakeAwarding {
    public init() {}
    public func awardKeepsakes(for memory: TravelMemory) async {}
}

/// Confirmation feedback. Separated from audio so haptics can be disabled
/// independently (VISUAL_DESIGN_SYSTEM.md §11).
public protocol HapticFeedback: Sendable {
    func selection()
    func success()
    /// Only for genuine attention states, never for routine reminders.
    func attention()
}
