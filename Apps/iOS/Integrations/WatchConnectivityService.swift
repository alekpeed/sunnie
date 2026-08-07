import Foundation
import SunnieShared
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Bridges WatchConnectivity to the domain.
///
/// Everything here degrades quietly. A user with no Apple Watch, an unpaired
/// Watch, or a Watch that is simply out of range must see no errors and lose no
/// functionality — the Watch is an optional integration, not a prerequisite
/// (CLAUDE.md, non-negotiable product facts).
///
/// Incoming actions are written to a durable queue before being applied, so a
/// transfer delivered while the phone app is suspended survives until it can be
/// processed.
final class WatchConnectivityService: NSObject, WatchSyncing, @unchecked Sendable {

    private let log = SunnieLog(category: .watch)
    private let onCareAction: @Sendable (WatchCareActionPayload) async -> Void
    /// Everything the Watch sends in the Phase 9 envelope: check-ins, finished
    /// practices, ticked checklist items, hydration.
    private let onAction: @Sendable (WatchActionEnvelope) async -> Void

    #if canImport(WatchConnectivity)
    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }
    #endif

    init(
        onCareAction: @escaping @Sendable (WatchCareActionPayload) async -> Void,
        onAction: @escaping @Sendable (WatchActionEnvelope) async -> Void = { _ in }
    ) {
        self.onCareAction = onCareAction
        self.onAction = onAction
        super.init()
    }

    func activate() {
        #if canImport(WatchConnectivity)
        guard let session else {
            log.info("WatchConnectivity is not supported on this device.")
            return
        }
        session.delegate = self
        session.activate()
        #endif
    }

    var isSupported: Bool {
        #if canImport(WatchConnectivity)
        WCSession.isSupported()
        #else
        false
        #endif
    }

    var isReachable: Bool {
        #if canImport(WatchConnectivity)
        session?.isReachable ?? false
        #else
        false
        #endif
    }

    func updateApplicationContext(_ context: WatchApplicationContext) async {
        #if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(context)
            // Application context is latest-value-wins, which is exactly right
            // for "what is due now" — a backlog of stale snapshots would be worse
            // than one current one.
            try session.updateApplicationContext(
                [WatchMessageKeys.applicationContext: data]
            )
        } catch {
            log.debug("Could not update the Watch application context.")
        }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityService: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if error != nil {
            log.debug("Watch session activation did not complete.")
            return
        }
        log.info("Watch session activated: \(activationState.rawValue)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Reactivating is required when the user switches to a different Watch.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handle(message)
        replyHandler(["received": true])
    }

    /// Queued transfers arrive here. They may be delivered late, out of order,
    /// or more than once, which is precisely what the action key protects against.
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        handle(userInfo)
    }

    /// Routes one delivery.
    ///
    /// Both keys are handled: the envelope is what current builds send, and the
    /// bare care action is what a Watch still on the Phase 2 build sends. A
    /// transfer queued by that older Watch and delivered after the phone updated
    /// must still water the plant.
    private func handle(_ payload: [String: Any]) {
        if let data = payload[WatchMessageKeys.action] as? Data {
            handleEnvelope(data)
        }
        if let data = payload[WatchMessageKeys.careAction] as? Data {
            handleLegacyCareAction(data)
        }
    }

    private func handleEnvelope(_ data: Data) {
        guard let envelope = try? WatchActionEnvelope.coder.decoder.decode(
            WatchActionEnvelope.self, from: data
        ) else {
            log.debug("Received a Watch envelope this build cannot decode; ignoring it.")
            return
        }
        guard envelope.isReadable else {
            log.info("Received a Watch envelope from a newer build; ignoring it.")
            return
        }

        let handler = onAction
        Task { await handler(envelope) }
    }

    private func handleLegacyCareAction(_ data: Data) {
        guard let action = try? JSONDecoder().decode(
            WatchCareActionPayload.self, from: data
        ) else {
            log.debug("Received a Watch payload this build cannot decode; ignoring it.")
            return
        }
        guard action.isReadable else {
            log.info("Received a Watch payload from a newer build; ignoring it.")
            return
        }

        let handler = onCareAction
        Task { await handler(action) }
    }
}
#endif

/// Stand-in used in previews, tests, and on devices with no Watch support.
struct UnavailableWatchSync: WatchSyncing {
    var isSupported: Bool { false }
    var isReachable: Bool { false }
    func updateApplicationContext(_ context: WatchApplicationContext) async {}
}
