import Foundation

/// What kind of day a meal is planned for (MEALS_AND_PREP.md §3).
///
/// Context changes what is suggested and when prep makes sense — a travel day
/// wants portable food prepared the night before, a recovery day wants something
/// with no work in it at all.
public enum DayContext: String, Hashable, Sendable, Codable, CaseIterable {
    case home
    case work
    case travel
    case layover
    case recovery
    case custom

    public var localizationKey: String { "meals.context.\(rawValue)" }

    /// Whether food for this day needs to travel. Drives the portability
    /// suggestions and the packed-food section.
    public var needsPortableFood: Bool {
        self == .travel || self == .layover || self == .work
    }
}

public enum MealSlot: String, Hashable, Sendable, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case custom

    public var localizationKey: String { "meals.slot.\(rawValue)" }

    /// Display order. Snacks last, because they sit alongside the others rather
    /// than at a time.
    public var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        case .custom: 4
        }
    }
}

/// How well a meal travels (MEALS_AND_PREP.md §9).
///
/// **Entered by the creator or the user — never inferred.** The app does not
/// know how long food keeps, and every value here is somebody's judgement rather
/// than a measurement.
public enum Portability: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case workable
    case awkward
    case stayHome

    public var localizationKey: String { "meals.portability.\(rawValue)" }

    public var travelsWell: Bool { self == .easy || self == .workable }
}

public enum MessLevel: String, Hashable, Sendable, Codable, CaseIterable {
    case tidy
    case someMess
    case messy

    public var localizationKey: String { "meals.mess.\(rawValue)" }
}

/// One ingredient line.
///
/// Quantity and unit are free text on purpose: "a splash", "2 handfuls", and
/// "300g" are all things people write, and a structured amount would reject two
/// of them.
public struct Ingredient: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amount: String?
    /// Which aisle it belongs to, so the grocery list groups sensibly.
    public var category: GroceryCategory
    /// The user can mark a line as something they always have in.
    public var isPantryStaple: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        amount: String? = nil,
        category: GroceryCategory = .other,
        isPantryStaple: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
        self.isPantryStaple = isPantryStaple
    }
}

/// A recipe (MEALS_AND_PREP.md §5).
public struct Recipe: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var ingredients: [Ingredient]
    public var steps: [String]
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var servings: Int?
    public var storageNotes: String?
    public var keepsRefrigerated: Bool
    public var freezes: Bool
    public var portability: Portability
    public var messLevel: MessLevel
    public var containerNote: String?
    /// How long the *user or creator* thinks it keeps, in hours. Carries no
    /// safety guarantee and the copy around it must say so
    /// (MEALS_AND_PREP.md §9).
    public var estimatedKeepsHours: Int?
    public var tags: [String]
    public var isFavorite: Bool
    public var notes: String?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        ingredients: [Ingredient] = [],
        steps: [String] = [],
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        servings: Int? = nil,
        storageNotes: String? = nil,
        keepsRefrigerated: Bool = false,
        freezes: Bool = false,
        portability: Portability = .workable,
        messLevel: MessLevel = .tidy,
        containerNote: String? = nil,
        estimatedKeepsHours: Int? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        notes: String? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.servings = servings
        self.storageNotes = storageNotes
        self.keepsRefrigerated = keepsRefrigerated
        self.freezes = freezes
        self.portability = portability
        self.messLevel = messLevel
        self.containerNote = containerNote
        self.estimatedKeepsHours = estimatedKeepsHours
        self.tags = tags
        self.isFavorite = isFavorite
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Total hands-on plus cooking time, when both are known.
    public var totalMinutes: Int? {
        switch (prepMinutes, cookMinutes) {
        case let (p?, c?): p + c
        case let (p?, nil): p
        case let (nil, c?): c
        case (nil, nil): nil
        }
    }

    public var mediaOwner: MediaOwner { .meal(id) }
}

