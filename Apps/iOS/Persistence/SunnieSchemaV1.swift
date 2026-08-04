import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 1.
///
/// Two deliberate choices shape every model here, both made for CloudKit
/// compatibility (ADR-011):
///
/// 1. **No `@Attribute(.unique)`.** CloudKit's private database does not support
///    unique constraints. Idempotency is enforced in the repositories instead,
///    inside a serialized `@ModelActor`, so the guarantee holds identically with
///    or without sync enabled.
/// 2. **No SwiftData relationships; UUID foreign keys throughout.** The product
///    rule is archive-never-delete, so cascade semantics buy little, and plain
///    keys keep the eventual CloudKit record shape predictable.
///
/// Every stored property has a default value, which CloudKit also requires.
enum SunnieSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
            SDPendingWatchAction.self
        ]
    }
}

// MARK: - Identity and settings

@Model
final class SDUserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var preferredNickname: String?
    var homeTimeZoneID: String = TimeZone.current.identifier
    var preferredLocale: String = "en_US"
    var enabledLanguageIDs: [String] = ["en"]
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        displayName: String = "",
        preferredNickname: String? = nil,
        homeTimeZoneID: String = TimeZone.current.identifier,
        preferredLocale: String = "en_US",
        enabledLanguageIDs: [String] = ["en"],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredNickname = preferredNickname
        self.homeTimeZoneID = homeTimeZoneID
        self.preferredLocale = preferredLocale
        self.enabledLanguageIDs = enabledLanguageIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// Preferences are stored as one encoded blob rather than thirty columns.
///
/// They are read and written whole, never queried by field, and the shape churns
/// as settings are added — a blob keeps that churn out of the migration path.
@Model
final class SDUserPreferences {
    var id: UUID = UUID()
    var encoded: Data = Data()
    var modifiedAt: Date = Date()

