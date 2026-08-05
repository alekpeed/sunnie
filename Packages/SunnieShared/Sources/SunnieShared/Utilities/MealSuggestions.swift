import Foundation

/// Deterministic, rule-based meal suggestions (MEALS_AND_PREP.md §10).
///
/// **No generative AI, and the spec says so for the initial release.** Every
/// suggestion here is a filter and a sort over recipes the user already saved.
/// It cannot invent a recipe, and it cannot recommend anything the user has not
/// written down.
///
/// Being deterministic is also what makes it testable and explainable: each
/// suggestion carries the reasons it was chosen, so the UI can say *why*
/// something is being offered rather than presenting it as an oracle.
public enum MealSuggestionEngine {

    /// Why a recipe was suggested. Shown to the user, so each case has to be
    /// something a person would accept as a reason.
    public enum Reason: String, Hashable, Sendable, CaseIterable {
        /// Uses something marked to eat before a trip.
        case usesPantryFirst
        /// Fits the time available.
        case quick
        /// Travels well, on a day that needs it to.
        case portable
        /// The user marked it a favourite.
        case favorite
        /// Not planned recently, so the week is not four identical dinners.
        case notRecent

        public var localizationKey: String { "meals.reason.\(rawValue)" }
    }

    public struct Suggestion: Identifiable, Hashable, Sendable {
        public let recipe: Recipe
        public let reasons: [Reason]
        /// Pantry items this would use up, when that was one of the reasons.
        public let usesPantryItems: [String]

        public var id: UUID { recipe.id }

        public init(recipe: Recipe, reasons: [Reason], usesPantryItems: [String] = []) {
            self.recipe = recipe
            self.reasons = reasons
            self.usesPantryItems = usesPantryItems
        }
    }

    /// Everything a suggestion depends on, passed as one value so the whole
    /// thing stays a pure function of stated inputs.
    public struct Context: Sendable {
        public let dayContext: DayContext
        /// Minutes the user says they have. Nil means no constraint.
        public let availableMinutes: Int?
        public let pantry: [PantryItem]
        public let exclusions: [DietaryExclusion]
        /// Recipes planned in the recent past, so suggestions vary.
        public let recentlyPlannedRecipeIDs: Set<UUID>
        public let needsRefrigeration: Bool

        public init(
            dayContext: DayContext = .home,
            availableMinutes: Int? = nil,
            pantry: [PantryItem] = [],
            exclusions: [DietaryExclusion] = [],
            recentlyPlannedRecipeIDs: Set<UUID> = [],
            needsRefrigeration: Bool = false
        ) {
            self.dayContext = dayContext
            self.availableMinutes = availableMinutes
            self.pantry = pantry
            self.exclusions = exclusions
            self.recentlyPlannedRecipeIDs = recentlyPlannedRecipeIDs
            self.needsRefrigeration = needsRefrigeration
        }
    }

    /// How many to offer. Small on purpose: a list of thirty suggestions is a
    /// second problem, not a solution to the first.
    public static let maximumSuggestions = 5

