import Foundation
import Observation
import SunnieShared

/// State for the Watch app.
///
/// The Watch is a thin client on purpose. It renders the snapshot the phone
/// sends and generates care actions; it holds no schedule logic, computes no due
/// dates, and selects no Sunnie messages. Everything it needs arrives already
/// resolved in the application context.
///
/// The one piece of real logic here is action-key generation. The key is created
/// at the moment of the tap and travels with the action, which is what makes a
/// redelivered transfer resolve to the same care event on the phone rather than
/// a second one.
@MainActor
@Observable
final class WatchModel {

    private(set) var context: WatchApplicationContext?
    /// Actions taken on the wrist that the phone has not confirmed yet. Shown as
    /// done immediately — the user gets their confirmation from the tap, not
    /// from the round trip.
    private(set) var locallyCompletedTaskIDs: Set<UUID> = []
    private(set) var isReachable = false

    private let connectivity = WatchConnectivityClient()
    private let deviceID = DeviceID(rawValue: "watch")

    func activate() {
        connectivity.onContextReceived = { [weak self] context in
            Task { @MainActor in
                self?.apply(context)
            }
        }
        connectivity.onReachabilityChanged = { [weak self] reachable in
            Task { @MainActor in
                self?.isReachable = reachable
            }
        }
        connectivity.activate()
    }

    /// A newer snapshot clears the optimistic set: whatever the phone now says is
    /// due is the truth.
    private func apply(_ context: WatchApplicationContext) {
        guard context.payloadVersion <= WatchPayloadVersion.current else { return }
        if let existing = self.context, existing.generatedAt > context.generatedAt {
            // Snapshots can arrive out of order; keep the newer one.
            return
        }
        self.context = context
        locallyCompletedTaskIDs = []
    }

    var dueTasks: [WatchDueTask] {
        context?.dueTasks ?? []
    }

    func isCompleted(_ task: WatchDueTask) -> Bool {
        locallyCompletedTaskIDs.contains(task.id)
    }

    /// Records a care action and sends it to the phone.
    ///
    /// Sent as a queued transfer rather than a live message, so a tap made out of
    /// range still arrives — WatchConnectivity holds it until the phone is
    /// available (PLANT_CARE.md §14, "Queue action offline").
    func completeCare(_ task: WatchDueTask) {
        guard let careType = task.careType else { return }

        let performedAt = Date()
        let payload = WatchCareActionPayload(
            plantID: task.plantID,
            scheduleID: task.scheduleID,
            careTypeStorageKey: careType.storageKey,
            performedAt: performedAt,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: ActionKeyFactory.plantCare(
                plantID: task.plantID,
                careType: careType,
                performedAt: performedAt
            ).rawValue
        )

        locallyCompletedTaskIDs.insert(task.id)
        connectivity.send(payload)
    }

    var presentationName: String {
        guard
            let key = context?.dayCyclePresentationKey,
            let presentation = DayCyclePresentation(rawValue: key)
        else {
            return DayCyclePresentation.sunnieDays.canonicalDisplayName
        }
        return presentation.canonicalDisplayName
    }
}
