import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Phase 8 behaviour against a real in-memory store: the unlock sweep, keepsakes
/// from a saved memory, home placement, and the scene.
///
/// The sweep's idempotency is tested here rather than only in the shared package
/// because the guarantee is really about the store: the planner being pure is
/// half of it, and the repository collapsing a repeated deterministic key is the
/// other.
@Suite("Collection flows")
struct CollectionFlowTests {

    /// 2026-02-02T12:00:00Z. Noon UTC keeps the rhythm and trip-status tests
    /// inside one local day whatever zone the test machine is set to.
    private static let referenceDate = Date(timeIntervalSince1970: 1_770_033_600)

    @MainActor
    private func makeDependencies(
        now: Date = CollectionFlowTests.referenceDate
    ) throws -> AppDependencies {
        AppDependencies(
            modelContainer: try ModelContainerFactory.make(storage: .inMemory),
            clock: FixedClock(now: now),
            enableWatchConnectivity: false
        )
    }

    // MARK: - The sweep

    @Test("The first sweep grants everything owned from the start")
    @MainActor
    func starterRewardsArriveOnTheFirstSweep() async throws {
        let dependencies = try makeDependencies()

        let granted = await dependencies.manageCollection.sweep()
        #expect(!granted.isEmpty)
        #expect(granted.allSatisfy { $0.unlockSource == .fromTheStart })

        let owned = await dependencies.manageCollection.ownedRewardIDs()
        #expect(owned.contains("sunnie.reward.outfit.everyday"))
    }

    @Test("Sweeping again grants nothing and removes nothing")
    @MainActor
    func sweepIsIdempotent() async throws {
        let dependencies = try makeDependencies()

        let first = await dependencies.manageCollection.sweep()
        #expect(!first.isEmpty)

        let second = await dependencies.manageCollection.sweep()
        #expect(second.isEmpty)

        // And nothing was lost by running it twice.
        let owned = await dependencies.manageCollection.ownedRewardIDs()
        #expect(owned.count == first.count)
    }

    @Test("A level rises and the sweep grants what that level unlocks")
    @MainActor
    func levelUnlocksArrive() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()

        var profile = try await dependencies.progressionRepository.profile()
        profile.level = 5
        try await dependencies.progressionRepository.save(profile)

