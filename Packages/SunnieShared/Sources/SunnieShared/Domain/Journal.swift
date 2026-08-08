import Foundation

/// What a media attachment belongs to. Explicit rather than a loose owner ID so
/// an orphaned file can be traced back to what it was for.
public enum MediaOwner: Hashable, Sendable, Codable {
    case journalEntry(UUID)
    case checkIn(UUID)
    case plant(UUID)
    case trip(UUID)
    case meal(UUID)
}

public enum MediaKind: String, Hashable, Sendable, Codable, CaseIterable {
    case photo
    case voiceNote
}

/// A reference to a stored file (DATA_MODEL.md §5).
///
/// Holds tokens, never bytes and never absolute paths: a container path is not
/// stable across reinstalls or devices, and syncing one would break silently.
/// Resolving a token to a URL is the media repository's job.
public struct MediaAttachment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let owner: MediaOwner
    public let kind: MediaKind
    /// Opaque token for the file in local storage.
    public var localToken: String
    /// Opaque token for the synced copy, once uploaded.
    public var cloudToken: String?
    public var thumbnailToken: String?
    /// Seconds, for voice notes.
    public var duration: TimeInterval?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        owner: MediaOwner,
        kind: MediaKind,
        localToken: String,
        cloudToken: String? = nil,
        thumbnailToken: String? = nil,
        duration: TimeInterval? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.owner = owner
        self.kind = kind
        self.localToken = localToken
        self.cloudToken = cloudToken
        self.thumbnailToken = thumbnailToken
        self.duration = duration
        self.createdAt = createdAt
    }
}

/// One thing the user was grateful for.
///
/// A record with its own identity rather than a line of text, so gratitude can be
/// searched and revisited later without parsing prose apart.
public struct GratitudeItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var text: String
    public var photoID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        photoID: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.text = text
        self.photoID = photoID
        self.createdAt = createdAt
    }
}

/// What a journal entry is linked to, so an entry can be found from the plant,
/// trip, or mood it was about (WELLNESS_JOURNAL_AND_CALM.md §6).
public struct JournalLinks: Hashable, Sendable, Codable {
    public var checkInID: UUID?
    public var tripID: UUID?
    public var placeID: UUID?
    public var plantID: UUID?
    public var mealID: UUID?

    public static let none = JournalLinks()

    public init(
        checkInID: UUID? = nil,
        tripID: UUID? = nil,
        placeID: UUID? = nil,
        plantID: UUID? = nil,
        mealID: UUID? = nil
    ) {
        self.checkInID = checkInID
        self.tripID = tripID
        self.placeID = placeID
        self.plantID = plantID
        self.mealID = mealID
    }

    public var isEmpty: Bool {
        checkInID == nil && tripID == nil && placeID == nil
            && plantID == nil && mealID == nil
    }
}

/// A journal entry.
///
/// Drafts are first-class: an entry exists from the moment the user starts
/// typing, autosaves as they go, and is only "published" when they choose. Losing
/// half-written writing to an interruption is not acceptable
/// (INFORMATION_ARCHITECTURE.md §14).
public struct JournalEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String?
    public var body: String
    public var isDraft: Bool
    public var tags: [String]
    public var isFavorite: Bool
    public var links: JournalLinks
    public var attachmentIDs: [UUID]
    public var gratitudeItems: [GratitudeItem]
    public let createdAt: Date
    public var modifiedAt: Date
    /// Set when the user deletes the entry, rather than removing the record.
    ///
    /// Deleting writing is easy to regret, so deletion is reversible for a window
    /// before anything is destroyed (WELLNESS_JOURNAL_AND_CALM.md §6).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String = "",
        isDraft: Bool = true,
        tags: [String] = [],
        isFavorite: Bool = false,
        links: JournalLinks = .none,
        attachmentIDs: [UUID] = [],
        gratitudeItems: [GratitudeItem] = [],
        createdAt: Date,
        modifiedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isDraft = isDraft
        self.tags = tags
        self.isFavorite = isFavorite
        self.links = links
        self.attachmentIDs = attachmentIDs
        self.gratitudeItems = gratitudeItems
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Whether there is anything worth keeping. An untouched draft is discarded
    /// rather than cluttering the list.
    public var hasContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !attachmentIDs.isEmpty
            || !gratitudeItems.isEmpty
    }

    /// How long a deleted entry can still be restored.
    public static let restoreWindow: TimeInterval = 60 * 60 * 24 * 30

    /// The same window in whole days, for the sentence shown when an entry is
    /// deleted.
    ///
    /// Derived rather than written out again. ADR-033 requires the user to be
    /// told that "delete" is reversible and for how long; a hardcoded "30" in a
    /// string file would drift from `restoreWindow` the first time anyone tuned
    /// it, and the app would then be quietly promising the wrong thing — which
    /// is the same class of problem the rule exists to prevent.
    public static var restoreWindowDays: Int {
        Int((restoreWindow / (60 * 60 * 24)).rounded())
    }

    public func isRestorable(at date: Date) -> Bool {
        guard let deletedAt else { return false }
        return date.timeIntervalSince(deletedAt) < Self.restoreWindow
    }
}
