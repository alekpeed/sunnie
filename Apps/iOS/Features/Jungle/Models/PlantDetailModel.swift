import Foundation
import Observation
import SunnieShared

/// Feature model for one plant.
@MainActor
@Observable
final class PlantDetailModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Loaded)
        case failed(String)
    }

    struct Loaded: Equatable {
        let plant: Plant
        let schedules: [PlantCareSchedule]
        let recentEvents: [PlantCareEvent]
    }

    private(set) var state: LoadState = .idle
    private(set) var lastReaction: SunnieMessage?
    /// Drives the "Watching" chip. A count rather than a flag so the same value
    /// can label the row later without another query.
    private(set) var openObservationCount = 0
    var isQuickCarePresented = false

    let plantID: UUID
    private let dependencies: AppDependencies

    /// Care history shown on detail. Full history is a Phase 4 screen.
    private let historyLimit = 20

    init(plantID: UUID, dependencies: AppDependencies) {
        self.plantID = plantID
        self.dependencies = dependencies
    }

    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }

        do {
            guard let plant = try await dependencies.plantRepository.plant(id: plantID) else {
                state = .failed(String(
                    localized: "plant.error.missing",
                    defaultValue: "I can't find that plant anymore. It may have been archived.",
                    comment: "Shown when a plant no longer exists"
                ))
                return
            }

            let schedules = try await dependencies.plantRepository
                .schedules(forPlantID: plantID)
            let events = try await dependencies.careEventRepository
                .events(forPlantID: plantID, limit: historyLimit)

            // Best effort: a failure here costs the "Watching" chip, not the
            // screen.
            openObservationCount = (try? await dependencies.managePlantHealth
                .observations(forPlantID: plantID)
                .filter { !$0.isResolved }
                .count) ?? 0

            state = .loaded(Loaded(
                plant: plant,
                schedules: schedules.sorted { $0.careType.storageKey < $1.careType.storageKey },
                recentEvents: events
            ))
        } catch {
            state = .failed(String(
                localized: "plant.error.load",
                defaultValue: "I couldn't open this plant just now. Nothing has been lost, and you can try again.",
                comment: "Shown when a plant cannot be loaded"
            ))
        }
    }

    /// Records care. `performedAt` lets the quick-care sheet backdate an action
    /// the user did earlier and is logging now.
    func logCare(
        careType: CareType,
        performedAt: Date,
        note: String?
    ) async {
        do {
            let scheduleID: UUID?
            if case .loaded(let loaded) = state {
                scheduleID = loaded.schedules
                    .first { $0.careType == careType && $0.isEnabled }?.id
            } else {
                scheduleID = nil
            }

            let result = try await dependencies.logPlantCare(
                plantID: plantID,
                careType: careType,
                performedAt: performedAt,
                note: note,
                scheduleID: scheduleID
            )

            lastReaction = result.message
            if result.wasNewlyRecorded {
                dependencies.haptics.success()
            }
            isQuickCarePresented = false
            await load()
        } catch DomainError.validationFailed(.timestampInFuture) {
            state = .failed(String(
                localized: "plant.error.futureDate",
                defaultValue: "That time is in the future. Pick now or a moment that has already passed.",
                comment: "Shown when a care timestamp is ahead of the clock"
            ))
        } catch {
            state = .failed(String(
                localized: "plant.error.logCare",
                defaultValue: "That didn't save just now. Nothing else has changed, and you can try again.",
                comment: "Shown when logging care fails"
            ))
        }
    }

    /// Care types offered in the quick sheet: everything scheduled for this
    /// plant, plus water so the primary action is always reachable.
    var offeredCareTypes: [CareType] {
        guard case .loaded(let loaded) = state else { return [.water] }
        var types = loaded.schedules.filter(\.isEnabled).map(\.careType)
        if !types.contains(.water) { types.insert(.water, at: 0) }
        return types
    }
}