        let granted = await dependencies.manageCollection.sweep()
        let ids = Set(granted.map(\.id))
        // Everything at or below level 5 arrives at once.
        #expect(ids.contains("sunnie.reward.decor.readingLamp"))
        #expect(ids.contains("sunnie.reward.outfit.cozyPajamas"))
        #expect(ids.contains("sunnie.reward.decor.wovenRug"))
        #expect(granted.allSatisfy { ($0.unlockSource.requiredLevel ?? 0) <= 5 })
    }

    @Test("A dropped level takes nothing away")
    @MainActor
    func loweringALevelRevokesNothing() async throws {
        let dependencies = try makeDependencies()

        var profile = try await dependencies.progressionRepository.profile()
        profile.level = 5
        try await dependencies.progressionRepository.save(profile)
        await dependencies.manageCollection.sweep()

        let ownedAtFive = await dependencies.manageCollection.ownedRewardIDs()
        #expect(ownedAtFive.contains("sunnie.reward.decor.wovenRug"))

        // Back to level 1 — which cannot happen through play, and which the app
        // must survive anyway.
        profile.level = 1
        try await dependencies.progressionRepository.save(profile)
        await dependencies.manageCollection.sweep()

        let ownedAtOne = await dependencies.manageCollection.ownedRewardIDs()
        #expect(ownedAtOne == ownedAtFive, "a level change took something away")
    }

    @Test("Launch housekeeping runs the sweep")
    @MainActor
    func housekeepingSweeps() async throws {
        let dependencies = try makeDependencies()
        await dependencies.performLaunchHousekeeping()

        let owned = await dependencies.manageCollection.ownedRewardIDs()
        #expect(owned.contains("sunnie.reward.outfit.everyday"))
    }

    // MARK: - Keepsakes

    /// A past trip to a place in France, with a memory saved about it.
    @MainActor
    private func makeParisTrip(
        _ dependencies: AppDependencies
    ) async throws -> (trip: Trip, place: Place) {
        let now = Self.referenceDate
        var place = dependencies.manageTrip.newPlace()
        place.name = "Lyon"
        place.country = "France"
        place = try await dependencies.manageTrip.save(place)

        var trip = dependencies.manageTrip.newDraft(type: .past)
        trip.title = "A few days in Lyon"
        trip.startsAt = now.addingTimeInterval(-30 * 86_400)
        trip.endsAt = now.addingTimeInterval(-25 * 86_400)
        trip.placeIDs = [place.id]
        let saved = try await dependencies.manageTrip.save(trip)
        return (saved, place)
    }

    @Test("Saving a memory grants the stamp and postcard for that place")
    @MainActor
    func memoryGrantsKeepsakes() async throws {
        let dependencies = try makeDependencies()
        let (trip, place) = try await makeParisTrip(dependencies)

        var memory = dependencies.manageTrip.newMemory(tripID: trip.id, placeID: place.id)
        memory.title = "The one with the stairs"
        _ = try await dependencies.manageTrip.save(memory)

        let owned = await dependencies.manageCollection.ownedRewardIDs()
        #expect(owned.contains("sunnie.reward.stamp.paris"))
        #expect(owned.contains("sunnie.reward.postcard.paris"))
    }

    @Test("Editing a memory does not earn a second stamp")
    @MainActor
    func editingAMemoryIsNotASecondVisit() async throws {
        let dependencies = try makeDependencies()
        let (trip, place) = try await makeParisTrip(dependencies)

        var memory = dependencies.manageTrip.newMemory(tripID: trip.id, placeID: place.id)
        memory.title = "First draft"
        memory = try await dependencies.manageTrip.save(memory)

        let afterFirst = try await dependencies.progressionRepository.allGrants().count

        memory.title = "Second draft"
        _ = try await dependencies.manageTrip.save(memory)
        memory.text = "And a bit more"
        _ = try await dependencies.manageTrip.save(memory)

        #expect(try await dependencies.progressionRepository.allGrants().count == afterFirst)
    }

    @Test("A second memory from the same place reuses the stamp it already earned")
    @MainActor
    func twoMemoriesShareOneStamp() async throws {
        let dependencies = try makeDependencies()
        let (trip, place) = try await makeParisTrip(dependencies)

        for title in ["The stairs", "The bakery"] {
            var memory = dependencies.manageTrip.newMemory(tripID: trip.id, placeID: place.id)
            memory.title = title
            _ = try await dependencies.manageTrip.save(memory)
        }

        let grants = try await dependencies.progressionRepository.allGrants()
        let stamps = grants.filter { $0.rewardID == "sunnie.reward.stamp.paris" }
        #expect(stamps.count == 1)
    }

    @Test("Saving a memory earns progression once, on the first save")
    @MainActor
    func memoryProgressionIsOnlyForNewMemories() async throws {
        let dependencies = try makeDependencies()
        let (trip, place) = try await makeParisTrip(dependencies)

        var memory = dependencies.manageTrip.newMemory(tripID: trip.id, placeID: place.id)
        memory.title = "First"
        memory = try await dependencies.manageTrip.save(memory)

        let after = try await dependencies.progressionRepository.profile().experience
        #expect(after > 0)

        memory.title = "First, edited"
        _ = try await dependencies.manageTrip.save(memory)

        #expect(try await dependencies.progressionRepository.profile().experience == after)
    }

    @Test("A memory from somewhere with no pack earns nothing rather than a blank stamp")
    @MainActor
    func unknownPlacesEarnNoKeepsakes() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()
        let before = await dependencies.manageCollection.ownedRewardIDs()

        var place = dependencies.manageTrip.newPlace()
        place.name = "Somewhere else"
        place.country = "Iceland"
        place = try await dependencies.manageTrip.save(place)

        var trip = dependencies.manageTrip.newDraft(type: .past)
        trip.title = "North"
        trip.placeIDs = [place.id]
        let saved = try await dependencies.manageTrip.save(trip)

        var memory = dependencies.manageTrip.newMemory(tripID: saved.id, placeID: place.id)
        memory.title = "Very cold"
        _ = try await dependencies.manageTrip.save(memory)

        let after = await dependencies.manageCollection.ownedRewardIDs()
        let stamps = after.subtracting(before).filter { $0.rawValue.contains(".stamp.") }
        #expect(stamps.isEmpty)
    }

    @Test("A past trip counts as a place visited; an upcoming one does not")
    @MainActor
    func onlyPastTripsCountAsVisited() async throws {
        let dependencies = try makeDependencies()

        var place = dependencies.manageTrip.newPlace()
        place.name = "Tokyo"
        place.country = "Japan"
        place = try await dependencies.manageTrip.save(place)

        var upcoming = dependencies.manageTrip.newDraft()
        upcoming.title = "Next spring"
        upcoming.startsAt = Self.referenceDate.addingTimeInterval(60 * 86_400)
        upcoming.endsAt = Self.referenceDate.addingTimeInterval(70 * 86_400)
        upcoming.placeIDs = [place.id]
        _ = try await dependencies.manageTrip.save(upcoming)

        // A booked flight is a plan. Stamping the passport for it would be the
        // app claiming something that has not happened.
        var visited = await dependencies.manageCollection.visitedDestinationIDs()
        #expect(!visited.contains("sunnie.destination.tokyo"))

        var past = dependencies.manageTrip.newDraft(type: .past)
        past.title = "Last autumn"
        past.placeIDs = [place.id]
        _ = try await dependencies.manageTrip.save(past)

        visited = await dependencies.manageCollection.visitedDestinationIDs()
        #expect(visited.contains("sunnie.destination.tokyo"))
    }

    // MARK: - Home

    @Test("A first launch has a default scene without writing one")
    @MainActor
    func sceneDefaultsWithoutWriting() async throws {
        let dependencies = try makeDependencies()

        let state = try await dependencies.manageHome.sceneState()
        #expect(state.equippedOutfitID == nil)
        #expect(state.selectedSoundRewardID == nil)
        #expect(try await dependencies.manageHome.placements().isEmpty)
    }

    @Test("Something owned goes in a slot that accepts it")
    @MainActor
    func placingWorks() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()

        let refusal = await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.woodenStool", in: "sunnie.slot.cozy.shelf"
        )
        #expect(refusal == nil)

        let placements = await dependencies.manageHome.placementsBySlot()
        #expect(placements["sunnie.slot.cozy.shelf"]?.id == "sunnie.reward.decor.woodenStool")
    }

    @Test("A slot holds one thing: placing again replaces rather than stacks")
    @MainActor
    func slotsHoldOneThing() async throws {
        let dependencies = try makeDependencies()
        var profile = try await dependencies.progressionRepository.profile()
        profile.level = 5
        try await dependencies.progressionRepository.save(profile)
        await dependencies.manageCollection.sweep()

        await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.woodenStool", in: "sunnie.slot.cozy.shelf"
        )
        await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.readingLamp", in: "sunnie.slot.cozy.shelf"
        )

        let placements = try await dependencies.manageHome.placements()
        #expect(placements.filter { $0.slotID == "sunnie.slot.cozy.shelf" }.count == 1)
        #expect(placements.first?.rewardID == "sunnie.reward.decor.readingLamp")
    }

    @Test("Something not owned is refused, and says which rule it hit")
    @MainActor
    func placingWhatYouDoNotOwnIsRefused() async throws {
        let dependencies = try makeDependencies()
        // No sweep, so nothing is owned yet.
        let refusal = await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.woodenStool", in: "sunnie.slot.cozy.shelf"
        )
        #expect(refusal == .notOwned("sunnie.reward.decor.woodenStool"))
        #expect(try await dependencies.manageHome.placements().isEmpty)
    }

    @Test("Something owned is refused from a slot that does not take it")
    @MainActor
    func placingInTheWrongSlotIsRefused() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()

        // The stool is cozy-room decor; the plant stand takes little plants.
        let refusal = await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.woodenStool", in: "sunnie.slot.jungle.stand"
        )
        #expect(refusal != nil)
        #expect(try await dependencies.manageHome.placements().isEmpty)
    }

    @Test("Clearing a slot empties it and leaves the rest alone")
    @MainActor
    func clearingASlot() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()

        await dependencies.manageHome.place(
            rewardID: "sunnie.reward.decor.woodenStool", in: "sunnie.slot.cozy.shelf"
        )
        await dependencies.manageHome.clear(slotID: "sunnie.slot.cozy.shelf")

        #expect(try await dependencies.manageHome.placements().isEmpty)
    }

    @Test("An outfit can only be equipped if it is owned and is an outfit")
    @MainActor
    func equippingChecksOwnership() async throws {
        let dependencies = try makeDependencies()

        #expect(await dependencies.manageHome.equip(
            outfitID: "sunnie.reward.outfit.everyday"
        ) == false)

        await dependencies.manageCollection.sweep()
        #expect(await dependencies.manageHome.equip(
            outfitID: "sunnie.reward.outfit.everyday"
        ) == true)

        // Decor is not an outfit, even when it is owned.
        #expect(await dependencies.manageHome.equip(
            outfitID: "sunnie.reward.decor.woodenStool"
        ) == false)

        let state = try await dependencies.manageHome.sceneState()
        #expect(state.equippedOutfitID == "sunnie.reward.outfit.everyday")

        // And taking it off is always allowed.
        #expect(await dependencies.manageHome.equip(outfitID: nil) == true)
        #expect(try await dependencies.manageHome.sceneState().equippedOutfitID == nil)
    }

    @Test("Choosing a sound stores the choice")
    @MainActor
    func selectingASoundStoresIt() async throws {
        let dependencies = try makeDependencies()
        await dependencies.manageCollection.sweep()

        #expect(await dependencies.manageHome.selectSound(
            "sunnie.reward.ambience.roomTone"
        ) == true)

        let state = try await dependencies.manageHome.sceneState()
        #expect(state.selectedSoundRewardID == "sunnie.reward.ambience.roomTone")
    }

    @Test("Displayed memories and favourite plants are bounded")
    @MainActor
    func displayListsAreBounded() async throws {
        let dependencies = try makeDependencies()

        let tooMany = (0..<20).map { _ in UUID() }
        await dependencies.manageHome.setDisplayedMemories(tooMany)
        await dependencies.manageHome.setFavoritePlants(tooMany)

        let state = try await dependencies.manageHome.sceneState()
        #expect(state.displayedMemoryIDs.count == HomeSceneState.maximumDisplayedMemories)
        #expect(state.favoritePlantIDs.count == HomeSceneState.maximumFavoritePlants)
    }

    @Test("A displayed memory that was deleted drops out rather than leaving a gap")
    @MainActor
    func deletedMemoriesDropOut() async throws {
        let dependencies = try makeDependencies()
        let (trip, place) = try await makeParisTrip(dependencies)

        var memory = dependencies.manageTrip.newMemory(tripID: trip.id, placeID: place.id)
        memory.title = "Kept"
        memory = try await dependencies.manageTrip.save(memory)

        await dependencies.manageHome.setDisplayedMemories([memory.id, UUID()])
        #expect(await dependencies.manageHome.displayedMemories().count == 1)

        try await dependencies.manageTrip.deleteMemory(id: memory.id)
        #expect(await dependencies.manageHome.displayedMemories().isEmpty)
    }

    @Test("A story scene is offered once")
    @MainActor
    func storyScenesAreOfferedOnce() async throws {
        let dependencies = try makeDependencies()

        // The first-plant story needs a plant added.
        var draft = dependencies.managePlant.newDraft()
        draft.name = "Monstera"
        _ = try await dependencies.managePlant.save(draft)

        let unread = await dependencies.manageHome.unreadStoryScenes()
        #expect(unread.contains { $0.id == "sunnie.story.firstMorning" })

        await dependencies.manageHome.markSceneRead("sunnie.story.firstMorning")
        let after = await dependencies.manageHome.unreadStoryScenes()
        #expect(!after.contains { $0.id == "sunnie.story.firstMorning" })
    }

    @Test("The scene resolves without anything owned or arranged")
    @MainActor
    func sceneResolvesOnAFreshInstall() async throws {
        let dependencies = try makeDependencies()

        let variant = await dependencies.manageHome.variant(
            themeID: ThemeCatalog.lushTropicalJungleID,
            phase: .day,
            isNorthernHemisphere: true,
            reduceMotion: false
        )
        #expect(variant.outfitID == nil)
        #expect(variant.destinationID == nil)
        #expect(variant.visualState.animationIntensity > 0)
    }

    // MARK: - Storage

    @Test("A placement whose reward is unknown stays stored but leaves the scene")
    @MainActor
    func unknownPlacementsAreKeptButNotDrawn() async throws {
        let dependencies = try makeDependencies()

        // Written straight to the repository, as a pack that is no longer
        // installed would have left it.
        try await dependencies.homeRepository.place(
            rewardID: "sunnie.reward.fromAPackThatIsGone",
            in: "sunnie.slot.cozy.shelf",
            at: Self.referenceDate
        )

        #expect(try await dependencies.homeRepository.placements().count == 1)
        #expect(await dependencies.manageHome.placementsBySlot().isEmpty)
    }

    @Test("The scene survives the store")
    @MainActor
    func sceneSurvivesStorage() async throws {
        let dependencies = try makeDependencies()

        let memoryID = UUID()
        let plantID = UUID()
        try await dependencies.homeRepository.save(HomeSceneState(
            equippedOutfitID: "sunnie.reward.outfit.everyday",
            selectedSoundRewardID: "sunnie.reward.ambience.roomTone",
            displayedMemoryIDs: [memoryID],
            favoritePlantIDs: [plantID],
            updatedAt: Self.referenceDate
        ))

        let restored = try await dependencies.homeRepository.sceneState()
        #expect(restored.equippedOutfitID == "sunnie.reward.outfit.everyday")
        #expect(restored.selectedSoundRewardID == "sunnie.reward.ambience.roomTone")
        #expect(restored.displayedMemoryIDs == [memoryID])
        #expect(restored.favoritePlantIDs == [plantID])
    }

    // MARK: - Routing

    @Test("Collections and Sunnie's home are reachable from More")
    @MainActor
    func moreLeadsToBothScreens() {
        #expect(MoreDestination.collections.route == .collections)
        #expect(MoreDestination.sunnieHome.route == .sunnieHome)
        // A closure rather than a key path: `allSatisfy` is `rethrows`, and
        // #expect decomposes its argument into a separate value, at which point
        // the compiler can no longer see that the predicate cannot throw.
        #expect(MoreDestination.allCases.allSatisfy { $0.isImplemented })
    }
}
