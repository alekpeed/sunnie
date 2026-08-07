import Foundation

/// The Health data types this app may touch
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §2, §3).
///
/// Every one of these is individually permissioned. That is the whole point of
/// the enum being granular rather than a single "Health" switch: §1 says request
/// the minimum necessary, and a user who wants Sunnie to write mindful minutes
/// should not have to hand over their heart rate to do it.
///
/// The list is deliberately short. §2 ends with "do not request every type merely
/// because it exists", and nothing is here without a screen that uses it.
public enum HealthDataType: String, Hashable, Sendable, Codable, CaseIterable {
    case stepCount
    case sleepAnalysis
    case heartRate
    case restingHeartRate
    case workouts
    case activeEnergy
    case standTime
    case mindfulSession
    case dietaryWater

    public var localizationKey: String { "health.type.\(rawValue)" }

    /// Why the app would ask for this. Shown next to the switch, so the reason is
    /// visible at the moment of the decision rather than buried in a privacy
    /// page.
    public var reasonKey: String { "health.reason.\(rawValue)" }

    /// Whether the app ever reads this type.
    public var isRead: Bool { true }

    /// Whether the app ever writes this type (§3).
    ///
    /// Only two, and both only after a clear user action that completed:
    /// a finished mindful practice, and an explicit hydration log.
    public var isWritten: Bool {
        self == .mindfulSession || self == .dietaryWater
    }

    /// Types the app asks for by default when the user turns Health on with no
    /// further choices.
    ///
    /// Just the two it writes. Reading anything is an additional, separate
    /// decision — the app works completely without a single read.
    public static let writeOnlyDefaults: [HealthDataType] = [.mindfulSession, .dietaryWater]
}

/// What the system says about one type.
///
/// `sharingDenied` and `notDetermined` are treated the same by every screen: the
/// value is simply absent. HealthKit deliberately does not reveal read denial —
/// a denied read looks like no data — so nothing here may claim to distinguish
/// them (§12).
public enum HealthAuthorization: String, Hashable, Sendable, Codable {
    case notDetermined
    case sharingAuthorized
    case sharingDenied
    /// The device has no Health store at all — iPad, or a Mac.
    case unavailable

    public var localizationKey: String { "health.authorization.\(rawValue)" }

    public var canWrite: Bool { self == .sharingAuthorized }
}

/// One value read from Health, with the honesty about it built in.
///
/// `coverage` exists because §4 forbids "presenting incomplete data as
/// complete". A step count for a day that is one hour old is not a daily total,
/// and a sleep figure from a night the watch was charging is not a night's sleep.
public struct HealthReading: Hashable, Sendable, Codable {
    public enum Coverage: String, Hashable, Sendable, Codable {
        /// The window this covers is over and the data looks whole.
        case complete
        /// The window is still open — today's steps at lunchtime.
        case inProgress
        /// Some of the window has no data at all.
        case partial
        /// Nothing was found. Which may mean denied, may mean no device, and the
        /// app cannot tell the difference.
        case none

        public var localizationKey: String { "health.coverage.\(rawValue)" }
    }

    public let type: HealthDataType
    /// In the type's own natural unit: steps, minutes, beats per minute, millilitres.
    public let value: Double?
    public let coverage: Coverage
    public let start: Date
    public let end: Date

    public init(
        type: HealthDataType,
        value: Double?,
        coverage: Coverage,
        start: Date,
        end: Date
    ) {
        self.type = type
        self.value = value
        self.coverage = coverage
        self.start = start
        self.end = end
    }

    /// Nothing to show. A reading with no value is not zero — zero steps and no
    /// step data are different facts, and only one of them is true.
    public static func absent(_ type: HealthDataType, start: Date, end: Date) -> HealthReading {
        HealthReading(type: type, value: nil, coverage: .none, start: start, end: end)
    }

    public var hasValue: Bool { value != nil && coverage != .none }
}

/// Today's Health picture, as much of it as the user allowed.
public struct HealthSnapshot: Hashable, Sendable, Codable {
    public let generatedAt: Date
    public let readings: [HealthDataType: HealthReading]

    public init(generatedAt: Date, readings: [HealthDataType: HealthReading]) {
        self.generatedAt = generatedAt
        self.readings = readings
    }

    public static func empty(at date: Date) -> HealthSnapshot {
        HealthSnapshot(generatedAt: date, readings: [:])
    }

