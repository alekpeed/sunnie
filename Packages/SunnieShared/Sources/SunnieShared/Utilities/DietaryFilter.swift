import Foundation

/// A thing the user does not want in their food (MEALS_AND_PREP.md §2).
///
/// Built-in rules ship with a term list; a user-defined rule carries its own.
/// Both work the same way, which means the no-eggs rule has no special-cased
/// code path that could quietly diverge from the rest.
public struct DietaryExclusion: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    /// Localization key for the rule's name.
    public var displayNameKey: String
    /// What to look for in ingredient text. Matched whole-word, so "egg" does
    /// not fire on "eggplant".
    public var terms: [String]
    /// User-created rather than shipped. A built-in rule can be turned off but
    /// not deleted, so the no-eggs default is always recoverable.
    public var isUserDefined: Bool

    public init(
        id: ContentID,
        displayNameKey: String,
        terms: [String],
        isUserDefined: Bool = false
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.terms = terms
        self.isUserDefined = isUserDefined
    }
}

/// The built-in exclusions.
public enum DietaryExclusionCatalog {

    /// Vanessa's locked rule: no eggs (MASTER_SOURCE_OF_TRUTH.md).
    ///
    /// The term list covers the obvious forms the spec asks for — the word
    /// itself, its plurals, and the named preparations and derivatives that do
    /// not contain the string "egg". It is deliberately *not* exhaustive, and
    /// nothing in the app claims it is: `DietaryFilter` reports a match as
    /// "contains something the rule looks for", never as an allergen judgement.
    ///
    /// "Eggplant" and "egg noodle" are handled by whole-word matching plus the
    /// explicit allowances below, because both contain the term and neither is
    /// what the rule means.
    public static let noEggs = DietaryExclusion(
        id: DietaryRule.noEggs,
        displayNameKey: "diet.noEggs",
        terms: [
            "egg", "eggs", "egg white", "egg whites", "egg yolk", "egg yolks",
            "eggwhite", "eggyolk",
            // Preparations that are eggs by another name.
            "omelette", "omelet", "frittata", "quiche", "meringue",
            "custard", "hollandaise", "aioli", "mayonnaise", "mayo",
            // Derivatives on an ingredients list.
            "albumen", "albumin", "ovalbumin", "lysozyme", "globulin",
            "livetin", "lecithin (egg)", "egg powder", "dried egg",
            "egg wash", "eggnog"
        ]
    )

    public static let all: [DietaryExclusion] = [noEggs]

    /// Words that contain an excluded term but are not the excluded thing.
    ///
    /// Checked before the term list, so "eggplant parmesan" is not filtered out
    /// of a no-eggs plan. This is the kind of rule that has to be explicit —
    /// there is no general way to derive it.
    public static let allowances: [ContentID: [String]] = [
        DietaryRule.noEggs: ["eggplant", "eggplants", "aubergine", "egg noodle", "egg noodles"]
    ]

    public static func exclusion(for id: ContentID) -> DietaryExclusion? {
        all.first { $0.id == id }
    }
}

/// Applies dietary exclusions to recipes and ingredients
/// (MEALS_AND_PREP.md §2, §10).
///
/// **This is text matching, and the app says so.** It reads the ingredient names
/// as written and reports what it found. It has no ingredient database, no
/// knowledge of manufacturing, and no way to know what is in a product beyond
/// what someone typed. Every string built from a result must describe it that
/// way: *"this lists something the rule looks for"*, never *"this is safe"* or
/// *"this is egg-free"*.
///
/// The spec is explicit: it must not claim allergen safety unless all ingredient
/// data is verified and the product is intentionally built for that purpose.
/// This one is not.
public enum DietaryFilter {

    /// What matching a recipe against the active rules turned up.
    public struct Verdict: Hashable, Sendable {
        /// Rules with at least one matching ingredient.
        public let matchedExclusions: [ContentID]
        /// The ingredient lines that matched, for showing *why*.
        public let matchingIngredients: [String]

