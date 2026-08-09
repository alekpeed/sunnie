import CoreSpotlight
import Foundation
import Observation
import UniformTypeIdentifiers
import SunnieShared

/// Rebuildable projection over authoritative repositories. Spotlight is a
/// presentation cache; deleting it never deletes user data.
@MainActor
@Observable
final class UnifiedSearchService {
    private let dependencies: AppDependencies
    private let indexer: any SearchIndexing
    private(set) var entities: [SearchEntity] = []

    init(dependencies: AppDependencies, indexer: any SearchIndexing = SpotlightSearchIndexer()) {
        self.dependencies = dependencies
        self.indexer = indexer
    }

    func rebuild() async {
        async let plants = try? dependencies.plantRepository.allPlants(includingArchived: false)
        async let trips = try? dependencies.travelRepository.trips(includingArchived: true)
        async let places = try? dependencies.travelRepository.places()
        async let memories = try? dependencies.travelRepository.allMemories(limit: 500)
        async let recipes = try? dependencies.mealRepository.recipes()

        var result: [SearchEntity] = []
        result += await (plants ?? []).map {
            SearchEntity(id: "plant.\($0.id)", kind: .plant, title: $0.name,
                         keywords: [$0.speciesName ?? "", "plant", "jungle"], destination: .plant($0.id))
        }
        result += await (trips ?? []).map {
            SearchEntity(id: "trip.\($0.id)", kind: .trip, title: $0.title,
                         keywords: ["trip", "travel"], destination: .trip($0.id))
        }
        result += await (places ?? []).map {
            SearchEntity(id: "place.\($0.id)", kind: .place, title: $0.name, subtitle: $0.country,
                         keywords: ["place", "travel", $0.country ?? ""], destination: .travel)
        }
        result += await (memories ?? []).map {
            SearchEntity(id: "memory.\($0.id)", kind: .memory, title: $0.title ?? "Travel memory",
                         keywords: ["memory", "travel"] + $0.tags,
                         destination: $0.tripID.map(SearchDestination.trip) ?? .travel)
        }
        result += await (recipes ?? []).map {
            SearchEntity(id: "recipe.\($0.id)", kind: .recipe, title: $0.title,
                         keywords: ["recipe", "meal"] + $0.tags, destination: .recipes)
        }
        result += dependencies.contentRegistry.gamePack.games.map {
            SearchEntity(id: "game.\($0.id.rawValue)", kind: .game,
                         title: String(localized: String.LocalizationValue($0.displayNameKey)),
                         keywords: ["game", "puzzle"], destination: .game($0.id.rawValue))
        }
        for curio in CurioCatalog.unlocked(atLevel: ((try? await dependencies.progressionRepository.profile()) ?? .init()).level) {
            result.append(SearchEntity(id: "curio.\(curio.id)", kind: .curio, title: curio.title,
                                       subtitle: curio.detail, keywords: ["curio", "collection"], destination: .collections))
        }
        entities = SearchRanking.rank(result, favorites: dependencies.favorites.signals)
        await indexer.replace(with: entities)
    }

    func results(matching query: String) -> [SearchEntity] {
        entities.filter { $0.matches(query) }
    }

}

@MainActor
protocol SearchIndexing: AnyObject {
    func replace(with entities: [SearchEntity]) async
}

@MainActor
final class SpotlightSearchIndexer: SearchIndexing {
    private static let identifiersKey = "sunnie.search.indexedIdentifiers"

    func replace(with entities: [SearchEntity]) async {
        let previous = Set(UserDefaults.standard.stringArray(forKey: Self.identifiersKey) ?? [])
        let current = Set(entities.map(\.id))
        let removed = Array(previous.subtracting(current))
        let items = entities.map { entity in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = entity.title
            attributes.contentDescription = entity.subtitle
            attributes.keywords = entity.keywords
            attributes.relatedUniqueIdentifier = entity.destination.routeURL.absoluteString
            attributes.contentURL = entity.destination.routeURL
            return CSSearchableItem(uniqueIdentifier: entity.id, domainIdentifier: "sunniedays.unified", attributeSet: attributes)
        }
        do {
            if !removed.isEmpty {
                try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: removed)
            }
            try await CSSearchableIndex.default().indexSearchableItems(items)
            UserDefaults.standard.set(Array(current).sorted(), forKey: Self.identifiersKey)
        } catch {
            SunnieLog(category: .integrations).error("Could not refresh the private search index.")
        }
    }
}
