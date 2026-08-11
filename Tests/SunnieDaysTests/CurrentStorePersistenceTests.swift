import Foundation
import Testing
import SunnieShared
@testable import SunnieDays

/// Relaunch coverage against the current schema and a real SQLite store.
///
/// Migration tests prove that an old schema can be opened. This suite proves a
/// more ordinary but separate promise: records written by today's repositories
/// remain readable after every container and repository has been destroyed.
@Suite("Current store persistence", .serialized)
struct CurrentStorePersistenceTests {

    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieRelaunch-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix)
            )
        }
    }

    @Test("Plant care and progression survive a complete store reopen")
    func coreRecordsSurviveRelaunch() async throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let plant = Plant(
            name: "Relaunch Monstera",
            status: .active,
            qrToken: "relaunch-token",
            createdAt: now,
            modifiedAt: now
        )
        let event = PlantCareEvent(
            plantID: plant.id,
            careType: .water,
            performedAt: now,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            note: "Persist me",
            actionKey: ActionKeyFactory.plantCare(
                plantID: plant.id,
                careType: .water,
                performedAt: now
            ),
            createdAt: now
        )
        let progressionEvent = ProgressionEvent(
            type: .plantCareCompleted,
            sourceEntityID: event.id,
            occurredAt: now,
            deterministicKey: "progression|\(event.actionKey.rawValue)",
            experienceAwarded: 10
        )

        do {
            let container = try ModelContainerFactory.make(storage: .onDiskAt(url))
            let plants = SwiftDataPlantRepository(modelContainer: container)
            let care = SwiftDataPlantCareEventRepository(modelContainer: container)
            let progression = SwiftDataProgressionRepository(modelContainer: container)

            try await plants.save(plant)
            _ = try await care.save(event)
            try await progression.save(ProgressionProfile(
                experience: 10,
                level: 1,
                activeDayCount: 1,
                lastActivityAt: now
            ))
            _ = try await progression.save(progressionEvent)
        }

        do {
            let reopened = try ModelContainerFactory.make(storage: .onDiskAt(url))
            let plants = SwiftDataPlantRepository(modelContainer: reopened)
            let care = SwiftDataPlantCareEventRepository(modelContainer: reopened)
            let progression = SwiftDataProgressionRepository(modelContainer: reopened)

            #expect(try await plants.plant(id: plant.id)?.name == "Relaunch Monstera")
            #expect(try await care.event(actionKey: event.actionKey)?.note == "Persist me")
            #expect(try await progression.profile().experience == 10)
            #expect(
                try await progression.event(
                    deterministicKey: progressionEvent.deterministicKey
                )?.experienceAwarded == 10
            )

            // Relaunch does not weaken idempotency: a transfer redelivered after
            // process death still resolves to the row written before it.
            let replay = try await care.save(event)
            #expect(!replay.wasCreated)
            #expect(try await care.events(forPlantID: plant.id, limit: 10).count == 1)
        }
    }
}
