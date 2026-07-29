import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 2 — adds wellness, journal, media, and reminders.
///
/// **This migration is purely additive.** No V1 model changes shape, so V2
/// re-lists the same model classes alongside the new ones and the stage is
/// lightweight. That is why the classes are shared between versions rather than
/// copied into a per-version namespace.
///
/// The moment a *existing* model changes — a renamed property, a changed type, a
/// split entity — that shortcut stops working. At that point V1's models must be
/// copied into a `SunnieSchemaV1` namespace, frozen there, and the stage becomes
/// custom with an explicit data transform. `SchemaMigrationTests` exists to make
/// that failure loud rather than silent.
enum SunnieSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            // Unchanged from V1.
            SDUserProfile.self,
            SDUserPreferences.self,
            SDPlant.self,
            SDPlantLocation.self,
            SDPlantCareSchedule.self,
            SDPlantCareEvent.self,
            SDProgressionProfile.self,
            SDProgressionEvent.self,
            SDRewardGrant.self,
            SDThemeSelection.self,
            SDPendingWatchAction.self,
            // New in V2.
            SDWellnessCheckIn.self,
            SDWellnessSession.self,
            SDJournalEntry.self,
            SDMediaAttachment.self,
            SDScheduledReminder.self
        ]
    }
}

// MARK: - Wellness

@Model
final class SDWellnessCheckIn {
    var id: UUID = UUID()
    var recordedAt: Date = Date()
    var timeZoneID: String = TimeZone.current.identifier
    /// Scale values are stored as optional Ints rather than an enum raw value so
    /// "not answered" stays distinct from any point on the scale.
    var mood: Int?
    var energy: Int?
    var stress: Int?
    var sleepQuality: Int?
    var note: String?
    var voiceNoteID: UUID?
    var photoID: UUID?
    var sourceDeviceID: String = ""
    /// Uniqueness enforced by the repository, not a constraint (ADR-011).
    var actionKey: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        timeZoneID: String = TimeZone.current.identifier,
        mood: Int? = nil,
        energy: Int? = nil,
        stress: Int? = nil,
        sleepQuality: Int? = nil,
        note: String? = nil,
        voiceNoteID: UUID? = nil,
        photoID: UUID? = nil,
        sourceDeviceID: String = "",
        actionKey: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.timeZoneID = timeZoneID
        self.mood = mood
        self.energy = energy
        self.stress = stress
        self.sleepQuality = sleepQuality
        self.note = note
        self.voiceNoteID = voiceNoteID
        self.photoID = photoID
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
        self.createdAt = createdAt
    }
}

@Model
final class SDWellnessSession {
    var id: UUID = UUID()
    var typeRaw: String = WellnessSessionType.breathing.rawValue
    var practiceID: String?
    var startedAt: Date = Date()
    var endedAt: Date?
    var plannedDuration: Double = 0
    var completionRaw: String?
    var audioCueID: String?
    /// Set once written to HealthKit, so a retry cannot write the same mindful
    /// minutes twice.
    var healthKitSampleID: String?
    var sourceDeviceID: String = ""
    var actionKey: String = ""

    init(
        id: UUID = UUID(),
        typeRaw: String = WellnessSessionType.breathing.rawValue,
        practiceID: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        plannedDuration: Double = 0,
        completionRaw: String? = nil,
        audioCueID: String? = nil,
        healthKitSampleID: String? = nil,
        sourceDeviceID: String = "",
        actionKey: String = ""
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.practiceID = practiceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDuration = plannedDuration
        self.completionRaw = completionRaw
        self.audioCueID = audioCueID
        self.healthKitSampleID = healthKitSampleID
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
    }
}

// MARK: - Journal

@Model
final class SDJournalEntry {
    var id: UUID = UUID()
    var title: String?
    var body: String = ""
    var isDraft: Bool = true
    var tags: [String] = []
    var isFavorite: Bool = false

    // Links are flat columns rather than relationships, matching the V1
    // convention of UUID foreign keys throughout (ADR-011).
    var linkedCheckInID: UUID?
    var linkedTripID: UUID?
    var linkedPlaceID: UUID?
    var linkedPlantID: UUID?
    var linkedMealID: UUID?

