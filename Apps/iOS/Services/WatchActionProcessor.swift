import Foundation
import SunnieShared

/// Applies care actions that arrived from the Watch.
///
/// Two layers of protection against duplicate delivery, because WatchConnectivity
/// makes no once-only guarantee:
///
/// 1. The queue rejects an action whose key it already holds.
/// 2. `LogPlantCare` collapses it against the stored care event anyway.
///
/// Either alone would be sufficient; both together mean the flow is safe even if
/// the queue is cleared, the app is reinstalled, or a transfer is redelivered
/// after processing.
actor WatchActionProcessor {

    private let queue: any PendingWatchActionRepository
    private let logCare: LogPlantCare
    private let clock: any SunnieClock
    private let log = SunnieLog(category: .watch)

    init(
        queue: any PendingWatchActionRepository,
        logCare: LogPlantCare,
        clock: any SunnieClock
    ) {
        self.queue = queue
        self.logCare = logCare
        self.clock = clock
    }

    /// Durably records an incoming action, then tries to apply it.
    ///
    /// Enqueueing first is what makes this survive termination: if the app is
    /// killed between receiving and applying, `processPending` picks it up at
    /// next launch.
    func receive(_ payload: WatchCareActionPayload) async {
        guard payload.isReadable else { return }

        do {
            let data = try JSONEncoder().encode(payload)
            let pending = PendingWatchAction(
                payloadVersion: payload.payloadVersion,
                payloadData: data,
                createdAt: clock.now,
                sourceDeviceID: payload.deviceID,
                actionKey: payload.actionKey
            )

            let outcome = try await queue.enqueue(pending)
            guard outcome.wasCreated else {
                log.debug("This Watch action was already queued; ignoring the repeat.")
                return
            }

            await apply(payload, queuedActionID: outcome.value.id)
        } catch {
            log.error("Could not queue an incoming Watch action.")
        }
    }

    /// Drains the queue. Called at launch and when the app returns to the
    /// foreground.
    func processPending() async {
        let pending: [PendingWatchAction]
        do {
            pending = try await queue.unprocessedActions()
        } catch {
            log.error("Could not read the pending Watch action queue.")
            return
        }

        for action in pending {
            guard let payload = try? JSONDecoder().decode(
                WatchCareActionPayload.self, from: action.payloadData
            ) else {
                // Unreadable payloads are marked processed rather than retried
                // forever. The record stays in storage for audit.
                log.info("A queued Watch action could not be decoded; skipping it.")
                try? await queue.markProcessed(actionID: action.id, at: clock.now)
                continue
            }
            await apply(payload, queuedActionID: action.id)
        }
    }

    private func apply(_ payload: WatchCareActionPayload, queuedActionID: UUID) async {
        guard let careType = payload.careType else {
            log.info("A Watch action referenced an unknown care type; skipping it.")
            try? await queue.markProcessed(actionID: queuedActionID, at: clock.now)
            return
        }

        do {
            _ = try await logCare(
                plantID: payload.plantID,
                careType: careType,
                performedAt: payload.performedAt,
                note: nil,
                scheduleID: payload.scheduleID,
                // The Watch's key travels with the action, so redelivery
                // resolves to the same care event.
                actionKey: payload.actionKey,
                sourceDeviceID: payload.deviceID
            )
            try? await queue.markProcessed(actionID: queuedActionID, at: clock.now)
        } catch DomainError.notFound {
            // The plant was archived or removed after the Watch queued this.
            // Nothing to apply, and retrying will never succeed.
            log.info("A Watch action referenced a plant that no longer exists.")
            try? await queue.markProcessed(actionID: queuedActionID, at: clock.now)
        } catch {
            // Leave it pending so the next drain retries it.
            log.error("Applying a queued Watch action failed; it stays queued.")
        }
    }
}
