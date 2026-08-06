import Foundation
import Testing
@testable import SunnieShared

/// Unlocking, ownership, placement, rhythm, and the shipped collectibles pack.
///
/// The two properties worth stating plainly, because the whole feature is built
/// to preserve them:
///
/// - **Nothing is ever taken away.** There is no revoke path, and the tests below
///   check that no sequence of inputs produces one.
/// - **Ownership outlives content.** A grant is keyed on a content ID, not on the
///   pack that produced it, so uninstalling a pack cannot cascade a reward away.
@Suite("Collections")
struct CollectionsTests {

    private let now = Date(timeIntervalSince1970: 1_770_033_600)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func reward(
        _ id: ContentID,
        category: RewardCategory = .decor,
        source: UnlockSource = .fromTheStart,
        zones: [HomeZone] = [.cozyRoom]
    ) -> RewardDefinition {
        RewardDefinition(
            id: id,
            category: category,
            displayNameKey: "k.\(id.rawValue).name",
            descriptionKey: "k.\(id.rawValue).description",
            unlockSource: source,
            zones: zones
        )
    }

    private func grant(_ rewardID: ContentID, at date: Date) -> RewardGrant {
        RewardGrant(
            rewardID: rewardID,
            grantedAt: date,
            sourceEventID: nil,
            deterministicKey: "test|\(rewardID.rawValue)"
        )
    }

    // MARK: - Unlock rules

