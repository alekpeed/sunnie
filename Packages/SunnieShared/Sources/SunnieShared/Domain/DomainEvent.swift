import Foundation

/// Typed cross-feature notification. Features never mutate each other directly;
/// they publish and observe these (TECHNICAL_ARCHITECTURE.md §6).
public enum DomainEventType: String, Hashable, Sendable, Codable, CaseIterable {
    case plantCareLogged
    case plantAdded
    case plantArchived
    case wellnessCheckInRecorded
    case tripCreated
    case puzzleCompleted
    case rewardGranted
    case preferencesChanged
}

/// Versioned so a queued Watch payload or a replayed sync record written by an
/// older build can still be interpreted (TECHNICAL_ARCHITECTURE.md §10).
public struct DomainEvent: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let type: DomainEventType
    public let occurredAt: Date
    public let sourceEntityID: UUID?
    /// Present when the event affects persistence or progression, so downstream
    /// handlers can collapse duplicates.
    public let deterministicKey: String?
    public let payloadVersion: Int

    public init(
        id: UUID = UUID(),
        type: DomainEventType,
        occurredAt: Date,
        sourceEntityID: UUID?,
        deterministicKey: String? = nil,
        payloadVersion: Int = 1
    ) {
        self.id = id
        self.type = type
        self.occurredAt = occurredAt
        self.sourceEntityID = sourceEntityID
        self.deterministicKey = deterministicKey
        self.payloadVersion = payloadVersion
    }
}
