import Foundation
import Observation
import SunnieShared

/// Feature model for the Jungle landing screen and due list.
@MainActor
@Observable
final class JungleModel {

    struct PlantRow: Identifiable, Equatable {
        let id: UUID
        let displayName: String
        let speciesName: String?
        let nextTask: DueCareTask?
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(summary: PlantTodaySummary, rows: [PlantRow])
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var lastReaction: SunnieMessage?

    let showsDueOnly: Bool

    private let dependencies: AppDependencies
    private var eventToken: UUID?

    init(dependencies: AppDependencies, showsDueOnly: Bool) {
        self.dependencies = dependencies
        self.showsDueOnly = showsDueOnly
    }

    func onAppear() async {
        await load()
        guard eventToken == nil else { return }
        eventToken = await dependencies.eventBus.subscribe { [weak self] event in
            guard event.type == .plantCareLogged else { return }
            await self?.load()
        }
    }

    func onDisappear() async {
        guard let eventToken else { return }
        await dependencies.eventBus.unsubscribe(eventToken)
        self.eventToken = nil
    }

    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }

        do {
            let summary = try await dependencies.summaryProvider.summary()
            let plants = try await dependencies.plantRepository
                .allPlants(includingArchived: false)

            // One lookup pass rather than a scan per plant, so this stays flat
            // as the collection grows past fifty.
            let tasksByPlant = Dictionary(
                summary.actionableTasks.map { ($0.plantID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let rows = plants
                .map { plant in
                    PlantRow(
                        id: plant.id,
                        displayName: plant.displayName,
                        speciesName: plant.speciesName,
                        nextTask: tasksByPlant[plant.id]
                    )
                }
                .sorted { lhs, rhs in
                    // Anything waiting rises to the top; the rest stay alphabetical.
                    switch (lhs.nextTask, rhs.nextTask) {
                    case (let l?, let r?): l.dueDate < r.dueDate
                    case (nil, _?): false
                    case (_?, nil): true
                    case (nil, nil): lhs.displayName < rhs.displayName
                    }
                }

            state = .loaded(summary: summary, rows: rows)
        } catch {
            state = .failed(String(
                localized: "jungle.error.load",
                defaultValue: "I couldn't open your jungle just now. Nothing has been lost, and you can try again.",
                comment: "Shown when the plant list cannot be loaded"
            ))
        }
    }

    func completeCare(task: DueCareTask) async {
        do {
            let result = try await dependencies.logPlantCare(
                plantID: task.plantID,
                careType: task.careType,
                scheduleID: task.scheduleID
            )
            lastReaction = result.message
            if result.wasNewlyRecorded {
                dependencies.haptics.success()
            }
            await load()
        } catch {
            state = .failed(String(
                localized: "jungle.error.logCare",
                defaultValue: "That didn't save just now. Nothing else has changed, and you can try again.",
                comment: "Shown when logging care fails"
            ))
        }
    }
}
