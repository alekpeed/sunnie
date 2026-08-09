import Foundation
import SunnieShared

/// Ownership, unlocking, and the collection view
/// (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md).
///
/// The sweep is the heart of it: given the level, the event counts, and what is
/// already owned, work out what is newly earned and grant it. Because both the
/// planner and the grant keys are pure functions of *what is true*, running the
/// sweep twice grants nothing the second time and running it after a restore
/// grants whatever the restore is missing.
///
/// Nothing here can take anything away. There is no revoke, no expiry, and no
/// input that could ask for one (§4).
struct ManageCollection: TravelKeepsakeAwarding {

    private let progressionRepository: any ProgressionRepository
    private let travelRepository: any TravelRepository
    private let gameRepository: any GameRepository
    private let preferencesRepository: any PreferencesRepository
    private let pack: CollectionPack
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        progressionRepository: any ProgressionRepository,
        travelRepository: any TravelRepository,
        gameRepository: any GameRepository,
        preferencesRepository: any PreferencesRepository,
        pack: CollectionPack,
        clock: any SunnieClock
    ) {
        self.progressionRepository = progressionRepository
        self.travelRepository = travelRepository
        self.gameRepository = gameRepository
        self.preferencesRepository = preferencesRepository
        self.pack = pack
        self.clock = clock
    }

    // MARK: - Catalogue

    var rewards: [RewardDefinition] { pack.rewards }
    var slots: [DecorSlot] { pack.slots }
    var storyScenes: [StoryScene] { pack.storyScenes }
    var destinations: [DestinationDefinition] { pack.destinations }

    func reward(id: ContentID) -> RewardDefinition? { pack.reward(id: id) }
    func slot(id: ContentID) -> DecorSlot? { pack.slot(id: id) }
    func destination(id: ContentID) -> DestinationDefinition? { pack.destination(id: id) }

    /// The name to show for a reward, falling back to the raw identifier only
    /// when no pack describes it.
    func displayNameKey(for rewardID: ContentID) -> String {
        pack.reward(id: rewardID)?.displayNameKey ?? "collection.orphan.name"
    }

    // MARK: - Ownership

    func ownedRewardIDs() async -> Set<ContentID> {
        let grants = (try? await progressionRepository.allGrants()) ?? []
        return Set(grants.map(\.rewardID))
    }

    /// The additive progression profile for shared surfaces such as Today.
    ///
    /// Exposed through this use case rather than letting those surfaces reach
    /// directly into progression storage. `experience` and `level` can only move
    /// forward through normal progression; nothing here provides a subtraction,
    /// revoke, decay, or missed-day path.
    func progressionProfile() async -> ProgressionProfile {
        (try? await progressionRepository.profile()) ?? ProgressionProfile()
    }

    /// The whole collection, owned and locked (S-21).
    func items(filter: CollectionFilter = .everything) async throws -> [CollectionItem] {
        let grants = try await progressionRepository.allGrants()
        return CollectionBuilder
            .items(definitions: pack.rewards, grants: grants)
            .filter(filter.matches)
    }

    /// The most recently granted reward, for the "just unlocked" highlight.
    func newestGrant() async throws -> RewardGrant? {
        try await progressionRepository.grants(limit: 1).first
    }

    func counts() async throws -> [RewardCategory: (owned: Int, total: Int)] {
        let grants = try await progressionRepository.allGrants()
        return CollectionBuilder.counts(
            CollectionBuilder.items(definitions: pack.rewards, grants: grants)
        )
    }

    // MARK: - Where the user has been

    /// How far back the finished-game scan reaches.
    ///
    /// Only distinct game IDs are wanted, and there are seven games. Two hundred
    /// results is far more than enough to have seen each of them, and bounding it
    /// keeps a long history from being loaded on every launch.
    static let gameResultScanLimit = 200

    /// Destinations the user has actually been to.
    ///
    /// Two routes, because trips are recorded two ways. A trip may name its
    /// destination pack outright, and a trip may instead just have places with a
    /// country typed into them. Only *past* trips count — a booked flight to
    /// Tokyo is a plan, and stamping the passport for it would be the app
    /// claiming something that has not happened.
    func visitedDestinationIDs() async -> Set<ContentID> {
        let trips = (try? await travelRepository.trips(includingArchived: true)) ?? []
        let past = trips.filter {
            let status = TripStatusCalculator.status(
                for: $0, now: clock.now, calendar: clock.calendar
            )
            return status == .completed || status == .archived
        }
        guard !past.isEmpty else { return [] }

        var visited = Set(past.flatMap(\.destinationPackIDs))

        let places = (try? await travelRepository.places()) ?? []
        let countriesByPlace = Dictionary(
            places.compactMap { place in place.country.map { (place.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for trip in past {
            for placeID in trip.placeIDs {
                guard
                    let country = countriesByPlace[placeID],
                    let destination = pack.destination(countryName: country)
                else { continue }
                visited.insert(destination.id)
            }
        }
        return visited
    }

    // MARK: - The sweep

    /// Everything the player has done, gathered for the unlock rules.
    ///
    /// Assembled from three repositories rather than a cached summary, because a
    /// cache that drifts here means a reward that never arrives — and the user
    /// has no way to tell that from a reward that does not exist.
    func currentProgress() async throws -> RewardUnlockPlanner.Progress {
        let profile = try await progressionRepository.profile()
        let counts = try await progressionRepository.eventCounts()

        let visited = await visitedDestinationIDs()

        let results = (try? await gameRepository.results(limit: Self.gameResultScanLimit)) ?? []
        let finishedGames = Set(
            results.filter { $0.completion.isFinished }.map(\.gameID)
        )

        let memories = (try? await travelRepository.allMemories(limit: 1)) ?? []

        return RewardUnlockPlanner.Progress(
            level: profile.level,
            eventCounts: counts,
            visitedDestinationIDs: visited,
            finishedGameIDs: finishedGames,
            hasTravelMemory: !memories.isEmpty
        )
    }

    /// Grants everything that is earned and not yet owned.
    ///
    /// Returns only what was actually created, so the caller can announce three
    /// new things on the launch that earns them and nothing on every launch
    /// after.
    @discardableResult
    func sweep() async -> [RewardDefinition] {
        guard let progress = try? await currentProgress() else { return [] }
        let owned = await ownedRewardIDs()

        let due = RewardUnlockPlanner.due(
            rewards: pack.rewards, progress: progress, ownedRewardIDs: owned
        )
        guard !due.isEmpty else { return [] }

        var granted: [RewardDefinition] = []
        let now = clock.now
        for reward in due {
            let grant = RewardUnlockPlanner.grant(for: reward, at: now)
            // A grant that already existed under this key is the ordinary
            // outcome on a second device, not a failure.
            if let outcome = try? await progressionRepository.save(grant), outcome.wasCreated {
                granted.append(reward)
            }
        }
        return granted
    }

    /// The destination a memory is about, if the app can tell.
    ///
    /// The place's country is tried first because it is the more specific of the
    /// two — a trip may cover several countries, but a memory is about one
    /// place. The trip's declared destination pack is the fallback.
    func destination(for memory: TravelMemory) async -> DestinationDefinition? {
        if let placeID = memory.placeID,
           let place = try? await travelRepository.place(id: placeID),
           let country = place.country,
           let destination = pack.destination(countryName: country) {
            return destination
        }
        if let tripID = memory.tripID,
           let trip = try? await travelRepository.trip(id: tripID),
           let packID = trip.destinationPackIDs.first {
            return pack.destination(id: packID)
        }
        return nil
    }

    /// Grants the stamp and postcard for the place a memory is about
    /// (TRAVEL_AND_FLIGHT_ATTENDANT.md §11).
    ///
    /// Idempotent per destination, so editing and re-saving the same memory adds
    /// nothing, and a second memory from the same place reuses the stamp it
    /// already earned rather than issuing an identical duplicate.
    ///
    /// A memory from somewhere with no destination pack earns nothing. A
    /// passport full of identical blank stamps would be worse than one with gaps.
    /// The protocol conformance Travel calls. Discards the detail: the memory
    /// screen has nothing useful to do with the list, and the collection screen
    /// will show what arrived next time it is opened.
    func awardKeepsakes(for memory: TravelMemory) async {
        guard let destination = await destination(for: memory) else { return }
        await awardKeepsakes(destinationID: destination.id, sourceEventID: nil)
    }

    /// Awards all travel keepsakes tied to a destination. The deterministic key
    /// is per reward + destination, so a second memory from the same destination
    /// is safely a no-op.
    private func awardKeepsakes(
        destinationID: ContentID,
        sourceEventID: UUID?
    ) async {
        let due = pack.rewards.filter { reward in
            switch reward.unlock {
            case .visitedDestination(let id): return id == destinationID
            case .firstTravelMemory(let id): return id == destinationID
            default: return false
            }
        }

        guard !due.isEmpty else { return }
        let owned = await ownedRewardIDs()
        let now = clock.now
        for reward in due where !owned.contains(reward.id) {
            let grant = RewardUnlockPlanner.grant(
                for: reward,
                at: now,
                sourceEventID: sourceEventID
            )
            _ = try? await progressionRepository.save(grant)
        }
    }

    // MARK: - Rhythm

    func rhythmSummary() async -> RhythmSummary? {
        guard (try? await preferencesRepository.preferences().showsActivityRhythm) == true else {
            return nil
        }
        let dates = (try? await progressionRepository.eventDates(
            since: clock.calendar.date(byAdding: .day, value: -56, to: clock.now) ?? clock.now
        )) ?? []
        return RhythmCalculator.summary(
            dates: dates,
            now: clock.now,
            calendar: clock.calendar
        )
    }
}
