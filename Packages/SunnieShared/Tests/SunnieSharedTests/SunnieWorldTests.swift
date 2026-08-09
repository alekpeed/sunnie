import XCTest
@testable import SunnieShared

final class SunnieWorldTests: XCTestCase {
    func testCurioUnlocksAreMonotonic() {
        let levelOne = CurioCatalog.unlocked(atLevel: 1)
        let levelEight = CurioCatalog.unlocked(atLevel: 8)

        XCTAssertFalse(levelOne.isEmpty)
        XCTAssertTrue(Set(levelOne.map(\.id)).isSubset(of: Set(levelEight.map(\.id))))
    }

    func testHigherLevelUnlocksMoreCurios() {
        XCTAssertGreaterThan(
            CurioCatalog.unlocked(atLevel: 12).count,
            CurioCatalog.unlocked(atLevel: 1).count
        )
    }

    func testMemoryChaptersSortNewestFirst() {
        let older = MemoryChapter(
            id: "older",
            title: "Older",
            occurredAt: Date(timeIntervalSince1970: 100),
            symbol: "airplane"
        )
        let newer = MemoryChapter(
            id: "newer",
            title: "Newer",
            occurredAt: Date(timeIntervalSince1970: 200),
            symbol: "airplane"
        )

        let snapshot = SunnieWorldSnapshot(
            generatedAt: Date(timeIntervalSince1970: 300),
            memories: [older, newer]
        )

        XCTAssertEqual(snapshot.memories.map(\.id), ["newer", "older"])
    }
}
