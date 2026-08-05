import Foundation
import SunnieShared

/// Recipes, meal plans, grocery, pantry, prep, and timers
/// (MEALS_AND_PREP.md).
///
/// **Three things this feature explicitly is not** (§13): a calorie counter, a
/// macro tracker, or medical diet management. There is no weight goal, no
/// nutrition database, and nothing that scores what someone eats. Progression
/// rewards planning and prep — never restriction (§12).
struct ManageMeals: Sendable {

    private let repository: any MealRepository
    private let preferencesRepository: any PreferencesRepository
    private let progressionEngine: ProgressionEngine
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    init(
        repository: any MealRepository,
        preferencesRepository: any PreferencesRepository,
        progressionEngine: ProgressionEngine,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.preferencesRepository = preferencesRepository
        self.progressionEngine = progressionEngine
        self.clock = clock
    }

    // MARK: - Dietary rules

    /// The exclusions the user currently has on.
    ///
    /// Read from preferences every time rather than cached: the rule can be
    /// changed in Settings, and a cached copy would keep filtering by a rule the
    /// user just turned off.
    func activeExclusions() async -> [DietaryExclusion] {
        let preferences = (try? await preferencesRepository.preferences()) ?? .default
        return preferences.dietaryRuleIDs.compactMap(DietaryExclusionCatalog.exclusion(for:))
    }

    /// Checks one recipe against the active rules.
    ///
    /// The result says what the ingredient text contains, not whether the food is
    /// safe. Nothing built on this may present it as an allergen judgement
    /// (MEALS_AND_PREP.md §2).
    func check(_ recipe: Recipe) async -> DietaryFilter.Verdict {
        DietaryFilter.check(recipe, against: await activeExclusions())
    }

    // MARK: - Recipes

    func newRecipe() -> Recipe {
        let now = clock.now
        return Recipe(title: "", createdAt: now, modifiedAt: now)
    }

    func recipes() async throws -> [Recipe] {
        try await repository.recipes()
    }

    /// Recipes split into those with nothing matching and those set aside.
    ///
    /// Both halves come back so the UI can say plainly that some were set aside
    /// and why — a list that silently shrinks leaves the user hunting for a
    /// recipe they know they saved.
    func partitionedRecipes() async throws -> (
        clear: [Recipe],
        setAside: [(recipe: Recipe, verdict: DietaryFilter.Verdict)]
    ) {
        DietaryFilter.partition(try await repository.recipes(), against: await activeExclusions())
    }

    func recipe(id: UUID) async throws -> Recipe? {
        try await repository.recipe(id: id)
    }

    @discardableResult
    func save(_ recipe: Recipe) async throws -> Recipe {
        var cleaned = recipe
        cleaned.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.storageNotes = tidy(recipe.storageNotes)
        cleaned.containerNote = tidy(recipe.containerNote)
        cleaned.notes = tidy(recipe.notes)
        cleaned.steps = recipe.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        cleaned.ingredients = recipe.ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        cleaned.modifiedAt = clock.now

        try await repository.save(cleaned)
        return cleaned
    }

    func deleteRecipe(id: UUID) async throws {
        try await repository.deleteRecipe(id: id)
    }

    // MARK: - Planning

    /// The start of a day in the user's zone, which is how entries are keyed.
    func startOfDay(_ date: Date) -> Date {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        return calendar.startOfDay(for: date)
    }

    func newEntry(
        on date: Date,
        slot: MealSlot,
        context: DayContext = .home
    ) -> MealPlanEntry {
        let now = clock.now
        return MealPlanEntry(
            date: startOfDay(date),
            slot: slot,
            context: context,
            createdAt: now,
            modifiedAt: now
        )
    }

    func entries(forDay day: Date) async throws -> [MealPlanEntry] {
        try await repository.entries(forDay: startOfDay(day))
    }

    func entries(from start: Date, to end: Date) async throws -> [MealPlanEntry] {
        try await repository.entries(from: startOfDay(start), to: startOfDay(end))
    }

