import Foundation

/// Built-in care actions (PLANT_CARE.md §3). `custom` carries a content ID so a
/// user-defined action keeps a stable identity across renames.
public enum CareType: Hashable, Sendable, Codable {
    case water
    case fertilize
    case mist
    case rotate
    case cleanLeaves
    case prune
    case repot
    case propagate
    case pestTreatment
    case healthInspection
    case custom(ContentID)

    /// Stable string used in action keys and persisted records. Changing these
    /// values is a migration, not a rename.
    public var storageKey: String {
        switch self {
        case .water: "water"
        case .fertilize: "fertilize"
        case .mist: "mist"
        case .rotate: "rotate"
        case .cleanLeaves: "cleanLeaves"
        case .prune: "prune"
        case .repot: "repot"
        case .propagate: "propagate"
        case .pestTreatment: "pestTreatment"
        case .healthInspection: "healthInspection"
        case .custom(let id): "custom:\(id.rawValue)"
        }
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("custom:") {
            let raw = String(storageKey.dropFirst("custom:".count))
            guard !raw.isEmpty else { return nil }
            self = .custom(ContentID(rawValue: raw))
            return
        }
        switch storageKey {
        case "water": self = .water
        case "fertilize": self = .fertilize
        case "mist": self = .mist
        case "rotate": self = .rotate
        case "cleanLeaves": self = .cleanLeaves
        case "prune": self = .prune
        case "repot": self = .repot
        case "propagate": self = .propagate
        case "pestTreatment": self = .pestTreatment
        case "healthInspection": self = .healthInspection
        default: return nil
        }
    }

    public static let builtIn: [CareType] = [
        .water, .fertilize, .mist, .rotate, .cleanLeaves,
        .prune, .repot, .propagate, .pestTreatment, .healthInspection
    ]

    /// The shortest interval after which repeating this action is plausible.
    ///
    /// Used to keep progression honest: logging the same care ten times in an
    /// hour must not farm rewards (PLANT_CARE.md §13). This is a rewards guard,
    /// not a restriction — the user may always record what they actually did.
    public var minimumPlausibleRepeat: TimeInterval {
        switch self {
        case .water, .fertilize, .repot, .propagate: 60 * 60 * 20
        case .mist, .cleanLeaves, .prune, .pestTreatment: 60 * 60 * 8
        case .rotate, .healthInspection: 60 * 60 * 8
        case .custom: 60 * 60 * 8
        }
    }
}

/// How often a care action recurs. Deliberately small for the vertical slice;
/// seasonal and calendar-anchored recurrences arrive in Phase 4.
public enum CareRecurrence: Hashable, Sendable, Codable {
    /// Repeat a fixed number of days after the last completion.
    case everyDays(Int)
    /// No schedule; the user logs this action when they choose to.
    case manual

    public var intervalDays: Int? {
        if case .everyDays(let days) = self { return days }
        return nil
    }
}

/// Multiplies the base interval by season. Plants drink less in winter; the app
/// models that as a schedule adjustment rather than a biological claim.
public struct SeasonalModifier: Hashable, Sendable, Codable {
    public var springMultiplier: Double
    public var summerMultiplier: Double
    public var autumnMultiplier: Double
    public var winterMultiplier: Double

    public static let none = SeasonalModifier(
        springMultiplier: 1, summerMultiplier: 1,
        autumnMultiplier: 1, winterMultiplier: 1
    )

    public init(
        springMultiplier: Double,
        summerMultiplier: Double,
        autumnMultiplier: Double,
        winterMultiplier: Double
    ) {
        self.springMultiplier = springMultiplier
        self.summerMultiplier = summerMultiplier
        self.autumnMultiplier = autumnMultiplier
        self.winterMultiplier = winterMultiplier
    }

    public func multiplier(for season: Season) -> Double {
        switch season {
        case .spring: springMultiplier
        case .summer: summerMultiplier
        case .autumn: autumnMultiplier
        case .winter: winterMultiplier
        }
    }
}

public enum Season: String, Hashable, Sendable, Codable, CaseIterable {
    case spring, summer, autumn, winter

    public var localizationKey: String { "season.\(rawValue)" }

    /// Northern-hemisphere meteorological seasons.
    public static func from(month: Int) -> Season {
        switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }

    /// The season at a date, in whichever hemisphere the user is in.
    ///
    /// Hemisphere matters for the home scene's window: a Brazilian December is
    /// summer, and insisting otherwise would be wrong about the weather someone
    /// is actually looking at. Care scheduling still uses `from(month:)`
    /// directly, because a plant's watering rhythm follows the light it is
    /// getting rather than the calendar's name for the season.
    public static func current(
        for date: Date, calendar: Calendar, isNorthernHemisphere: Bool
    ) -> Season {
        let northern = from(month: calendar.component(.month, from: date))
        return isNorthernHemisphere ? northern : northern.opposite
    }

    public var opposite: Season {
        switch self {
        case .spring: .autumn
        case .summer: .winter
        case .autumn: .spring
        case .winter: .summer
        }
    }
}

/// A recurring care commitment for one plant and one care type.
public struct PlantCareSchedule: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let plantID: UUID
    public var careType: CareType
    public var recurrence: CareRecurrence
    public var seasonalModifier: SeasonalModifier
    /// Hour of day (0–23) the task should surface. Times are resolved in the
    /// user's active time zone, not stored as absolute instants.
    public var preferredHour: Int
    public var isEnabled: Bool
    public var lastCompletedAt: Date?
    public var nextDueDate: Date?

    public init(
        id: UUID = UUID(),
        plantID: UUID,
        careType: CareType,
        recurrence: CareRecurrence,
        seasonalModifier: SeasonalModifier = .none,
        preferredHour: Int = 9,
        isEnabled: Bool = true,
        lastCompletedAt: Date? = nil,
        nextDueDate: Date? = nil
    ) {
        self.id = id
        self.plantID = plantID
        self.careType = careType
        self.recurrence = recurrence
        self.seasonalModifier = seasonalModifier
        self.preferredHour = preferredHour
        self.isEnabled = isEnabled
        self.lastCompletedAt = lastCompletedAt
        self.nextDueDate = nextDueDate
    }
}

/// An append-only record that a care action happened (PLANT_CARE.md §7).
public struct PlantCareEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let plantID: UUID
    public let careType: CareType
    public var performedAt: Date
    public let sourceDeviceID: DeviceID
    public var caretakerID: UUID?
    public var note: String?
    public var photoID: UUID?
    /// Optional quantity or duration, e.g. millilitres of water.
    public var measurement: Double?
    public var measurementUnit: String?
    /// Deterministic key that makes a replayed action a no-op.
    public let actionKey: ActionKey
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        plantID: UUID,
        careType: CareType,
        performedAt: Date,
        sourceDeviceID: DeviceID,
        caretakerID: UUID? = nil,
        note: String? = nil,
        photoID: UUID? = nil,
        measurement: Double? = nil,
        measurementUnit: String? = nil,
        actionKey: ActionKey,
        createdAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.careType = careType
        self.performedAt = performedAt
        self.sourceDeviceID = sourceDeviceID
        self.caretakerID = caretakerID
        self.note = note
        self.photoID = photoID
        self.measurement = measurement
        self.measurementUnit = measurementUnit
        self.actionKey = actionKey
        self.createdAt = createdAt
    }
}
