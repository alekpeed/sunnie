import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// The V1 → V2 migration, against a real on-disk store.
///
/// In-memory stores cannot be closed and reopened at a newer schema version,
/// which is precisely the thing under test — so these write to a temporary
/// directory and clean up after themselves.
///
/// The point of this suite is not that lightweight migration works; Apple's code
/// does that. It is that *this project's* V1 data survives, because a migration
/// that silently drops a plant collection or a year of care history is the worst
/// failure this app could have.
@Suite("Schema migration", .serialized)
struct SchemaMigrationTests {

    /// A fresh store location per test, removed afterwards.
    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieMigration-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    private func removeStore(at url: URL) {
        let manager = FileManager.default
        // SwiftData writes sidecar files alongside the store.
        for suffix in ["", "-shm", "-wal"] {
            let path = URL(fileURLWithPath: url.path + suffix)
            try? manager.removeItem(at: path)
        }
    }

    // MARK: - V1 data survives

    @Test("A V1 store opens at V2 with every plant and care event intact")
    func v1DataSurvivesMigration() async throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        let plantID = UUID()
        let scheduleID = UUID()
        let careEventKey = "plantCare.v1|\(plantID.uuidString)|water|29000000"
        let acquired = Date(timeIntervalSince1970: 1_700_000_000)

        // 1. Write a V1 store, using only the V1 schema and no migration plan —
        //    exactly what a build shipped before V2 existed would produce.
        do {
            let container = try ModelContainerFactory.make(
                storage: .onDiskAt(url),
                schemaVersion: SunnieSchemaV1.self,
                migrationPlan: nil
            )
            let context = ModelContext(container)

            context.insert(SDPlant(
                id: plantID,
                name: "Monstera",
                speciesName: "Monstera deliciosa",
                acquiredDate: acquired,
                qrToken: "token-abc"
            ))
            context.insert(SDPlantCareSchedule(
                id: scheduleID,
                plantID: plantID,
                careTypeKey: CareType.water.storageKey,
                intervalDays: 7,
                nextDueDate: acquired
            ))
            context.insert(SDPlantCareEvent(
                plantID: plantID,
                careTypeKey: CareType.water.storageKey,
                performedAt: acquired,
                sourceDeviceID: "phone",
                note: "A good long drink",
                actionKey: careEventKey
            ))
            context.insert(SDProgressionProfile(experience: 40, level: 1, activeDayCount: 4))
            try context.save()
        }

        // 2. Reopen the same file at V2, through the migration plan.
        let migrated = try ModelContainerFactory.make(storage: .onDiskAt(url))
        let context = ModelContext(migrated)

        let plants = try context.fetch(FetchDescriptor<SDPlant>())
        #expect(plants.count == 1)
        let plant = try #require(plants.first)
        #expect(plant.id == plantID)
        #expect(plant.name == "Monstera")
        #expect(plant.speciesName == "Monstera deliciosa")
        #expect(plant.qrToken == "token-abc")
        #expect(plant.acquiredDate == acquired)

        let schedules = try context.fetch(FetchDescriptor<SDPlantCareSchedule>())
        #expect(schedules.count == 1)
        #expect(schedules.first?.intervalDays == 7)
        #expect(schedules.first?.plantID == plantID)

        let events = try context.fetch(FetchDescriptor<SDPlantCareEvent>())
        #expect(events.count == 1)
        #expect(events.first?.actionKey == careEventKey)
        #expect(events.first?.note == "A good long drink")

        // Progression must survive too — this is the thing that can never be
        // taken away (MASTER_SOURCE_OF_TRUTH.md §8).
        let progression = try context.fetch(FetchDescriptor<SDProgressionProfile>())
        #expect(progression.first?.experience == 40)
        #expect(progression.first?.activeDayCount == 4)
    }

    @Test("The V2 models are usable immediately after migrating")
    func newModelsWorkAfterMigration() async throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        do {
            let container = try ModelContainerFactory.make(
                storage: .onDiskAt(url),
                schemaVersion: SunnieSchemaV1.self,
                migrationPlan: nil
            )
            let context = ModelContext(container)
            context.insert(SDPlant(name: "Pothos", qrToken: "t"))
            try context.save()
        }

        let migrated = try ModelContainerFactory.make(storage: .onDiskAt(url))
        let repository = SwiftDataWellnessRepository(modelContainer: migrated)

        let recordedAt = Date()
        let outcome = try await repository.save(WellnessCheckIn(
            recordedAt: recordedAt,
            timeZoneID: "UTC",
            mood: .four,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            actionKey: ActionKeyFactory.wellnessCheckIn(recordedAt: recordedAt),
            createdAt: recordedAt
        ))

        #expect(outcome.wasCreated)
        #expect(try await repository.mostRecentCheckIn()?.mood == .four)
    }

    @Test("Migrating a store twice is a no-op")
    func migratingTwiceIsSafe() async throws {
        // The app opens the store on every launch, so this path runs constantly.
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        do {
            let container = try ModelContainerFactory.make(
                storage: .onDiskAt(url),
                schemaVersion: SunnieSchemaV1.self,
                migrationPlan: nil
            )
            let context = ModelContext(container)
            context.insert(SDPlant(name: "Calathea", qrToken: "t"))
            try context.save()
        }

        _ = try ModelContainerFactory.make(storage: .onDiskAt(url))
        let second = try ModelContainerFactory.make(storage: .onDiskAt(url))

        let context = ModelContext(second)
        #expect(try context.fetch(FetchDescriptor<SDPlant>()).count == 1)
    }

    @Test("An empty V1 store migrates cleanly")
    func emptyStoreMigrates() throws {
        let url = makeStoreURL()
        defer { removeStore(at: url) }

        do {
            _ = try ModelContainerFactory.make(
                storage: .onDiskAt(url),
                schemaVersion: SunnieSchemaV1.self,
                migrationPlan: nil
            )
        }

        let migrated = try ModelContainerFactory.make(storage: .onDiskAt(url))
        let context = ModelContext(migrated)
        #expect(try context.fetch(FetchDescriptor<SDPlant>()).isEmpty)
    }

    // MARK: - The plan itself

    @Test("The migration plan lists both versions in order")
    func planIsOrdered() {
        let versions = SunnieMigrationPlan.schemas.map { $0.versionIdentifier }

        #expect(versions.count == 2)
        #expect(versions[0] == Schema.Version(1, 0, 0))
        #expect(versions[1] == Schema.Version(2, 0, 0))
        #expect(SunnieMigrationPlan.stages.count == 1)
    }

    @Test("V2 keeps every V1 model")
    func v2IsAdditive() {
        // The stage is lightweight, which is only correct while V2 is a strict
        // superset of V1. Dropping a model here without changing the stage would
        // silently destroy data.
        let v1 = Set(SunnieSchemaV1.models.map { String(describing: $0) })
        let v2 = Set(SunnieSchemaV2.models.map { String(describing: $0) })

        #expect(v1.isSubset(of: v2), "V2 dropped: \(v1.subtracting(v2))")
        #expect(v2.count > v1.count)
    }

    @Test("The app opens stores at the current schema version")
    func currentSchemaIsLatest() {
        #expect(
            SunnieCurrentSchema.versionIdentifier
                == SunnieMigrationPlan.schemas.last?.versionIdentifier
        )
    }
}
