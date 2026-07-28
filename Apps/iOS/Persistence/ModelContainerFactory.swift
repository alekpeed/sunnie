import Foundation
import SwiftData
import SunnieShared

/// Builds the app's `ModelContainer`.
///
/// CloudKit is opt-in and off by default. Enabling it requires the iCloud
/// entitlement and a real development team, neither of which a fresh clone has,
/// so defaulting it on would make the project fail to build for anyone who has
/// not configured signing. Local-first is also the documented behaviour: records
/// are written locally and synchronised later, and network availability never
/// blocks an ordinary save (TECHNICAL_ARCHITECTURE.md §12).
enum ModelContainerFactory {

    enum Storage {
        case onDisk(cloudKit: Bool)
        /// Used by tests. Nothing touches the file system.
        case inMemory
    }

    static func make(storage: Storage = .onDisk(cloudKit: false)) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SunnieSchemaV1.self)

        let configuration: ModelConfiguration
        switch storage {
        case .inMemory:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        case .onDisk(let cloudKit):
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: cloudKit ? .automatic : .none
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: SunnieMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// A container that always succeeds, for the case where on-disk storage
    /// cannot be opened.
    ///
    /// Falling back to memory keeps the app usable for the session and makes the
    /// problem visible, rather than crashing on launch with no explanation. The
    /// caller is responsible for telling the user their data is not being saved.
    static func makeWithFallback() -> (container: ModelContainer, isEphemeral: Bool) {
        do {
            return (try make(), false)
        } catch {
            SunnieLog(category: .persistence).error(
                "On-disk store unavailable; running with in-memory storage for this session."
            )
            do {
                return (try make(storage: .inMemory), true)
            } catch {
                // An in-memory container failing means the schema itself is
                // invalid — a programming error that no runtime handling can fix.
                fatalError("SwiftData schema is invalid: \(error)")
            }
        }
    }
}
