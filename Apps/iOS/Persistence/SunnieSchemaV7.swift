import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 7 — Sunnie's home.
///
/// **Additive, like V2 through V6.** The scene, its placements, and the record
/// of which story scenes have been read are all new models.
///
/// Ownership needed no new model at all: a reward has been owned since V1 as an
/// `SDRewardGrant`, keyed by content ID and deterministic key. That is what makes
/// "content-pack removal does not delete ownership records"
/// (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §12) true by construction rather
/// than by a rule someone has to remember — the grant does not reference the pack
/// that produced it and cannot be cascaded away with it.
enum SunnieSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SunnieSchemaV6.models + [
            SDHomeScene.self,
            SDHomePlacement.self,
            SDStorySceneSeen.self
        ]
    }
}

/// The single home-scene record.
///
/// One row, like `SDUserPreferences` and `SDThemeSelection`. The displayed
/// memories and favourite plants are stored as ID arrays rather than as
/// relationships, because SwiftData relationships and CloudKit do not coexist
/// (ADR-011) and these are read whole with the scene anyway.
@Model
final class SDHomeScene {
    var id: UUID = UUID()
    var equippedOutfitID: String = ""
    var selectedSoundID: String = ""
    var displayedMemoryIDs: [UUID] = []
    var favoritePlantIDs: [UUID] = []
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        equippedOutfitID: String = "",
        selectedSoundID: String = "",
        displayedMemoryIDs: [UUID] = [],
        favoritePlantIDs: [UUID] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.equippedOutfitID = equippedOutfitID
        self.selectedSoundID = selectedSoundID
        self.displayedMemoryIDs = displayedMemoryIDs
        self.favoritePlantIDs = favoritePlantIDs
        self.updatedAt = updatedAt
    }
}

/// One thing in one slot.
///
/// A row per placement rather than a dictionary on the scene, so two devices
/// that each moved a different object merge by row instead of one whole scene
/// overwriting the other (§12).
@Model
final class SDHomePlacement {
    var id: UUID = UUID()
    var slotID: String = ""
    var rewardID: String = ""
    var placedAt: Date = Date()

    init(
        id: UUID = UUID(),
        slotID: String = "",
        rewardID: String = "",
        placedAt: Date = Date()
    ) {
        self.id = id
        self.slotID = slotID
        self.rewardID = rewardID
        self.placedAt = placedAt
    }
}

/// A story scene the user has read.
///
/// Stored so a scene is offered once rather than every launch. Deliberately not
/// a reward grant: reading a story is not an achievement, and putting it in the
/// collection would turn optional content into a checklist.
@Model
final class SDStorySceneSeen {
    var id: UUID = UUID()
    var sceneID: String = ""
    var seenAt: Date = Date()

    init(id: UUID = UUID(), sceneID: String = "", seenAt: Date = Date()) {
        self.id = id
        self.sceneID = sceneID
        self.seenAt = seenAt
    }
}
