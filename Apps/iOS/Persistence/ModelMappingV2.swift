import Foundation
import SunnieShared

/// Mapping for the models added in schema V2.
///
/// Same discipline as V1: nothing outside Persistence ever sees an `SD` type, and
/// an unreadable raw value falls back to a safe default rather than trapping.
/// Losing a record to a force-unwrap would be worse than showing it
/// conservatively.
extension ModelMapping {

    // MARK: - Check-ins

    static func domain(_ model: SDWellnessCheckIn) -> WellnessCheckIn {
        WellnessCheckIn(
            id: model.id,
            recordedAt: model.recordedAt,
            timeZoneID: model.timeZoneID,
            mood: scaleValue(model.mood),
            energy: scaleValue(model.energy),
            stress: scaleValue(model.stress),
            sleepQuality: scaleValue(model.sleepQuality),
            note: model.note,
            voiceNoteID: model.voiceNoteID,
            photoID: model.photoID,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            actionKey: ActionKey(rawValue: model.actionKey),
            createdAt: model.createdAt
        )
    }

    static func model(_ checkIn: WellnessCheckIn) -> SDWellnessCheckIn {
        SDWellnessCheckIn(
            id: checkIn.id,
            recordedAt: checkIn.recordedAt,
            timeZoneID: checkIn.timeZoneID,
            mood: checkIn.mood?.rawValue,
            energy: checkIn.energy?.rawValue,
            stress: checkIn.stress?.rawValue,
            sleepQuality: checkIn.sleepQuality?.rawValue,
            note: checkIn.note,
            voiceNoteID: checkIn.voiceNoteID,
            photoID: checkIn.photoID,
            sourceDeviceID: checkIn.sourceDeviceID.rawValue,
            actionKey: checkIn.actionKey.rawValue,
            createdAt: checkIn.createdAt
        )
    }

    /// An out-of-range stored value reads as "not answered" rather than being
    /// clamped onto the scale — inventing an answer the user never gave would be
    /// worse than showing a gap.
    private static func scaleValue(_ raw: Int?) -> WellnessScaleValue? {
        guard let raw else { return nil }
        return WellnessScaleValue(rawValue: raw)
    }

    // MARK: - Sessions

    static func domain(_ model: SDWellnessSession) -> WellnessSession {
        WellnessSession(
            id: model.id,
            type: WellnessSessionType(rawValue: model.typeRaw) ?? .breathing,
            practiceID: model.practiceID.map { ContentID(rawValue: $0) },
            startedAt: model.startedAt,
            endedAt: model.endedAt,
            plannedDuration: model.plannedDuration,
            completion: model.completionRaw.flatMap(WellnessSessionCompletion.init(rawValue:)),
            audioCueID: model.audioCueID.map { ContentID(rawValue: $0) },
            healthKitSampleID: model.healthKitSampleID,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            actionKey: ActionKey(rawValue: model.actionKey)
        )
    }

    static func apply(_ session: WellnessSession, to model: SDWellnessSession) {
        model.id = session.id
        model.typeRaw = session.type.rawValue
        model.practiceID = session.practiceID?.rawValue
        model.startedAt = session.startedAt
        model.endedAt = session.endedAt
        model.plannedDuration = session.plannedDuration
        model.completionRaw = session.completion?.rawValue
        model.audioCueID = session.audioCueID?.rawValue
        model.healthKitSampleID = session.healthKitSampleID
        model.sourceDeviceID = session.sourceDeviceID.rawValue
        model.actionKey = session.actionKey.rawValue
    }

    // MARK: - Journal

    static func domain(_ model: SDJournalEntry) -> JournalEntry {
        JournalEntry(
            id: model.id,
            title: model.title,
            body: model.body,
            isDraft: model.isDraft,
            tags: model.tags,
            isFavorite: model.isFavorite,
            links: JournalLinks(
                checkInID: model.linkedCheckInID,
                tripID: model.linkedTripID,
                placeID: model.linkedPlaceID,
                plantID: model.linkedPlantID,
                mealID: model.linkedMealID
            ),
            attachmentIDs: model.attachmentIDs,
            gratitudeItems: decodeGratitude(model.gratitudeData),
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt,
            deletedAt: model.deletedAt
        )
    }

