import Foundation
import SunnieShared

/// Durable one-shot bridge between an App Intent process and the application.
/// The App Group is preferred; the app container is the honest fallback for
/// configurations where the optional group entitlement is not active.
struct IntentHandoffStore: Sendable {
    static let fileName = "pending-intent-handoff.json"
    static let live = IntentHandoffStore()

    private let fileURL: URL?

    init(directory: URL? = nil) {
        if let directory {
            self.fileURL = directory.appendingPathComponent(Self.fileName)
            return
        }
        #if canImport(Darwin)
        let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupIdentifier
        )
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.fileURL = (group ?? fallback)?.appendingPathComponent(Self.fileName)
        #else
        self.fileURL = nil
        #endif
    }

    func save(routeURL: URL, tellSunnieText: String? = nil, now: Date = Date()) throws {
        guard let fileURL else { throw IntentHandoffError.storageUnavailable }
        let envelope = IntentHandoffEnvelope(
            createdAt: now,
            routeURL: routeURL,
            tellSunnieText: tellSunnieText
        )
        let data = try JSONEncoder().encode(envelope)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes before returning so a crash during routing cannot replay a stale
    /// action on the next launch.
    func take(now: Date = Date()) -> IntentHandoffEnvelope? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        guard let envelope = try? JSONDecoder().decode(IntentHandoffEnvelope.self, from: data),
              envelope.isConsumable(at: now) else { return nil }
        return envelope
    }
}

enum IntentHandoffError: Error {
    case storageUnavailable
}