    public func reading(_ type: HealthDataType) -> HealthReading? {
        readings[type].flatMap { $0.hasValue ? $0 : nil }
    }

    public var isEmpty: Bool {
        readings.values.allSatisfy { !$0.hasValue }
    }
}

/// Turns Health readings into sentences the app is allowed to say (§4).
///
/// The rule this encodes: **describe, never judge.** "You recorded 12 mindful
/// minutes today" is a fact the user produced. "Your heart rate suggests you are
/// anxious" is a diagnosis, "you should sleep more" is medical advice, and
/// "only 3,000 steps" is a verdict. None of the three has a function here that
/// could produce it.
///
/// Note what is missing and cannot be added without changing the shape of this
/// type: there is no target, no goal, no comparison to yesterday, and no
/// adjective. A phrase is a number and a noun.
public enum HealthPhrasing {

    /// One line about one reading, or nil when there is nothing honest to say.
    ///
    /// Returns nil rather than "no data" for an absent reading: a row that says
    /// "no data" every day is the app nagging about a permission the user
    /// already declined (§12, "without repeated prompting").
    public static func descriptor(for reading: HealthReading) -> Descriptor? {
        guard let value = reading.value, reading.coverage != .none else { return nil }

        return Descriptor(
            type: reading.type,
            formattedValue: format(value, for: reading.type),
            unitKey: unitKey(for: reading.type),
            // The caveat is attached to the phrase rather than left to the
            // screen, so no screen can forget it.
            caveatKey: caveatKey(for: reading.coverage)
        )
    }

    /// A phrase, in parts, so the app can lay it out.
    public struct Descriptor: Hashable, Sendable {
        public let type: HealthDataType
        public let formattedValue: String
        public let unitKey: String
        /// Present when the window is still open or has gaps.
        public let caveatKey: String?

        public init(
            type: HealthDataType,
            formattedValue: String,
            unitKey: String,
            caveatKey: String?
        ) {
            self.type = type
            self.formattedValue = formattedValue
            self.unitKey = unitKey
            self.caveatKey = caveatKey
        }
    }

    static func caveatKey(for coverage: HealthReading.Coverage) -> String? {
        switch coverage {
        case .complete: nil
        case .inProgress: "health.caveat.inProgress"
        case .partial: "health.caveat.partial"
        case .none: nil
        }
    }

    static func unitKey(for type: HealthDataType) -> String {
        switch type {
        case .stepCount: "health.unit.steps"
        case .sleepAnalysis: "health.unit.hours"
        case .heartRate, .restingHeartRate: "health.unit.bpm"
        case .workouts: "health.unit.workouts"
        case .activeEnergy: "health.unit.kilocalories"
        case .standTime, .mindfulSession: "health.unit.minutes"
        case .dietaryWater: "health.unit.millilitres"
        }
    }

    /// Rounds to a sensible precision per type.
    ///
    /// Whole numbers almost everywhere: a step count with a decimal point reads
    /// as a measurement rather than a tally, and sleep to one decimal is as
    /// precise as anyone needs.
    static func format(_ value: Double, for type: HealthDataType) -> String {
        switch type {
        case .sleepAnalysis:
            return String(format: "%.1f", max(0, value))
        default:
            return String(Int(max(0, value).rounded()))
        }
    }
}

/// A hydration entry the user made deliberately (§3).
public struct HydrationLog: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let millilitres: Int
    public let loggedAt: Date
    public let sourceDeviceID: DeviceID
    public let actionKey: ActionKey
    /// Set once written to Health, so a retry cannot write it twice.
    public var healthKitSampleID: String?

    public init(
        id: UUID = UUID(),
        millilitres: Int,
        loggedAt: Date,
        sourceDeviceID: DeviceID,
        actionKey: ActionKey,
        healthKitSampleID: String? = nil
    ) {
        self.id = id
        self.millilitres = millilitres
        self.loggedAt = loggedAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
        self.healthKitSampleID = healthKitSampleID
    }

    /// The amounts the app offers as one tap.
    ///
    /// Round numbers a person recognises as "a glass" or "a bottle", rather than
    /// a slider that implies precision nobody has about what they drank.
    public static let quickAmounts = [250, 500, 750]

    /// A sanity bound, not a target and not a limit on what may be logged in a
    /// day. It exists so a mistyped entry does not become a five-litre glass.
    public static let maximumSingleEntry = 3_000
}
