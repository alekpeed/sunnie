import Foundation

/// The Watch's five destinations (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §5).
public enum WatchDestination: String, Hashable, Sendable, Codable, CaseIterable {
    case today
    case checkIn
    case plants
    case calm
    case travel

    public var localizationKey: String { "watch.destination.\(rawValue)" }
}

/// Everything the Watch needs beyond plant tasks (§6).
///
/// Bolted onto the existing application context as a separate optional value
/// rather than folded into it, so a Watch running an older build keeps working:
/// it decodes the part it knows and ignores the rest, and the phone does not
/// have to know which build is on the wrist.
public struct WatchFeatureContext: Hashable, Sendable, Codable {
    public let payloadVersion: Int

    /// A short affirmation, already chosen by the phone. The Watch does no
    /// message selection — it has no content pack and no nickname rules.
    public let affirmation: String?
    /// The one thing worth surfacing, already prioritised by the phone.
    public let nextTaskDescription: String?

    public let checkIn: CheckInPanel
    public let calm: CalmPanel
    public let travel: TravelPanel?

    public init(
        payloadVersion: Int = WatchPayloadVersion.current,
        affirmation: String? = nil,
        nextTaskDescription: String? = nil,
        checkIn: CheckInPanel = CheckInPanel(),
        calm: CalmPanel = CalmPanel(),
        travel: TravelPanel? = nil
    ) {
        self.payloadVersion = payloadVersion
        self.affirmation = affirmation
        self.nextTaskDescription = nextTaskDescription
        self.checkIn = checkIn
        self.calm = calm
        self.travel = travel
    }

    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }

    /// Check In on the wrist (§6).
    ///
    /// Mood and optionally energy — two of the phone's four dimensions. Stress
    /// and sleep quality are deliberately absent: a wrist form should be one or
    /// two taps, and the phone accepts a partial check-in as a complete record
    /// anyway (WELLNESS_JOURNAL_AND_CALM.md §2).
    public struct CheckInPanel: Hashable, Sendable, Codable {
        public let offersEnergy: Bool
        /// Whether one was already recorded today. Shown as a quiet note, never
        /// as a prompt to do it again.
        public let recordedToday: Bool

        public init(offersEnergy: Bool = true, recordedToday: Bool = false) {
            self.offersEnergy = offersEnergy
            self.recordedToday = recordedToday
        }
    }

    /// Calm on the wrist (§6).
    public struct CalmPanel: Hashable, Sendable, Codable {
        public struct Practice: Hashable, Sendable, Codable, Identifiable {
            public let id: ContentID
            public let displayName: String
            public let typeRawValue: String
            /// One cycle, for the breathing pacer.
            public let inhaleSeconds: Double
            public let holdAfterInhaleSeconds: Double
            public let exhaleSeconds: Double
            public let holdAfterExhaleSeconds: Double
            public let defaultDuration: TimeInterval

            public init(
                id: ContentID,
                displayName: String,
                typeRawValue: String,
                inhaleSeconds: Double,
                holdAfterInhaleSeconds: Double,
                exhaleSeconds: Double,
                holdAfterExhaleSeconds: Double,
                defaultDuration: TimeInterval
            ) {
                self.id = id
                self.displayName = displayName
                self.typeRawValue = typeRawValue
                self.inhaleSeconds = inhaleSeconds
                self.holdAfterInhaleSeconds = holdAfterInhaleSeconds
                self.exhaleSeconds = exhaleSeconds
                self.holdAfterExhaleSeconds = holdAfterExhaleSeconds
                self.defaultDuration = defaultDuration
            }

            public var sessionType: WellnessSessionType {
                WellnessSessionType(rawValue: typeRawValue) ?? .breathing
            }

            public var cycleDuration: TimeInterval {
                inhaleSeconds + holdAfterInhaleSeconds + exhaleSeconds + holdAfterExhaleSeconds
            }

            public init(pattern: BreathingPattern, displayName: String) {
                self.init(
                    id: pattern.id,
                    displayName: displayName,
                    typeRawValue: WellnessSessionType.breathing.rawValue,
                    inhaleSeconds: pattern.inhaleSeconds,
                    holdAfterInhaleSeconds: pattern.holdAfterInhaleSeconds,
                    exhaleSeconds: pattern.exhaleSeconds,
                    holdAfterExhaleSeconds: pattern.holdAfterExhaleSeconds,
                    defaultDuration: pattern.totalDuration(cycles: pattern.defaultCycles)
                )
            }
        }

        public let practices: [Practice]
        /// Whether the user has haptic pacing on. A preference, so the wrist and
        /// the phone agree without the Watch storing its own settings.
        public let usesHapticPacing: Bool

        public init(practices: [Practice] = [], usesHapticPacing: Bool = true) {
            self.practices = practices
            self.usesHapticPacing = usesHapticPacing
        }

        /// Keeps the payload small; the wrist is not a browsing surface.
        public static let maximumPractices = 4
    }

    /// Travel on the wrist (§6).
    public struct TravelPanel: Hashable, Sendable, Codable {
        public let tripTitle: String
        public let startsAt: Date?
        public let endsAt: Date?
        public let homeTimeZoneID: String
        public let destinationTimeZoneID: String?
        public let statusKey: String
        /// A handful of unticked checklist items, already chosen by the phone.
        public let checklistItems: [ChecklistEntry]
        /// The next thing to eat or drink, when the phone has one. A single
        /// already-composed line rather than a meal model.
        public let nextRefreshment: String?

        public init(
            tripTitle: String,
            startsAt: Date?,
            endsAt: Date?,
            homeTimeZoneID: String,
            destinationTimeZoneID: String?,
            statusKey: String,
            checklistItems: [ChecklistEntry] = [],
            nextRefreshment: String? = nil
        ) {
            self.tripTitle = tripTitle
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.homeTimeZoneID = homeTimeZoneID
            self.destinationTimeZoneID = destinationTimeZoneID
            self.statusKey = statusKey
            self.checklistItems = checklistItems
            self.nextRefreshment = nextRefreshment
        }

        public struct ChecklistEntry: Hashable, Sendable, Codable, Identifiable {
            public let id: UUID
            public let title: String

            public init(id: UUID, title: String) {
                self.id = id
                self.title = title
            }
        }

        public static let maximumChecklistItems = 5

        public func daysUntilDeparture(now: Date, calendar: Calendar) -> Int? {
            guard let startsAt, startsAt > now else { return nil }
            return calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: startsAt)
            ).day
        }
    }
}

