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
    public let fireDate: Date
    public let route: String
    public let respectsQuietHours: Bool

    public init(
        id: UUID,
        messageID: ContentID,
        fireDate: Date,
        route: String,
        respectsQuietHours: Bool = true
    ) {
        self.id = id
        self.messageID = messageID
        self.fireDate = fireDate
        self.route = route
        self.respectsQuietHours = respectsQuietHours
    }
}

public protocol AudioPlaying: Sendable {
    func playCue(_ cueID: ContentID) async
    func startAmbience(_ cueID: ContentID) async
    func stopAmbience() async
    func apply(preferences: AudioPreferences) async
}

/// Confirmation feedback. Separated from audio so haptics can be disabled
/// independently (VISUAL_DESIGN_SYSTEM.md §11).
public protocol HapticFeedback: Sendable {
    func selection()
    func success()
    /// Only for genuine attention states, never for routine reminders.
    func attention()
}