    static func apply(_ entry: JournalEntry, to model: SDJournalEntry) {
        model.id = entry.id
        model.title = entry.title
        model.body = entry.body
        model.isDraft = entry.isDraft
        model.tags = entry.tags
        model.isFavorite = entry.isFavorite
        model.linkedCheckInID = entry.links.checkInID
        model.linkedTripID = entry.links.tripID
        model.linkedPlaceID = entry.links.placeID
        model.linkedPlantID = entry.links.plantID
        model.linkedMealID = entry.links.mealID
        model.attachmentIDs = entry.attachmentIDs
        model.gratitudeData = encodeGratitude(entry.gratitudeItems)
        model.createdAt = entry.createdAt
        model.modifiedAt = entry.modifiedAt
        model.deletedAt = entry.deletedAt
    }

    /// Gratitude round-trips through JSON on the entry.
    ///
    /// A decode failure yields an empty list rather than throwing: losing the
    /// gratitude items is bad, losing the whole entry — someone's writing —
    /// would be far worse.
    static func decodeGratitude(_ data: Data) -> [GratitudeItem] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([GratitudeItem].self, from: data)) ?? []
    }

    static func encodeGratitude(_ items: [GratitudeItem]) -> Data {
        guard !items.isEmpty else { return Data() }
        return (try? JSONEncoder().encode(items)) ?? Data()
    }

    // MARK: - Media

    static func domain(_ model: SDMediaAttachment) -> MediaAttachment {
        let kind = MediaOwnerKind(rawValue: model.ownerKindRaw) ?? .journalEntry
        return MediaAttachment(
            id: model.id,
            owner: kind.owner(id: model.ownerID),
            kind: MediaKind(rawValue: model.kindRaw) ?? .photo,
            localToken: model.localToken,
            cloudToken: model.cloudToken,
            thumbnailToken: model.thumbnailToken,
            duration: model.duration,
            createdAt: model.createdAt
        )
    }

    static func model(_ attachment: MediaAttachment) -> SDMediaAttachment {
        SDMediaAttachment(
            id: attachment.id,
            ownerKindRaw: MediaOwnerKind(owner: attachment.owner).rawValue,
            ownerID: MediaOwnerKind.id(of: attachment.owner),
            kindRaw: attachment.kind.rawValue,
            localToken: attachment.localToken,
            cloudToken: attachment.cloudToken,
            thumbnailToken: attachment.thumbnailToken,
            duration: attachment.duration,
            createdAt: attachment.createdAt
        )
    }

    // MARK: - Reminders

    static func domain(_ model: SDScheduledReminder) -> ScheduledReminderRecord? {
        guard let category = ReminderCategory(rawValue: model.categoryRaw) else {
            // Written by a newer build that knows a category this one does not.
            // Skipping is safer than guessing which reminder it was.
            return nil
        }
        return ScheduledReminderRecord(
            id: model.id,
            category: category,
            sourceEntityID: model.sourceEntityID,
            scheduledAt: model.scheduledAt,
            timeZonePolicy: ReminderTimeZonePolicy(rawValue: model.timeZonePolicyRaw)
                ?? .deviceTimeZone,
            cadenceLevel: AdaptiveCadenceLevel(rawValue: model.cadenceLevelRaw) ?? .single,
            respectsQuietHours: model.respectsQuietHours,
            response: ReminderResponse(rawValue: model.responseRaw) ?? .noResponse,
            respondedAt: model.respondedAt,
            notificationRequestID: model.notificationRequestID,
            isEnabled: model.isEnabled
        )
    }

    static func apply(_ record: ScheduledReminderRecord, to model: SDScheduledReminder) {
        model.id = record.id
        model.categoryRaw = record.category.rawValue
        model.sourceEntityID = record.sourceEntityID
        model.scheduledAt = record.scheduledAt
        model.timeZonePolicyRaw = record.timeZonePolicy.rawValue
        model.cadenceLevelRaw = record.cadenceLevel.rawValue
        model.respectsQuietHours = record.respectsQuietHours
        model.responseRaw = record.response.rawValue
        model.respondedAt = record.respondedAt
        model.notificationRequestID = record.notificationRequestID
        model.isEnabled = record.isEnabled
    }
}
