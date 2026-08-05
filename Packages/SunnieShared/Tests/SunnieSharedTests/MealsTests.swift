import Foundation
import Testing
@testable import SunnieShared

/// The dietary filter, grocery consolidation, suggestions, and the pre-trip
/// plan. All pure.
///
/// The filter tests carry most of the weight, because the filter is where this
/// feature can be wrong in a way that matters. Two failure modes are worth
/// naming: a rule that misses something the user expects it to catch, and a rule
/// that is presented as an allergen guarantee. The first is tested here; the
/// second is prevented by naming — `isClear` means "the text did not contain
/// anything the rules look for", and there is no `isSafe` anywhere to reach for.
@Suite("Meals")
struct MealsTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func recipe(
        _ title: String,
        ingredients: [String],
        favorite: Bool = false,
        prep: Int? = nil,
        cook: Int? = nil,
        portability: Portability = .workable,
        refrigerated: Bool = false
    ) -> Recipe {
        Recipe(
            title: title,
            ingredients: ingredients.map { Ingredient(name: $0) },
            prepMinutes: prep,
            cookMinutes: cook,
            keepsRefrigerated: refrigerated,
            portability: portability,
            isFavorite: favorite,
            createdAt: now,
            modifiedAt: now
        )
    }

    private var noEggs: [DietaryExclusion] { [DietaryExclusionCatalog.noEggs] }

    // MARK: - The egg rule

    @Test("The rule catches the word in its ordinary forms")
    func catchesOrdinaryForms() {
        for ingredient in ["egg", "Eggs", "2 eggs", "EGG YOLK", "egg whites", "eggs,"] {
            let subject = recipe("Thing", ingredients: [ingredient])
            #expect(!DietaryFilter.check(subject, against: noEggs).isClear, ingredient)
        }
    }

    @Test("The rule catches preparations that are eggs by another name")
    func catchesNamedPreparations() {
        // The spec asks for "obvious egg forms". A user who turns on no-eggs and
        // is then suggested a quiche would reasonably call that broken.
        for ingredient in ["mayonnaise", "aioli", "hollandaise", "meringue", "custard"] {
            let subject = recipe("Thing", ingredients: [ingredient])
            #expect(!DietaryFilter.check(subject, against: noEggs).isClear, ingredient)
        }
    }

    @Test("The rule catches derivatives that appear on ingredient lists")
    func catchesDerivatives() {
        for ingredient in ["albumen", "ovalbumin", "dried egg", "egg powder"] {
            let subject = recipe("Thing", ingredients: [ingredient])
            #expect(!DietaryFilter.check(subject, against: noEggs).isClear, ingredient)
        }
    }

    @Test("Eggplant is not eggs")
    func eggplantIsAllowed() {
        // The classic false positive. Whole-word matching alone is not enough
        // for "egg noodles", so allowances handle those explicitly.
        for ingredient in ["eggplant", "2 eggplants", "aubergine", "egg noodles"] {
            let subject = recipe("Thing", ingredients: [ingredient])
            #expect(DietaryFilter.check(subject, against: noEggs).isClear, ingredient)
        }
    }

    @Test("A word merely containing the term does not match")
    func wholeWordMatchingHolds() {
        for ingredient in ["beggar's purse", "leggings", "nutmeg"] {
            let subject = recipe("Thing", ingredients: [ingredient])
            #expect(DietaryFilter.check(subject, against: noEggs).isClear, ingredient)
        }
    }

    @Test("Matching survives punctuation and accents")
    func matchingNormalizes() {
        let punctuated = recipe("Thing", ingredients: ["1 large (egg)"])
        #expect(!DietaryFilter.check(punctuated, against: noEggs).isClear)

        let accented = recipe("Thing", ingredients: ["Omelètte"])
        #expect(!DietaryFilter.check(accented, against: noEggs).isClear)
    }

    @Test("The verdict names which ingredients matched")
    func verdictExplainsItself() {
        // The UI has to be able to say *why* something was set aside, or the
        // user is left guessing.
        let subject = recipe("Brunch", ingredients: ["flour", "2 eggs", "milk"])
        let verdict = DietaryFilter.check(subject, against: noEggs)

        #expect(!verdict.isClear)
        #expect(verdict.matchedExclusions == [DietaryRule.noEggs])
        #expect(verdict.matchingIngredients == ["2 eggs"])
    }

    @Test("No active rules means nothing is set aside")
    func noRulesMeansNoFiltering() {
        let subject = recipe("Omelette", ingredients: ["eggs"])
        #expect(DietaryFilter.check(subject, against: []).isClear)
    }

    @Test("Partitioning returns both halves, not just the survivors")
    func partitionKeepsBothHalves() {
        // A filter that silently shrinks a list leaves the user hunting for a
        // recipe they know they saved.
        let recipes = [
            recipe("Soup", ingredients: ["stock", "carrot"]),
            recipe("Quiche", ingredients: ["eggs", "cream"])
        ]

        let result = DietaryFilter.partition(recipes, against: noEggs)
        #expect(result.clear.map(\.title) == ["Soup"])
        #expect(result.setAside.map(\.recipe.title) == ["Quiche"])
        #expect(result.setAside.first?.verdict.matchingIngredients == ["eggs"])
    }

    @Test("A single ingredient can be checked as it is typed")
    func singleIngredientMatching() {
        #expect(!DietaryFilter.matches(ingredientName: "egg", against: noEggs).isEmpty)
        #expect(DietaryFilter.matches(ingredientName: "eggplant", against: noEggs).isEmpty)
    }

    // MARK: - Grocery

    private func entry(_ recipeID: UUID?, custom: String? = nil) -> MealPlanEntry {
        MealPlanEntry(
            date: now,
            slot: .dinner,
            recipeID: recipeID,
            customTitle: custom,
            createdAt: now,
            modifiedAt: now
        )
    }

    @Test("Two meals wanting the same thing produce one line")
    func groceryConsolidates() {
        var soup = recipe("Soup", ingredients: [])
        soup.ingredients = [
            Ingredient(name: "Onion", amount: "1", category: .produce),
            Ingredient(name: "Stock", category: .pantry)
        ]
        var curry = recipe("Curry", ingredients: [])
        curry.ingredients = [Ingredient(name: "onion", amount: "2", category: .produce)]

        let entries = [entry(soup.id), entry(curry.id)]
        let lines = GroceryListBuilder.lines(
            forEntries: entries,
            recipes: [soup.id: soup, curry.id: curry],
            existing: [],
            now: now
        )

        #expect(lines.count == 2)
        let onion = try! #require(lines.first { $0.name.lowercased() == "onion" })
        // Both meals attached, so the list can answer "why is this here?".
        #expect(onion.linkedEntryIDs.count == 2)
        // Amounts joined, not summed: "1" and "2" of an onion might not be
        // comparable, and inventing a total would be worse than showing both.
        #expect(onion.amount == "1 + 2")
    }

    @Test("Pantry staples are not put on the shopping list")
    func staplesAreSkipped() {
        var subject = recipe("Toast", ingredients: [])
        subject.ingredients = [
            Ingredient(name: "Bread", category: .bakery),
            Ingredient(name: "Salt", category: .pantry, isPantryStaple: true)
        ]

        let lines = GroceryListBuilder.lines(
            forEntries: [entry(subject.id)],
            recipes: [subject.id: subject],
            existing: [],
            now: now
        )
        #expect(lines.map(\.name) == ["Bread"])
    }

    @Test("Something already on the list is not added again")
    func existingLinesAreNotDuplicated() {
        var subject = recipe("Soup", ingredients: [])
        subject.ingredients = [Ingredient(name: "Onion", category: .produce)]

        let existing = [GroceryItem(name: "onion", category: .produce, createdAt: now)]
        let lines = GroceryListBuilder.lines(
            forEntries: [entry(subject.id)],
            recipes: [subject.id: subject],
            existing: existing,
            now: now
        )
        #expect(lines.isEmpty)
    }

    @Test("Grouping walks the shop and sinks purchased items")
    func groupingOrdersForShopping() {
        var bought = GroceryItem(name: "Apples", category: .produce, createdAt: now)
        bought.isPurchased = true
        let items = [
            bought,
            GroceryItem(name: "Bananas", category: .produce, createdAt: now),
            GroceryItem(name: "Milk", category: .dairy, createdAt: now)
        ]

        let grouped = GroceryListBuilder.grouped(items)
        #expect(grouped.map(\.category) == [.produce, .dairy])
        // Purchased last within its group, so the list does not reshuffle as it
        // is worked through.
        #expect(grouped.first?.items.map(\.name) == ["Bananas", "Apples"])
    }

    @Test("Merging keeps every link and both amounts")
    func mergingIsLossless() {
        let entryA = UUID(), entryB = UUID()
        var first = GroceryItem(
            name: "Onion", amount: "1", linkedEntryIDs: [entryA], createdAt: now
        )
        first.isPurchased = false
        let second = GroceryItem(
            name: "onion",
            amount: "2",
            isPurchased: true,
            linkedEntryIDs: [entryB],
            createdAt: now.addingTimeInterval(60)
        )

        let merged = try! #require(GroceryListBuilder.merge([first, second]))
        #expect(Set(merged.linkedEntryIDs) == Set([entryA, entryB]))
        #expect(merged.amount == "1 + 2")
        // If any copy was bought, the thing is in the house.
        #expect(merged.isPurchased)
    }

    @Test("Duplicates are grouped rather than merged automatically")
    func duplicatesAreSurfaced() {
        let items = [
            GroceryItem(name: "Onion", createdAt: now),
            GroceryItem(name: "onion", createdAt: now.addingTimeInterval(1)),
            GroceryItem(name: "Milk", createdAt: now)
        ]
        let groups = GroceryListBuilder.duplicateGroups(in: items)
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
    }

    // MARK: - Suggestions

    @Test("A recipe matching an active rule is never suggested")
    func exclusionsAreAbsolute() {
        // Whatever else it scores. This is the one hard constraint.
        var quiche = recipe("Quiche", ingredients: ["eggs"], favorite: true, prep: 5)
        quiche.isFavorite = true

        let suggestions = MealSuggestionEngine.suggest(
            from: [quiche, recipe("Soup", ingredients: ["stock"])],
            context: MealSuggestionEngine.Context(exclusions: noEggs)
        )
        #expect(suggestions.map(\.recipe.title) == ["Soup"])
    }

    @Test("Using something up ranks above being a favourite")
    func pantryFirstOutranksFavourite() {
        // The one reason where taking the suggestion prevents waste.
        let usesPantry = recipe("Carrot soup", ingredients: ["Carrots", "stock"])
        let favourite = recipe("Pasta", ingredients: ["pasta"], favorite: true)

        let suggestions = MealSuggestionEngine.suggest(
            from: [favourite, usesPantry],
            context: MealSuggestionEngine.Context(
                pantry: [PantryItem(
                    name: "Carrots", useBeforeTrip: true, createdAt: now, modifiedAt: now
                )]
            )
        )
        #expect(suggestions.first?.recipe.title == "Carrot soup")
        #expect(suggestions.first?.reasons.contains(.usesPantryFirst) == true)
        #expect(suggestions.first?.usesPantryItems == ["Carrots"])
    }

    @Test("A travel day is never offered something that stays home")
    func travelDaysExcludeStayHome() {
        let suggestions = MealSuggestionEngine.suggest(
            from: [
                recipe("Soufflé", ingredients: ["flour"], portability: .stayHome),
                recipe("Wrap", ingredients: ["tortilla"], portability: .easy)
            ],
            context: MealSuggestionEngine.Context(dayContext: .travel)
        )
        #expect(suggestions.map(\.recipe.title) == ["Wrap"])
        #expect(suggestions.first?.reasons.contains(.portable) == true)
    }

    @Test("Time available filters and ranks")
    func availableTimeMatters() {
        let quick = recipe("Quick", ingredients: ["a"], prep: 5, cook: 5)
        let slow = recipe("Slow", ingredients: ["b"], prep: 30, cook: 90)

        let suggestions = MealSuggestionEngine.suggest(
            from: [slow, quick],
            context: MealSuggestionEngine.Context(availableMinutes: 20)
        )
        // Both are still offered — a long recipe is not forbidden — but the one
        // that fits leads and says so.
        #expect(suggestions.first?.recipe.title == "Quick")
        #expect(suggestions.first?.reasons.contains(.quick) == true)
    }

    @Test("Recently planned recipes rank lower")
    func varietyIsPreferred() {
        let a = recipe("A", ingredients: ["x"])
        let b = recipe("B", ingredients: ["y"])

        let suggestions = MealSuggestionEngine.suggest(
            from: [a, b],
            context: MealSuggestionEngine.Context(recentlyPlannedRecipeIDs: [a.id])
        )
        #expect(suggestions.first?.recipe.title == "B")
    }

    @Test("Suggestions are deterministic and capped")
    func suggestionsAreStable() {
        // Same inputs, same order — which is what makes them explainable and the
        // tests non-flaky.
        let recipes = (1...12).map { recipe("Recipe \($0)", ingredients: ["x"]) }
        let context = MealSuggestionEngine.Context()

        let first = MealSuggestionEngine.suggest(from: recipes, context: context)
        let second = MealSuggestionEngine.suggest(from: recipes, context: context)

        #expect(first.map(\.recipe.id) == second.map(\.recipe.id))
        #expect(first.count == MealSuggestionEngine.maximumSuggestions)
    }

    @Test("Every suggestion carries at least one reason")
    func suggestionsExplainThemselves() {
        let suggestions = MealSuggestionEngine.suggest(
            from: [recipe("Soup", ingredients: ["stock"])],
            context: MealSuggestionEngine.Context()
        )
        #expect(suggestions.allSatisfy { !$0.reasons.isEmpty })
    }

    // MARK: - Pre-trip

    @Test("The pre-trip plan orders use-first items by their date")
    func preTripOrdersByDate() {
        // An ordering, not a judgement: nothing here says food has gone off.
        let soon = PantryItem(
            name: "Soon",
            bestBefore: now.addingTimeInterval(86_400),
            useBeforeTrip: true,
            createdAt: now,
            modifiedAt: now
        )
        let later = PantryItem(
            name: "Later",
            bestBefore: now.addingTimeInterval(86_400 * 10),
            useBeforeTrip: true,
            createdAt: now,
            modifiedAt: now
        )
        let ignored = PantryItem(name: "Ignored", createdAt: now, modifiedAt: now)

        let plan = PreTripFoodPlanner.plan(
            departureDate: now,
            returnDate: now.addingTimeInterval(86_400 * 5),
            pantry: [later, ignored, soon],
            entries: [],
            calendar: calendar
        )

        #expect(plan.useFirst.map(\.name) == ["Soon", "Later"])
    }

    @Test("The pre-trip plan finds what to pack and what to prepare")
    func preTripFindsMeals() {
        var packed = entry(nil, custom: "Wrap")
        packed.date = now.addingTimeInterval(86_400)
        packed.isPacked = true

        var prepared = entry(nil, custom: "Soup")
        prepared.date = now.addingTimeInterval(86_400 * 2)
        prepared.isPrepared = true

        let plan = PreTripFoodPlanner.plan(
            departureDate: now,
            returnDate: now.addingTimeInterval(86_400 * 5),
            pantry: [],
            entries: [packed, prepared],
            calendar: calendar
        )

        #expect(plan.toPack.map(\.customTitle) == ["Wrap"])
        // Already prepared, so not on the to-prepare list.
        #expect(plan.toPrepare.map(\.customTitle) == ["Wrap"])
        #expect(!plan.isEmpty)
    }

    @Test("An empty pre-trip plan reports itself as empty")
    func emptyPreTripPlan() {
        let plan = PreTripFoodPlanner.plan(
            departureDate: now,
            returnDate: now.addingTimeInterval(86_400),
            pantry: [],
            entries: [],
            calendar: calendar
        )
        #expect(plan.isEmpty)
    }

    // MARK: - Day summary and timers

    @Test("An unplanned slot is not a meal")
    func unplannedSlotsAreNotMeals() {
        let empty = MealPlanEntry(date: now, slot: .lunch, createdAt: now, modifiedAt: now)
        #expect(!empty.isPlanned)

        let named = entry(nil, custom: "Leftovers")
        #expect(named.isPlanned)
    }

    @Test("The day summary sorts by slot and reports packed meals")
    func daySummaryOrdersSlots() {
        var dinner = entry(nil, custom: "Dinner")
        dinner.slot = .dinner
        var breakfast = entry(nil, custom: "Breakfast")
        breakfast.slot = .breakfast
        breakfast.isPacked = true

        let summary = MealDaySummary(
            date: now, context: .work, entries: [dinner, breakfast]
        )

        #expect(summary.plannedEntries.map(\.slot) == [.breakfast, .dinner])
        #expect(summary.packedEntries.map(\.customTitle) == ["Breakfast"])
        #expect(summary.hasAnything)
    }

    @Test("A timer is measured from its end instant, not a countdown")
    func timersSurviveBeingClosed() {
        // A countdown held in memory is wrong the moment anything interrupts it.
        let timer = KitchenTimer(
            name: "Pasta", endsAt: now.addingTimeInterval(600), totalSeconds: 600
        )

        #expect(timer.remaining(at: now) == 600)
        #expect(!timer.hasElapsed(at: now))
        #expect(timer.progress(at: now) == 0)

        let halfway = now.addingTimeInterval(300)
        #expect(abs(timer.progress(at: halfway) - 0.5) < 0.001)

        // Reopened long after it finished: elapsed, and clamped rather than
        // reporting negative time or progress above 1.
        let later = now.addingTimeInterval(86_400)
        #expect(timer.hasElapsed(at: later))
        #expect(timer.remaining(at: later) == 0)
        #expect(timer.progress(at: later) == 1)
    }

    @Test("Work, travel, and layover days want portable food")
    func portableContexts() {
        #expect(DayContext.travel.needsPortableFood)
        #expect(DayContext.work.needsPortableFood)
        #expect(DayContext.layover.needsPortableFood)
        #expect(!DayContext.home.needsPortableFood)
        #expect(!DayContext.recovery.needsPortableFood)
    }
}
