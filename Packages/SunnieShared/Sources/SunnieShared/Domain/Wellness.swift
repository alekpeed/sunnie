import Foundation

/// A five-point scale value.
///
/// Deliberately a plain 1–5 with no built-in adjectives: labels belong to the
/// dimension, not the number, and every option must be neutrally labelled and
/// usable without relying on imagery (WELLNESS_JOURNAL_AND_CALM.md §2).
public enum WellnessScaleValue: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The middle of the scale. Used as the starting selection so the form does
    /// not imply an expected answer.
    public static let neutral = WellnessScaleValue.three
}

/// What a check-in dimension measures.
///
/// `polarity` matters: stress runs the other way, so a summary that naively
/// averaged all four would describe a calm week as a bad one.
public enum WellnessDimension: String, Hashable, Sendable, Codable, CaseIterable {
    case mood
    case energy
    case stress
    case sleepQuality

    public enum Polarity: Sendable {
        /// Higher is the more comfortable end.
        case higherIsEasier
        /// Lower is the more comfortable end.
        case lowerIsEasier
    }

    public var polarity: Polarity {
        switch self {
        case .mood, .energy, .sleepQuality: .higherIsEasier
        case .stress: .lowerIsEasier
        }
    }

    /// Localization key for the dimension's own name.
    public var localizationKey: String { "wellness.dimension.\(rawValue)" }

    /// Localization key for one point on this dimension's scale.
    ///
    /// Per-dimension because "low" means something different for energy than for
    /// stress, and reusing one adjective set would produce nonsense labels.
    public func scaleLabelKey(for value: WellnessScaleValue) -> String {
        "wellness.scale.\(rawValue).\(value.rawValue)"
    }
}

/// One recorded check-in (DATA_MODEL.md §5).
///
/// Every dimension is optional. The user may answer one question and leave the
/// rest, and an entry with nothing but a note is still a valid entry — the app
/// never requires a complete form to accept what someone wants to record.
public struct WellnessCheckIn: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var recordedAt: Date
    public var timeZoneID: String
    public var mood: WellnessScaleValue?
    public var energy: WellnessScaleValue?
    public var stress: WellnessScaleValue?
    public var sleepQuality: WellnessScaleValue?
    public var note: String?
    public var voiceNoteID: UUID?
    public var photoID: UUID?
    public let sourceDeviceID: DeviceID
    public let actionKey: ActionKey
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        recordedAt: Date,
        timeZoneID: String,
        mood: WellnessScaleValue? = nil,
        energy: WellnessScaleValue? = nil,
        stress: WellnessScaleValue? = nil,
        sleepQuality: WellnessScaleValue? = nil,
        note: String? = nil,
        voiceNoteID: UUID? = nil,
        photoID: UUID? = nil,
        sourceDeviceID: DeviceID,
        actionKey: ActionKey,
        createdAt: Date
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.timeZoneID = timeZoneID
        self.mood = mood
        self.energy = energy
        self.stress = stress
        self.sleepQuality = sleepQuality
        self.note = note
        self.voiceNoteID = voiceNoteID
        self.photoID = photoID
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
        self.createdAt = createdAt
    }

    public func value(for dimension: WellnessDimension) -> WellnessScaleValue? {
        switch dimension {
        case .mood: mood
        case .energy: energy
        case .stress: stress
        case .sleepQuality: sleepQuality
        }
    }

    /// True when the user recorded nothing at all. Such an entry is not saved.
    public var isEmpty: Bool {
        mood == nil && energy == nil && stress == nil && sleepQuality == nil
            && (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && voiceNoteID == nil
            && photoID == nil
    }

    /// Whether this check-in describes a harder moment.
    ///
    /// Used only to soften how Sunnie responds — never to diagnose, and never to
    /// trigger any kind of intervention. Sunnie Days is not a crisis service and
    /// performs no crisis detection (WELLNESS_JOURNAL_AND_CALM.md §12); this flag
    /// exists so a nickname or a bright celebration does not land on someone
    /// having a difficult day.
    public var suggestsSensitiveMoment: Bool {
        if let mood, mood <= .two { return true }
        if let stress, stress >= .four { return true }
        return false
    }
}

/// A calming practice the user ran.
public enum WellnessSessionType: String, Hashable, Sendable, Codable, CaseIterable {
    case breathing
    case meditation
    case grounding
    case sleepWindDown
    case travelReset
    case calmSounds
}

public enum WellnessSessionCompletion: String, Hashable, Sendable, Codable {
    case completed
    /// Stopped early. Recorded exactly as neutrally as completion — leaving a
    /// practice partway is a legitimate outcome, not a failure.
    case endedEarly
    case interrupted
}

public struct WellnessSession: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let type: WellnessSessionType
    /// The practice that was run, e.g. `sunnie.breathing.longerExhale`.
    public let practiceID: ContentID?
    public var startedAt: Date
    public var endedAt: Date?
    /// Intended length. The actual length is `endedAt - startedAt`.
    public var plannedDuration: TimeInterval
    public var completion: WellnessSessionCompletion?
    public var audioCueID: ContentID?
    /// Set once the session has been written to HealthKit as a mindful minute,
    /// so a retry cannot write it twice.
    public var healthKitSampleID: String?
    public let sourceDeviceID: DeviceID
    public let actionKey: ActionKey

    public init(
        id: UUID = UUID(),
        type: WellnessSessionType,
        practiceID: ContentID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        plannedDuration: TimeInterval,
        completion: WellnessSessionCompletion? = nil,
        audioCueID: ContentID? = nil,
        healthKitSampleID: String? = nil,
        sourceDeviceID: DeviceID,
        actionKey: ActionKey
    ) {
        self.id = id
        self.type = type
        self.practiceID = practiceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDuration = plannedDuration
        self.completion = completion
        self.audioCueID = audioCueID
        self.healthKitSampleID = healthKitSampleID
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
    }

    public var actualDuration: TimeInterval? {
        guard let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var isFinished: Bool { endedAt != nil }
}
