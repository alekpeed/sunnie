import Foundation

/// One plant's part of a bulk care action, with its own overrides.
///
/// Per-plant overrides exist because "water these six" is usually true and
/// sometimes nearly true — one of them got half as much, one got a note. Without
/// overrides the user would have to drop out of the bulk flow to record that
/// (PLANT_CARE.md §6).
public struct BulkCareItem: Hashable, Sendable, Identifiable {
    public let plantID: UUID
    /// Overrides the action's care type for this plant only.
    public var careTypeOverride: CareType?
    public var note: String?
    public var measurement: Double?
    public var measurementUnit: String?
    /// Unticking a plant keeps it visible in the sheet while excluding it, which
    /// is easier to correct than removing the row.
    public var isIncluded: Bool

    public var id: UUID { plantID }

    public init(
        plantID: UUID,
        careTypeOverride: CareType? = nil,
        note: String? = nil,
        measurement: Double? = nil,
        measurementUnit: String? = nil,
        isIncluded: Bool = true
    ) {
        self.plantID = plantID
        self.careTypeOverride = careTypeOverride
        self.note = note
        self.measurement = measurement
        self.measurementUnit = measurementUnit
        self.isIncluded = isIncluded
    }
}

/// What happened to each plant in a bulk action.
///
/// A bulk action is many independent saves, not one transaction. Fifteen plants
/// watered and one failure is fifteen plants watered — rolling the others back
/// would destroy real work to preserve a tidy abstraction (PLANT_CARE.md §15,
/// "bulk action partially fails").
public struct BulkCareResult: Hashable, Sendable {

    public enum Outcome: Hashable, Sendable {
        case recorded
        /// Already logged — a double tap, or the same minute from the Watch.
        /// Presented to the user as success, because from their point of view it
        /// worked (ADR-013).
        case alreadyRecorded
        case failed(String)
    }

    public let outcomes: [UUID: Outcome]

    public init(outcomes: [UUID: Outcome]) {
        self.outcomes = outcomes
    }

    public var recordedCount: Int {
        outcomes.values.filter { $0 == .recorded || $0 == .alreadyRecorded }.count
    }

    public var failedPlantIDs: [UUID] {
        outcomes.compactMap { key, value in
            if case .failed = value { return key }
            return nil
        }
    }

    public var hasFailures: Bool { !failedPlantIDs.isEmpty }

    /// True when nothing at all went through, which is the only case worth
    /// presenting as a problem rather than a partial success.
    public var isCompleteFailure: Bool {
        !outcomes.isEmpty && recordedCount == 0
    }
}
