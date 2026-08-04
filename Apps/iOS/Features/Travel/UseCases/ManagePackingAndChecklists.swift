import Foundation
import SunnieShared

/// Packing lists, templates, and trip checklists
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §6, §7).
///
/// **No checklist here is an official procedure, and none may be presented as
/// one** (§1, §7). These are one person's reminders to themselves. Nothing is
/// enforced, nothing blocks, and an unpacked item is never a failure.
struct ManagePacking: Sendable {

    private let repository: any TravelRepository
    private let clock: any SunnieClock

    init(repository: any TravelRepository, clock: any SunnieClock) {
        self.repository = repository
        self.clock = clock
    }

    // MARK: - Items

    func items(forTripID tripID: UUID) async throws -> [PackingItem] {
        try await repository.packingItems(forTripID: tripID)
    }

    @discardableResult
    func save(_ item: PackingItem) async throws -> PackingItem {
        var cleaned = item
        cleaned.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.notes = tidy(item.notes)
        try await repository.save(cleaned)
        return cleaned
    }

    /// Toggles packed state. Separate from `save` so a tick is one write rather
    /// than a whole-item round trip.
    func setPacked(_ isPacked: Bool, item: PackingItem) async throws {
        var updated = item
        updated.isPacked = isPacked
        try await repository.save(updated)
    }

    func delete(itemID: UUID) async throws {
        try await repository.deletePackingItem(id: itemID)
    }

    /// Applies a template, skipping anything already on the list.
    ///
    /// Returns how many were added, so the UI can say "added 12" rather than
    /// leaving the user to spot the difference. Applying the same template twice
    /// adds nothing the second time, which is what makes it safe to tap when
    /// unsure whether you already did.
    @discardableResult
    func apply(
        template: PackingTemplate,
        toTripID tripID: UUID
    ) async throws -> Int {
        let existing = try await repository.packingItems(forTripID: tripID)
        let added = PackingListBuilder.applying(template, to: existing, tripID: tripID)
        try await repository.savePackingItems(added)
        return added.count
    }

    /// Copies another trip's list, unpacked.
    @discardableResult
    func reuse(
        fromTripID sourceTripID: UUID,
        toTripID tripID: UUID
    ) async throws -> Int {
        let source = try await repository.packingItems(forTripID: sourceTripID)
        let existing = try await repository.packingItems(forTripID: tripID)

        let copied = PackingListBuilder.reusing(source, for: tripID)
        // Filtered through the same duplicate rule as a template, so reusing on
        // top of a partly built list does not double everything.
        let deduplicated = PackingListBuilder.applying(
            PackingTemplate(
                name: "",
                entries: copied.map {
                    PackingTemplate.Entry(
                        name: $0.name,
                        category: $0.category,
                        quantity: $0.quantity,
                        isRequired: $0.isRequired
                    )
                },
                createdAt: clock.now,
                modifiedAt: clock.now
            ),
            to: existing,
            tripID: tripID
        )

        try await repository.savePackingItems(deduplicated)
        return deduplicated.count
    }

    /// Items that look like duplicates. Surfaced, never merged — two things
    /// called "charger" might genuinely be two chargers.
    func duplicates(forTripID tripID: UUID) async throws -> [[PackingItem]] {
        PackingListBuilder.duplicateGroups(
            in: try await repository.packingItems(forTripID: tripID)
        )
    }

    // MARK: - Templates

    func templates() async throws -> [PackingTemplate] {
        try await repository.packingTemplates()
    }