/// One planned meal on one day (MEALS_AND_PREP.md §4).
public struct MealPlanEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Start of the day it is planned for, in the user's zone.
    public var date: Date
    public var slot: MealSlot
    public var context: DayContext
    /// Either a saved recipe or a one-off name. Both are normal.
    public var recipeID: UUID?
    public var customTitle: String?
    public var prepAt: Date?
    public var isPacked: Bool
    public var needsRefrigeration: Bool
    public var tripID: UUID?
    public var notes: String?
    public var isPrepared: Bool
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        slot: MealSlot,
        context: DayContext = .home,
        recipeID: UUID? = nil,
        customTitle: String? = nil,
        prepAt: Date? = nil,
        isPacked: Bool = false,
        needsRefrigeration: Bool = false,
        tripID: UUID? = nil,
        notes: String? = nil,
        isPrepared: Bool = false,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.context = context
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

    /// A slot with neither a recipe nor a name is an empty slot, not a meal.
    public var isPlanned: Bool {
        recipeID != nil
            || !(customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Where an item sits in a shop, so the list groups the way someone walks
/// (MEALS_AND_PREP.md §6).
public enum GroceryCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case produce
    case dairy
    case bakery
    case meatAndFish
    case frozen
    case pantry
    case drinks
    case household
    case other

    public var localizationKey: String { "grocery.category.\(rawValue)" }
}

public struct GroceryItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amount: String?
    public var category: GroceryCategory
    public var isPurchased: Bool
    /// Meals this line came from, so the list can answer "why is this here?".
    public var linkedEntryIDs: [UUID]
    /// True when the user typed it rather than it arriving from a meal.
    public var isManual: Bool
    public var notes: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        amount: String? = nil,
        category: GroceryCategory = .other,
        isPurchased: Bool = false,
        linkedEntryIDs: [UUID] = [],
        isManual: Bool = false,
        notes: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
        self.isPurchased = isPurchased
        self.linkedEntryIDs = linkedEntryIDs
        self.isManual = isManual
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Something in the cupboard or fridge (MEALS_AND_PREP.md §7).
///
/// **Dates are the user's own and mean only what they wrote.** The app may
/// suggest using something sooner rather than later; it must never assert that
/// anything is safe or unsafe to eat from a date alone.
public struct PantryItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amount: String?
    public var category: GroceryCategory
    public var purchasedOn: Date?
    public var openedOn: Date?
    /// Whatever the user read off the packet.
    public var bestBefore: Date?
    public var storageLocation: String?
    /// Marked by the user as something to eat before they go away.
    public var useBeforeTrip: Bool
    public var linkedRecipeIDs: [UUID]
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        amount: String? = nil,
        category: GroceryCategory = .other,
        purchasedOn: Date? = nil,
        openedOn: Date? = nil,
        bestBefore: Date? = nil,
        storageLocation: String? = nil,
        useBeforeTrip: Bool = false,
        linkedRecipeIDs: [UUID] = [],
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
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

/// A batch-prep task (MEALS_AND_PREP.md §8).
public struct PrepTask: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var scheduledFor: Date?
    public var entryIDs: [UUID]
    public var tripID: UUID?
    public var isDone: Bool
    public var estimatedMinutes: Int?
    public var notes: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        scheduledFor: Date? = nil,
        entryIDs: [UUID] = [],
        tripID: UUID? = nil,
        isDone: Bool = false,
        estimatedMinutes: Int? = nil,
        notes: String? = nil,
        createdAt: Date
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

/// A named kitchen timer (MEALS_AND_PREP.md §11).
///
/// Stored as an end instant rather than a remaining duration, so it survives the
/// app being backgrounded, killed, or the device restarting — a countdown held
/// in memory is wrong the moment anything interrupts it.
public struct KitchenTimer: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var endsAt: Date
    public var totalSeconds: Int
    public var isFinished: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        endsAt: Date,
        totalSeconds: Int,
        isFinished: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endsAt = endsAt
        self.totalSeconds = max(1, totalSeconds)
        self.isFinished = isFinished
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    public func hasElapsed(at now: Date) -> Bool {
        now >= endsAt
    }

    public func progress(at now: Date) -> Double {
        let elapsed = Double(totalSeconds) - remaining(at: now)
        return min(1, max(0, elapsed / Double(totalSeconds)))
    }
}
