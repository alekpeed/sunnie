import Foundation
import os

/// Unified logging behind a wrapper, with redaction built in
/// (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §7).
///
/// The rule this enforces: journal text, voice-note content, health data, travel
/// documents, private notes, and photos never reach a log. Rather than trusting
/// each call site to remember, `redacted(_:)` is the only way to include a value
/// that might be personal, and it emits a shape description instead of content.
public struct SunnieLog: Sendable {
    private let logger: Logger

    public static let subsystem = "com.sunniedays.app"

    public init(category: Category) {
        self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
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
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Logs a domain error without leaking any user content it may reference.
    public func error(_ error: DomainError, operation: String) {
        logger.error("\(operation, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
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