    /// Templates suited to a trip type, the matching ones first.
    func templates(for tripType: TripType) async throws -> [PackingTemplate] {
        try await repository.packingTemplates().sorted { lhs, rhs in
            let lhsMatches = lhs.tripType == tripType
            let rhsMatches = rhs.tripType == tripType
            if lhsMatches != rhsMatches { return lhsMatches }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    func save(_ template: PackingTemplate) async throws -> PackingTemplate {
        var cleaned = template
        cleaned.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.modifiedAt = clock.now
        try await repository.save(cleaned)
        return cleaned
    }

    /// Turns a trip's current list into a reusable template.
    ///
    /// The obvious way to build one: pack for a trip once, then keep the list.
    /// Packed state is not carried over — a template describes what to bring, not
    /// what was brought.
    @discardableResult
    func makeTemplate(
        named name: String,
        fromTripID tripID: UUID,
        tripType: TripType?
    ) async throws -> PackingTemplate {
        let items = try await repository.packingItems(forTripID: tripID)
        let now = clock.now

        let template = PackingTemplate(
            name: name,
            tripType: tripType,
            entries: items.map {
                PackingTemplate.Entry(
                    name: $0.name,
                    category: $0.category,
                    quantity: $0.quantity,
                    isRequired: $0.isRequired
                )
            },
            createdAt: now,
            modifiedAt: now
        )
        return try await save(template)
    }

    func deleteTemplate(id: UUID) async throws {
        try await repository.deletePackingTemplate(id: id)
    }

    /// Seeds the built-in templates on first launch.
    ///
    /// Idempotent by name: running it again adds nothing. The work template is
    /// the flight-attendant one, and it uses **semantic identifiers only** — no
    /// airline is named anywhere in it, because brand assets stay isolated and
    /// replaceable (TRAVEL_AND_FLIGHT_ATTENDANT.md §5).
    func seedBuiltInTemplatesIfNeeded() async throws {
        let existing = try await repository.packingTemplates()
        let existingNames = Set(existing.map { $0.name.lowercased() })
        let now = clock.now

        for builtIn in Self.builtInTemplates(at: now)
        where !existingNames.contains(builtIn.name.lowercased()) {
            try await repository.save(builtIn)
        }
    }

    private static func builtInTemplates(at now: Date) -> [PackingTemplate] {
        func entry(
            _ key: String,
            _ fallback: String,
            _ category: PackingCategory,
            required: Bool = false,
            quantity: Int = 1
        ) -> PackingTemplate.Entry {
            PackingTemplate.Entry(
                name: String(localized: .init(key), defaultValue: .init(fallback)),
                category: category,
                quantity: quantity,
                isRequired: required
            )
        }

        return [
            PackingTemplate(
                name: String(
                    localized: "packing.template.work",
                    defaultValue: "Work trip",
                    comment: "Built-in packing template for a work trip"
                ),
                tripType: .work,
                entries: [
                    entry("packing.item.uniform", "Uniform", .uniform, required: true),
                    entry("packing.item.shoes", "Work shoes", .uniform, required: true),
                    entry("packing.item.badge", "ID and badge", .documents, required: true),
                    entry("packing.item.passport", "Passport", .documents, required: true),
                    entry("packing.item.charger", "Phone charger", .technology, required: true),
                    entry("packing.item.headphones", "Headphones", .technology),
                    entry("packing.item.toiletries", "Toiletries", .toiletries),
                    entry("packing.item.waterBottle", "Water bottle", .food),
                    entry("packing.item.snacks", "Snacks", .food),
                    entry("packing.item.comfortClothes", "Something comfortable", .personal)
                ],
                isBuiltIn: true,
                createdAt: now,
                modifiedAt: now
            ),
            PackingTemplate(
                name: String(
                    localized: "packing.template.personal",
                    defaultValue: "Away for a few days",
                    comment: "Built-in packing template for a personal trip"
                ),
                tripType: .personal,
                entries: [
                    entry("packing.item.clothes", "Clothes", .personal),
                    entry("packing.item.toiletries", "Toiletries", .toiletries),
                    entry("packing.item.charger", "Phone charger", .technology, required: true),
                    entry("packing.item.medication", "Anything you take daily", .personal, required: true),
                    entry("packing.item.snacks", "Snacks", .food)
                ],
                isBuiltIn: true,
                createdAt: now,
                modifiedAt: now
            )
        ]
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// Departure and return checklists (TRAVEL_AND_FLIGHT_ATTENDANT.md §7).
///
/// **No safety-critical checklist is represented as official airline procedure**
/// (§7). These are personal reminders — lock the door, water the plants, take the
/// bins out — and the copy stays in that register throughout.
struct ManageChecklists: Sendable {

    private let repository: any TravelRepository
    private let clock: any SunnieClock

    init(repository: any TravelRepository, clock: any SunnieClock) {
        self.repository = repository
        self.clock = clock
    }

    func items(forTripID tripID: UUID) async throws -> [ChecklistItem] {
        try await repository.checklistItems(forTripID: tripID)
    }

    func items(
        forTripID tripID: UUID,
        phase: ChecklistKind.Phase
    ) async throws -> [ChecklistItem] {
        try await repository.checklistItems(forTripID: tripID)
            .filter { $0.kind.phase == phase }
    }

    @discardableResult
    func save(_ item: ChecklistItem) async throws -> ChecklistItem {
        var cleaned = item
        cleaned.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }
        cleaned.notes = tidy(item.notes)
        try await repository.save(cleaned)
        return cleaned
    }

    func setDone(_ isDone: Bool, item: ChecklistItem) async throws {
        var updated = item
        updated.isDone = isDone
        try await repository.save(updated)
    }

    func delete(itemID: UUID) async throws {
        try await repository.deleteChecklistItem(id: itemID)
    }

    /// Creates the default checklists for a trip, once.
    ///
    /// Idempotent: a trip that already has checklist items gets nothing added, so
    /// this can run whenever the trip screen opens without accumulating
    /// duplicates.
    ///
    /// The plant line carries a route, so ticking it opens the coverage screen
    /// rather than asking the user to remember what "plants" meant.
    @discardableResult
    func seedDefaultsIfNeeded(
        tripID: UUID,
        tripType: TripType
    ) async throws -> Int {
        let existing = try await repository.checklistItems(forTripID: tripID)
        guard existing.isEmpty else { return 0 }

        var items: [ChecklistItem] = []
        var order = 0

        func add(
            _ kind: ChecklistKind,
            _ key: String,
            _ fallback: String,
            route: String? = nil
        ) {
            items.append(ChecklistItem(
                tripID: tripID,
                kind: kind,
                title: String(localized: .init(key), defaultValue: .init(fallback)),
                linkedRoute: route,
                sortOrder: order
            ))
            order += 1
        }

        add(.beforeLeaving, "checklist.default.documents", "Documents and passport")
        add(.beforeLeaving, "checklist.default.chargers", "Chargers packed")
        add(
            .beforeLeaving, "checklist.default.plants", "Plants sorted",
            route: "sunniedays://trip/\(tripID.uuidString)"
        )
        add(.beforeLeaving, "checklist.default.perishables", "Perishables and bins")
        add(.beforeLeaving, "checklist.default.home", "Windows, doors, heating")

        if tripType.isWork {
            add(.beforeLeaving, "checklist.default.uniform", "Uniform ready")
            add(.airport, "checklist.default.food", "Food packed")
        }

        add(.returnHome, "checklist.default.unpack", "Unpack")
        add(.returnHome, "checklist.default.laundry", "Laundry on")
        add(.returnHome, "checklist.default.groceries", "Something in for tomorrow")
        add(
            .returnHome, "checklist.default.plantReview", "Look the plants over",
            route: "sunniedays://jungle/due"
        )
        add(.recovery, "checklist.default.rest", "A slow evening")

        try await repository.saveChecklistItems(items)
        return items.count
    }

    private func tidy(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
