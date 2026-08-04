import Foundation
import Observation
import SunnieShared

/// Feature model for the plant collection (S-03).
///
/// Holds the whole collection once and filters it in memory. At the sizes this
/// app targets — fifty to a few hundred plants — one fetch plus an in-memory
/// filter is both faster and simpler than re-querying storage on every keystroke,
/// and it makes the filtering itself pure and testable
/// (`PlantCollectionFilter`).
@MainActor
@Observable
final class CollectionModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var allItems: [PlantCollectionItem] = []
    private(set) var locations: [PlantLocation] = []
    private(set) var caretakers: [Caretaker] = []

    /// Persisted between launches, because a filter that resets itself is a
    /// filter the user has to reapply every time (INFORMATION_ARCHITECTURE.md
    /// §14).
    var query: PlantCollectionQuery {
        didSet { persistQuery() }
    }

    /// Multi-select. Empty means selection mode is off, so there is no separate
    /// flag to keep in step with it.
    private(set) var selection: Set<UUID> = []
    var isSelecting: Bool { !selection.isEmpty }

    private let dependencies: AppDependencies
    private static let queryDefaultsKey = "sunnie.collection.query"

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.query = Self.loadQuery()
    }

    /// The filtered, sorted result. Recomputed on demand; `@Observable` tracks
    /// the properties it reads, so changing the query re-renders the list.
    var visibleItems: [PlantCollectionItem] {
        PlantCollectionFilter.apply(
            query,
            to: allItems,
            now: dependencies.clock.now,
            calendar: dependencies.clock.calendar,
            timeZone: dependencies.clock.timeZone
        )
    }

    /// Species present in the collection, for the filter menu. Built from the
    /// data rather than a fixed list, so the menu only ever offers species the
    /// user actually owns.
    var availableSpecies: [String] {
        Set(allItems.compactMap(\.plant.speciesName)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func load() async {
        if state != .loaded { state = .loading }

        do {
            // Archived plants are always fetched; the status filter decides
            // whether they are shown. Re-fetching on a filter change would make
            // toggling "archived" a round trip for no reason.
            async let items = dependencies.plantRepository.collectionItems(includingArchived: true)
            async let locations = dependencies.plantRepository.locations()
            async let caretakers = dependencies.plantHealthRepository.caretakers(includingInactive: false)

            allItems = try await items
            self.locations = try await locations
            self.caretakers = try await caretakers
            state = .loaded
        } catch {
            state = .failed(String(
                localized: "collection.error.load",
                defaultValue: "I couldn't open your collection just now. Nothing has been lost, and you can try again.",
                comment: "Shown when the plant collection cannot be loaded"
            ))
        }
    }

    // MARK: - Selection

    func toggleSelection(_ plantID: UUID) {
        if selection.contains(plantID) {
            selection.remove(plantID)
        } else {
            selection.insert(plantID)
        }
    }

    func selectAllVisible() {
        selection = Set(visibleItems.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    var selectedItems: [PlantCollectionItem] {
        visibleItems.filter { selection.contains($0.id) }
    }

    // MARK: - Filters

    func clearFilters() {
        query = query.clearingFilters()
    }

    func locationName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return locations.first { $0.id == id }?.name
    }

    // MARK: - Query persistence

    /// Stored in user defaults rather than SwiftData: it is a view preference,
    /// not user content, and it should not sync or survive a restore.
    private func persistQuery() {
        guard let data = try? JSONEncoder().encode(query) else { return }
        UserDefaults.standard.set(data, forKey: Self.queryDefaultsKey)
    }

    private static func loadQuery() -> PlantCollectionQuery {
        guard
            let data = UserDefaults.standard.data(forKey: queryDefaultsKey),
            let decoded = try? JSONDecoder().decode(PlantCollectionQuery.self, from: data)
        else { return .default }

        // A persisted search term is not restored. Reopening the app to a
        // collection silently filtered by something typed last week reads as
        // missing plants.
        var restored = decoded
        restored.searchText = ""
        return restored
    }
}