// MARK: - Watch-originated actions

/// The kinds of thing the Watch can send back.
///
/// A discriminator on the wire, so the phone can route a queued transfer without
/// attempting each decode in turn — and so an unrecognised kind is *recognisably*
/// unrecognised rather than a decode failure that looks like corruption.
public enum WatchActionKind: String, Hashable, Sendable, Codable {
    case plantCare
    case wellnessCheckIn
    case wellnessSession
    case checklistItem
    case hydration
}

/// A check-in made on the wrist (§6, "save with stable action ID").
public struct WatchCheckInPayload: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let recordedAt: Date
    public let timeZoneID: String
    public let moodRawValue: Int?
    public let energyRawValue: Int?
    public let sourceDeviceID: String
    public let actionKeyRawValue: String

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        recordedAt: Date,
        timeZoneID: String,
        moodRawValue: Int?,
        energyRawValue: Int?,
        sourceDeviceID: String,
        actionKeyRawValue: String
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.recordedAt = recordedAt
        self.timeZoneID = timeZoneID
        self.moodRawValue = moodRawValue
        self.energyRawValue = energyRawValue
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
    }

    public var mood: WellnessScaleValue? {
        moodRawValue.flatMap(WellnessScaleValue.init(rawValue:))
    }
    public var energy: WellnessScaleValue? {
        energyRawValue.flatMap(WellnessScaleValue.init(rawValue:))
    }
    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }
}

