import Foundation
import WatchConnectivity
import SunnieShared

/// The Watch side of the phone/Watch bridge.
///
/// Care actions go out via `transferUserInfo`, which WatchConnectivity queues and
/// retries until delivery. That guarantees eventual arrival but explicitly does
/// not guarantee exactly-once, which is precisely why the payload carries its own
/// action key.
final class WatchConnectivityClient: NSObject, @unchecked Sendable {

    var onContextReceived: (@Sendable (WatchApplicationContext) -> Void)?
    var onReachabilityChanged: (@Sendable (Bool) -> Void)?

    private let log = SunnieLog(category: .watch)

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()

        // The phone may have set a context before this app launched; pick it up
        // rather than showing an empty list until the next update.
        applyContext(from: session.receivedApplicationContext)
    }

    func send(_ payload: WatchCareActionPayload) {
        guard let session else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        // Queued, not live: a tap made out of range is delivered when the phone
        // is next reachable rather than being lost.
        session.transferUserInfo([WatchMessageKeys.careAction: data])
    }

    private func applyContext(from dictionary: [String: Any]) {
        guard let data = dictionary[WatchMessageKeys.applicationContext] as? Data else { return }
        guard let context = try? JSONDecoder().decode(
            WatchApplicationContext.self, from: data
        ) else {
            log.debug("Received an application context this build cannot decode.")
            return
        }
        onContextReceived?(context)
    }
}

extension WatchConnectivityClient: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        onReachabilityChanged?(session.isReachable)
        applyContext(from: session.receivedApplicationContext)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        applyContext(from: applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        onReachabilityChanged?(session.isReachable)
    }
}
