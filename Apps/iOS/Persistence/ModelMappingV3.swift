import Foundation
import SunnieShared

/// Mapping for the models added in schema V3.
///
/// Same discipline as V1 and V2: nothing outside Persistence sees an `SD` type,
/// and an unreadable raw value falls back to a safe default rather than trapping.
/// Losing a record to a force-unwrap would be worse than showing it
/// conservatively.
extension ModelMapping {

    // MARK: - Health observations

    static func domain(_ model: SDPlantHealthObservation) -> PlantHealthObservation {
        PlantHealthObservation(
            id: model.id,
            plantID: model.plantID,
            observedAt: model.observedAt,
            // An unknown category reads as "other" rather than being dropped. The
            // user's note is the substance of the record; the category is how it
            // is filed, and filing it under the wrong heading loses less than
            // discarding the observation entirely.
            category: SymptomCategory(rawValue: model.categoryRaw) ?? .other,
            severity: ObservationSeverity(rawValue: model.severityRaw) ?? .mild,
            notes: model.notes,
            suspectedCause: model.suspectedCause,
            treatment: model.treatment,
            followUpDate: model.followUpDate,
            resolvedAt: model.resolvedAt,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func model(_ observation: PlantHealthObservation) -> SDPlantHealthObservation {
        SDPlantHealthObservation(
            id: observation.id,
            plantID: observation.plantID,
            observedAt: observation.observedAt,
            categoryRaw: observation.category.rawValue,
            severityRaw: observation.severity.rawValue,
            notes: observation.notes,
            suspectedCause: observation.suspectedCause,
            treatment: observation.treatment,
            followUpDate: observation.followUpDate,
            resolvedAt: observation.resolvedAt,
            sourceDeviceID: observation.sourceDeviceID.rawValue,
            createdAt: observation.createdAt,
            modifiedAt: observation.modifiedAt
        )
    }

    static func apply(_ observation: PlantHealthObservation, to model: SDPlantHealthObservation) {
        model.observedAt = observation.observedAt
        model.categoryRaw = observation.category.rawValue
        model.severityRaw = observation.severity.rawValue
        model.notes = observation.notes
        model.suspectedCause = observation.suspectedCause
        model.treatment = observation.treatment
        model.followUpDate = observation.followUpDate
        model.resolvedAt = observation.resolvedAt
        model.modifiedAt = observation.modifiedAt
    }

    // MARK: - Growth

    static func domain(_ model: SDGrowthEntry) -> GrowthEntry {
        GrowthEntry(
            id: model.id,
            plantID: model.plantID,
            recordedAt: model.recordedAt,
            metric: model.metricRaw.flatMap(GrowthMetric.init(rawValue:)),
            value: model.value,
            unit: model.unit,
            note: model.note,
            isMilestone: model.isMilestone,
            milestoneLabel: model.milestoneLabel,
            photoAttachmentID: model.photoAttachmentID,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            createdAt: model.createdAt
        )
    }

    static func model(_ entry: GrowthEntry) -> SDGrowthEntry {
        SDGrowthEntry(
            id: entry.id,
            plantID: entry.plantID,
            recordedAt: entry.recordedAt,
            metricRaw: entry.metric?.rawValue,
            value: entry.value,
            unit: entry.unit,
            note: entry.note,
            isMilestone: entry.isMilestone,
            milestoneLabel: entry.milestoneLabel,
            photoAttachmentID: entry.photoAttachmentID,
            sourceDeviceID: entry.sourceDeviceID.rawValue,
            createdAt: entry.createdAt
        )
    }

    static func apply(_ entry: GrowthEntry, to model: SDGrowthEntry) {
        model.recordedAt = entry.recordedAt
        model.metricRaw = entry.metric?.rawValue
        model.value = entry.value
        model.unit = entry.unit
        model.note = entry.note
        model.isMilestone = entry.isMilestone
        model.milestoneLabel = entry.milestoneLabel
        model.photoAttachmentID = entry.photoAttachmentID
    }

    // MARK: - Caretakers

    static func domain(_ model: SDCaretaker) -> Caretaker {
        Caretaker(
            id: model.id,
            name: model.name,
            contactNote: model.contactNote,
            isActive: model.isActive,
            createdAt: model.createdAt
        )
    }

    static func model(_ caretaker: Caretaker) -> SDCaretaker {
        SDCaretaker(
            id: caretaker.id,
            name: caretaker.name,
            contactNote: caretaker.contactNote,
            isActive: caretaker.isActive,
            createdAt: caretaker.createdAt
        )
    }

    static func apply(_ caretaker: Caretaker, to model: SDCaretaker) {
        model.name = caretaker.name
        model.contactNote = caretaker.contactNote
        model.isActive = caretaker.isActive
    }

    // MARK: - Coverage

    /// Assignment raw values. Written out rather than derived from the enum,
    /// because `CoverageAssignment` has an associated value and its `caretaker`
    /// case has no free-standing raw string to borrow.
    enum CoverageAssignmentKey {
        static let selfManaged = "selfManaged"
        static let caretaker = "caretaker"
        static let unresolved = "unresolved"
    }

    static func domain(_ model: SDPlantTravelCoverage) -> PlantTravelCoverage {
        let assignment: CoverageAssignment
        switch model.assignmentRaw {
        case CoverageAssignmentKey.selfManaged:
            assignment = .selfManaged
        case CoverageAssignmentKey.caretaker:
            // A caretaker assignment with no caretaker is not an assignment. It
            // reads as undecided, which surfaces it for the user to settle rather
            // than quietly claiming the plant is covered.
            assignment = model.caretakerID.map(CoverageAssignment.caretaker) ?? .unresolved
        default:
            assignment = .unresolved
        }

        return PlantTravelCoverage(
            id: model.id,
            tripID: model.tripID,
            plantID: model.plantID,
            assignment: assignment,
            instructions: model.instructions,
            lastCareBeforeDeparture: model.lastCareBeforeDeparture,
            caretakerUpdateNote: model.caretakerUpdateNote,
            caretakerUpdatedAt: model.caretakerUpdatedAt,
            createdAt: model.createdAt,
            modifiedAt: model.modifiedAt
        )
    }

    static func model(_ coverage: PlantTravelCoverage) -> SDPlantTravelCoverage {
        SDPlantTravelCoverage(
            id: coverage.id,
            tripID: coverage.tripID,
            plantID: coverage.plantID,
            assignmentRaw: assignmentRaw(coverage.assignment),
            caretakerID: coverage.assignment.caretakerID,
            instructions: coverage.instructions,
            lastCareBeforeDeparture: coverage.lastCareBeforeDeparture,
            caretakerUpdateNote: coverage.caretakerUpdateNote,
            caretakerUpdatedAt: coverage.caretakerUpdatedAt,
            createdAt: coverage.createdAt,
            modifiedAt: coverage.modifiedAt
        )
    }

    static func apply(_ coverage: PlantTravelCoverage, to model: SDPlantTravelCoverage) {
        model.assignmentRaw = assignmentRaw(coverage.assignment)
        model.caretakerID = coverage.assignment.caretakerID
        model.instructions = coverage.instructions
        model.lastCareBeforeDeparture = coverage.lastCareBeforeDeparture
        model.caretakerUpdateNote = coverage.caretakerUpdateNote
        model.caretakerUpdatedAt = coverage.caretakerUpdatedAt
        model.modifiedAt = coverage.modifiedAt
    }

    private static func assignmentRaw(_ assignment: CoverageAssignment) -> String {
        switch assignment {
        case .selfManaged: CoverageAssignmentKey.selfManaged
        case .caretaker: CoverageAssignmentKey.caretaker
        case .unresolved: CoverageAssignmentKey.unresolved
        }
    }
}
