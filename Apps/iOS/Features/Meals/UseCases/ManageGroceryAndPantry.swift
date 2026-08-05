import Foundation
import SunnieShared

/// The grocery list and the pantry (MEALS_AND_PREP.md §6, §7).
///
/// **Nothing here asserts food safety.** Dates are what the user read off a
/// packet, and the app uses them only to order a list. It has no basis for
/// saying anything is safe or unsafe to eat, and the spec forbids it (§7).
struct ManageGrocery: Sendable {

    private let repository: any MealRepository
    private let clock: any SunnieClock

    init(repository: any MealRepository, clock: any SunnieClock) {
        self.repository = repository
        self.clock = clock
    }

    // MARK: - Grocery

    func items() async throws -> [GroceryItem] {
        try await repository.groceryItems()
    }

    /// Grouped the way someone walks a shop, purchased last within each group.
    func grouped() async throws -> [(category: GroceryCategory, items: [GroceryItem])] {
        GroceryListBuilder.grouped(try await repository.groceryItems())
    }

    @discardableResult
    func add(name: String, category: GroceryCategory, amount: String? = nil) async throws -> GroceryItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        let item = GroceryItem(
            name: trimmed,
            amount: amount,
            category: category,
            isManual: true,
            createdAt: clock.now
        )
        try await repository.save(item)
        return item
    }

    func setPurchased(_ isPurchased: Bool, item: GroceryItem) async throws {
        var updated = item
        updated.isPurchased = isPurchased
        try await repository.save(updated)
    }

    func delete(itemID: UUID) async throws {
        try await repository.deleteGroceryItem(id: itemID)
    }

    /// Adds everything a set of planned meals needs, minus what is already on
    /// the list.
    ///
    /// Returns how many were added, so the UI can say so rather than leaving the
    /// user to spot the difference. Running it twice adds nothing the second
    /// time.
    @discardableResult
    func addFromPlan(from start: Date, to end: Date) async throws -> Int {
        let entries = try await repository.entries(from: start, to: end)
        let recipes = Dictionary(
            uniqueKeysWithValues: try await repository.recipes().map { ($0.id, $0) }
        )
        let existing = try await repository.groceryItems()

        let lines = GroceryListBuilder.lines(
            forEntries: entries,
            recipes: recipes,
            existing: existing,
            now: clock.now
        )
        try await repository.saveGroceryItems(lines)
        return lines.count
    }

    /// Lines that look like the same thing. Surfaced with a merge offered rather
    /// than merged automatically — the two might be deliberate.
    func duplicates() async throws -> [[GroceryItem]] {
        GroceryListBuilder.duplicateGroups(in: try await repository.groceryItems())
    }

    /// Merges a duplicate group into one line, keeping every meal link and both
    /// amounts.
    func merge(_ group: [GroceryItem]) async throws {
        guard let merged = GroceryListBuilder.merge(group) else { return }
        try await repository.save(merged)
        for item in group where item.id != merged.id {
            try await repository.deleteGroceryItem(id: item.id)
        }
    }

    /// Moves bought items into the pantry and clears them off the list.
    ///
    /// The natural end of a shop, and the only place pantry items appear without
    /// being typed.
    @discardableResult
    func movePurchasedToPantry() async throws -> Int {
        let purchased = try await repository.groceryItems().filter(\.isPurchased)
        guard !purchased.isEmpty else { return 0 }

        for item in purchased {
            try await repository.save(
                GroceryListBuilder.pantryItem(from: item, now: clock.now)
            )
            try await repository.deleteGroceryItem(id: item.id)
        }
        return purchased.count
    }

    // MARK: - Pantry

    func pantryItems() async throws -> [PantryItem] {
        try await repository.pantryItems()
    }

    /// Items marked to use before a trip, soonest date first.
    ///
    /// The ordering uses `bestBefore` where there is one. That is an ordering and
    /// nothing more — the app is not saying anything has gone off.
    func useBeforeTrip() async throws -> [PantryItem] {
        try await repository.pantryItems()
            .filter(\.useBeforeTrip)
            .sorted { lhs, rhs in
                switch (lhs.bestBefore, rhs.bestBefore) {
                case let (l?, r?): l < r
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil):
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    func newPantryItem() -> PantryItem {
        let now = clock.now
        return PantryItem(name: "", createdAt: now, modifiedAt: now)
    }

    @discardableResult
    func save(_ item: PantryItem) async throws -> PantryItem {
        var cleaned = item
        cleaned.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.storageLocation = tidy(item.storageLocation)
        cleaned.modifiedAt = clock.now
        try await repository.save(cleaned)
        return cleaned
    }

    func deletePantryItem(id: UUID) async throws {
        try await repository.deletePantryItem(id: id)
    }

    /// Marks a batch to use before a trip, so someone can sweep the fridge in
    /// one pass rather than editing each item.
    func setUseBeforeTrip(_ useBeforeTrip: Bool, itemIDs: Set<UUID>) async throws {
        for var item in try await repository.pantryItems() where itemIDs.contains(item.id) {
            item.useBeforeTrip = useBeforeTrip
            item.modifiedAt = clock.now
            try await repository.save(item)
        }
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// Batch prep and kitchen timers (MEALS_AND_PREP.md §8, §11).
struct ManagePrep: Sendable {

    private let repository: any MealRepository
    private let notifications: any NotificationScheduling
    private let progressionEngine: ProgressionEngine
    private let clock: any SunnieClock

    private var log: SunnieLog { SunnieLog(category: .notifications) }

    init(
        repository: any MealRepository,
        notifications: any NotificationScheduling,
        progressionEngine: ProgressionEngine,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.notifications = notifications
        self.progressionEngine = progressionEngine
        self.clock = clock
    }

    // MARK: - Prep tasks

    func tasks() async throws -> [PrepTask] {
        try await repository.prepTasks()
    }

    func openTasks() async throws -> [PrepTask] {
        try await repository.prepTasks().filter { !$0.isDone }
    }

    @discardableResult
    func save(_ task: PrepTask) async throws -> PrepTask {
        var cleaned = task
        cleaned.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.notes = tidy(task.notes)
        try await repository.save(cleaned)
        return cleaned
    }

    func setDone(_ isDone: Bool, task: PrepTask) async throws {
        var updated = task
        updated.isDone = isDone
        try await repository.save(updated)

        guard isDone else { return }

        // Marking the meals prepared too, so the plan and the prep list agree
        // without the user having to tick both.
        for entryID in task.entryIDs {
            guard var entry = try await repository.entry(id: entryID) else { continue }
            entry.isPrepared = true
            entry.modifiedAt = clock.now
            try await repository.save(entry)
        }

        _ = try? await progressionEngine.award(
            type: .mealPrepCompleted,
            sourceEntityID: task.id,
            occurredAt: clock.now,
            deterministicKey: "mealPrep.\(task.id.uuidString)"
        )
    }

    func delete(taskID: UUID) async throws {
        try await repository.deletePrepTask(id: taskID)
    }

    /// Builds the pre-trip food plan (MEALS_AND_PREP.md §8).
    func preTripPlan(
        departureDate: Date,
        returnDate: Date
    ) async throws -> PreTripFoodPlanner.Plan {
        var calendar = clock.calendar
        calendar.timeZone = clock.timeZone

        return PreTripFoodPlanner.plan(
            departureDate: departureDate,
            returnDate: returnDate,
            pantry: try await repository.pantryItems(),
            entries: try await repository.entries(
                from: calendar.startOfDay(for: departureDate), to: returnDate
            ),
            calendar: calendar
        )
    }

    // MARK: - Timers

    func timers() async throws -> [KitchenTimer] {
        try await repository.timers()
    }

    /// Starts a named timer.
    ///
    /// The end instant is persisted and a local notification is scheduled for it,
    /// so the timer survives the app being backgrounded or killed. A countdown
    /// held only in memory silently loses time, which for a kitchen timer is the
    /// whole failure.
    @discardableResult
    func startTimer(name: String, seconds: Int) async throws -> KitchenTimer {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard seconds > 0 else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        let timer = KitchenTimer(
            name: trimmed.isEmpty
                ? String(
                    localized: "meals.timer.untitled",
                    defaultValue: "Timer",
                    comment: "A timer with no name"
                )
                : trimmed,
            endsAt: clock.now.addingTimeInterval(TimeInterval(seconds)),
            totalSeconds: seconds
        )
        try await repository.save(timer)
        await scheduleNotification(for: timer)
        return timer
    }

    func cancelTimer(_ timer: KitchenTimer) async throws {
        await notifications.cancel(reminderID: timer.id)
        try await repository.deleteTimer(id: timer.id)
    }

    /// Marks elapsed timers finished.
    ///
    /// Called when the meals screen appears. The end instant is the truth, so a
    /// timer that ran out while the app was closed is correctly finished on the
    /// next look rather than still counting down.
    @discardableResult
    func reconcileTimers() async throws -> [KitchenTimer] {
        var finished: [KitchenTimer] = []
        for var timer in try await repository.timers()
        where !timer.isFinished && timer.hasElapsed(at: clock.now) {
            timer.isFinished = true
            try await repository.save(timer)
            finished.append(timer)
        }
        return finished
    }

    /// A local notification so the timer works with the app closed.
    ///
    /// Silent failure: without notification permission the timer still runs and
    /// still shows as finished when the screen is next opened. It just does not
    /// announce itself, which is a smaller loss than a permission prompt the user
    /// did not ask for.
    private func scheduleNotification(for timer: KitchenTimer) async {
        guard await notifications.authorizationStatus() == .authorized else { return }

        try? await notifications.schedule(ScheduledReminderRequest(
            id: timer.id,
            messageID: "sunnie.timer.finished",
            title: timer.name,
            body: String(
                localized: "meals.timer.done",
                defaultValue: "That's time.",
                comment: "Body of a kitchen timer notification"
            ),
            fireDate: timer.endsAt,
            route: "sunniedays://meals",
            // A timer the user set themselves should sound even during quiet
            // hours — they are standing in the kitchen waiting for it.
            respectsQuietHours: false,
            threadIdentifier: "sunnie.timers"
        ))
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
