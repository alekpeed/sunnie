import Foundation

/// Storage boundary for plants and their schedules.
///
/// Views never touch these; feature models reach them through use cases
/// (TECHNICAL_ARCHITECTURE.md §3).
public protocol PlantRepository: Sendable {
    func allPlants(includingArchived: Bool) async throws -> [Plant]
    func plant(id: UUID) async throws -> Plant?
    /// Resolves a scanned QR label. Nil when the token belongs to no plant —
    /// scanning a stranger's label, or one from a plant since deleted.
    func plant(qrToken: String) async throws -> Plant?
    func save(_ plant: Plant) async throws
    func archive(plantID: UUID, at date: Date) async throws
    /// Removes the plant and everything that belongs only to it: schedules, care
    /// events, observations, growth entries, coverage rows, and media.
    ///
    /// Archiving is the reversible option and the one the UI leads with. This
    /// exists because a plant added by mistake should not have to be archived
    /// forever (PLANT_CARE.md §15, "plant deleted with history").
    func delete(plantID: UUID) async throws

    /// The collection screen's data, assembled in one pass.
    ///
    /// A screen that fetched schedules and history per plant would issue a
    /// hundred queries at fifty plants. Filtering and sorting happen in
    /// `PlantCollectionFilter` on the result.
    func collectionItems(includingArchived: Bool) async throws -> [PlantCollectionItem]

    func schedules(forPlantID plantID: UUID) async throws -> [PlantCareSchedule]
    func enabledSchedules() async throws -> [PlantCareSchedule]
    func schedule(id: UUID) async throws -> PlantCareSchedule?
    func save(_ schedule: PlantCareSchedule) async throws
    func deleteSchedule(id: UUID) async throws

    func locations() async throws -> [PlantLocation]
    func save(_ location: PlantLocation) async throws
    func deleteLocation(id: UUID) async throws
}

/// Health observations and the growth timeline (PLANT_CARE.md §8, §9).
///
/// Separate from `PlantRepository` because these are records *about* a plant
/// rather than the plant itself, and because a screen that only shows growth
/// photos should not gain the ability to archive plants.
public protocol PlantHealthRepository: Sendable {
    func observations(forPlantID plantID: UUID) async throws -> [PlantHealthObservation]
    /// Unresolved observations across every plant, for "needs attention".
    func openObservations() async throws -> [PlantHealthObservation]
    func observation(id: UUID) async throws -> PlantHealthObservation?
    func save(_ observation: PlantHealthObservation) async throws
    func deleteObservation(id: UUID) async throws

    /// Newest first.
    func growthEntries(forPlantID plantID: UUID) async throws -> [GrowthEntry]
    func growthEntry(id: UUID) async throws -> GrowthEntry?
    func save(_ entry: GrowthEntry) async throws
    func deleteGrowthEntry(id: UUID) async throws

    func caretakers(includingInactive: Bool) async throws -> [Caretaker]
    func caretaker(id: UUID) async throws -> Caretaker?
    func save(_ caretaker: Caretaker) async throws

    func coverage(forTripID tripID: UUID) async throws -> [PlantTravelCoverage]
    func coverage(forPlantID plantID: UUID) async throws -> [PlantTravelCoverage]
    func save(_ coverage: PlantTravelCoverage) async throws
}

/// Append-only care history.
public protocol PlantCareEventRepository: Sendable {
    /// Stores the event unless one with the same `actionKey` already exists.
    ///
    /// Implementations must make this atomic. A duplicate returns
    /// `.alreadyExisted` with the original record — replaying a queued Watch
    /// action must never create a second event.
    func save(_ event: PlantCareEvent) async throws -> SaveOutcome<PlantCareEvent>

    func event(actionKey: ActionKey) async throws -> PlantCareEvent?
    func events(forPlantID plantID: UUID, limit: Int) async throws -> [PlantCareEvent]
    /// Page through a long history. At 500+ records per plant, loading the lot to
    /// show the first twenty is the difference between a screen that opens and one
    /// that stalls (PLANT_CARE.md §15).
    func events(
        forPlantID plantID: UUID,
        limit: Int,
        offset: Int
    ) async throws -> [PlantCareEvent]
    func eventCount(forPlantID plantID: UUID) async throws -> Int
    func mostRecentEvent(
        forPlantID plantID: UUID,
        careType: CareType
    ) async throws -> PlantCareEvent?
    /// Every event in a window, for export.
    func allEvents(limit: Int) async throws -> [PlantCareEvent]