    init(id: UUID = UUID(), encoded: Data = Data(), modifiedAt: Date = Date()) {
        self.id = id
        self.encoded = encoded
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Plants

@Model
final class SDPlantLocation {
    var id: UUID = UUID()
    var name: String = ""
    var room: String?
    var lightNotes: String?
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        name: String = "",
        room: String? = nil,
        lightNotes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.lightNotes = lightNotes
        self.sortOrder = sortOrder
    }
}

@Model
final class SDPlant {
    var id: UUID = UUID()
    var name: String = ""
    var nickname: String?
    var speciesName: String?
    var variety: String?
    var locationID: UUID?
    var lightProfileRaw: String = LightProfile.unknown.rawValue
    var difficultyRaw: String = CareDifficulty.moderate.rawValue
    var acquiredDate: Date?
    var source: String?
    var pot: String?
    var soil: String?
    var notes: String?
    var statusRaw: String = PlantStatus.active.rawValue
    var qrToken: String = ""
    var primaryPhotoID: UUID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        nickname: String? = nil,
        speciesName: String? = nil,
        variety: String? = nil,
        locationID: UUID? = nil,
        lightProfileRaw: String = LightProfile.unknown.rawValue,
        difficultyRaw: String = CareDifficulty.moderate.rawValue,
        acquiredDate: Date? = nil,
        source: String? = nil,
        pot: String? = nil,
        soil: String? = nil,
        notes: String? = nil,
        statusRaw: String = PlantStatus.active.rawValue,
        qrToken: String = "",
        primaryPhotoID: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.speciesName = speciesName
        self.variety = variety
        self.locationID = locationID
        self.lightProfileRaw = lightProfileRaw
        self.difficultyRaw = difficultyRaw
        self.acquiredDate = acquiredDate
        self.source = source
        self.pot = pot
        self.soil = soil
        self.notes = notes
        self.statusRaw = statusRaw
        self.qrToken = qrToken
        self.primaryPhotoID = primaryPhotoID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDPlantCareSchedule {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    var careTypeKey: String = CareType.water.storageKey
    /// Nil means a manual schedule with no due date.
    var intervalDays: Int?
    var springMultiplier: Double = 1
    var summerMultiplier: Double = 1
    var autumnMultiplier: Double = 1
    var winterMultiplier: Double = 1
    var preferredHour: Int = 9
    var isEnabled: Bool = true
    var lastCompletedAt: Date?
    var nextDueDate: Date?

    init(
        id: UUID = UUID(),
        plantID: UUID = UUID(),
        careTypeKey: String = CareType.water.storageKey,
        intervalDays: Int? = nil,
        springMultiplier: Double = 1,
        summerMultiplier: Double = 1,
        autumnMultiplier: Double = 1,
        winterMultiplier: Double = 1,
        preferredHour: Int = 9,
        isEnabled: Bool = true,
        lastCompletedAt: Date? = nil,
        nextDueDate: Date? = nil
    ) {
        self.id = id
        self.plantID = plantID
        self.careTypeKey = careTypeKey
        self.intervalDays = intervalDays
        self.springMultiplier = springMultiplier
        self.summerMultiplier = summerMultiplier
        self.autumnMultiplier = autumnMultiplier
        self.winterMultiplier = winterMultiplier
        self.preferredHour = preferredHour
        self.isEnabled = isEnabled
        self.lastCompletedAt = lastCompletedAt
        self.nextDueDate = nextDueDate
    }
}

@Model
final class SDPlantCareEvent {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    var careTypeKey: String = CareType.water.storageKey
    var performedAt: Date = Date()
    var sourceDeviceID: String = ""
    var caretakerID: UUID?
    var note: String?
    var photoID: UUID?
    var measurement: Double?
    var measurementUnit: String?
    /// Uniqueness is enforced by `SwiftDataPlantCareEventRepository`, not by a
    /// `.unique` attribute — see the note on `SunnieSchemaV1`.
    var actionKey: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        plantID: UUID = UUID(),
        careTypeKey: String = CareType.water.storageKey,
        performedAt: Date = Date(),
        sourceDeviceID: String = "",
        caretakerID: UUID? = nil,
        note: String? = nil,
        photoID: UUID? = nil,
        measurement: Double? = nil,
        measurementUnit: String? = nil,
        actionKey: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.plantID = plantID
        self.careTypeKey = careTypeKey
        self.performedAt = performedAt
        self.sourceDeviceID = sourceDeviceID
        self.caretakerID = caretakerID
        self.note = note
        self.photoID = photoID
        self.measurement = measurement
        self.measurementUnit = measurementUnit
        self.actionKey = actionKey
        self.createdAt = createdAt
    }
}

// MARK: - Progression

@Model
final class SDProgressionProfile {
    var id: UUID = UUID()
    var experience: Int = 0
    var level: Int = 1
    var activeDayCount: Int = 0
    var lastActivityAt: Date?

    init(
        id: UUID = UUID(),
        experience: Int = 0,
        level: Int = 1,
        activeDayCount: Int = 0,
        lastActivityAt: Date? = nil
    ) {
        self.id = id
        self.experience = experience
        self.level = level
        self.activeDayCount = activeDayCount
        self.lastActivityAt = lastActivityAt
    }
}

@Model
final class SDProgressionEvent {
    var id: UUID = UUID()
    var typeRaw: String = ""
    var sourceEntityID: UUID?
    var occurredAt: Date = Date()
    var deterministicKey: String = ""
    var payloadVersion: Int = 1
    var experienceAwarded: Int = 0

    init(
        id: UUID = UUID(),
        typeRaw: String = "",
        sourceEntityID: UUID? = nil,
        occurredAt: Date = Date(),
        deterministicKey: String = "",
        payloadVersion: Int = 1,
        experienceAwarded: Int = 0
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.sourceEntityID = sourceEntityID
        self.occurredAt = occurredAt
        self.deterministicKey = deterministicKey
        self.payloadVersion = payloadVersion
        self.experienceAwarded = experienceAwarded
    }
}

@Model
final class SDRewardGrant {
    var id: UUID = UUID()
    var rewardID: String = ""
    var grantedAt: Date = Date()
    var sourceEventID: UUID?
    var deterministicKey: String = ""

