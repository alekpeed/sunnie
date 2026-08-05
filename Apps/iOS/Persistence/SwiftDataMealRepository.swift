import Foundation
import SwiftData
import SunnieShared

/// Recipes, meal plans, grocery, pantry, prep, and timers.
///
/// Same `@ModelActor` discipline as the other repositories (ADR-011).
@ModelActor
actor SwiftDataMealRepository: MealRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    // MARK: - Recipes

    func recipes() async throws -> [Recipe] {
        let descriptor = FetchDescriptor<SDRecipe>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            log.error("Fetching recipes failed.")
            throw DomainError.persistenceFailed(operation: "recipes")
        }
    }

    func recipe(id: UUID) async throws -> Recipe? {
        var descriptor = FetchDescriptor<SDRecipe>(
            predicate: #Predicate<SDRecipe> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ recipe: Recipe) async throws {
        let id = recipe.id
        var descriptor = FetchDescriptor<SDRecipe>(
            predicate: #Predicate<SDRecipe> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(recipe, to: existing)
            } else {
                let model = SDRecipe()
                ModelMapping.apply(recipe, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveRecipe")
        }
    }

    /// Deleting a recipe unlinks the plan entries that used it rather than
    /// deleting them. "Thursday: that pasta thing" is still a plan for Thursday
    /// even after the recipe is gone.
    func deleteRecipe(id: UUID) async throws {
        do {
            for entry in try modelContext.fetch(FetchDescriptor<SDMealPlanEntry>(
                predicate: #Predicate<SDMealPlanEntry> { $0.recipeID == id }
            )) {
                entry.recipeID = nil
            }
            var descriptor = FetchDescriptor<SDRecipe>(
                predicate: #Predicate<SDRecipe> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteRecipe")
        }
    }

    // MARK: - Plan entries

    func entries(forDay day: Date) async throws -> [MealPlanEntry] {
        let descriptor = FetchDescriptor<SDMealPlanEntry>(
            predicate: #Predicate<SDMealPlanEntry> { $0.date == day }
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "entriesForDay")
        }
    }

    func entries(from start: Date, to end: Date) async throws -> [MealPlanEntry] {
        let descriptor = FetchDescriptor<SDMealPlanEntry>(
            predicate: #Predicate<SDMealPlanEntry> { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "entriesInRange")
        }
    }

    func entry(id: UUID) async throws -> MealPlanEntry? {
        var descriptor = FetchDescriptor<SDMealPlanEntry>(
            predicate: #Predicate<SDMealPlanEntry> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ entry: MealPlanEntry) async throws {
        let id = entry.id
        var descriptor = FetchDescriptor<SDMealPlanEntry>(
            predicate: #Predicate<SDMealPlanEntry> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(entry, to: existing)
            } else {
                let model = SDMealPlanEntry()
                ModelMapping.apply(entry, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveMealEntry")
        }
    }

    func deleteEntry(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDMealPlanEntry>(
                predicate: #Predicate<SDMealPlanEntry> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteMealEntry")
        }
    }

    // MARK: - Grocery

    func groceryItems() async throws -> [GroceryItem] {
        let descriptor = FetchDescriptor<SDGroceryItem>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "groceryItems")
        }
    }

    func save(_ item: GroceryItem) async throws {
        let id = item.id
        var descriptor = FetchDescriptor<SDGroceryItem>(
            predicate: #Predicate<SDGroceryItem> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(item, to: existing)
            } else {
                let model = SDGroceryItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveGroceryItem")
        }
    }

    /// One transaction for a whole generated list, so it is either added or not.
    func saveGroceryItems(_ items: [GroceryItem]) async throws {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                let model = SDGroceryItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveGroceryItems")
        }
    }

    func deleteGroceryItem(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDGroceryItem>(
                predicate: #Predicate<SDGroceryItem> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteGroceryItem")
        }
    }

    // MARK: - Pantry

    func pantryItems() async throws -> [PantryItem] {
        let descriptor = FetchDescriptor<SDPantryItem>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "pantryItems")
        }
    }

    func pantryItem(id: UUID) async throws -> PantryItem? {
        var descriptor = FetchDescriptor<SDPantryItem>(
            predicate: #Predicate<SDPantryItem> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ item: PantryItem) async throws {
        let id = item.id
        var descriptor = FetchDescriptor<SDPantryItem>(
            predicate: #Predicate<SDPantryItem> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(item, to: existing)
            } else {
                let model = SDPantryItem()
                ModelMapping.apply(item, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePantryItem")
        }
    }

    func deletePantryItem(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDPantryItem>(
                predicate: #Predicate<SDPantryItem> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deletePantryItem")
        }
    }

    // MARK: - Prep and timers

    func prepTasks() async throws -> [PrepTask] {
        let descriptor = FetchDescriptor<SDPrepTask>(
            sortBy: [SortDescriptor(\.scheduledFor, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "prepTasks")
        }
    }

    func save(_ task: PrepTask) async throws {
        let id = task.id
        var descriptor = FetchDescriptor<SDPrepTask>(
            predicate: #Predicate<SDPrepTask> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(task, to: existing)
            } else {
                let model = SDPrepTask()
                ModelMapping.apply(task, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "savePrepTask")
        }
    }

    func deletePrepTask(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDPrepTask>(
                predicate: #Predicate<SDPrepTask> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deletePrepTask")
        }
    }

    func timers() async throws -> [KitchenTimer] {
        let descriptor = FetchDescriptor<SDKitchenTimer>(
            sortBy: [SortDescriptor(\.endsAt, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "timers")
        }
    }

    func save(_ timer: KitchenTimer) async throws {
        let id = timer.id
        var descriptor = FetchDescriptor<SDKitchenTimer>(
            predicate: #Predicate<SDKitchenTimer> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(timer, to: existing)
            } else {
                let model = SDKitchenTimer()
                ModelMapping.apply(timer, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveTimer")
        }
    }

    func deleteTimer(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDKitchenTimer>(
                predicate: #Predicate<SDKitchenTimer> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteTimer")
        }
    }
}
