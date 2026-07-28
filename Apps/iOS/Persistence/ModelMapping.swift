import Foundation
import SunnieShared

/// Converts between SwiftData models and the shared domain value types.
///
/// Keeping the mapping in one file is what makes "domain models separated from
/// SwiftData model classes" (DATA_MODEL.md §1) practical rather than aspirational
/// — nothing outside Persistence ever sees an `SD` type.
///
/// Where a stored raw value cannot be interpreted — an enum case written by a
/// newer build, a care type from a content pack that is no longer installed —
/// mapping falls back to a safe default rather than trapping. Losing a record to
/// a force-unwrap would be worse than showing it with a conservative default.
enum ModelMapping {

    // MARK: - Plants

    static func domain(_ model: SDPlant) -> Plant {
        Plant(
            id: model.id,
            name: model.name,
            nickname: model.nickname,
            speciesName: model.speciesName,
            variety: model.variety,
            locationID: model.locationID,
            lightProfile: LightProfile(rawValue: model.lightProfileRaw) ?? .unknown,
            difficulty: CareDifficulty(rawValue: model.difficultyRaw) ?? .moderate,
            acquiredDate: model.acquiredDate,
            source: model.source,
            pot: model.pot,
            soil: model.soil,
            notes: model.notes,
            status: PlantStatus(rawValue: model.statusRaw) ?? .active,
            qrToken: model.qrToken,
            primaryPhotoID: model.primaryPhotoID,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ plant: Plant, to model: SDPlant) {
        model.id = plant.id
        model.name = plant.name
        model.nickname = plant.nickname
        model.speciesName = plant.speciesName
        model.variety = plant.variety
        model.locationID = plant.locationID
        model.lightProfileRaw = plant.lightProfile.rawValue
        model.difficultyRaw = plant.difficulty.rawValue
        model.acquiredDate = plant.acquiredDate
        model.source = plant.source
        model.pot = plant.pot
        model.soil = plant.soil
        model.notes = plant.notes
        model.statusRaw = plant.status.rawValue
        model.qrToken = plant.qrToken
        model.primaryPhotoID = plant.primaryPhotoID
        model.createdAt = plant.createdAt
        model.modifiedAt = plant.modifiedAt
    }

    static func domain(_ model: SDPlantLocation) -> PlantLocation {
        PlantLocation(
            id: model.id,
            name: model.name,
            room: model.room,
            lightNotes: model.lightNotes,
            sortOrder: model.sortOrder
        )
    }

    static func apply(_ location: PlantLocation, to model: SDPlantLocation) {
        model.id = location.id
        model.name = location.name
        model.room = location.room
        model.lightNotes = location.lightNotes
        model.sortOrder = location.sortOrder
    }

    // MARK: - Schedules

    static func domain(_ model: SDPlantCareSchedule) -> PlantCareSchedule {
        PlantCareSchedule(
            id: model.id,
            plantID: model.plantID,
            careType: CareType(storageKey: model.careTypeKey) ?? .water,
            recurrence: model.intervalDays.map { CareRecurrence.everyDays($0) } ?? .manual,
            seasonalModifier: SeasonalModifier(
                springMultiplier: model.springMultiplier,
                summerMultiplier: model.summerMultiplier,
                autumnMultiplier: model.autumnMultiplier,
                winterMultiplier: model.winterMultiplier
            ),
            preferredHour: model.preferredHour,
            isEnabled: model.isEnabled,
            lastCompletedAt: model.lastCompletedAt,
            nextDueDate: model.nextDueDate
        )
    }

    static func apply(_ schedule: PlantCareSchedule, to model: SDPlantCareSchedule) {
        model.id = schedule.id
        model.plantID = schedule.plantID
        model.careTypeKey = schedule.careType.storageKey
        model.intervalDays = schedule.recurrence.intervalDays
        model.springMultiplier = schedule.seasonalModifier.springMultiplier
        model.summerMultiplier = schedule.seasonalModifier.summerMultiplier
        model.autumnMultiplier = schedule.seasonalModifier.autumnMultiplier
        model.winterMultiplier = schedule.seasonalModifier.winterMultiplier
        model.preferredHour = schedule.preferredHour
        model.isEnabled = schedule.isEnabled
        model.lastCompletedAt = schedule.lastCompletedAt
        model.nextDueDate = schedule.nextDueDate
    }

    // MARK: - Care events

    static func domain(_ model: SDPlantCareEvent) -> PlantCareEvent {
        PlantCareEvent(
            id: model.id,
            plantID: model.plantID,
            careType: CareType(storageKey: model.careTypeKey) ?? .water,
            performedAt: model.performedAt,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            caretakerID: model.caretakerID,
            note: model.note,
            photoID: model.photoID,
            measurement: model.measurement,
            measurementUnit: model.measurementUnit,
            actionKey: ActionKey(rawValue: model.actionKey),
            createdAt: model.createdAt
        )
    }

    static func model(_ event: PlantCareEvent) -> SDPlantCareEvent {
        SDPlantCareEvent(
            id: event.id,
            plantID: event.plantID,
            careTypeKey: event.careType.storageKey,
            performedAt: event.performedAt,
            sourceDeviceID: event.sourceDeviceID.rawValue,
            caretakerID: event.caretakerID,
            note: event.note,
            photoID: event.photoID,
            measurement: event.measurement,
            measurementUnit: event.measurementUnit,
            actionKey: event.actionKey.rawValue,
            createdAt: event.createdAt
        )
    }

    // MARK: - Progression

    static func domain(_ model: SDProgressionProfile) -> ProgressionProfile {
        ProgressionProfile(
            id: model.id,
            experience: model.experience,
            level: model.level,
            activeDayCount: model.activeDayCount,
            lastActivityAt: model.lastActivityAt
        )
    }

    static func apply(_ profile: ProgressionProfile, to model: SDProgressionProfile) {
        model.id = profile.id
        model.experience = profile.experience
        model.level = profile.level
        model.activeDayCount = profile.activeDayCount
        model.lastActivityAt = profile.lastActivityAt
    }

    /// Returns nil when the stored type is unreadable, so an event written by a
    /// newer build is skipped rather than misreported as some other event.
    static func domain(_ model: SDProgressionEvent) -> ProgressionEvent? {
        guard let type = ProgressionEventType(rawValue: model.typeRaw) else { return nil }
        return ProgressionEvent(
            id: model.id,
            type: type,
            sourceEntityID: model.sourceEntityID,
            occurredAt: model.occurredAt,
            deterministicKey: model.deterministicKey,
            payloadVersion: model.payloadVersion,
            experienceAwarded: model.experienceAwarded
        )
    }

    static func model(_ event: ProgressionEvent) -> SDProgressionEvent {
        SDProgressionEvent(
            id: event.id,
            typeRaw: event.type.rawValue,
            sourceEntityID: event.sourceEntityID,
            occurredAt: event.occurredAt,
            deterministicKey: event.deterministicKey,
            payloadVersion: event.payloadVersion,
            experienceAwarded: event.experienceAwarded
        )
    }

    static func domain(_ model: SDRewardGrant) -> RewardGrant {
        RewardGrant(
            id: model.id,
            rewardID: ContentID(rawValue: model.rewardID),
            grantedAt: model.grantedAt,
            sourceEventID: model.sourceEventID,
            deterministicKey: model.deterministicKey
        )
    }

    static func model(_ grant: RewardGrant) -> SDRewardGrant {
        SDRewardGrant(
            id: grant.id,
            rewardID: grant.rewardID.rawValue,
            grantedAt: grant.grantedAt,
            sourceEventID: grant.sourceEventID,
            deterministicKey: grant.deterministicKey
        )
    }

    // MARK: - Profile and preferences

    static func domain(_ model: SDUserProfile) -> UserProfile {
        UserProfile(
            id: model.id,
            displayName: model.displayName,
            preferredNickname: model.preferredNickname,
            homeTimeZoneID: model.homeTimeZoneID,
            preferredLocale: model.preferredLocale,
            enabledLanguageIDs: model.enabledLanguageIDs,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ profile: UserProfile, to model: SDUserProfile) {
        model.id = profile.id
        model.displayName = profile.displayName
        model.preferredNickname = profile.preferredNickname
        model.homeTimeZoneID = profile.homeTimeZoneID
        model.preferredLocale = profile.preferredLocale
        model.enabledLanguageIDs = profile.enabledLanguageIDs
        model.createdAt = profile.createdAt
        model.modifiedAt = profile.modifiedAt
    }

    // MARK: - Pending Watch actions

    static func domain(_ model: SDPendingWatchAction) -> PendingWatchAction {
        PendingWatchAction(
            id: model.id,
            payloadVersion: model.payloadVersion,
            payloadData: model.payloadData,
            createdAt: model.createdAt,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            processedAt: model.processedAt,
            state: PendingWatchActionState(rawValue: model.stateRaw) ?? .pending,
            actionKey: ActionKey(rawValue: model.actionKey)
        )
    }

    static func model(_ action: PendingWatchAction) -> SDPendingWatchAction {
        SDPendingWatchAction(
            id: action.id,
            payloadVersion: action.payloadVersion,
            payloadData: action.payloadData,
            createdAt: action.createdAt,
            sourceDeviceID: action.sourceDeviceID.rawValue,
            processedAt: action.processedAt,
            stateRaw: action.state.rawValue,
            actionKey: action.actionKey.rawValue
        )
    }
}