    init(
        id: UUID = UUID(),
        rewardID: String = "",
        grantedAt: Date = Date(),
        sourceEventID: UUID? = nil,
        deterministicKey: String = ""
    ) {
        self.id = id
        self.rewardID = rewardID
        self.grantedAt = grantedAt
        self.sourceEventID = sourceEventID
        self.deterministicKey = deterministicKey
    }
}

// MARK: - Themes and Watch

@Model
final class SDThemeSelection {
    var id: UUID = UUID()
    var activeThemeID: String = ThemeCatalog.lushTropicalJungleID.rawValue
    var selectedAt: Date = Date()

    init(
        id: UUID = UUID(),
        activeThemeID: String = ThemeCatalog.lushTropicalJungleID.rawValue,
        selectedAt: Date = Date()
    ) {
        self.id = id
        self.activeThemeID = activeThemeID
        self.selectedAt = selectedAt
    }
}

@Model
final class SDPendingWatchAction {
    var id: UUID = UUID()
    var payloadVersion: Int = WatchPayloadVersion.current
    var payloadData: Data = Data()
    var createdAt: Date = Date()
    var sourceDeviceID: String = ""
    var processedAt: Date?
    var stateRaw: String = PendingWatchActionState.pending.rawValue
    var actionKey: String = ""

    init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        payloadData: Data = Data(),
        createdAt: Date = Date(),
        sourceDeviceID: String = "",
        processedAt: Date? = nil,
        stateRaw: String = PendingWatchActionState.pending.rawValue,
        actionKey: String = ""
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.sourceDeviceID = sourceDeviceID
        self.processedAt = processedAt
        self.stateRaw = stateRaw
        self.actionKey = actionKey
    }
}

/// Migration plan.
///
/// Migrations are product work, not an afterthought (CLAUDE.md). The rule this
/// file enforces: a shipped schema version is frozen. Adding to the model set
/// means a new `VersionedSchema` and a new stage here, never an edit to an
/// existing one — someone's store on disk is already shaped like the old version.
///
/// V1 → V2 is purely additive (wellness, journal, media, reminders), so the stage
/// is lightweight and SwiftData handles it. A future version that *changes* an
/// existing model needs a custom stage with an explicit data transform, and V1's
/// model classes will have to be copied into a frozen namespace at that point.
enum SunnieMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SunnieSchemaV1.self,
            SunnieSchemaV2.self,
            SunnieSchemaV3.self,
            SunnieSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }

    /// Additive only: every V1 model keeps its exact shape, so no data moves.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SunnieSchemaV1.self,
        toVersion: SunnieSchemaV2.self
    )

    /// Also additive: health observations, growth entries, caretakers, coverage,
    /// and care-event supersession are all new models. Keeping it that way was a
    /// constraint on the design rather than a happy accident — see the note on
    /// `SunnieSchemaV3`.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SunnieSchemaV2.self,
        toVersion: SunnieSchemaV3.self
    )

    /// Additive again: trips, segments, places, packing, templates, checklists,
    /// and memories are all new models. `SDPlantTravelCoverage` already carried
    /// `tripID` from V3, so trips arriving here needed no change to it — the one
    /// place this could plausibly have stopped being additive.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SunnieSchemaV3.self,
        toVersion: SunnieSchemaV4.self
    )
}

/// The version the app currently opens stores at.
///
/// Referenced in one place so bumping the schema is a single edit rather than a
/// search for every `Schema(versionedSchema:)` call site.
typealias SunnieCurrentSchema = SunnieSchemaV4
