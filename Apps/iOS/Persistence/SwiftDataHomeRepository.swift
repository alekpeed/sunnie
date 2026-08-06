import Foundation
import SwiftData
import SunnieShared

/// The home scene, its placements, and which story scenes have been read.
///
/// Same `@ModelActor` discipline as every other repository: check-then-insert
/// inside the serialized context, no uniqueness attributes (ADR-011).
@ModelActor
actor SwiftDataHomeRepository: HomeRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    // MARK: - Scene

    func sceneState() async throws -> HomeSceneState {
        do {
            if let model = try fetchScene() {
                return ModelMapping.domain(model)
            }
            // A first launch has no scene yet. Returning the default rather than
            // creating a row keeps a read from writing — the row appears the
            // first time the user actually arranges something.
            return HomeSceneState(updatedAt: Date())
        } catch {
            log.error("Fetching the home scene failed.")
            throw DomainError.persistenceFailed(operation: "homeScene")
        }
    }

    func save(_ state: HomeSceneState) async throws {
        do {
            if let existing = try fetchScene() {
                ModelMapping.apply(state, to: existing)
            } else {
                let model = SDHomeScene()
                ModelMapping.apply(state, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveHomeScene")
        }
    }

    private func fetchScene() throws -> SDHomeScene? {
        var descriptor = FetchDescriptor<SDHomeScene>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Placements

    func placements() async throws -> [HomePlacement] {
        do {
            return try modelContext
                .fetch(FetchDescriptor<SDHomePlacement>(
                    sortBy: [SortDescriptor(\.slotID, order: .forward)]
                ))
                .map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "homePlacements")
        }
    }

    /// One thing per slot: placing replaces whatever was there.
    ///
    /// The replacement is a delete-then-insert rather than an update, so a store
    /// that somehow ended up with two rows for one slot is repaired by the next
    /// placement instead of accumulating.
    func place(rewardID: ContentID, in slotID: ContentID, at date: Date) async throws {
        let slot = slotID.rawValue
        do {
            for existing in try modelContext.fetch(FetchDescriptor<SDHomePlacement>(
                predicate: #Predicate<SDHomePlacement> { $0.slotID == slot }
            )) {
                modelContext.delete(existing)
            }
            modelContext.insert(SDHomePlacement(
                slotID: slot, rewardID: rewardID.rawValue, placedAt: date
            ))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "placeDecor")
        }
    }

    func clear(slotID: ContentID) async throws {
        let slot = slotID.rawValue
        do {
            for existing in try modelContext.fetch(FetchDescriptor<SDHomePlacement>(
                predicate: #Predicate<SDHomePlacement> { $0.slotID == slot }
            )) {
                modelContext.delete(existing)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "clearSlot")
        }
    }

    // MARK: - Story scenes

    func seenStorySceneIDs() async throws -> Set<ContentID> {
        do {
            return Set(
                try modelContext
                    .fetch(FetchDescriptor<SDStorySceneSeen>())
                    .map { ContentID(rawValue: $0.sceneID) }
            )
        } catch {
            throw DomainError.persistenceFailed(operation: "seenStoryScenes")
        }
    }

    func markStorySceneSeen(_ id: ContentID, at date: Date) async throws {
        let raw = id.rawValue
        do {
            var descriptor = FetchDescriptor<SDStorySceneSeen>(
                predicate: #Predicate<SDStorySceneSeen> { $0.sceneID == raw }
            )
            descriptor.fetchLimit = 1
            guard try modelContext.fetch(descriptor).isEmpty else { return }

            modelContext.insert(SDStorySceneSeen(sceneID: raw, seenAt: date))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "markStorySceneSeen")
        }
    }
}
