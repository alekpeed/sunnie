import Foundation

/// Check-in and practice-session storage.
public protocol WellnessRepository: Sendable {
    /// Stores a check-in unless one with the same `actionKey` already exists.
    ///
    /// Same guarantee as care events, for the same reason: a check-in completed
    /// on the Watch and redelivered must not become two entries in the history.
    func save(_ checkIn: WellnessCheckIn) async throws -> SaveOutcome<WellnessCheckIn>
    func checkIn(actionKey: ActionKey) async throws -> WellnessCheckIn?
    func checkIn(id: UUID) async throws -> WellnessCheckIn?

    /// Check-ins within a date range, newest first.
    func checkIns(from: Date, to: Date, limit: Int) async throws -> [WellnessCheckIn]
    func mostRecentCheckIn() async throws -> WellnessCheckIn?

    func save(_ session: WellnessSession) async throws -> SaveOutcome<WellnessSession>
    func session(id: UUID) async throws -> WellnessSession?
    /// Updates a session in place — used when a practice ends, so the session is
    /// recorded from the moment it starts and survives the app being killed.
    func update(_ session: WellnessSession) async throws
    func sessions(from: Date, to: Date, limit: Int) async throws -> [WellnessSession]
}

/// Journal storage.
///
/// Deletion is soft everywhere in this protocol. `purge` is the only call that
/// destroys anything, and it is expected to run against entries past the restore
/// window rather than on user request.
public protocol JournalRepository: Sendable {
    func save(_ entry: JournalEntry) async throws
    func entry(id: UUID) async throws -> JournalEntry?
    /// Published entries, newest first. Drafts and deleted entries are excluded.
    func entries(limit: Int, offset: Int) async throws -> [JournalEntry]
    func drafts() async throws -> [JournalEntry]
    func deletedEntries() async throws -> [JournalEntry]
    func entries(matching query: String, limit: Int) async throws -> [JournalEntry]
    func entries(withTag tag: String, limit: Int) async throws -> [JournalEntry]

    func softDelete(entryID: UUID, at date: Date) async throws
    func restore(entryID: UUID) async throws
    /// Permanently removes entries deleted before `cutoff`, and their media.
    func purge(deletedBefore cutoff: Date) async throws -> Int
}

/// Photo and voice-note storage.
///
/// Files live outside the database; this owns the mapping between a token and the
/// bytes. Nothing here ever hands out a raw path, because a container path is not
/// stable across reinstalls.
public protocol MediaRepository: Sendable {
    func save(_ attachment: MediaAttachment, data: Data) async throws -> MediaAttachment
    func attachment(id: UUID) async throws -> MediaAttachment?
    func attachments(for owner: MediaOwner) async throws -> [MediaAttachment]
    func data(for attachmentID: UUID) async throws -> Data?
    func delete(attachmentID: UUID) async throws
    /// Moves every attachment from one owner to another.
    ///
    /// A capture surface has to name an owner before the record it belongs to
    /// exists — someone can attach a photo to a check-in they have not saved yet.
    /// The surface invents the ID, and if saving resolves to a different record
    /// (an idempotent save collapsing onto an existing one), the attachments
    /// follow rather than being stranded. Returns how many moved.
    @discardableResult
    func reassign(from oldOwner: MediaOwner, to newOwner: MediaOwner) async throws -> Int
    /// Removes files with no owning record left. Media outliving its entry is the
    /// normal way storage silently fills up.
    func deleteOrphans() async throws -> Int
}

/// Storage for scheduled reminders and their response history.
public protocol ReminderRepository: Sendable {
    func scheduled(category: ReminderCategory) async throws -> [ScheduledReminderRecord]
    func record(_ reminder: ScheduledReminderRecord) async throws
    func markResponse(
        reminderID: UUID,
        response: ReminderResponse,
        at date: Date
    ) async throws
    /// Fire dates already used for a task today, which the planner needs to
    /// enforce its daily ceilings.
    func firedToday(sourceEntityID: UUID, category: ReminderCategory, now: Date) async throws -> [Date]
    func cancelAll(sourceEntityID: UUID) async throws
}

/// The persisted form of a scheduled reminder
/// (NOTIFICATIONS_AND_REMINDERS.md §3).
public struct ScheduledReminderRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let category: ReminderCategory
    public let sourceEntityID: UUID?
    public var scheduledAt: Date
    public var timeZonePolicy: ReminderTimeZonePolicy
    public var cadenceLevel: AdaptiveCadenceLevel
    public var respectsQuietHours: Bool
    public var response: ReminderResponse
    public var respondedAt: Date?
    /// The identifier handed to UserNotifications, so a superseded request can be
    /// cancelled rather than left to fire alongside its replacement.
    public var notificationRequestID: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        category: ReminderCategory,
        sourceEntityID: UUID?,
        scheduledAt: Date,
        timeZonePolicy: ReminderTimeZonePolicy,
        cadenceLevel: AdaptiveCadenceLevel,
        respectsQuietHours: Bool = true,
        response: ReminderResponse = .noResponse,
        respondedAt: Date? = nil,
        notificationRequestID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.category = category
        self.sourceEntityID = sourceEntityID
        self.scheduledAt = scheduledAt
        self.timeZonePolicy = timeZonePolicy
        self.cadenceLevel = cadenceLevel
        self.respectsQuietHours = respectsQuietHours
        self.response = response
        self.respondedAt = respondedAt
        self.notificationRequestID = notificationRequestID
        self.isEnabled = isEnabled
    }
}