    @Test("A reward is earned only when its own condition is met")
    func unlockConditionsHold() {
        let progress = RewardUnlockPlanner.Progress(
            level: 3,
            eventCounts: [.plantCareCompleted: 10],
            visitedDestinationIDs: ["sunnie.destination.paris"],
            finishedGameIDs: ["sunnie.game.jungleLogic"],
            hasTravelMemory: true
        )

        #expect(RewardUnlockPlanner.isEarned(.fromTheStart, progress: progress))
        #expect(RewardUnlockPlanner.isEarned(.level(3), progress: progress))
        #expect(!RewardUnlockPlanner.isEarned(.level(4), progress: progress))
        #expect(RewardUnlockPlanner.isEarned(.firstTime(.plantCareCompleted), progress: progress))
        #expect(!RewardUnlockPlanner.isEarned(.firstTime(.mealsPlanned), progress: progress))
        #expect(RewardUnlockPlanner.isEarned(
            .milestone(.plantCareCompleted, count: 10), progress: progress
        ))
        #expect(!RewardUnlockPlanner.isEarned(
            .milestone(.plantCareCompleted, count: 11), progress: progress
        ))
        #expect(RewardUnlockPlanner.isEarned(
            .destination("sunnie.destination.paris"), progress: progress
        ))
        #expect(!RewardUnlockPlanner.isEarned(
            .destination("sunnie.destination.tokyo"), progress: progress
        ))
        #expect(RewardUnlockPlanner.isEarned(.travelMemory, progress: progress))
        #expect(RewardUnlockPlanner.isEarned(
            .game("sunnie.game.jungleLogic"), progress: progress
        ))
    }

    @Test("The planner returns only what is earned and not already owned")
    func plannerSkipsWhatIsOwned() {
        let rewards = [
            reward("test.reward.a", source: .fromTheStart),
            reward("test.reward.b", source: .level(2)),
            reward("test.reward.c", source: .level(9))
        ]
        let progress = RewardUnlockPlanner.Progress(level: 3)

        let due = RewardUnlockPlanner.due(
            rewards: rewards, progress: progress, ownedRewardIDs: ["test.reward.a"]
        )
        #expect(due.map(\.id) == ["test.reward.b"])
    }

    @Test("Running the planner again after granting returns nothing")
    func plannerIsIdempotent() {
        let rewards = [
            reward("test.reward.a", source: .fromTheStart),
            reward("test.reward.b", source: .level(2))
        ]
        let progress = RewardUnlockPlanner.Progress(level: 5)

        let first = RewardUnlockPlanner.due(
            rewards: rewards, progress: progress, ownedRewardIDs: []
        )
        #expect(first.count == 2)

        let owned = Set(first.map(\.id))
        let second = RewardUnlockPlanner.due(
            rewards: rewards, progress: progress, ownedRewardIDs: owned
        )
        #expect(second.isEmpty)
    }

    @Test("A grant key depends on the reward and its source, not on when or where")
    func grantKeysAreDeterministic() {
        let definition = reward("test.reward.a", source: .level(4))

        let early = RewardUnlockPlanner.grant(for: definition, at: now)
        let late = RewardUnlockPlanner.grant(
            for: definition, at: now.addingTimeInterval(90_000), sourceEventID: UUID()
        )
        // Two devices noticing the same level being reached, hours apart, must
        // produce the same key so the second grant collapses into the first.
        #expect(early.deterministicKey == late.deterministicKey)
    }

    @Test("The same reward earned two ways keeps two distinct keys")
    func differentSourcesAreDifferentGrants() {
        let byLevel = RewardUnlockPlanner.grant(
            for: reward("test.reward.a", source: .level(4)), at: now
        )
        let byGame = RewardUnlockPlanner.grant(
            for: reward("test.reward.a", source: .game("sunnie.game.jungleLogic")), at: now
        )
        #expect(byLevel.deterministicKey != byGame.deterministicKey)
        // The collection dedups by reward, so this is a storage detail rather
        // than two copies of the thing.
        #expect(byLevel.rewardID == byGame.rewardID)
    }

    @Test("Level progress never removes anything already earned")
    func nothingIsEverRevoked() {
        let rewards = [reward("test.reward.a", source: .level(5))]
        let owned: Set<ContentID> = ["test.reward.a"]

        // Even at a level *below* the requirement — which a corrupted profile
        // could produce — the planner has no way to express a revocation.
        let due = RewardUnlockPlanner.due(
            rewards: rewards,
            progress: RewardUnlockPlanner.Progress(level: 1),
            ownedRewardIDs: owned
        )
        #expect(due.isEmpty)

        let items = CollectionBuilder.items(
            definitions: rewards, grants: [grant("test.reward.a", at: now)]
        )
        #expect(items[0].isOwned)
    }

    // MARK: - Building the collection

    @Test("Owned items come first, then locked ones by how close they are")
    func collectionOrdering() {
        let definitions = [
            reward("test.reward.far", source: .level(9)),
            reward("test.reward.near", source: .level(2)),
            reward("test.reward.owned", source: .fromTheStart)
        ]
        let items = CollectionBuilder.items(
            definitions: definitions, grants: [grant("test.reward.owned", at: now)]
        )
        #expect(items.map(\.id) == ["test.reward.owned", "test.reward.near", "test.reward.far"])
    }

    @Test("A reward granted twice reports the earlier date")
    func earliestGrantWins() {
        let earlier = now.addingTimeInterval(-100_000)
        let items = CollectionBuilder.items(
            definitions: [reward("test.reward.a")],
            grants: [grant("test.reward.a", at: now), grant("test.reward.a", at: earlier)]
        )
        #expect(items.count == 1)
        #expect(items[0].grantedAt == earlier)
    }

    /// §12: content-pack removal does not delete ownership records.
    @Test("A reward stays owned when nothing describes it any more")
    func ownershipOutlivesTheContentPack() {
        let items = CollectionBuilder.items(
            definitions: [],
            grants: [grant("sunnie.reward.fromAPackThatIsGone", at: now)]
        )
        #expect(items.count == 1)
        #expect(items[0].isOwned)
        #expect(items[0].isOrphaned)
        #expect(items[0].grantedAt == now)
    }

    @Test("Filters narrow the collection without hiding what is locked by default")
    func filtersBehave() {
        let definitions = [
            reward("test.reward.owned", category: .decor, source: .fromTheStart),
            reward("test.reward.locked", category: .outfit, source: .level(9), zones: [])
        ]
        let items = CollectionBuilder.items(
            definitions: definitions, grants: [grant("test.reward.owned", at: now)]
        )

        // The default shows everything, which is the point of a collection.
        #expect(items.filter(CollectionFilter.everything.matches).count == 2)
        #expect(items.filter(CollectionFilter(ownership: .owned).matches).count == 1)
        #expect(items.filter(CollectionFilter(ownership: .locked).matches).count == 1)
        #expect(items.filter(CollectionFilter(category: .outfit).matches).count == 1)
    }

    @Test("Counts are per category, owned out of total")
    func countsAreCorrect() {
        let definitions = [
            reward("test.reward.a", category: .decor, source: .fromTheStart),
            reward("test.reward.b", category: .decor, source: .level(9)),
            reward("test.reward.c", category: .outfit, source: .level(2), zones: [])
        ]
        let counts = CollectionBuilder.counts(
            CollectionBuilder.items(
                definitions: definitions, grants: [grant("test.reward.a", at: now)]
            )
        )
        #expect(counts[.decor]?.owned == 1)
        #expect(counts[.decor]?.total == 2)
        #expect(counts[.outfit]?.owned == 0)
    }

    @Test("The next unlock is the nearest level above the current one")
    func nextUnlockLooksForward() throws {
        let definitions = [
            reward("test.reward.a", source: .level(2)),
            reward("test.reward.b", source: .level(6)),
            reward("test.reward.c", source: .level(4)),
            // A non-level source is never offered as "what's next": there is no
            // number to watch yourself approach, and showing it as one would
            // invent a deadline nobody set.
            reward("test.reward.d", source: .travelMemory)
        ]
        let next = try #require(
            RewardUnlockPlanner.nextLevelUnlock(rewards: definitions, level: 3)
        )
        #expect(next.reward.id == "test.reward.c")
        #expect(next.level == 4)

        #expect(RewardUnlockPlanner.nextLevelUnlock(rewards: definitions, level: 99) == nil)
    }

    // MARK: - Placement

    private var slot: DecorSlot {
        DecorSlot(
            id: "test.slot.shelf",
            zone: .cozyRoom,
            displayNameKey: "k.slot",
            accepts: [.decor],
            order: 0
        )
    }

    @Test("Placing needs ownership, the right category, and the right zone")
    func placementRulesRefuseSpecifically() {
        let fits = reward("test.reward.a", category: .decor, zones: [.cozyRoom])

        #expect(PlacementRules.check(reward: fits, slot: slot, isOwned: true) == nil)
        #expect(PlacementRules.check(reward: fits, slot: slot, isOwned: false)
            == .notOwned("test.reward.a"))
        #expect(PlacementRules.check(reward: fits, slot: nil, isOwned: true)
            == .slotUnknown("test.reward.a"))

        let wrongCategory = reward("test.reward.b", category: .outfit, zones: [.cozyRoom])
        #expect(PlacementRules.check(reward: wrongCategory, slot: slot, isOwned: true)
            == .wrongCategory(slot: "test.slot.shelf", category: .outfit))

        let wrongZone = reward("test.reward.c", category: .decor, zones: [.musicCorner])
        #expect(PlacementRules.check(reward: wrongZone, slot: slot, isOwned: true)
            == .zoneDoesNotSuit(slot: "test.slot.shelf", zone: .cozyRoom))
    }

    @Test("Candidates for a slot are only what fits it")
    func candidatesAreFiltered() {
        let owned = [
            reward("test.reward.a", category: .decor, zones: [.cozyRoom]),
            reward("test.reward.b", category: .outfit, zones: []),
            reward("test.reward.c", category: .decor, zones: [.musicCorner])
        ]
        let candidates = PlacementRules.candidates(for: slot, owned: owned)
        #expect(candidates.map(\.id) == ["test.reward.a"])
    }

    // MARK: - Scene resolution

    private func context(
        phase: TimePhase = .day,
        destination: ContentID? = nil,
        recentUnlock: ContentID? = nil
    ) -> HomeSceneContext {
        HomeSceneContext(
            themeID: ThemeCatalog.lushTropicalJungleID,
            phase: phase,
            destinationID: destination,
            recentUnlockID: recentUnlock,
            season: .summer
        )
    }

    @Test("A destination outfit is worn during a trip and only if it is owned")
    func destinationOutfitWinsDuringATrip() {
        let parisOutfit = RewardDefinition(
            id: "test.reward.beret",
            category: .outfit,
            displayNameKey: "k.a",
            descriptionKey: "k.b",
            unlockSource: .destination("sunnie.destination.paris"),
            destinationID: "sunnie.destination.paris"
        )
        let definitions: [ContentID: RewardDefinition] = [parisOutfit.id: parisOutfit]
        let state = HomeSceneState(equippedOutfitID: "test.reward.everyday", updatedAt: now)

        let worn = HomeSceneResolver.variant(
            context: context(destination: "sunnie.destination.paris"),
            state: state,
            ownedRewardIDs: ["test.reward.everyday", "test.reward.beret"],
            definitions: definitions,
            reduceMotion: false
        )
        #expect(worn.outfitID == "test.reward.beret")

        // Not owned: the user's own choice stands rather than being replaced by
        // something they do not have.
        let notOwned = HomeSceneResolver.variant(
            context: context(destination: "sunnie.destination.paris"),
            state: state,
            ownedRewardIDs: ["test.reward.everyday"],
            definitions: definitions,
            reduceMotion: false
        )
        #expect(notOwned.outfitID == "test.reward.everyday")

        // No trip: the user's choice stands.
        let home = HomeSceneResolver.variant(
            context: context(),
            state: state,
            ownedRewardIDs: ["test.reward.everyday", "test.reward.beret"],
            definitions: definitions,
            reduceMotion: false
        )
        #expect(home.outfitID == "test.reward.everyday")
    }

    @Test("An outfit that is no longer owned is not shown")
    func unownedEquippedOutfitFallsBack() {
        let variant = HomeSceneResolver.variant(
            context: context(),
            state: HomeSceneState(equippedOutfitID: "test.reward.gone", updatedAt: now),
            ownedRewardIDs: [],
            definitions: [:],
            reduceMotion: false
        )
        #expect(variant.outfitID == nil)
    }

    @Test("Reduced motion makes the scene a still picture, not a slower one")
    func reduceMotionPinsAnimationToZero() {
        let still = HomeSceneResolver.variant(
            context: context(),
            state: HomeSceneState(updatedAt: now),
            ownedRewardIDs: [],
            definitions: [:],
            reduceMotion: true
        )
        #expect(still.visualState.animationIntensity == 0)

        let moving = HomeSceneResolver.variant(
            context: context(),
            state: HomeSceneState(updatedAt: now),
            ownedRewardIDs: [],
            definitions: [:],
            reduceMotion: false
        )
        #expect(moving.visualState.animationIntensity > 0)
    }

    @Test("Sunnie is never disappointed at home, whatever the context")
    func sunnieIsNeverDisappointed() {
        // The resolver takes nothing that could express "the user has not done
        // enough", which is the structural guarantee. This walks every input it
        // does take and checks the expressions that come out.
        let kind: Set<SunnieExpression> = [
            .happyOpenEyed, .happyClosedEyed, .sleepyHalfLidded,
            .excitedDiscovery, .traveling
        ]
        for phase in TimePhase.allCases {
            let destinations: [ContentID?] = [nil, ContentID(rawValue: "sunnie.destination.paris")]
            let unlocks: [ContentID?] = [nil, ContentID(rawValue: "test.reward.a")]
            for destination in destinations {
                for unlock in unlocks {
                    let variant = HomeSceneResolver.variant(
                        context: context(
                            phase: phase, destination: destination, recentUnlock: unlock
                        ),
                        state: HomeSceneState(updatedAt: now),
                        ownedRewardIDs: unlock.map { Set([$0]) } ?? [],
                        definitions: [:],
                        reduceMotion: false
                    )
                    #expect(kind.contains(variant.visualState.expression))
                }
            }
        }
    }

    @Test("A recent unlock is highlighted only if it is actually owned")
    func highlightRequiresOwnership() {
        let owned = HomeSceneResolver.variant(
            context: context(recentUnlock: "test.reward.a"),
            state: HomeSceneState(updatedAt: now),
            ownedRewardIDs: ["test.reward.a"],
            definitions: [:],
            reduceMotion: false
        )
        #expect(owned.highlightedRewardID == "test.reward.a")

        let notOwned = HomeSceneResolver.variant(
            context: context(recentUnlock: "test.reward.a"),
            state: HomeSceneState(updatedAt: now),
            ownedRewardIDs: [],
            definitions: [:],
            reduceMotion: false
        )
        #expect(notOwned.highlightedRewardID == nil)
    }

    // MARK: - Seasons

    @Test("Seasons flip in the southern hemisphere")
    func seasonsFollowTheHemisphere() throws {
        let december = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 12, day: 15))
        )
        #expect(Season.current(
            for: december, calendar: calendar, isNorthernHemisphere: true
        ) == .winter)
        #expect(Season.current(
            for: december, calendar: calendar, isNorthernHemisphere: false
        ) == .summer)
    }

    // MARK: - Rhythm

    @Test("Rhythm counts days with something in them, not days in a row")
    func rhythmCountsDaysNotRuns() throws {
        // Monday, Wednesday, Saturday — three caring days with two gaps. A
        // streak counter would report one; this reports three, because a gap is
        // not a failure to be recorded (§5).
        let monday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 9))
        )
        let dates = [
            monday,
            monday.addingTimeInterval(2 * 86_400),
            monday.addingTimeInterval(2 * 86_400 + 3600),
            monday.addingTimeInterval(5 * 86_400)
        ]

        let summary = RhythmCalculator.summary(
            eventDates: dates,
            now: monday.addingTimeInterval(5 * 86_400),
            calendar: calendar,
            isVisible: true
        )
        // Two events on the same day count once.
        #expect(summary.daysThisWeek == 3)
    }

    @Test("A quiet week takes nothing away from the best week")
    func aQuietWeekDoesNotErodeTheBest() throws {
        let busyMonday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))
        )
        let busyWeek = (0..<5).map { busyMonday.addingTimeInterval(Double($0) * 86_400) }

        // Four weeks later, nothing at all.
        let quietNow = busyMonday.addingTimeInterval(28 * 86_400)
        let summary = RhythmCalculator.summary(
            eventDates: busyWeek, now: quietNow, calendar: calendar, isVisible: true
        )

        #expect(summary.daysThisWeek == 0)
        #expect(summary.bestWeek == 5)
        // And nothing in the summary says the quiet week was a loss.
        #expect(!summary.matchesBest)
    }

    @Test("Rhythm can be hidden entirely")
    func rhythmRespectsTheHidePreference() {
        let summary = RhythmCalculator.summary(
            eventDates: [now], now: now, calendar: calendar, isVisible: false
        )
        #expect(!summary.isVisible)
    }

    // MARK: - Keepsakes

    @Test("A memory's stamp and postcard are keyed on the place, not the memory")
    func keepsakeKeysAreDestinationScoped() throws {
        let destination = try #require(
            BuiltInCollectionContent.pack.destination(id: "sunnie.destination.paris")
        )

        let first = TravelKeepsakes.grants(for: destination, at: now)
        let second = TravelKeepsakes.grants(
            for: destination, at: now.addingTimeInterval(1_000_000)
        )

        #expect(first.count == 2)
        #expect(first.map(\.deterministicKey) == second.map(\.deterministicKey))
        // Six memories from Paris are six memories, one stamp, one template.
        #expect(Set(first.map(\.rewardID)).count == 2)
    }

    @Test("Nowhere with a pack earns nothing rather than a blank stamp")
    func unknownPlacesEarnNothing() {
        #expect(TravelKeepsakes.keepsakes(for: nil).isEmpty)
    }

    @Test("A country is matched however it was typed")
    func countryMatchingFoldsAccentsAndCase() {
        let pack = BuiltInCollectionContent.pack
        #expect(pack.destination(countryName: "France")?.id == "sunnie.destination.paris")
        #expect(pack.destination(countryName: "franca")?.id == "sunnie.destination.paris")
        #expect(pack.destination(countryName: "  BRASIL ")?.id == "sunnie.destination.brazil")
        // A partial match is refused: a wrong stamp is worse than no stamp.
        #expect(pack.destination(countryName: "Fran") == nil)
        #expect(pack.destination(countryName: "") == nil)
    }
}

