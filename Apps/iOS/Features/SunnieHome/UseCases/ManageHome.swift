import Foundation
import SunnieShared

/// Arranging Sunnie's home (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §8, §9).
///
/// Every mutation goes through an ownership check, because the alternative is a
/// scene that can be told to display something the user does not have — which
/// then renders as a blank space with no explanation.
struct ManageHome: Sendable {

    private let repository: any HomeRepository
    private let collection: ManageCollection
    private let travelRepository: any TravelRepository
    private let plantRepository: any PlantRepository
    /// Only the noise generator, not `AudioService`. Nothing in the home plays a
    /// file yet, and taking a dependency on the file player now would be
    /// composing something this feature does not use.
    private let noise: any NoiseGenerating
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        repository: any HomeRepository,
        collection: ManageCollection,
        travelRepository: any TravelRepository,
        plantRepository: any PlantRepository,
        noise: any NoiseGenerating,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.collection = collection
        self.travelRepository = travelRepository
        self.plantRepository = plantRepository
        self.noise = noise
        self.clock = clock
    }

    // MARK: - Reading

    func sceneState() async throws -> HomeSceneState {
        try await repository.sceneState()
    }

    func placements() async throws -> [HomePlacement] {
        try await repository.placements()
    }

    /// Placements keyed by slot, which is how the scene draws.
    func placementsBySlot() async -> [ContentID: RewardDefinition] {
        let placements = (try? await repository.placements()) ?? []
        var result: [ContentID: RewardDefinition] = [:]
        for placement in placements {
            // A placement whose reward no installed pack describes is dropped
            // from the scene but left in the store: the pack may come back, and
            // deleting the row would lose an arrangement the user made (§12).
            guard let reward = collection.reward(id: placement.rewardID) else { continue }
            result[placement.slotID] = reward
        }
        return result
    }

    /// The owned rewards that could go in a slot.
    func candidates(for slot: DecorSlot) async -> [RewardDefinition] {
        let owned = await collection.ownedRewardIDs()
        return PlacementRules.candidates(
            for: slot,
            owned: collection.rewards.filter { owned.contains($0.id) }
        )
    }

    func ownedOutfits() async -> [RewardDefinition] {
        let owned = await collection.ownedRewardIDs()
        return collection.rewards
            .filter { $0.category == .outfit && owned.contains($0.id) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func ownedSounds() async -> [RewardDefinition] {
        let owned = await collection.ownedRewardIDs()
        return collection.rewards
            .filter {
                (($0.category == .music) || ($0.category == .ambience)) && owned.contains($0.id)
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    // MARK: - Arranging

    /// Puts something in a slot.
    ///
    /// Returns the refusal rather than throwing, because every refusal here is a
    /// thing the UI should explain in place — not an error to surface as a
    /// failure banner.
    @discardableResult
    func place(rewardID: ContentID, in slotID: ContentID) async -> PlacementRefusal? {
        guard let reward = collection.reward(id: rewardID) else {
            return .slotUnknown(rewardID)
        }
        let owned = await collection.ownedRewardIDs()

        if let refusal = PlacementRules.check(
            reward: reward,
            slot: collection.slot(id: slotID),
            isOwned: owned.contains(rewardID)
        ) {
            return refusal
        }

        do {
            try await repository.place(rewardID: rewardID, in: slotID, at: clock.now)
            return nil
        } catch {
            log.error("Placing \(rewardID.rawValue) failed.")
            return .slotUnknown(slotID)
        }
    }

    func clear(slotID: ContentID) async {
        try? await repository.clear(slotID: slotID)
    }

    /// Equips an outfit, or takes one off when passed nil.
    @discardableResult
    func equip(outfitID: ContentID?) async -> Bool {
        if let outfitID {
            let owned = await collection.ownedRewardIDs()
            guard owned.contains(outfitID),
                  collection.reward(id: outfitID)?.category == .outfit
            else { return false }
        }

        guard var state = try? await repository.sceneState() else { return false }
        state.equippedOutfitID = outfitID
        state.updatedAt = clock.now
        try? await repository.save(state)
        return true
    }

    /// Chooses what plays in the home, and starts or stops it.
    ///
    /// Only generated noise makes sound today, so a reward pointing at a
    /// recorded ambience is stored as the selection and simply plays nothing
    /// until Phase 10 brings the asset. That is better than refusing the
    /// selection: the choice is real, the audio is what is missing.
    @discardableResult
    func selectSound(_ rewardID: ContentID?) async -> Bool {
        var soundID: ContentID?
        if let rewardID {
            let owned = await collection.ownedRewardIDs()
            guard owned.contains(rewardID), let reward = collection.reward(id: rewardID) else {
                return false
            }
            guard reward.category == .music || reward.category == .ambience else { return false }
            soundID = reward.soundID
        }

        guard var state = try? await repository.sceneState() else { return false }
        state.selectedSoundRewardID = rewardID
        state.updatedAt = clock.now
        try? await repository.save(state)

        if let soundID, let color = NoiseColor.from(contentID: soundID) {
            await noise.start(color)
        } else {
            await noise.stop()
        }
        return true
    }

    /// Stops whatever the home was playing.
    ///
    /// Called when the screen goes away. The *selection* is kept — leaving the
    /// room should not forget what the user chose to have on in it.
    func stopSound() async {
        await noise.stop()
    }

    // MARK: - What is on display

    /// Sets the memories shown in the travel nook, newest first.
    func setDisplayedMemories(_ ids: [UUID]) async {
        guard var state = try? await repository.sceneState() else { return }
        state.displayedMemoryIDs = Array(ids.prefix(HomeSceneState.maximumDisplayedMemories))
        state.updatedAt = clock.now
        try? await repository.save(state)
    }

    func setFavoritePlants(_ ids: [UUID]) async {
        guard var state = try? await repository.sceneState() else { return }
        state.favoritePlantIDs = Array(ids.prefix(HomeSceneState.maximumFavoritePlants))
        state.updatedAt = clock.now
        try? await repository.save(state)
    }

    /// The memories actually on display, resolved and in the stored order.
    ///
    /// A memory the user deleted drops out silently rather than leaving a gap:
    /// the display list is a preference, not a second copy of the data.
    func displayedMemories() async -> [TravelMemory] {
        guard let state = try? await repository.sceneState() else { return [] }
        var memories: [TravelMemory] = []
        for id in state.displayedMemoryIDs {
            if let memory = try? await travelRepository.memory(id: id) {
                memories.append(memory)
            }
        }
        return memories
    }

    func favoritePlants() async -> [Plant] {
        guard let state = try? await repository.sceneState() else { return [] }
        var plants: [Plant] = []
        for id in state.favoritePlantIDs {
            if let plant = try? await plantRepository.plant(id: id) {
                plants.append(plant)
            }
        }
        return plants
    }

    // MARK: - Story scenes

    /// Scenes that are earned and not yet read.
    func unreadStoryScenes() async -> [StoryScene] {
        guard let progress = try? await collection.currentProgress() else { return [] }
        let seen = (try? await repository.seenStorySceneIDs()) ?? []
        return RewardUnlockPlanner.dueScenes(
            scenes: collection.storyScenes, progress: progress, ownedRewardIDs: seen
        )
    }

    func markSceneRead(_ id: ContentID) async {
        try? await repository.markStorySceneSeen(id, at: clock.now)
    }

    // MARK: - Scene resolution

    /// What the scene shows right now (§9).
    func variant(
        themeID: ContentID,
        phase: TimePhase,
        isNorthernHemisphere: Bool,
        reduceMotion: Bool
    ) async -> HomeSceneVariant {
        let state = (try? await repository.sceneState())
            ?? HomeSceneState(updatedAt: clock.now)
        let owned = await collection.ownedRewardIDs()

        let trips = (try? await travelRepository.trips(includingArchived: false)) ?? []
        let activeTrip = trips.first {
            TripStatusCalculator.status(
                for: $0, now: clock.now, calendar: clock.calendar
            ).isCurrent
        }
        let destinationID = activeTrip?.destinationPackIDs.first

        let recent = await recentUnlockID()

        return HomeSceneResolver.variant(
            context: HomeSceneContext(
                themeID: themeID,
                phase: phase,
                destinationID: destinationID,
                recentUnlockID: recent,
                season: Season.current(
                    for: clock.now,
                    calendar: clock.calendar,
                    isNorthernHemisphere: isNorthernHemisphere
                )
            ),
            state: state,
            ownedRewardIDs: owned,
            definitions: Dictionary(
                collection.rewards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            ),
            reduceMotion: reduceMotion
        )
    }

    /// The most recent unlock, if it is recent enough to still be worth pointing
    /// at.
    private func recentUnlockID() async -> ContentID? {
        guard let latest = try? await collection.newestGrant() else { return nil }
        let age = clock.now.timeIntervalSince(latest.grantedAt)
        guard age >= 0, age <= HomeSceneContext.recentUnlockWindow else { return nil }
        return latest.rewardID
    }
}
