import BackgroundTasks
import Foundation
import SunnieShared

/// Best-effort orchestration only. Every operation is idempotent and no
/// deadline, reminder, or safety-sensitive behavior depends on this running.
@MainActor
final class BackgroundMaintenanceCoordinator {
    static let taskIdentifier = "com.sunniedays.app.refresh"

    private let dependencies: AppDependencies
    private weak var appState: AppState?
    private var isRegistered = false

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in await self?.handle(task) }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 4)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { SunnieLog(category: .integrations).debug("Background refresh was not scheduled.") }
    }

    @discardableResult
    func perform(_ plan: MaintenancePlan = MaintenancePlan()) async -> MaintenanceReport {
        var completed: [MaintenanceOperation] = []
        var failed: [MaintenanceOperation] = []
        var refreshedContext = false
        for operation in plan.operations {
            guard !Task.isCancelled else {
                return MaintenanceReport(completed: completed, failed: failed, wasCancelled: true)
            }
            switch operation {
            case .context, .world:
                if !refreshedContext {
                    await appState?.refreshCurrentContext()
                    refreshedContext = true
                }
                completed.append(operation)
            case .widgets:
                await dependencies.publishWidgetSnapshot(force: true)
                completed.append(operation)
            case .rewards:
                _ = await dependencies.manageCollection.sweep()
                completed.append(operation)
            case .searchIndex:
                await dependencies.unifiedSearch.rebuild()
                completed.append(operation)
            case .housekeeping:
                do {
                    _ = try await dependencies.manageJournalEntry.purgeExpired()
                    _ = try await dependencies.mediaRepository.deleteOrphans()
                    await dependencies.favorites.rebuild()
                    completed.append(operation)
                } catch {
                    failed.append(operation)
                }
            }
        }
        return MaintenanceReport(completed: completed, failed: failed, wasCancelled: false)
    }

    private func handle(_ task: BGAppRefreshTask) async {
        schedule()
        let work = Task { @MainActor in await perform() }
        task.expirationHandler = { work.cancel() }
        let report = await work.value
        task.setTaskCompleted(success: !report.wasCancelled && report.failed.isEmpty)
    }
}