/// The shipped collectibles pack, checked the way the app reads it.
@Suite("Collection content")
struct CollectionContentTests {

    @Test("The built-in pack has no content problems")
    func packIsValid() {
        let issues = CollectionPackValidator.validate(BuiltInCollectionContent.pack)
        #expect(issues.isEmpty, "\(issues.map(\.description))")
    }

    @Test("Every placeable reward has somewhere it can actually go")
    func everythingPlaceableHasASlot() {
        let pack = BuiltInCollectionContent.pack
        let placeable = pack.rewards.filter {
            $0.category.action == .place
        }
        #expect(!placeable.isEmpty)

        for reward in placeable {
            #expect(
                pack.slots.contains { $0.accepts(reward) },
                "\(reward.id.rawValue) can be placed but nothing accepts it"
            )
        }
    }

    @Test("Every reward explains where it came from")
    func everyRewardHasASource() {
        // Structurally guaranteed — `UnlockSource` has no "unspecified" case —
        // so this checks the other half: that the description is reachable.
        for reward in BuiltInCollectionContent.pack.rewards {
            #expect(!reward.unlockSource.localizationKey.isEmpty)
            #expect(!reward.displayNameKey.isEmpty)
            #expect(!reward.descriptionKey.isEmpty)
        }
    }

    @Test("Rewards the earlier phases already grant are still described here")
    func inheritedRewardsAreNotOrphaned() {
        // Phases 1 and 7 grant these by identifier. If this pack renamed them,
        // every store that already has the grant would show an orphan (§12).
        let inherited: Set<ContentID> = [
            "sunnie.reward.collectible.firstSprout",
            "sunnie.reward.collectible.wateringCan",
            "sunnie.reward.collectible.luggageTag",
            "sunnie.reward.collectible.inkStamp",
            "sunnie.reward.collectible.brassLabel"
        ]
        let described = Set(BuiltInCollectionContent.pack.rewards.map(\.id))
        #expect(inherited.isSubset(of: described))
    }

    @Test("Every reward the progression engine grants first-time is in the pack")
    func firstTimeRewardsAreDescribed() {
        let described = Set(BuiltInCollectionContent.pack.rewards.map(\.id))
        for (_, rewardID) in ProgressionEngine.RewardRules.standard.firstTimeRewards {
            #expect(
                described.contains(rewardID),
                "\(rewardID.rawValue) is granted but nothing describes it"
            )
        }
    }

    @Test("Every destination's stamp and postcard exist as rewards")
    func destinationKeepsakesResolve() {
        let pack = BuiltInCollectionContent.pack
        #expect(!pack.destinations.isEmpty)

        for destination in pack.destinations {
            let stampID = destination.stampID
            let postcardID = destination.postcardID
            #expect(stampID != nil)
            #expect(postcardID != nil)
            #expect(stampID.flatMap { pack.reward(id: $0) }?.category == .passportStamp)
            #expect(postcardID.flatMap { pack.reward(id: $0) }?.category == .postcard)
        }
    }

    @Test("The five initial destinations from the specification ship")
    func destinationsAreComplete() {
        let expected: Set<ContentID> = [
            "sunnie.destination.paris",
            "sunnie.destination.tokyo",
            "sunnie.destination.vietnam",
            "sunnie.destination.spain",
            "sunnie.destination.brazil"
        ]
        #expect(Set(BuiltInCollectionContent.pack.destinations.map(\.id)) == expected)
    }

    @Test("The pack survives a JSON round trip")
    func packRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let restored = try decoder.decode(
            CollectionPack.self, from: try encoder.encode(BuiltInCollectionContent.pack)
        )
        #expect(restored == BuiltInCollectionContent.pack)
    }

    @Test("The registry serves the built-in pack")
    func registryCarriesCollectibles() {
        let registry = ContentRegistry(
            messagePack: FallbackContent.messagePack,
            themePack: FallbackContent.themePack
        )
        #expect(!registry.collectionPack.rewards.isEmpty)
        #expect(registry.collectionIssues.isEmpty)
        #expect(registry.reward(id: "sunnie.reward.outfit.everyday") != nil)
    }

    @Test("A pack with a reward nothing can hold is rejected")
    func validatorCatchesAnUnplaceableReward() {
        let pack = CollectionPack(
            manifest: BuiltInCollectionContent.manifest,
            rewards: [
                RewardDefinition(
                    id: "test.reward.homeless",
                    category: .decor,
                    displayNameKey: "k.a",
                    descriptionKey: "k.b",
                    unlockSource: .fromTheStart,
                    zones: [.musicCorner]
                )
            ],
            slots: [
                DecorSlot(
                    id: "test.slot.shelf",
                    zone: .cozyRoom,
                    displayNameKey: "k.slot",
                    accepts: [.decor],
                    order: 0
                )
            ]
        )

        let issues = CollectionPackValidator.validate(pack)
        #expect(issues.contains { issue in
            if case .unplaceableReward = issue { return true }
            return false
        })
        // And the slot that accepts nothing is reported too.
        #expect(issues.contains { issue in
            if case .emptySlot = issue { return true }
            return false
        })
    }

    @Test("A pack whose music has no sound is rejected")
    func validatorCatchesAnIncompleteReward() {
        let pack = CollectionPack(
            manifest: BuiltInCollectionContent.manifest,
            rewards: [
                RewardDefinition(
                    id: "test.reward.silent",
                    category: .ambience,
                    displayNameKey: "k.a",
                    descriptionKey: "k.b",
                    unlockSource: .fromTheStart
                )
            ],
            slots: []
        )
        #expect(CollectionPackValidator.validate(pack).contains { issue in
            if case .incompleteReward = issue { return true }
            return false
        })
    }

    @Test("Every authored story panel exists")
    func storyScenesHavePanels() {
        for scene in BuiltInCollectionContent.pack.storyScenes {
            #expect(!scene.panelKeys.isEmpty)
            #expect(!scene.titleKey.isEmpty)
        }
    }
}
