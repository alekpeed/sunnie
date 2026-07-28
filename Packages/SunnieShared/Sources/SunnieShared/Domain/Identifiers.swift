import Foundation

/// Stable identifier for shipped, non-user content: messages, themes, rewards,
/// audio cues, destinations, games. Uses dot-delimited strings so content packs
/// can be namespaced and diffed without renumbering.
///
/// Example: `sunnie.message.plantCare.completed.01`
public struct ContentID: Hashable, Sendable, Codable, RawRepresentable,
                         ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Content IDs are lowercase-initial, dot-delimited, alphanumeric segments.
    /// Validated by `ContentValidator` at test time rather than trusted at runtime.
    public var isWellFormed: Bool {
        guard !rawValue.isEmpty else { return false }
        let segments = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }
}

/// Identifies the device that originated a record. Required wherever idempotency
/// or sync reconciliation needs to distinguish "the phone did this" from
/// "the Watch did this".
public struct DeviceID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A deterministic key for a user action.
///
/// The same logical action produced twice — a Watch tap that also replays from
/// the queued transfer, a notification action delivered twice — must collapse to
/// one persisted record. Repositories treat this as a uniqueness constraint.
public struct ActionKey: Hashable, Sendable, Codable, RawRepresentable,
                         CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