    /// Records a correction: `replacement` supersedes `eventID`.
    ///
    /// The log is append-only, so a correction adds a record and marks the old
    /// one superseded rather than editing it in place — which is what makes the
    /// history trustworthy after the fact (PLANT_CARE.md §7).
    ///
    /// The link lives in its own record rather than as a field on the event, so
    /// the care-event row keeps the exact shape it had in schema V1 (ADR-017).
    func replace(
        eventID: UUID,
        with replacement: PlantCareEvent
    ) async throws -> SaveOutcome<PlantCareEvent>

    /// Event IDs that have been corrected. History screens show these as
    /// superseded rather than hiding them — a correction is part of the record.
    func supersededEventIDs(forPlantID plantID: UUID) async throws -> Set<UUID>
}

/// Trips, places, packing, checklists, and memories
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md).
///
/// One boundary for the whole feature. Splitting it further would mean a screen
/// that shows a trip's packing progress needing two repositories to answer one
/// question.
public protocol TravelRepository: Sendable {
    func trips(includingArchived: Bool) async throws -> [Trip]
    func trip(id: UUID) async throws -> Trip?
    func save(_ trip: Trip) async throws
    /// Removes the trip and everything belonging only to it. Plant coverage rows
    /// go too — they are about this trip and mean nothing without it.
    func delete(tripID: UUID) async throws

    func segments(forTripID tripID: UUID) async throws -> [TripSegment]
    func save(_ segment: TripSegment) async throws
    func deleteSegment(id: UUID) async throws

    func places() async throws -> [Place]
    func place(id: UUID) async throws -> Place?
    func save(_ place: Place) async throws
    func deletePlace(id: UUID) async throws
    /// Places with the facts the map and list need to filter them, in one pass.
    func placeListItems() async throws -> [PlaceListItem]

    func packingItems(forTripID tripID: UUID) async throws -> [PackingItem]
    func save(_ item: PackingItem) async throws
    /// Inserts many at once, for applying a template.
    func savePackingItems(_ items: [PackingItem]) async throws
    func deletePackingItem(id: UUID) async throws

    func packingTemplates() async throws -> [PackingTemplate]
    func packingTemplate(id: UUID) async throws -> PackingTemplate?
    func save(_ template: PackingTemplate) async throws
    func deletePackingTemplate(id: UUID) async throws

    func checklistItems(forTripID tripID: UUID) async throws -> [ChecklistItem]
    func save(_ item: ChecklistItem) async throws
    func saveChecklistItems(_ items: [ChecklistItem]) async throws
    func deleteChecklistItem(id: UUID) async throws

    func memories(forTripID tripID: UUID?) async throws -> [TravelMemory]
    func allMemories(limit: Int) async throws -> [TravelMemory]
    func memory(id: UUID) async throws -> TravelMemory?
    func save(_ memory: TravelMemory) async throws
    func deleteMemory(id: UUID) async throws
}

/// Recipes, meal plans, grocery, pantry, prep, and timers
/// (MEALS_AND_PREP.md).
public protocol MealRepository: Sendable {
    func recipes() async throws -> [Recipe]
    func recipe(id: UUID) async throws -> Recipe?
    func save(_ recipe: Recipe) async throws
    func deleteRecipe(id: UUID) async throws

    /// Entries for one day. The date is normalised to the start of day by the
    /// caller, so a day's meals group without a range query.
    func entries(forDay day: Date) async throws -> [MealPlanEntry]
    func entries(from start: Date, to end: Date) async throws -> [MealPlanEntry]
    func entry(id: UUID) async throws -> MealPlanEntry?
    func save(_ entry: MealPlanEntry) async throws
    func deleteEntry(id: UUID) async throws

    func groceryItems() async throws -> [GroceryItem]
    func save(_ item: GroceryItem) async throws
    func saveGroceryItems(_ items: [GroceryItem]) async throws
    func deleteGroceryItem(id: UUID) async throws

    func pantryItems() async throws -> [PantryItem]
    func pantryItem(id: UUID) async throws -> PantryItem?
    func save(_ item: PantryItem) async throws
    func deletePantryItem(id: UUID) async throws