    /// Suggests from the user's own recipes.
    ///
    /// Dietary exclusions are applied first and absolutely — a recipe that
    /// matches an active rule is never suggested, whatever else it scores.
    /// Everything after that is ordering.
    public static func suggest(
        from recipes: [Recipe],
        context: Context,
        limit: Int = maximumSuggestions
    ) -> [Suggestion] {
        let eligible = DietaryFilter
            .partition(recipes, against: context.exclusions)
            .clear
            .filter { fits(recipe: $0, context: context) }

        let scored = eligible.map { recipe -> (Suggestion, Int) in
            var reasons: [Reason] = []
            var score = 0
            var pantryHits: [String] = []

            // Using something up ranks highest: it is the one reason where
            // taking the suggestion prevents waste.
            let hits = pantryMatches(recipe: recipe, pantry: context.pantry)
            if !hits.isEmpty {
                reasons.append(.usesPantryFirst)
                pantryHits = hits
                score += 40 + min(hits.count, 3) * 5
            }

            if context.dayContext.needsPortableFood, recipe.portability.travelsWell {
                reasons.append(.portable)
                score += 25
            }

            if let available = context.availableMinutes,
               let total = recipe.totalMinutes,
               total <= available {
                reasons.append(.quick)
                // The more time to spare, the better the fit.
                score += 15 + max(0, (available - total) / 10)
            }

            if recipe.isFavorite {
                reasons.append(.favorite)
                score += 10
            }

            if !context.recentlyPlannedRecipeIDs.contains(recipe.id) {
                reasons.append(.notRecent)
                score += 5
            }

            return (Suggestion(recipe: recipe, reasons: reasons, usesPantryItems: pantryHits), score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                // Deterministic tiebreak, so the same inputs always produce the
                // same order and the tests are not flaky.
                return lhs.0.recipe.title
                    .localizedStandardCompare(rhs.0.recipe.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Hard constraints. A recipe failing one of these is not suggested at all,
    /// rather than being suggested with a low score.
    private static func fits(recipe: Recipe, context: Context) -> Bool {
        // Somewhere with no fridge cannot take something that needs one.
        if context.needsRefrigeration == false,
           context.dayContext.needsPortableFood,
           recipe.keepsRefrigerated,
           recipe.portability == .stayHome {
            return false
        }

        // A day that needs portable food should not be offered something the
        // user marked as staying home.
        if context.dayContext.needsPortableFood, recipe.portability == .stayHome {
            return false
        }

        return true
    }

    /// Pantry items a recipe's ingredients name, prioritising the ones marked to
    /// use before a trip.
    ///
    /// Matching is the same normalized whole-word comparison the dietary filter
    /// uses, so "Onions" in the pantry matches "onion" in a recipe.
    private static func pantryMatches(recipe: Recipe, pantry: [PantryItem]) -> [String] {
        let priority = pantry.filter(\.useBeforeTrip)
        let searched = priority.isEmpty ? pantry : priority

        return searched.compactMap { item in
            let matches = recipe.ingredients.contains { ingredient in
                DietaryFilter.contains(
                    anyOf: [item.name], in: ingredient.name, allowing: []
                )
                    || DietaryFilter.contains(
                        anyOf: [ingredient.name], in: item.name, allowing: []
                    )
            }
            return matches ? item.name : nil
        }
    }
}

/// The pre-trip food workflow (MEALS_AND_PREP.md §8).
///
/// Works out what to eat before leaving, what to take, and what to prepare. Pure,
/// so the whole sequence is testable without a trip or a store.
public enum PreTripFoodPlanner {

    public struct Plan: Hashable, Sendable {
        /// Pantry items the user marked to use before going.
        public let useFirst: [PantryItem]
        /// Meals already planned inside the trip that need packing.
        public let toPack: [MealPlanEntry]
        /// Meals needing preparation before departure.
        public let toPrepare: [MealPlanEntry]

        public init(
            useFirst: [PantryItem],
            toPack: [MealPlanEntry],
            toPrepare: [MealPlanEntry]
        ) {
            self.useFirst = useFirst
            self.toPack = toPack
            self.toPrepare = toPrepare
        }

        public var isEmpty: Bool {
            useFirst.isEmpty && toPack.isEmpty && toPrepare.isEmpty
        }
    }

    /// Builds the plan for an absence.
    ///
    /// `bestBefore` is used only for *ordering* what to use first. Nothing here
    /// decides that food has gone off — the app has no basis for that and the
    /// spec forbids asserting it (MEALS_AND_PREP.md §7).
    public static func plan(
        departureDate: Date,
        returnDate: Date,
        pantry: [PantryItem],
        entries: [MealPlanEntry],
        calendar: Calendar
    ) -> Plan {
        let useFirst = pantry
            .filter(\.useBeforeTrip)
            .sorted { lhs, rhs in
                switch (lhs.bestBefore, rhs.bestBefore) {
                // Soonest date first — an ordering, not a judgement.
                case let (l?, r?): l < r
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil):
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }

        let duringTrip = entries.filter {
            $0.date >= calendar.startOfDay(for: departureDate) && $0.date <= returnDate
        }

        return Plan(
            useFirst: useFirst,
            toPack: duringTrip.filter { $0.isPlanned && $0.isPacked },
            // Anything planned during the trip that has not been prepared yet
            // and needs doing before leaving.
            toPrepare: duringTrip.filter { $0.isPlanned && !$0.isPrepared }
        )
    }

    /// A batch-prep task covering several meals.
    public static func prepTask(
        for entries: [MealPlanEntry],
        scheduledFor: Date?,
        tripID: UUID?,
        title: String,
        now: Date
    ) -> PrepTask {
        PrepTask(
            title: title,
            scheduledFor: scheduledFor,
            entryIDs: entries.map(\.id),
            tripID: tripID,
            createdAt: now
        )
    }
}

/// Today's food, for the Today card and the meals dashboard.
public struct MealDaySummary: Hashable, Sendable {
    public let date: Date
    public let context: DayContext
    public let entries: [MealPlanEntry]
    public let prepTasksDue: [PrepTask]
    public let groceryOutstanding: Int
    public let useBeforeTripCount: Int

    public init(
        date: Date,
        context: DayContext,
        entries: [MealPlanEntry],
        prepTasksDue: [PrepTask] = [],
        groceryOutstanding: Int = 0,
        useBeforeTripCount: Int = 0
    ) {
        self.date = date
        self.context = context
        self.entries = entries
        self.prepTasksDue = prepTasksDue
        self.groceryOutstanding = groceryOutstanding
        self.useBeforeTripCount = useBeforeTripCount
    }

    public var plannedEntries: [MealPlanEntry] {
        entries.filter(\.isPlanned).sorted { $0.slot.sortOrder < $1.slot.sortOrder }
    }

    public var hasAnything: Bool {
        !plannedEntries.isEmpty || !prepTasksDue.isEmpty || groceryOutstanding > 0
    }

    /// Meals to take, on a day that needs them.
    public var packedEntries: [MealPlanEntry] {
        plannedEntries.filter(\.isPacked)
    }
}
