import Foundation
import SunnieShared

/// Mapping for the models added in schema V5.
extension ModelMapping {

    // MARK: - Recipes

    static func domain(_ model: SDRecipe) -> Recipe {
        // Undecodable ingredients come back empty rather than dropping the
        // recipe: the user keeps a titled recipe they can refill, which beats
        // one that silently vanished.
        let ingredients = (try? JSONDecoder().decode(
            [Ingredient].self, from: model.encodedIngredients
        )) ?? []

        return Recipe(
            id: model.id,
            title: model.title,
            ingredients: ingredients,
            steps: model.steps,
            prepMinutes: model.prepMinutes,
            cookMinutes: model.cookMinutes,
            servings: model.servings,
            storageNotes: model.storageNotes,
            keepsRefrigerated: model.keepsRefrigerated,
            freezes: model.freezes,
            // An unknown portability reads as `stayHome` — the conservative end.
            // Suggesting a recipe as portable when the value could not be read
            // would be the app asserting something it does not know.
            portability: Portability(rawValue: model.portabilityRaw) ?? .stayHome,
            messLevel: MessLevel(rawValue: model.messLevelRaw) ?? .tidy,
            containerNote: model.containerNote,
            estimatedKeepsHours: model.estimatedKeepsHours,
            tags: model.tags,
            isFavorite: model.isFavorite,
            notes: model.notes,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ recipe: Recipe, to model: SDRecipe) {
        model.id = recipe.id
        model.title = recipe.title
        model.encodedIngredients = (try? JSONEncoder().encode(recipe.ingredients)) ?? Data()
        model.steps = recipe.steps
        model.prepMinutes = recipe.prepMinutes
        model.cookMinutes = recipe.cookMinutes
        model.servings = recipe.servings
        model.storageNotes = recipe.storageNotes
        model.keepsRefrigerated = recipe.keepsRefrigerated
        model.freezes = recipe.freezes
        model.portabilityRaw = recipe.portability.rawValue
        model.messLevelRaw = recipe.messLevel.rawValue
        model.containerNote = recipe.containerNote
        model.estimatedKeepsHours = recipe.estimatedKeepsHours
        model.tags = recipe.tags
        model.isFavorite = recipe.isFavorite
        model.notes = recipe.notes
        model.createdAt = recipe.createdAt
        model.modifiedAt = recipe.modifiedAt
    }

    // MARK: - Plan entries

    static func domain(_ model: SDMealPlanEntry) -> MealPlanEntry {
        MealPlanEntry(
            id: model.id,
            date: model.date,
            slot: MealSlot(rawValue: model.slotRaw) ?? .custom,
            context: DayContext(rawValue: model.contextRaw) ?? .custom,
            recipeID: model.recipeID,
            customTitle: model.customTitle,
            prepAt: model.prepAt,
            isPacked: model.isPacked,
            needsRefrigeration: model.needsRefrigeration,
            tripID: model.tripID,
            notes: model.notes,
            isPrepared: model.isPrepared,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ entry: MealPlanEntry, to model: SDMealPlanEntry) {
        model.id = entry.id
        model.date = entry.date
        model.slotRaw = entry.slot.rawValue
        model.contextRaw = entry.context.rawValue
        model.recipeID = entry.recipeID
        model.customTitle = entry.customTitle
        model.prepAt = entry.prepAt
        model.isPacked = entry.isPacked
        model.needsRefrigeration = entry.needsRefrigeration
        model.tripID = entry.tripID
        model.notes = entry.notes
        model.isPrepared = entry.isPrepared
        model.createdAt = entry.createdAt
        model.modifiedAt = entry.modifiedAt
    }

    // MARK: - Grocery

    static func domain(_ model: SDGroceryItem) -> GroceryItem {
        GroceryItem(
            id: model.id,
            name: model.name,
            amount: model.amount,
            category: GroceryCategory(rawValue: model.categoryRaw) ?? .other,
            isPurchased: model.isPurchased,
            linkedEntryIDs: model.linkedEntryIDs,
            isManual: model.isManual,
            notes: model.notes,
            createdAt: model.createdAt
        )
    }

    static func apply(_ item: GroceryItem, to model: SDGroceryItem) {
        model.id = item.id
        model.name = item.name
        model.amount = item.amount
        model.categoryRaw = item.category.rawValue
        model.isPurchased = item.isPurchased
        model.linkedEntryIDs = item.linkedEntryIDs
        model.isManual = item.isManual
        model.notes = item.notes
        model.createdAt = item.createdAt
    }

    // MARK: - Pantry

    static func domain(_ model: SDPantryItem) -> PantryItem {
        PantryItem(
            id: model.id,
            name: model.name,
            amount: model.amount,
            category: GroceryCategory(rawValue: model.categoryRaw) ?? .other,
            purchasedOn: model.purchasedOn,
            openedOn: model.openedOn,
            bestBefore: model.bestBefore,
            storageLocation: model.storageLocation,
            useBeforeTrip: model.useBeforeTrip,
            linkedRecipeIDs: model.linkedRecipeIDs,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func apply(_ item: PantryItem, to model: SDPantryItem) {
        model.id = item.id
        model.name = item.name
        model.amount = item.amount
        model.categoryRaw = item.category.rawValue
        model.purchasedOn = item.purchasedOn
        model.openedOn = item.openedOn
        model.bestBefore = item.bestBefore
        model.storageLocation = item.storageLocation
        model.useBeforeTrip = item.useBeforeTrip
        model.linkedRecipeIDs = item.linkedRecipeIDs
        model.createdAt = item.createdAt
        model.modifiedAt = item.modifiedAt
    }

    // MARK: - Prep and timers

    static func domain(_ model: SDPrepTask) -> PrepTask {
        PrepTask(
            id: model.id,
            title: model.title,
            scheduledFor: model.scheduledFor,
            entryIDs: model.entryIDs,
            tripID: model.tripID,
            isDone: model.isDone,
            estimatedMinutes: model.estimatedMinutes,
            notes: model.notes,
            createdAt: model.createdAt
        )
    }

    static func apply(_ task: PrepTask, to model: SDPrepTask) {
        model.id = task.id
        model.title = task.title
        model.scheduledFor = task.scheduledFor
        model.entryIDs = task.entryIDs
        model.tripID = task.tripID
        model.isDone = task.isDone
        model.estimatedMinutes = task.estimatedMinutes
        model.notes = task.notes
        model.createdAt = task.createdAt
    }

    static func domain(_ model: SDKitchenTimer) -> KitchenTimer {
        KitchenTimer(
            id: model.id,
            name: model.name,
            endsAt: model.endsAt,
            totalSeconds: model.totalSeconds,
            isFinished: model.isFinished
        )
    }

    static func apply(_ timer: KitchenTimer, to model: SDKitchenTimer) {
        model.id = timer.id
        model.name = timer.name
        model.endsAt = timer.endsAt
        model.totalSeconds = timer.totalSeconds
        model.isFinished = timer.isFinished
    }
}
