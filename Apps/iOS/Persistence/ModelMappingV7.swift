import Foundation
import SunnieShared

/// Mapping for the models added in schema V7.
extension ModelMapping {

    // MARK: - Home scene

    /// Empty strings map back to nil.
    ///
    /// The stored columns are non-optional so every SwiftData property keeps a
    /// default (ADR-011); the domain type uses optionals because "no outfit" and
    /// "an outfit whose ID is the empty string" are different things everywhere
    /// above this line.
    static func domain(_ model: SDHomeScene) -> HomeSceneState {
        HomeSceneState(
            equippedOutfitID: model.equippedOutfitID.isEmpty
                ? nil : ContentID(rawValue: model.equippedOutfitID),
            selectedSoundRewardID: model.selectedSoundID.isEmpty
                ? nil : ContentID(rawValue: model.selectedSoundID),
            displayedMemoryIDs: model.displayedMemoryIDs,
            favoritePlantIDs: model.favoritePlantIDs,
            updatedAt: model.updatedAt
        )
    }

    static func apply(_ state: HomeSceneState, to model: SDHomeScene) {
        model.equippedOutfitID = state.equippedOutfitID?.rawValue ?? ""
        model.selectedSoundID = state.selectedSoundRewardID?.rawValue ?? ""
        // Trimmed on the way in as well as on the way out: a state built
        // elsewhere should not be able to grow the stored list past what the
        // scene can show.
        model.displayedMemoryIDs = Array(
            state.displayedMemoryIDs.prefix(HomeSceneState.maximumDisplayedMemories)
        )
        model.favoritePlantIDs = Array(
            state.favoritePlantIDs.prefix(HomeSceneState.maximumFavoritePlants)
        )
        model.updatedAt = state.updatedAt
    }

    // MARK: - Placements

    static func domain(_ model: SDHomePlacement) -> HomePlacement {
        HomePlacement(
            id: model.id,
            slotID: ContentID(rawValue: model.slotID),
            rewardID: ContentID(rawValue: model.rewardID),
            placedAt: model.placedAt
        )
    }

    static func apply(_ placement: HomePlacement, to model: SDHomePlacement) {
        model.id = placement.id
        model.slotID = placement.slotID.rawValue
        model.rewardID = placement.rewardID.rawValue
        model.placedAt = placement.placedAt
    }
}