/// A practice finished on the wrist (§6).
public struct WatchSessionPayload: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let practiceID: String?
    public let typeRawValue: String
    public let startedAt: Date
    public let endedAt: Date
    public let plannedDuration: TimeInterval
    public let completionRawValue: String
    public let sourceDeviceID: String
    public let actionKeyRawValue: String

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        practiceID: String?,
        typeRawValue: String,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        completionRawValue: String,
        sourceDeviceID: String,
        actionKeyRawValue: String
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.practiceID = practiceID
        self.typeRawValue = typeRawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDuration = plannedDuration
        self.completionRawValue = completionRawValue
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
    }

    public var sessionType: WellnessSessionType {
        WellnessSessionType(rawValue: typeRawValue) ?? .breathing
    }
    public var completion: WellnessSessionCompletion {
        WellnessSessionCompletion(rawValue: completionRawValue) ?? .endedEarly
    }
    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }
}

/// A checklist item ticked on the wrist (§6, Travel).
public struct WatchChecklistPayload: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let itemID: UUID
    public let completedAt: Date
    public let sourceDeviceID: String
    public let actionKeyRawValue: String

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        itemID: UUID,
        completedAt: Date,
        sourceDeviceID: String,
        actionKeyRawValue: String
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.itemID = itemID
        self.completedAt = completedAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
    }

    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }
}

/// Water logged on the wrist (§6, Travel — "meal/hydration reminder").
public struct WatchHydrationPayload: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let millilitres: Int
    public let loggedAt: Date
    public let sourceDeviceID: String
    public let actionKeyRawValue: String

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        millilitres: Int,
        loggedAt: Date,
        sourceDeviceID: String,
        actionKeyRawValue: String
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.millilitres = millilitres
        self.loggedAt = loggedAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
    }

    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }
}

/// The envelope every Watch-originated action travels in.
///
/// §7 requires each action to carry a stable action ID, a type, a timestamp, a
/// source device, and a payload version. The envelope carries all five, so the
/// phone can queue, dedupe, and audit a transfer without decoding the body — and
/// so an action of a kind this build does not know is stored intact rather than
/// dropped.
public struct WatchActionEnvelope: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let payloadVersion: Int
    public let kindRawValue: String
    public let occurredAt: Date
    public let sourceDeviceID: String
    public let actionKeyRawValue: String
    public let body: Data

    public init(
        id: UUID = UUID(),
        payloadVersion: Int = WatchPayloadVersion.current,
        kindRawValue: String,
        occurredAt: Date,
        sourceDeviceID: String,
        actionKeyRawValue: String,
        body: Data
    ) {
        self.id = id
        self.payloadVersion = payloadVersion
        self.kindRawValue = kindRawValue
        self.occurredAt = occurredAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKeyRawValue = actionKeyRawValue
        self.body = body
    }

    /// Nil for a kind this build does not recognise, which is a normal outcome
    /// when the wrist is running a newer app than the phone.
    public var kind: WatchActionKind? { WatchActionKind(rawValue: kindRawValue) }
    public var actionKey: ActionKey { ActionKey(rawValue: actionKeyRawValue) }
    public var deviceID: DeviceID { DeviceID(rawValue: sourceDeviceID) }
    public var isReadable: Bool { payloadVersion <= WatchPayloadVersion.current }

    /// The JSON coder both sides use.
    ///
    /// Declared once, here, because the envelope is encoded on one device and
    /// decoded on another: two independently configured coders that disagree
    /// about dates would produce transfers that arrive and cannot be read.
    public static var coder: (encoder: JSONEncoder, decoder: JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    public static func wrap<Payload: Encodable>(
        _ payload: Payload,
        kind: WatchActionKind,
        occurredAt: Date,
        deviceID: DeviceID,
        actionKey: ActionKey
    ) -> WatchActionEnvelope? {
        guard let body = try? Self.coder.encoder.encode(payload) else { return nil }
        return WatchActionEnvelope(
            kindRawValue: kind.rawValue,
            occurredAt: occurredAt,
            sourceDeviceID: deviceID.rawValue,
            actionKeyRawValue: actionKey.rawValue,
            body: body
        )
    }

    public func unwrap<Payload: Decodable>(_ type: Payload.Type) -> Payload? {
        try? Self.coder.decoder.decode(type, from: body)
    }
}
