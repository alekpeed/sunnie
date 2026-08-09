import XCTest
@testable import SunnieShared

final class SystemIntegrationTests: XCTestCase {
    func testCapabilitySnapshotDefaultsUnknownStateToUnavailable() {
        let snapshot = CapabilitySnapshot(generatedAt: .distantPast, states: [.camera: .authorized])
        XCTAssertTrue(snapshot[.camera].canUse)
        XCTAssertEqual(snapshot[.health], .unavailable)
        XCTAssertFalse(snapshot[.health].canRequest)
    }

    func testUnifiedSearchIsDiacriticInsensitiveAndRequiresEveryToken() {
        let entity = SearchEntity(id: "place.lisbon", kind: .place, title: "Café Lisboa", keywords: ["Portugal"], route: "sunniedays://travel")
        XCTAssertTrue(entity.matches("cafe portugal"))
        XCTAssertFalse(entity.matches("cafe tokyo"))
    }

    func testExplicitFavoriteOverridesInference() {
        let inferred = FavoriteSignal(kind: .place, entityID: "lisbon", title: "Lisbon", strength: .inferred, evidenceCount: 8)
        let explicit = FavoriteSignal(kind: .place, entityID: "lisbon", title: "Lisboa", strength: .explicit, evidenceCount: 1)
        XCTAssertEqual(FavoritesResolver.resolve(explicit: [explicit], observations: [inferred]), [explicit])
    }

    func testInferenceRequiresRepeatedEvidence() {
        let single = FavoriteSignal(kind: .trip, entityID: "tokyo", title: "Tokyo", strength: .inferred, evidenceCount: 1)
        let repeated = FavoriteSignal(kind: .trip, entityID: "madrid", title: "Madrid", strength: .inferred, evidenceCount: 2)
        XCTAssertEqual(FavoritesResolver.resolve(explicit: [], observations: [single, repeated]).map(\.entityID), ["madrid"])
    }

    func testMaintenancePlanDeduplicatesInOrder() {
        XCTAssertEqual(MaintenancePlan(operations: [.context, .widgets, .context]).operations, [.context, .widgets])
    }
}
