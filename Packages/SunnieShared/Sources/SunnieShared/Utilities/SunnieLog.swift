import Foundation
#if canImport(os)
import os
#endif

/// Unified logging behind a wrapper, with redaction built in
/// (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §7).
///
/// The rule this enforces: journal text, voice-note content, health data, travel
/// documents, private notes, and photos never reach a log. Rather than trusting
/// each call site to remember, `redacted(_:)` is the only way to include a value
/// that might be personal, and it emits a shape description instead of content.
///
/// **`os` is guarded by `canImport`, which is what lets this package build and
/// test on Linux.** The shared package only ever ships to Apple platforms, so on
/// paper the guard is unnecessary — but a package that compiles off-Apple is a
/// package whose 434 tests can run in ordinary CI, or on a machine with no Mac
/// anywhere near it. That is worth far more than the four lines it costs.
///
/// Off Apple the log methods do nothing rather than printing. The redaction
/// helpers are pure string work and behave identically everywhere, so the tests
/// that matter — the ones proving personal content never reaches a log — run on
/// both platforms.
public struct SunnieLog: Sendable {
    #if canImport(os)
    private let logger: Logger
    #else
    /// Kept so the type has the same shape on both platforms; unused off Apple.
    private let category: Category
    #endif

    public static let subsystem = "com.sunniedays.app"

    public init(category: Category) {
        #if canImport(os)
        self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
        #else
        self.category = category
        #endif
    }

    public enum Category: String, Sendable {
        case persistence
        case sync
        case watch
        case progression
        case theme
        case audio
        case notifications
        case content
        case ui
        /// WeatherKit, EventKit, MapKit — anything whose failure is ordinary
        /// and must not reach the user as an error.
        case integrations
    }

    public func debug(_ message: String) {
        #if canImport(os)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    public func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #endif
    }

    public func notice(_ message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #endif
    }

    public func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }

    /// Logs a domain error without leaking any user content it may reference.
    public func error(_ error: DomainError, operation: String) {
        #if canImport(os)
        logger.error("\(operation, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
        #endif
    }

    /// Describes a potentially personal value without revealing it.
    ///
    /// Use for anything the user wrote or captured. `redacted("I felt anxious
    /// today")` logs `<text 21 chars>`, never the sentence.
    public static func redacted(_ value: String?) -> String {
        guard let value else { return "<nil>" }
        return "<text \(value.count) chars>"
    }

    public static func redacted(_ value: Data?) -> String {
        guard let value else { return "<nil>" }
        return "<data \(value.count) bytes>"
    }

    /// Identifiers are safe to log: they resolve to a record only inside the
    /// user's own private store.
    public static func identifier(_ id: UUID?) -> String {
        id?.uuidString ?? "<nil>"
    }

    static func describe(_ error: DomainError) -> String {
        switch error {
        case .notFound(let entity, let id):
            "notFound(\(entity), \(identifier(id)))"
        case .validationFailed(let reason):
            "validationFailed(\(reason))"
        case .persistenceFailed(let operation):
            "persistenceFailed(\(operation))"
        case .unavailableOffline(let operation):
            "unavailableOffline(\(operation))"
        case .permissionDenied(let capability):
            "permissionDenied(\(capability))"
        case .contentInvalid(let reason):
            "contentInvalid(\(reason))"
        }
    }
}