    func prepTasks() async throws -> [PrepTask]
    func save(_ task: PrepTask) async throws
    func deletePrepTask(id: UUID) async throws

    func timers() async throws -> [KitchenTimer]
    func save(_ timer: KitchenTimer) async throws
    func deleteTimer(id: UUID) async throws
}

/// Saved sessions and finished results (GAMES_AND_FUTURE_MULTIPLAYER.md §2).
///
/// Sessions are stored by their move list, not by a snapshot of the board, so a
/// build that changes how a board is laid out still resumes correctly.
public protocol GameRepository: Sendable {
    /// Sessions the player can pick back up, most recent first.
    func resumableSessions() async throws -> [GameSessionState]
    func session(id: UUID) async throws -> GameSessionState?
    /// The session for a given day's puzzle, if one was started.
    func session(dailyKey: String) async throws -> GameSessionState?
    func save(_ session: GameSessionState) async throws
    func deleteSession(id: UUID) async throws

    func results(limit: Int) async throws -> [GameResult]
    func results(gameID: ContentID, limit: Int) async throws -> [GameResult]
    /// Stores the result unless one already exists for this session.
    func save(_ result: GameResult) async throws -> SaveOutcome<GameResult>
    /// Whether a puzzle has been finished before, at any difficulty. Drives the
    /// "played" marker on the games home — never a lock.
    func hasFinished(puzzleID: ContentID) async throws -> Bool
}

public protocol ProgressionRepository: Sendable {
    func profile() async throws -> ProgressionProfile
    func save(_ profile: ProgressionProfile) async throws

    /// Stores the event unless `deterministicKey` is already present.
    func save(_ event: ProgressionEvent) async throws -> SaveOutcome<ProgressionEvent>
    func event(deterministicKey: String) async throws -> ProgressionEvent?

    func save(_ grant: RewardGrant) async throws -> SaveOutcome<RewardGrant>
    func grants(limit: Int) async throws -> [RewardGrant]

    /// Every grant. The collection screen needs all of them, and a "recent"
    /// window would quietly hide the oldest things someone owns.
    func allGrants() async throws -> [RewardGrant]

    /// How many times each kind of event has happened, for the milestone rules.
    ///
    /// Counted in the store rather than by fetching every event, because a
    /// long-lived install has thousands of them and this runs on every launch.
    func eventCounts() async throws -> [ProgressionEventType: Int]

    /// The days on which anything at all happened, for the rhythm summary.
    /// Bounded to a recent window, since older weeks cannot change.
    func eventDates(since: Date) async throws -> [Date]
}

/// Sunnie's home: what is equipped, what is placed, what is playing
/// (PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §8).
///
/// Ownership deliberately lives elsewhere — it is a `RewardGrant` in the
/// progression store, written once and never removed. This repository holds only
/// what the user *arranged*, which is the part that changes often and the part
/// that a second device can conflict on (§12).
public protocol HomeRepository: Sendable {
    func sceneState() async throws -> HomeSceneState
    func save(_ state: HomeSceneState) async throws

    func placements() async throws -> [HomePlacement]
    /// Puts a reward in a slot, replacing whatever was there. One thing per
    /// slot, which is what makes placement constrained rather than freeform.
    func place(rewardID: ContentID, in slotID: ContentID, at date: Date) async throws
    func clear(slotID: ContentID) async throws

    /// Story scenes the user has already read, so a scene is announced once.
    func seenStorySceneIDs() async throws -> Set<ContentID>
    func markStorySceneSeen(_ id: ContentID, at date: Date) async throws
}

public protocol PreferencesRepository: Sendable {
    func profile() async throws -> UserProfile
    func save(_ profile: UserProfile) async throws
    func preferences() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
}

/// Durable queue of actions received from the Watch that have not yet been
/// applied. Survives relaunch so a transfer delivered while the phone app was
/// terminated is not lost.
public protocol PendingWatchActionRepository: Sendable {
    func enqueue(_ action: PendingWatchAction) async throws -> SaveOutcome<PendingWatchAction>
    func unprocessedActions() async throws -> [PendingWatchAction]
    func markProcessed(actionID: UUID, at date: Date) async throws
}
