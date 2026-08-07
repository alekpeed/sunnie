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

    /// Actions taken on the wrist that the phone has not confirmed yet, beyond
    /// care. Shown as done immediately for the same reason: the confirmation
    /// comes from the tap, not from the round trip.
    private(set) var locallyTickedChecklistIDs: Set<UUID> = []
    private(set) var didCheckInLocally = false

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
        locallyTickedChecklistIDs = []
        didCheckInLocally = false
    }

    // MARK: - The other four destinations

    var features: WatchFeatureContext? {
        guard let features = context?.features, features.isReadable else { return nil }
        return features
    }

    var affirmation: String? { features?.affirmation }
    var practices: [WatchFeatureContext.CalmPanel.Practice] { features?.calm.practices ?? [] }
    var usesHapticPacing: Bool { features?.calm.usesHapticPacing ?? true }
    var travel: WatchFeatureContext.TravelPanel? { features?.travel }

    var hasCheckedInToday: Bool {
        didCheckInLocally || (features?.checkIn.recordedToday ?? false)
    }

    var offersEnergy: Bool { features?.checkIn.offersEnergy ?? true }

    /// Records a check-in and sends it (§6, "save with stable action ID").
    ///
    /// The key is generated here, at the moment of the tap, exactly as care is —
    /// which is what makes a redelivered transfer resolve to the same entry on
    /// the phone rather than a second one.
    func recordCheckIn(mood: WellnessScaleValue?, energy: WellnessScaleValue?) {
        guard mood != nil || energy != nil else { return }

        let recordedAt = Date()
        let payload = WatchCheckInPayload(
            recordedAt: recordedAt,
            timeZoneID: TimeZone.current.identifier,
            moodRawValue: mood?.rawValue,
            energyRawValue: energy?.rawValue,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: ActionKeyFactory.wellnessCheckIn(
                recordedAt: recordedAt
            ).rawValue
        )

        didCheckInLocally = true
        send(payload, kind: .wellnessCheckIn, at: recordedAt, key: payload.actionKey)
    }

    /// Records a practice run on the wrist.
    ///
    /// Sent when it ends rather than when it starts: the phone is learning about
    /// something that already happened, and a session announced at the start
    /// would leave a window where the phone's history said a practice was
    /// running that had in fact been abandoned.
    func recordSession(
        practice: WatchFeatureContext.CalmPanel.Practice,
        startedAt: Date,
        endedAt: Date,
        completion: WellnessSessionCompletion
    ) {
        let sessionID = UUID()
        let payload = WatchSessionPayload(
            id: sessionID,
            practiceID: practice.id.rawValue,
            typeRawValue: practice.typeRawValue,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: practice.defaultDuration,
            completionRawValue: completion.rawValue,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: ActionKeyFactory.wellnessSession(
                sessionID: sessionID
            ).rawValue
        )
        send(payload, kind: .wellnessSession, at: endedAt, key: payload.actionKey)
    }

    func tickChecklistItem(_ entry: WatchFeatureContext.TravelPanel.ChecklistEntry) {
        guard !locallyTickedChecklistIDs.contains(entry.id) else { return }

        let completedAt = Date()
        let payload = WatchChecklistPayload(
            itemID: entry.id,
            completedAt: completedAt,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: ActionKeyFactory.checklistItem(itemID: entry.id).rawValue
        )

        locallyTickedChecklistIDs.insert(entry.id)
        send(payload, kind: .checklistItem, at: completedAt, key: payload.actionKey)
    }

    func logWater(millilitres: Int) {
        let loggedAt = Date()
        let payload = WatchHydrationPayload(
            millilitres: millilitres,
            loggedAt: loggedAt,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: ActionKeyFactory.hydration(
                millilitres: millilitres, loggedAt: loggedAt
            ).rawValue
        )
        send(payload, kind: .hydration, at: loggedAt, key: payload.actionKey)
    }

    func isTicked(_ entry: WatchFeatureContext.TravelPanel.ChecklistEntry) -> Bool {
        locallyTickedChecklistIDs.contains(entry.id)
    }

    private func send<Payload: Encodable>(
        _ payload: Payload,
        kind: WatchActionKind,
        at date: Date,
        key: ActionKey
    ) {
        guard let envelope = WatchActionEnvelope.wrap(
            payload, kind: kind, occurredAt: date, deviceID: deviceID, actionKey: key
        ) else { return }
        connectivity.send(envelope)
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
