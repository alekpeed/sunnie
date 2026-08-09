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
    private(set) var entities: [SearchEntity] = []

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func rebuild() async {
        async let plants = try? dependencies.plantRepository.allPlants(includingArchived: false)
        async let trips = try? dependencies.travelRepository.trips(includingArchived: true)
        async let places = try? dependencies.travelRepository.places()
        async let memories = try? dependencies.travelRepository.allMemories(limit: 500)
        async let recipes = try? dependencies.mealRepository.recipes()

        var result: [SearchEntity] = []
        result += await (plants ?? []).map {
            SearchEntity(id: "plant.\($0.id)", kind: .plant, title: $0.name,
                         keywords: [$0.speciesName ?? "", "plant", "jungle"], route: "sunniedays://plant/\($0.id)")
        }
        result += await (trips ?? []).map {
            SearchEntity(id: "trip.\($0.id)", kind: .trip, title: $0.title,
                         keywords: ["trip", "travel"], route: "sunniedays://trip/\($0.id)")
        }
        result += await (places ?? []).map {
            SearchEntity(id: "place.\($0.id)", kind: .place, title: $0.name, subtitle: $0.country,
                         keywords: ["place", "travel", $0.country ?? ""], route: "sunniedays://travel")
        }
        result += await (memories ?? []).map {
            SearchEntity(id: "memory.\($0.id)", kind: .memory, title: $0.title ?? "Travel memory",
                         keywords: ["memory", "travel"] + $0.tags,
                         route: $0.tripID.map { "sunniedays://trip/\($0)" } ?? "sunniedays://travel")
        }
        result += await (recipes ?? []).map {
            SearchEntity(id: "recipe.\($0.id)", kind: .recipe, title: $0.title,
                         keywords: ["recipe", "meal"] + $0.tags, route: "sunniedays://meals/recipes")
        }
        result += dependencies.contentRegistry.gamePack.games.map {
            SearchEntity(id: "game.\($0.id.rawValue)", kind: .game,
                         title: String(localized: String.LocalizationValue($0.displayNameKey)),
                         keywords: ["game", "puzzle"], route: "sunniedays://games/\($0.id.rawValue)")
        }
        for curio in CurioCatalog.unlocked(atLevel: ((try? await dependencies.progressionRepository.profile()) ?? .init()).level) {
            result.append(SearchEntity(id: "curio.\(curio.id)", kind: .curio, title: curio.title,
                                       subtitle: curio.detail, keywords: ["curio", "collection"], route: "sunniedays://collections"))
        }
        entities = result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        await indexInSpotlight(entities)
    }

    func results(matching query: String) -> [SearchEntity] {
        entities.filter { $0.matches(query) }
    }

    private func indexInSpotlight(_ entities: [SearchEntity]) async {
        let items = entities.map { entity in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = entity.title
            attributes.contentDescription = entity.subtitle
            attributes.keywords = entity.keywords
            attributes.relatedUniqueIdentifier = entity.route
            attributes.contentURL = URL(string: entity.route)
            return CSSearchableItem(uniqueIdentifier: entity.id, domainIdentifier: "sunniedays.unified", attributeSet: attributes)
        }
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["sunniedays.unified"])
            try await CSSearchableIndex.default().indexSearchableItems(items)
        } catch {
            SunnieLog(category: .integrations).error("Could not refresh the private search index.")
        }
    }
}
