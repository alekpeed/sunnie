import Foundation
import Observation
import SunnieShared

/// Conservative, reconstructable preference view. No inferred value is written
/// back to a repository, so resetting it simply means rebuilding from records.
@MainActor
@Observable
final class PersonalFavoritesService {
    private static let inferenceEnabledKey = "sunnie.favorites.inferenceEnabled"
    private let dependencies: AppDependencies
    private(set) var signals: [FavoriteSignal] = []
    private(set) var isInferenceEnabled: Bool

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.isInferenceEnabled = UserDefaults.standard.object(forKey: Self.inferenceEnabledKey) as? Bool ?? true
    }

    func rebuild() async {
        let places = (try? await dependencies.travelRepository.places()) ?? []
        let trips = (try? await dependencies.travelRepository.trips(includingArchived: true)) ?? []
        let recipes = (try? await dependencies.mealRepository.recipes()) ?? []

        var explicit = places.filter(\.isFavorite).map {
            FavoriteSignal(kind: .place, entityID: $0.id.uuidString, title: $0.name, strength: .explicit, evidenceCount: 1)
        }
        explicit += recipes.filter(\.isFavorite).map {
            FavoriteSignal(kind: .recipe, entityID: $0.id.uuidString, title: $0.title, strength: .explicit, evidenceCount: 1)
        }

        let namesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0.name) })
        let destinationIDs = trips.flatMap(\.placeIDs)
        let counts = Dictionary(destinationIDs.map { ($0, 1) }, uniquingKeysWith: +)
        let observations = counts.compactMap { id, count -> FavoriteSignal? in
            guard let name = namesByID[id] else { return nil }
            return FavoriteSignal(kind: .place, entityID: id.uuidString, title: name, strength: .inferred, evidenceCount: count)
        }
        signals = FavoritesResolver.resolve(
            explicit: explicit,
            observations: isInferenceEnabled ? observations : []
        )
    }

    func setInferenceEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.inferenceEnabledKey)
        isInferenceEnabled = enabled
        await rebuild()
    }
}