        public init(matchedExclusions: [ContentID], matchingIngredients: [String]) {
            self.matchedExclusions = matchedExclusions
            self.matchingIngredients = matchingIngredients
        }

        /// True when nothing matched.
        ///
        /// Deliberately not called `isSafe` or `isEggFree`. It means "the text
        /// did not contain anything the rules look for", which is a much smaller
        /// claim, and naming it accurately is what stops the smaller claim being
        /// presented as the larger one.
        public var isClear: Bool { matchedExclusions.isEmpty }
    }

    /// Checks one recipe against a set of rules.
    public static func check(
        _ recipe: Recipe,
        against exclusions: [DietaryExclusion]
    ) -> Verdict {
        var matched: [ContentID] = []
        var lines: [String] = []

        for exclusion in exclusions {
            let allowances = DietaryExclusionCatalog.allowances[exclusion.id] ?? []
            var hit = false

            for ingredient in recipe.ingredients {
                guard contains(
                    anyOf: exclusion.terms,
                    in: ingredient.name,
                    allowing: allowances
                ) else { continue }
                hit = true
                if !lines.contains(ingredient.name) { lines.append(ingredient.name) }
            }

            if hit { matched.append(exclusion.id) }
        }

        return Verdict(matchedExclusions: matched, matchingIngredients: lines)
    }

    /// Recipes with nothing matching, and the ones set aside.
    ///
    /// Both halves are returned rather than just the survivors. A filter that
    /// silently shrinks a list leaves the user wondering where a recipe went;
    /// returning what was set aside lets the UI say so plainly without turning
    /// into a restriction banner.
    public static func partition(
        _ recipes: [Recipe],
        against exclusions: [DietaryExclusion]
    ) -> (clear: [Recipe], setAside: [(recipe: Recipe, verdict: Verdict)]) {
        var clear: [Recipe] = []
        var setAside: [(Recipe, Verdict)] = []

        for recipe in recipes {
            let verdict = check(recipe, against: exclusions)
            if verdict.isClear {
                clear.append(recipe)
            } else {
                setAside.append((recipe, verdict))
            }
        }
        return (clear, setAside)
    }

    /// Whether a single ingredient line matches any rule. Used when adding an
    /// ingredient by hand, so the user is told at the point of typing.
    public static func matches(
        ingredientName: String,
        against exclusions: [DietaryExclusion]
    ) -> [ContentID] {
        exclusions.compactMap { exclusion in
            let allowances = DietaryExclusionCatalog.allowances[exclusion.id] ?? []
            return contains(anyOf: exclusion.terms, in: ingredientName, allowing: allowances)
                ? exclusion.id
                : nil
        }
    }

    /// Whole-word, case- and diacritic-insensitive matching, with allowances
    /// applied first.
    ///
    /// Whole-word is what keeps "egg" from firing on "eggplant" and "beggar";
    /// the allowance list handles the cases where the whole word genuinely is
    /// the term but the meaning is not, like "egg noodles".
    static func contains(
        anyOf terms: [String],
        in text: String,
        allowing allowances: [String]
    ) -> Bool {
        let normalized = normalize(text)

        // An allowance wins outright. "Eggplant parmesan" is not eggs, even
        // though the string starts with one.
        for allowance in allowances where containsPhrase(normalize(allowance), in: normalized) {
            return false
        }

        for term in terms where containsPhrase(normalize(term), in: normalized) {
            return true
        }
        return false
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            // Punctuation becomes a space so "eggs," and "(egg)" still match on
            // word boundaries.
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
    }

    /// Whether a normalized phrase appears in normalized text on word
    /// boundaries. Multi-word terms are matched as a run of whole words.
    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let phraseWords = phrase.split(separator: " ").map(String.init)
        guard !phraseWords.isEmpty else { return false }

        let textWords = text.split(separator: " ").map(String.init)
        guard textWords.count >= phraseWords.count else { return false }

        for start in 0...(textWords.count - phraseWords.count) {
            if Array(textWords[start..<(start + phraseWords.count)]) == phraseWords {
                return true
            }
        }
        return false
    }
}

