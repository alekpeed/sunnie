import XCTest
@testable import SunnieShared

final class SystemIntegrationTests: XCTestCase {
    func testIntentHandoffExpiresAndRejectsForeignSchemes() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = IntentHandoffEnvelope(
            createdAt: now,
            lifetime: 60,
            routeURL: try XCTUnwrap(URL(string: "sunniedays://today")),
            tellSunnieText: "Watered Fern"
        )
        XCTAssertTrue(envelope.isConsumable(at: now.addingTimeInterval(59)))
        XCTAssertFalse(envelope.isConsumable(at: now.addingTimeInterval(60)))

        let foreign = IntentHandoffEnvelope(
            createdAt: now,
            routeURL: try XCTUnwrap(URL(string: "https://example.com"))
        )
        XCTAssertFalse(foreign.isConsumable(at: now))
    }

    func testCapabilitySnapshotDefaultsUnknownStateToUnavailable() {
        let snapshot = CapabilitySnapshot(generatedAt: .distantPast, states: [.camera: .authorized])
        XCTAssertTrue(snapshot[.camera].canUse)
        XCTAssertEqual(snapshot[.health], .unavailable)
        XCTAssertFalse(snapshot[.health].canRequest)
    }

    func testUnifiedSearchIsDiacriticInsensitiveAndRequiresEveryToken() {
        let entity = SearchEntity(id: "place.lisbon", kind: .place, title: "Café Lisboa", keywords: ["Portugal"], destination: .travel)
        XCTAssertTrue(entity.matches("cafe portugal"))
        XCTAssertFalse(entity.matches("cafe tokyo"))
    }

    func testExplicitFavoriteOverridesInference() {
        let inferred = FavoriteSignal(kind: .place, entityID: "lisbon", title: "Lisbon", strength: .inferred, evidenceCount: 8)
        let explicit = FavoriteSignal(kind: .place, entityID: "lisbon", title: "Lisboa", strength: .explicit, evidenceCount: 1)
        XCTAssertEqual(FavoritesResolver.resolve(explicit: [explicit], observations: [inferred]), [explicit])
    }

    func testFavoritesActuallyRankSearchResults() {
        let favorite = FavoriteSignal(kind: .place, entityID: "lisbon", title: "Lisbon", strength: .explicit, evidenceCount: 1)
        let alphabeticFirst = SearchEntity(id: "place.amsterdam", kind: .place, title: "Amsterdam", destination: .travel)
        let favored = SearchEntity(id: favorite.id, kind: .place, title: "Lisbon", destination: .travel)
        XCTAssertEqual(SearchRanking.rank([alphabeticFirst, favored], favorites: [favorite]).map(\.id), [favorite.id, alphabeticFirst.id])
    }

    func testInferenceRequiresRepeatedEvidence() {
        let single = FavoriteSignal(kind: .trip, entityID: "tokyo", title: "Tokyo", strength: .inferred, evidenceCount: 1)
        let repeated = FavoriteSignal(kind: .trip, entityID: "madrid", title: "Madrid", strength: .inferred, evidenceCount: 2)
        XCTAssertEqual(FavoritesResolver.resolve(explicit: [], observations: [single, repeated]).map(\.entityID), ["madrid"])
    }

    func testMaintenancePlanDeduplicatesInOrder() {
        XCTAssertEqual(MaintenancePlan(operations: [.context, .widgets, .context]).operations, [.context, .widgets])
    }

    func testMaintenanceReportKeepsPartialFailureHonest() {
        let report = MaintenanceReport(completed: [.context], failed: [.searchIndex], wasCancelled: false)
        XCTAssertEqual(report.completed, [.context])
        XCTAssertEqual(report.failed, [.searchIndex])
        XCTAssertFalse(report.wasCancelled)
    }
}
