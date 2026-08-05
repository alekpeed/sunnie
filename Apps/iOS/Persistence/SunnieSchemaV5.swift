import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 5 — meals.
///
/// **Additive, like V2 through V4.** Recipes, plan entries, grocery, pantry,
/// prep tasks, and timers are all new models; nothing existing changes shape.
///
/// Four additive versions in a row is a streak, not a policy. The namespace
/// freeze described in ADR-017 is still owed the moment an existing model's
/// shape has to change, and each phase that dodges it makes the eventual job
/// slightly larger.
enum SunnieSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SunnieSchemaV4.models + [
            SDRecipe.self,
            SDMealPlanEntry.self,
            SDGroceryItem.self,
            SDPantryItem.self,
            SDPrepTask.self,
            SDKitchenTimer.self
        ]
    }
}

/// A recipe.
///
/// Ingredients and steps are stored as encoded blobs rather than child tables:
/// they are read and written whole with the recipe, never queried individually,
/// and a blob keeps the churn out of the migration path — the same reasoning as
/// `SDUserPreferences` and `SDPackingTemplate`.
@Model
final class SDRecipe {
    var id: UUID = UUID()
    var title: String = ""
    var encodedIngredients: Data = Data()
    var steps: [String] = []
    var prepMinutes: Int?
    var cookMinutes: Int?
    var servings: Int?
    var storageNotes: String?
    var keepsRefrigerated: Bool = false
    var freezes: Bool = false
    var portabilityRaw: String = Portability.workable.rawValue
    var messLevelRaw: String = MessLevel.tidy.rawValue
    var containerNote: String?
    /// The user's or creator's estimate. Carries no safety guarantee, and the
    /// copy around it says so (MEALS_AND_PREP.md §9).
    var estimatedKeepsHours: Int?
    var tags: [String] = []
    var isFavorite: Bool = false
    var notes: String?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "",
        encodedIngredients: Data = Data(),
        steps: [String] = [],
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        servings: Int? = nil,
        storageNotes: String? = nil,
        keepsRefrigerated: Bool = false,
        freezes: Bool = false,
        portabilityRaw: String = Portability.workable.rawValue,
        messLevelRaw: String = MessLevel.tidy.rawValue,
        containerNote: String? = nil,
        estimatedKeepsHours: Int? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.encodedIngredients = encodedIngredients
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.servings = servings
        self.storageNotes = storageNotes
        self.keepsRefrigerated = keepsRefrigerated
        self.freezes = freezes
        self.portabilityRaw = portabilityRaw
        self.messLevelRaw = messLevelRaw
        self.containerNote = containerNote
        self.estimatedKeepsHours = estimatedKeepsHours
        self.tags = tags
        self.isFavorite = isFavorite
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDMealPlanEntry {
    var id: UUID = UUID()
    /// Start of the planned day in the user's zone, so a day's meals group
    /// without a range query.
    var date: Date = Date()
    var slotRaw: String = MealSlot.dinner.rawValue
    var contextRaw: String = DayContext.home.rawValue
    var recipeID: UUID?
    var customTitle: String?
    var prepAt: Date?
    var isPacked: Bool = false
    var needsRefrigeration: Bool = false
    var tripID: UUID?
    var notes: String?
    var isPrepared: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        slotRaw: String = MealSlot.dinner.rawValue,
        contextRaw: String = DayContext.home.rawValue,
        recipeID: UUID? = nil,
        customTitle: String? = nil,
        prepAt: Date? = nil,
        isPacked: Bool = false,
        needsRefrigeration: Bool = false,
        tripID: UUID? = nil,
        notes: String? = nil,
        isPrepared: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.slotRaw = slotRaw
        self.contextRaw = contextRaw
        self.recipeID = recipeID
        self.customTitle = customTitle
        self.prepAt = prepAt
        self.isPacked = isPacked
        self.needsRefrigeration = needsRefrigeration
        self.tripID = tripID
        self.notes = notes
        self.isPrepared = isPrepared
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDGroceryItem {
    var id: UUID = UUID()
    var name: String = ""
    var amount: String?
    var categoryRaw: String = GroceryCategory.other.rawValue
    var isPurchased: Bool = false
    var linkedEntryIDs: [UUID] = []
    var isManual: Bool = false
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        amount: String? = nil,
        categoryRaw: String = GroceryCategory.other.rawValue,
        isPurchased: Bool = false,
        linkedEntryIDs: [UUID] = [],
        isManual: Bool = false,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryRaw = categoryRaw
        self.isPurchased = isPurchased
        self.linkedEntryIDs = linkedEntryIDs
        self.isManual = isManual
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Something in the cupboard.
///
/// Every date here was typed by the user off a packet. Nothing derives food
/// safety from them, and nothing may (MEALS_AND_PREP.md §7).
@Model
final class SDPantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var amount: String?
    var categoryRaw: String = GroceryCategory.other.rawValue
    var purchasedOn: Date?
    var openedOn: Date?
    var bestBefore: Date?
    var storageLocation: String?
    var useBeforeTrip: Bool = false
    var linkedRecipeIDs: [UUID] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        amount: String? = nil,
        categoryRaw: String = GroceryCategory.other.rawValue,
        purchasedOn: Date? = nil,
        openedOn: Date? = nil,
        bestBefore: Date? = nil,
        storageLocation: String? = nil,
        useBeforeTrip: Bool = false,
        linkedRecipeIDs: [UUID] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.categoryRaw = categoryRaw
        self.purchasedOn = purchasedOn
        self.openedOn = openedOn
        self.bestBefore = bestBefore
        self.storageLocation = storageLocation
        self.useBeforeTrip = useBeforeTrip
        self.linkedRecipeIDs = linkedRecipeIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SDPrepTask {
    var id: UUID = UUID()
    var title: String = ""
    var scheduledFor: Date?
    var entryIDs: [UUID] = []
    var tripID: UUID?
    var isDone: Bool = false
    var estimatedMinutes: Int?
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "",
        scheduledFor: Date? = nil,
        entryIDs: [UUID] = [],
        tripID: UUID? = nil,
        isDone: Bool = false,
        estimatedMinutes: Int? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.scheduledFor = scheduledFor
        self.entryIDs = entryIDs
        self.tripID = tripID
        self.isDone = isDone
        self.estimatedMinutes = estimatedMinutes
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// A kitchen timer.
///
/// Persisted as an end instant rather than a remaining duration. A countdown
/// held in memory is wrong the moment the app is backgrounded or killed, and a
/// timer that silently loses time is worse than no timer.
@Model
final class SDKitchenTimer {
    var id: UUID = UUID()
    var name: String = ""
    var endsAt: Date = Date()
    var totalSeconds: Int = 60
    var isFinished: Bool = false

    init(
        id: UUID = UUID(),
        name: String = "",
        endsAt: Date = Date(),
        totalSeconds: Int = 60,
        isFinished: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endsAt = endsAt
        self.totalSeconds = totalSeconds
        self.isFinished = isFinished
    }
}
