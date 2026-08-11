import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Reproducible release-scale data rather than the five-record first-launch seed.
private enum LargeJungleFixture {
    static let plantCount = 100
    static let eventsPerPlant = 5

    static func plants(at now: Date) -> [Plant] {
        (0..<plantCount).map { index in
            Plant(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                name: String(format: "Plant %03d", index + 1),
                speciesName: index.isMultiple(of: 2) ? "Monstera deliciosa" : "Epipremnum aureum",
                locationID: nil,
                lightProfile: index.isMultiple(of: 3) ? .indirectBright : .dappled,
                difficulty: index.isMultiple(of: 5) ? .demanding : .easy,
                status: .active,
                qrToken: String(format: "fixture-%03d", index + 1),
                createdAt: now.addingTimeInterval(-Double(index) * 86_400),
                modifiedAt: now
            )
        }
    }

    static func events(for plants: [Plant], at now: Date) -> [PlantCareEvent] {
        plants.flatMap { plant in
            (0..<eventsPerPlant).map { eventIndex in
                let performedAt = now.addingTimeInterval(
                    -Double(eventIndex + 1) * 7 * 86_400
                )
                return PlantCareEvent(
                    plantID: plant.id,
                    careType: .water,
                    performedAt: performedAt,
                    sourceDeviceID: DeviceID(rawValue: "fixture"),
                    actionKey: ActionKeyFactory.plantCare(
                        plantID: plant.id,
                        careType: .water,
                        performedAt: performedAt
                    ),
                    createdAt: performedAt
                )
            }
        }
    }
}

@Suite("Release-scale Jungle fixtures", .serialized)
struct LargeCollectionTests {

    @Test("One hundred plants and five hundred care events remain queryable")
    func largeJungleRoundTrips() async throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let plantsRepository = SwiftDataPlantRepository(modelContainer: container)
        let careRepository = SwiftDataPlantCareEventRepository(modelContainer: container)
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let plants = LargeJungleFixture.plants(at: now)
        let events = LargeJungleFixture.events(for: plants, at: now)

        for plant in plants {
            try await plantsRepository.save(plant)
        }
        for event in events {
            _ = try await careRepository.save(event)
        }

        let loaded = try await plantsRepository.allPlants(includingArchived: false)
        #expect(loaded.count == LargeJungleFixture.plantCount)
        #expect(Set(loaded.map(\.id)).count == LargeJungleFixture.plantCount)

        let firstHistory = try await careRepository.events(
            forPlantID: plants[0].id,
            limit: 100
        )
        #expect(firstHistory.count == LargeJungleFixture.eventsPerPlant)
        #expect(firstHistory == firstHistory.sorted { $0.performedAt > $1.performedAt })

        // The final record proves pagination/query logic did not accidentally
        // stop at a small first-launch-sized collection.
        #expect(loaded.contains { $0.name == "Plant 100" })
    }

    @Test("A large private journal remains searchable and paginated", .timeLimit(.minutes(1)))
    func largeJournalRemainsUsable() async throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let journal = SwiftDataJournalRepository(modelContainer: container)
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        for index in 0..<500 {
            try await journal.save(JournalEntry(
                title: String(format: "Entry %03d", index),
                body: index == 499 ? "A uniquely searchable jacaranda memory" : "Journal body \(index)",
                isDraft: false,
                tags: index.isMultiple(of: 10) ? ["travel"] : ["home"],
                createdAt: now.addingTimeInterval(Double(index)),
                modifiedAt: now.addingTimeInterval(Double(index))
            ))
        }

        let firstPage = try await journal.entries(limit: 100, offset: 0)
        let lastPage = try await journal.entries(limit: 100, offset: 400)
        #expect(firstPage.count == 100)
        #expect(lastPage.count == 100)
        #expect(Set(firstPage.map(\.id)).isDisjoint(with: Set(lastPage.map(\.id))))
        #expect(firstPage.first?.title == "Entry 499")

        let search = try await journal.entries(matching: "jacaranda", limit: 10)
        #expect(search.count == 1)
        #expect(search.first?.title == "Entry 499")

        let tagged = try await journal.entries(withTag: "travel", limit: 100)
        #expect(tagged.count == 50)
    }
}