    @discardableResult
    func save(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        var cleaned = entry
        cleaned.date = startOfDay(entry.date)
        cleaned.customTitle = tidy(entry.customTitle)
        cleaned.notes = tidy(entry.notes)
        cleaned.modifiedAt = clock.now

        // A day that needs food to travel implies packing it. Set once, on
        // creation, and editable afterwards — the app suggests, it does not
        // decide.
        if cleaned.context.needsPortableFood, entry.isPacked == false, entry.createdAt == entry.modifiedAt {
            cleaned.isPacked = true
        }

        try await repository.save(cleaned)

        if cleaned.isPlanned {
            await awardPlanningIfEligible(on: cleaned.date)
        }
        return cleaned
    }

    func deleteEntry(id: UUID) async throws {
        try await repository.deleteEntry(id: id)
    }

    func setPrepared(_ isPrepared: Bool, entry: MealPlanEntry) async throws {
        var updated = entry
        updated.isPrepared = isPrepared
        updated.modifiedAt = clock.now
        try await repository.save(updated)
    }

    /// Sets a whole day's context in one go.
    ///
    /// Context is per entry so a day can be mixed — a work lunch and a home
    /// dinner — but changing it for the whole day is the common case.
    func setContext(_ context: DayContext, forDay day: Date) async throws {
        for var entry in try await entries(forDay: day) {
            entry.context = context
            entry.modifiedAt = clock.now
            try await repository.save(entry)
        }
    }

    /// "Planned a day's meals" is an eligible progression event
    /// (MEALS_AND_PREP.md §12). Keyed to the day, so editing the same day again
    /// cannot earn twice, and it rewards *planning* rather than what was eaten.
    private func awardPlanningIfEligible(on day: Date) async {
        let planned = (try? await repository.entries(forDay: day))?.filter(\.isPlanned) ?? []
        // Two or more slots is a plan; one is just a note about dinner.
        guard planned.count >= 2 else { return }

        _ = try? await progressionEngine.award(
            type: .mealsPlanned,
            sourceEntityID: nil,
            occurredAt: clock.now,
            deterministicKey: "mealsPlanned.\(Int(day.timeIntervalSince1970))"
        )
    }

    // MARK: - Suggestions

    /// Deterministic, rule-based suggestions from the user's own recipes.
    ///
    /// No generative AI in the initial release (MEALS_AND_PREP.md §10). Every
    /// suggestion carries the reasons it was chosen.
    func suggestions(
        for context: DayContext,
        availableMinutes: Int? = nil,
        limit: Int = MealSuggestionEngine.maximumSuggestions
    ) async throws -> [MealSuggestionEngine.Suggestion] {
        let recipes = try await repository.recipes()
        let pantry = try await repository.pantryItems()

        // Recent plans, so a week is not four identical dinners.
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone
        let since = calendar.date(byAdding: .day, value: -10, to: clock.now) ?? clock.now
        let recent = try await repository.entries(from: startOfDay(since), to: startOfDay(clock.now))

        return MealSuggestionEngine.suggest(
            from: recipes,
            context: MealSuggestionEngine.Context(
                dayContext: context,
                availableMinutes: availableMinutes,
                pantry: pantry,
                exclusions: await activeExclusions(),
                recentlyPlannedRecipeIDs: Set(recent.compactMap(\.recipeID)),
                needsRefrigeration: false
            ),
            limit: limit
        )
    }

    // MARK: - Today

    /// Everything the Today card and the meals dashboard need for one day.
    func daySummary(for date: Date) async throws -> MealDaySummary {
        let day = startOfDay(date)
        let entries = try await repository.entries(forDay: day)
        let grocery = try await repository.groceryItems()
        let pantry = try await repository.pantryItems()

        let due = try await repository.prepTasks().filter { task in
            guard !task.isDone else { return false }
            guard let scheduled = task.scheduledFor else { return true }
            return startOfDay(scheduled) <= day
        }

        return MealDaySummary(
            date: day,
            // The day's context comes from its entries; an unplanned day is a
            // home day until something says otherwise.
            context: entries.first?.context ?? .home,
            entries: entries,
            prepTasksDue: due,
            groceryOutstanding: grocery.filter { !$0.isPurchased }.count,
            useBeforeTripCount: pantry.filter(\.useBeforeTrip).count
        )
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
