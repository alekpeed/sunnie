import Foundation

/// Dictionary keys used by both sides of the phone/Watch bridge.
///
/// Declared once, here, because both sides must agree exactly. Two separate
/// string constants would let a rename on one side break delivery silently — no
/// compiler error, no failing test, just actions that never arrive.
public enum WatchMessageKeys {
    public static let careAction = "sunnie.watch.careAction"
    public static let applicationContext = "sunnie.watch.applicationContext"
}

/// Payload versioning for everything crossing the phone/Watch boundary.
///
/// A queued transfer can be delivered long after it was created, potentially to
/// a differently-versioned counterpart app. Readers check the version before
/// interpreting, and unknown future versions are ignored rather than guessed at.
public enum WatchPayloadVersion {
    public static let current = 1
}

/// One due task as the Watch sees it.
///
/// Deliberately thin: the Watch shows selected due tasks and nothing else. Health
/// observations, photos, and full history are not exposed on the wrist
/// (PLANT_CARE.md §14).
public struct WatchDueTask: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let plantID: UUID
    public let scheduleID: UUID
    public let plantDisplayName: String
    public let careTypeStorageKey: String
    public let dueDate: Date
    public let urgency: DueUrgency

    public init(
        id: UUID,
        plantID: UUID,
        scheduleID: UUID,
        plantDisplayName: String,
        careTypeStorageKey: String,
        dueDate: Date,
        urgency: DueUrgency
    ) {
        self.id = id
        self.plantID = plantID
        self.scheduleID = scheduleID
        self.plantDisplayName = plantDisplayName
        self.careTypeStorageKey = careTypeStorageKey
        self.dueDate = dueDate
        self.urgency = urgency
    }

    public var careType: CareType? { CareType(storageKey: careTypeStorageKey) }

    public init(task: DueCareTask) {
        self.init(
            id: task.id,
            plantID: task.plantID,
            scheduleID: task.scheduleID,
            plantDisplayName: task.plantDisplayName,
            careTypeStorageKey: task.careType.storageKey,
            dueDate: task.dueDate,
            urgency: task.urgency
        )
    }
}

/// Latest-value-wins snapshot pushed to the Watch. Never a queue — WatchConnectivity
/// application context replaces wholesale, which is exactly the semantics we want
/// for "what is due right now".
public struct WatchApplicationContext: Hashable, Sendable, Codable {
    public let payloadVersion: Int
    public let generatedAt: Date
    public let dueTasks: [WatchDueTask]
    public let totalActivePlants: Int
    public let dayCyclePresentationKey: String
    /// A short, already-composed greeting. The Watch does no message selection.
    public let sunnieGreeting: String?

    public init(
        payloadVersion: Int = WatchPayloadVersion.current,
        generatedAt: Date,
        dueTasks: [WatchDueTask],
        totalActivePlants: Int,
        dayCyclePresentationKey: String,
        sunnieGreeting: String?
    ) {
        self.payloadVersion = payloadVersion
        self.generatedAt = generatedAt
        self.dueTasks = dueTasks
        self.totalActivePlants = totalActivePlants
        self.dayCyclePresentationKey = dayCyclePresentationKey
        self.sunnieGreeting = sunnieGreeting
    }

    /// Watch payloads should stay small; trim to the tasks that fit a glance.
    public static let maximumDueTasks = 12
}

/// A care action performed on the Watch.
///
/// Carries its own `actionKey`, generated on the Watch at the moment of the tap.
/// That is what makes redelivery safe: the phone recognises the repeat and stores
/// one event (FIRST_VERTICAL_SLICE.md, "Duplicate Watch action creates one care
/// event").
public struct WatchCareActionPayload: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let plantID: UUID
    public let scheduleID: UUID?
    public let careTypeStorageKey: String
    public let performedAt: Date
    public let sourceDeviceID: String
    public let actionKeyRawValue: String

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        plantID: UUID,
        scheduleID: UUID?,
        careTypeStorageKey: String,
        performedAt: Date,
        sourceDeviceID: String,
        actionKeyRawValue: String
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.plantID = plantID
        self.scheduleID = scheduleID
        self.careTypeStorageKey = careTypeStorageKey
        self.performedAt = performedAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
    }

    public var careType: CareType? { CareType(storageKey: careTypeStorageKey) }
    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }

    /// Payloads from a future version are not guessed at.
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }
}

public enum PendingWatchActionState: String, Hashable, Sendable, Codable {
    case pending
    case processed
    /// Readable but not applicable, e.g. the plant was archived meanwhile.
    /// Retained for audit rather than silently dropped.
    case discarded
}

/// A Watch action persisted on the phone until it has been applied.
public struct PendingWatchAction: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let payloadVersion: Int
    /// The encoded `WatchCareActionPayload`. Stored opaquely so an older build
    /// can hold a payload it does not fully understand without data loss.
    public let payloadData: Data
    public let createdAt: Date
    public let sourceDeviceID: DeviceID
    public var processedAt: Date?
    public var state: PendingWatchActionState
    /// Mirrors the payload's action key so the queue can dedupe without decoding.
    public let actionKey: ActionKey

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        payloadData: Data,
        createdAt: Date,
        sourceDeviceID: DeviceID,
        processedAt: Date? = nil,
        state: PendingWatchActionState = .pending,
        actionKey: ActionKey
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.sourceDeviceID = sourceDeviceID
        self.processedAt = processedAt
        self.state = state
        self.actionKey = actionKey
    }
}