/// Builds a grocery list from planned meals (MEALS_AND_PREP.md §6).
public enum GroceryListBuilder {

    /// Lines a set of meals needs, consolidated.
    ///
    /// Two meals both wanting onions produce one line with both meals attached,
    /// rather than two lines the user has to notice are the same thing. Amounts
    /// are joined rather than summed — "2" and "a handful" have no sum, and
    /// inventing one would be worse than showing both.
    ///
    /// Pantry staples are skipped: an ingredient the user marked as something
    /// they always have does not belong on a shopping list.
    public static func lines(
        forEntries entries: [MealPlanEntry],
        recipes: [UUID: Recipe],
        existing: [GroceryItem],
        now: Date
    ) -> [GroceryItem] {
        var byKey: [String: GroceryItem] = [:]
        let existingKeys = Set(existing.map { key($0.name) })

        for entry in entries {
            guard let recipeID = entry.recipeID, let recipe = recipes[recipeID] else {
                continue
            }

            for ingredient in recipe.ingredients where !ingredient.isPantryStaple {
                let itemKey = key(ingredient.name)

                // Already on the list — the meal is linked to the existing line
                // by the caller, not duplicated here.
                guard !existingKeys.contains(itemKey) else { continue }

                if var accumulated = byKey[itemKey] {
                    accumulated.linkedEntryIDs.append(entry.id)
                    accumulated.amount = joinAmounts(accumulated.amount, ingredient.amount)
                    byKey[itemKey] = accumulated
                } else {
                    byKey[itemKey] = GroceryItem(
                        name: ingredient.name,
                        amount: ingredient.amount,
                        category: ingredient.category,
                        linkedEntryIDs: [entry.id],
                        createdAt: now
                    )
                }
            }
        }

        return byKey.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Groups a list the way someone walks a shop, purchased items last within
    /// each group so the list does not reshuffle as it is worked through.
    public static func grouped(
        _ items: [GroceryItem]
    ) -> [(category: GroceryCategory, items: [GroceryItem])] {
        GroceryCategory.allCases.compactMap { category in
            let scoped = items
                .filter { $0.category == category }
                .sorted { lhs, rhs in
                    if lhs.isPurchased != rhs.isPurchased { return !lhs.isPurchased }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            return scoped.isEmpty ? nil : (category, scoped)
        }
    }

    /// Lines that look like the same thing, grouped.
    ///
    /// Surfaced with a merge offered, rather than merged automatically: the two
    /// might be deliberate.
    public static func duplicateGroups(in items: [GroceryItem]) -> [[GroceryItem]] {
        Dictionary(grouping: items) { key($0.name) }
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.createdAt < $1.createdAt } }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
    }

    /// Merges a duplicate group into its earliest line, keeping every link and
    /// both amounts.
    public static func merge(_ group: [GroceryItem]) -> GroceryItem? {
        guard var first = group.first else { return nil }
        for other in group.dropFirst() {
            first.linkedEntryIDs.append(contentsOf: other.linkedEntryIDs)
            first.amount = joinAmounts(first.amount, other.amount)
            // If any copy was bought, the thing is in the house.
            first.isPurchased = first.isPurchased || other.isPurchased
        }
        first.linkedEntryIDs = Array(Set(first.linkedEntryIDs))
        return first
    }

    /// Turns a bought line into a pantry item.
    public static func pantryItem(from item: GroceryItem, now: Date) -> PantryItem {
        PantryItem(
            name: item.name,
            amount: item.amount,
            category: item.category,
            purchasedOn: now,
            createdAt: now,
            modifiedAt: now
        )
    }

    private static func joinAmounts(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case let (l?, r?):
            // "2" and "a handful" have no sum. Both are shown; the user decides.
            l == r ? l : "\(l) + \(r)"
        case let (l?, nil): l
        case let (nil, r?): r
        case (nil, nil): nil
        }
    }

    private static func key(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