    var attachmentIDs: [UUID] = []
    /// Gratitude items are stored as an encoded blob on the entry.
    ///
    /// They are small, never queried independently, and always read with their
    /// entry — a separate model would add a relationship and a migration surface
    /// for no benefit. If gratitude ever needs its own search, that is a schema
    /// version and a real migration.
    var gratitudeData: Data = Data()

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Soft deletion. Writing is easy to regret, so nothing is destroyed until
    /// the restore window has passed.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String = "",
        isDraft: Bool = true,
        tags: [String] = [],
        isFavorite: Bool = false,
        linkedCheckInID: UUID? = nil,
        linkedTripID: UUID? = nil,
        linkedPlaceID: UUID? = nil,
        linkedPlantID: UUID? = nil,
        linkedMealID: UUID? = nil,
        attachmentIDs: [UUID] = [],
        gratitudeData: Data = Data(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isDraft = isDraft
        self.tags = tags
        self.isFavorite = isFavorite
        self.linkedCheckInID = linkedCheckInID
        self.linkedTripID = linkedTripID
        self.linkedPlaceID = linkedPlaceID
        self.linkedPlantID = linkedPlantID
        self.linkedMealID = linkedMealID
        self.attachmentIDs = attachmentIDs
        self.gratitudeData = gratitudeData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Media

@Model
final class SDMediaAttachment {
    var id: UUID = UUID()
    /// Owner is stored as a kind plus an ID rather than an enum with an
    /// associated value, so it remains queryable.
    var ownerKindRaw: String = ""
    var ownerID: UUID = UUID()
    var kindRaw: String = MediaKind.photo.rawValue
    var localToken: String = ""
    var cloudToken: String?
    var thumbnailToken: String?
    var duration: Double?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        ownerKindRaw: String = "",
        ownerID: UUID = UUID(),
        kindRaw: String = MediaKind.photo.rawValue,
        localToken: String = "",
        cloudToken: String? = nil,
        thumbnailToken: String? = nil,
        duration: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerKindRaw = ownerKindRaw
        self.ownerID = ownerID
        self.kindRaw = kindRaw
        self.localToken = localToken
        self.cloudToken = cloudToken
        self.thumbnailToken = thumbnailToken
        self.duration = duration
        self.createdAt = createdAt
    }
}

// MARK: - Reminders

@Model
final class SDScheduledReminder {
    var id: UUID = UUID()
    var categoryRaw: String = ""
    var sourceEntityID: UUID?
    var scheduledAt: Date = Date()
    var timeZonePolicyRaw: String = ReminderTimeZonePolicy.deviceTimeZone.rawValue
    var cadenceLevelRaw: Int = AdaptiveCadenceLevel.single.rawValue
    var respectsQuietHours: Bool = true
    var responseRaw: String = ReminderResponse.noResponse.rawValue
    var respondedAt: Date?
    /// The UserNotifications identifier, so a superseded request can be
    /// cancelled rather than left to fire alongside its replacement.
    var notificationRequestID: String?
    var isEnabled: Bool = true

    init(
        id: UUID = UUID(),
        categoryRaw: String = "",
        sourceEntityID: UUID? = nil,
        scheduledAt: Date = Date(),
        timeZonePolicyRaw: String = ReminderTimeZonePolicy.deviceTimeZone.rawValue,
        cadenceLevelRaw: Int = AdaptiveCadenceLevel.single.rawValue,
        respectsQuietHours: Bool = true,
        responseRaw: String = ReminderResponse.noResponse.rawValue,
        respondedAt: Date? = nil,
        notificationRequestID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.sourceEntityID = sourceEntityID
        self.scheduledAt = scheduledAt
        self.timeZonePolicyRaw = timeZonePolicyRaw
        self.cadenceLevelRaw = cadenceLevelRaw
        self.respectsQuietHours = respectsQuietHours
        self.responseRaw = responseRaw
        self.respondedAt = respondedAt
        self.notificationRequestID = notificationRequestID
        self.isEnabled = isEnabled
    }
}

/// Owner kinds for media, kept as strings so the column stays queryable.
enum MediaOwnerKind: String, CaseIterable {
    case journalEntry
    case checkIn
    case plant
    case trip
    case meal

    init(owner: MediaOwner) {
        switch owner {
        case .journalEntry: self = .journalEntry
        case .checkIn: self = .checkIn
        case .plant: self = .plant
        case .trip: self = .trip
        case .meal: self = .meal
        }
    }

    func owner(id: UUID) -> MediaOwner {
        switch self {
        case .journalEntry: .journalEntry(id)
        case .checkIn: .checkIn(id)
        case .plant: .plant(id)
        case .trip: .trip(id)
        case .meal: .meal(id)
        }
    }

    static func id(of owner: MediaOwner) -> UUID {
        switch owner {
        case .journalEntry(let id), .checkIn(let id), .plant(let id),
             .trip(let id), .meal(let id):
            id
        }
    }
}
