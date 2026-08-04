import Foundation

/// What was noticed. Categories are descriptive observations, not diagnoses —
/// "yellowing leaves" is something you can see, "root rot" is a conclusion, and
/// the app does not draw conclusions (PLANT_CARE.md §8).
///
/// The user's own suspected cause is recorded separately, as free text, because
/// it is *their* hypothesis and the app should not turn it into a fact.
public enum SymptomCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case yellowingLeaves
    case brownTips
    case droopingLeaves
    case leafDrop
    case spots
    case pests
    case mould
    case stuntedGrowth
    case rootConcern
    case damage
    case other

    public var localizationKey: String { "symptom.\(rawValue)" }
}

/// How much it seems to matter, **as judged by the user**.
///
/// Deliberately three coarse steps rather than a numeric scale: a finer scale
/// would invite the app to compute with it, and there is nothing here worth
/// computing. It orders a list; it does not measure a plant.
public enum ObservationSeverity: String, Hashable, Sendable, Codable, CaseIterable {
    case mild
    case noticeable
    case significant

    public var localizationKey: String { "severity.\(rawValue)" }

    /// Sort order for showing the more pressing observations first.
    public var rank: Int {
        switch self {
        case .mild: 0
        case .noticeable: 1
        case .significant: 2
        }
    }
}

/// Something the user noticed about a plant (PLANT_CARE.md §8).
///
/// Every interpretive field is the user's: the severity they chose, the cause
/// they suspect, the treatment they tried. The app stores and orders these. It
/// does not diagnose, predict, or infer, and no copy anywhere may present a
/// stored observation as a finding.
public struct PlantHealthObservation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let plantID: UUID
    public var observedAt: Date
    public var category: SymptomCategory
    public var severity: ObservationSeverity
    public var notes: String?
    /// The user's own hypothesis, in their words. Never generated.
    public var suspectedCause: String?
    /// What the user did about it, in their words.
    public var treatment: String?
    /// When the user asked to be reminded to look again.
    public var followUpDate: Date?
    /// Set when the user says it is better. Nothing sets this automatically —
    /// the app cannot tell.
    public var resolvedAt: Date?
    public let sourceDeviceID: DeviceID
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        plantID: UUID,
        observedAt: Date,
        category: SymptomCategory,
        severity: ObservationSeverity = .mild,
        notes: String? = nil,
        suspectedCause: String? = nil,
        treatment: String? = nil,
        followUpDate: Date? = nil,
        resolvedAt: Date? = nil,
        sourceDeviceID: DeviceID,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.observedAt = observedAt
        self.category = category
        self.severity = severity
        self.notes = notes
        self.suspectedCause = suspectedCause
        self.treatment = treatment
        self.followUpDate = followUpDate
        self.resolvedAt = resolvedAt
        self.sourceDeviceID = sourceDeviceID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var isResolved: Bool { resolvedAt != nil }

    /// Media attaches to the plant, so a growth photo and an observation photo
    /// live in the same place. This owner value keeps them addressable together.
    public var mediaOwner: MediaOwner { .plant(plantID) }
}

/// What a measurement is measuring. A closed set so two entries of the same kind
/// can be compared; anything else goes in the note.
public enum GrowthMetric: String, Hashable, Sendable, Codable, CaseIterable {
    case height
    case width
    case leafCount
    case newGrowth

    public var localizationKey: String { "growth.metric.\(rawValue)" }

    /// Whether the metric is a count rather than a length, which decides whether
    /// a unit applies at all.
    public var isCount: Bool { self == .leafCount || self == .newGrowth }
}

/// One point on a plant's growth timeline (PLANT_CARE.md §9).
///
/// A photo, a measurement, a note, or a milestone — any combination, all
/// optional except the date. Someone who only ever takes photos should never see
/// a measurement field they have to skip.
public struct GrowthEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let plantID: UUID
    public var recordedAt: Date
    public var metric: GrowthMetric?
    public var value: Double?
    /// Free text so a user can record inches, centimetres, or nothing at all.
    public var unit: String?
    public var note: String?
    /// Marks a moment worth returning to — first new leaf, first flower, repotted.
    public var isMilestone: Bool
    public var milestoneLabel: String?
    /// The photo for this point in the timeline, if there is one.
    public var photoAttachmentID: UUID?
    public let sourceDeviceID: DeviceID
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        plantID: UUID,
        recordedAt: Date,
        metric: GrowthMetric? = nil,
        value: Double? = nil,
        unit: String? = nil,
        note: String? = nil,
        isMilestone: Bool = false,
        milestoneLabel: String? = nil,
        photoAttachmentID: UUID? = nil,
        sourceDeviceID: DeviceID,
        createdAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.recordedAt = recordedAt
        self.metric = metric
        self.value = value
        self.unit = unit
        self.note = note
        self.isMilestone = isMilestone
        self.milestoneLabel = milestoneLabel
        self.photoAttachmentID = photoAttachmentID
        self.sourceDeviceID = sourceDeviceID
        self.createdAt = createdAt
    }

    /// An entry with nothing in it is not worth storing.
    public var isEmpty: Bool {
        value == nil
            && photoAttachmentID == nil
            && (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !isMilestone
    }

    /// True when this entry can be compared against another on the same axis.
    public func isComparable(with other: GrowthEntry) -> Bool {
        guard let metric, let otherMetric = other.metric, metric == otherMetric else {
            return false
        }
        guard value != nil, other.value != nil else { return false }
        // Comparing 30cm against 12in would produce a nonsense delta, so entries
        // with different units are simply not comparable rather than converted:
        // the unit is free text and the app cannot reliably interpret it.
        return metric.isCount || normalizedUnit == other.normalizedUnit
    }

    private var normalizedUnit: String {
        (unit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Someone who can look after plants while the user is away (PLANT_CARE.md §10).
///
/// A local record with a name and an optional way to reach them. No account, no
/// invitation, no backend — the caretaker app is a later specification, and
/// until it exists this exists so instructions can be addressed to a person.
public struct Caretaker: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    /// However the user wants to reach them, in their words. Not validated as an
    /// email or a phone number, because it might be neither.
    public var contactNote: String?
    public var isActive: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        contactNote: String? = nil,
        isActive: Bool = true,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.contactNote = contactNote
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
