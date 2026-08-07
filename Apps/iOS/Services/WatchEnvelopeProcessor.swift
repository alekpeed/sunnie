import Foundation
import SunnieShared

/// Applies the Watch actions that are not plant care
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §6, §7).
///
/// Every one goes through the same use case the phone's own UI uses, with the
/// action key the Watch generated at the moment of the tap. That is what makes
/// §7's "phone processing is idempotent" true rather than aspirational: a
/// redelivered transfer resolves to the record that already exists.
///
/// Kept separate from `WatchActionProcessor`, which owns care and its durable
/// queue. Care is the one action with a plant that may have been archived
/// meanwhile and therefore needs retry semantics; these four either apply or are
/// permanently inapplicable, so a queue would only add a way to get stuck.
actor WatchEnvelopeProcessor {

    private let recordCheckIn: RecordWellnessCheckIn
    private let wellnessRepository: any WellnessRepository
    private let travelRepository: any TravelRepository
    private let health: ManageHealthIntegration
    private let clock: any SunnieClock
    private let log = SunnieLog(category: .watch)

    init(
        recordCheckIn: RecordWellnessCheckIn,
        wellnessRepository: any WellnessRepository,
        travelRepository: any TravelRepository,
        health: ManageHealthIntegration,
        clock: any SunnieClock
    ) {
        self.recordCheckIn = recordCheckIn
        self.wellnessRepository = wellnessRepository
        self.travelRepository = travelRepository
        self.health = health
        self.clock = clock
    }

    func receive(_ envelope: WatchActionEnvelope) async {
        guard envelope.isReadable else { return }

        switch envelope.kind {
        case .wellnessCheckIn:
            await applyCheckIn(envelope)
        case .wellnessSession:
            await applySession(envelope)
        case .checklistItem:
            await applyChecklistItem(envelope)
        case .hydration:
            await applyHydration(envelope)
        case .plantCare:
            // Care travels its own path, with a durable queue behind it.
            log.debug("A care action arrived in an envelope; the care processor owns it.")
        case .none:
            // A kind this build does not know, which happens when the wrist is
            // ahead of the phone. Dropped rather than guessed at.
            log.info("Received a Watch action of an unrecognised kind; ignoring it.")
        }
    }

    // MARK: - Check in

    private func applyCheckIn(_ envelope: WatchActionEnvelope) async {
        guard let payload = envelope.unwrap(WatchCheckInPayload.self), payload.isReadable else {
            return
        }

        // Through the same use case the phone's own form uses, so the entry gets
        // its acknowledgement, its progression, and its domain event exactly as
        // one made on the phone would.
        //
        // The key is regenerated inside from the timestamp, which is the same
        // derivation the Watch used — so a redelivered transfer resolves to the
        // entry already stored. An empty check-in is rejected there too.
        _ = try? await recordCheckIn(
            mood: payload.mood,
            energy: payload.energy,
            recordedAt: payload.recordedAt,
            source: payload.deviceID,
            timeZoneID: payload.timeZoneID
        )
    }

    // MARK: - Practices

    /// Records a practice run on the wrist.
    ///
    /// Written as a finished session in one step rather than start-then-finish,
    /// because it already finished — the phone is learning about it afterwards,
    /// and a session inserted "in progress" and immediately closed would leave a
    /// window where history was wrong.
    private func applySession(_ envelope: WatchActionEnvelope) async {
        guard let payload = envelope.unwrap(WatchSessionPayload.self), payload.isReadable else {
            return
        }

        let session = WellnessSession(
            id: payload.id,
            type: payload.sessionType,
            practiceID: payload.practiceID.map(ContentID.init(rawValue:)),
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            plannedDuration: payload.plannedDuration,
            completion: payload.completion,
            sourceDeviceID: payload.deviceID,
            actionKey: payload.actionKey
        )

        guard let outcome = try? await wellnessRepository.save(session) else { return }
        guard outcome.wasCreated else {
            log.debug("This practice was already recorded; ignoring the repeat.")
            return
        }

        // Mindful minutes for a practice done on the wrist, exactly as for one
        // done on the phone. Guarded inside, so a stopped-early session or a
        // permission the user never granted simply produces nothing.
        _ = await health.recordMindfulSession(outcome.value)
    }

    // MARK: - Checklists

    private func applyChecklistItem(_ envelope: WatchActionEnvelope) async {
        guard let payload = envelope.unwrap(WatchChecklistPayload.self), payload.isReadable else {
            return
        }

        guard var item = try? await travelRepository.checklistItem(id: payload.itemID) else {
            // The trip or the item was deleted after the wrist queued this.
            // Nothing to apply, and nothing to report.
            log.info("A Watch checklist action referenced an item that no longer exists.")
            return
        }
        // Already done is the ordinary outcome of a redelivered transfer.
        guard !item.isDone else { return }

        item.isDone = true
        try? await travelRepository.save(item)
    }

    // MARK: - Hydration

    private func applyHydration(_ envelope: WatchActionEnvelope) async {
        guard let payload = envelope.unwrap(WatchHydrationPayload.self), payload.isReadable else {
            return
        }
        // The wrist's own key travels with the entry, so a transfer delivered
        // twice resolves to the one already stored.
        _ = try? await health.logWater(
            millilitres: payload.millilitres,
            loggedAt: payload.loggedAt,
            source: payload.deviceID,
            actionKey: payload.actionKey
        )
    }
}
