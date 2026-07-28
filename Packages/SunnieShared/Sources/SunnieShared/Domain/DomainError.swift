import Foundation

/// Typed domain errors. Adapters translate framework errors into these; raw
/// framework error strings are never shown to the user
/// (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §6).
public enum DomainError: Error, Hashable, Sendable {
    case notFound(entity: String, id: UUID?)
    case validationFailed(reason: ValidationReason)
    case persistenceFailed(operation: String)
    case unavailableOffline(operation: String)
    case permissionDenied(capability: String)
    case contentInvalid(reason: String)

    public enum ValidationReason: Hashable, Sendable {
        case emptyName
        /// A care event dated in the future beyond a small clock-skew tolerance.
        case timestampInFuture
        case scheduleDisabled
        case unknownCareType
    }
}

/// Distinguishes a genuine failure from an expected no-op.
///
/// Logging the same watering twice is not an error — the second attempt simply
/// resolves to the record that already exists, and the UI shows success either
/// way. Callers use this to avoid reporting a problem where none occurred.
public enum SaveOutcome<Value: Sendable>: Sendable {
    case created(Value)
    case alreadyExisted(Value)

    public var value: Value {
        switch self {
        case .created(let value), .alreadyExisted(let value): value
        }
    }

    public var wasCreated: Bool {
        if case .created = self { return true }
        return false
    }
}
