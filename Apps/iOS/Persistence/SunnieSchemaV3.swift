import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 3 — the full Jungle.
///
/// **Additive, like V2.** Health observations, growth entries, caretakers,
/// travel coverage, and care-event supersession are all new models. Not one
/// existing model changes shape, so the stage stays lightweight and the V1 and
/// V2 model classes remain shared rather than frozen into namespaces.
///
/// Keeping it additive was a design constraint, not a coincidence. Correcting a
/// care event wants a "this replaced that" link, and the obvious place for it is
/// a field on `SDPlantCareEvent` — but adding one would change a model that has
/// existed since V1, which is the exact point at which the shared-class shortcut
/// stops being sound and `SchemaMigrationTests` can no longer build a genuine V1
/// store to migrate. The link lives in `SDCareEventSupersession` instead, which
/// is also the better model: the care log is append-only, and "this event
/// replaces that one" is a fact about the pair rather than about either event
/// (ADR-017).
///
/// The next change that alters an existing model's shape must copy V1's and V2's
/// models into frozen per-version namespaces and use a custom stage.
enum SunnieSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            // Unchanged from V1.
            SDUserProfile.self,
            SDUserPreferences.self,
            SDPlant.self,
            SDPlantLocation.self,
            SDPlantCareSchedule.self,
            SDPlantCareEvent.self,
            SDProgressionProfile.self,
            SDProgressionEvent.self,
            SDRewardGrant.self,
            SDThemeSelection.self,
            SDPendingWatchAction.self,
            // Unchanged from V2.
            SDWellnessCheckIn.self,
            SDWellnessSession.self,
            SDJournalEntry.self,
            SDMediaAttachment.self,
            SDScheduledReminder.self,
            // New in V3.
            SDPlantHealthObservation.self,
            SDGrowthEntry.self,
            SDCaretaker.self,
            SDPlantTravelCoverage.self,
            SDCareEventSupersession.self
        ]
    }
}

// MARK: - Health

/// Something the user noticed (PLANT_CARE.md §8).
///
/// Every interpretive field here was chosen or typed by the user. Nothing in the
/// app writes a severity, a suspected cause, or a resolution on its own, and no
/// query may present these as findings.
@Model
final class SDPlantHealthObservation {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    var observedAt: Date = Date()
    var categoryRaw: String = SymptomCategory.other.rawValue
    var severityRaw: String = ObservationSeverity.mild.rawValue
    var notes: String?
    var suspectedCause: String?
    var treatment: String?
    var followUpDate: Date?
    var resolvedAt: Date?
    var sourceDeviceID: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        plantID: UUID = UUID(),
        observedAt: Date = Date(),
        categoryRaw: String = SymptomCategory.other.rawValue,
        severityRaw: String = ObservationSeverity.mild.rawValue,
        notes: String? = nil,
        suspectedCause: String? = nil,
        treatment: String? = nil,
        followUpDate: Date? = nil,
        resolvedAt: Date? = nil,
        sourceDeviceID: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.plantID = plantID
        self.observedAt = observedAt
        self.categoryRaw = categoryRaw
        self.severityRaw = severityRaw
        self.notes = notes
        self.suspectedCause = suspectedCause
        self.treatment = treatment
        self.followUpDate = followUpDate
        self.resolvedAt = resolvedAt
        self.sourceDeviceID = sourceDeviceID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// One point on the growth timeline (PLANT_CARE.md §9).
@Model
final class SDGrowthEntry {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    var recordedAt: Date = Date()
    /// Nil for a photo-only or note-only entry.
    var metricRaw: String?
    var value: Double?
    var unit: String?
    var note: String?
    var isMilestone: Bool = false
    var milestoneLabel: String?
    /// Points at an `SDMediaAttachment`. A UUID rather than a relationship,
    /// because relationships are not CloudKit-compatible here (ADR-011).
    var photoAttachmentID: UUID?
    var sourceDeviceID: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        plantID: UUID = UUID(),
        recordedAt: Date = Date(),
        metricRaw: String? = nil,
        value: Double? = nil,
        unit: String? = nil,
        note: String? = nil,
        isMilestone: Bool = false,
        milestoneLabel: String? = nil,
        photoAttachmentID: UUID? = nil,
        sourceDeviceID: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.plantID = plantID
        self.recordedAt = recordedAt
        self.metricRaw = metricRaw
        self.value = value
        self.unit = unit
        self.note = note
        self.isMilestone = isMilestone
        self.milestoneLabel = milestoneLabel
        self.photoAttachmentID = photoAttachmentID
        self.sourceDeviceID = sourceDeviceID
        self.createdAt = createdAt
    }
}

// MARK: - Coverage

/// Someone who can look after plants during an absence (PLANT_CARE.md §10).
///
/// Purely local. No account, no invitation, no backend — the caretaker app is a
/// later specification.
@Model
final class SDCaretaker {
    var id: UUID = UUID()
    var name: String = ""
    var contactNote: String?
    var isActive: Bool = true
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        contactNote: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.contactNote = contactNote
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

/// A plant's coverage plan for one trip.
///
/// Trips arrive in Phase 5. This ships now because the plant side of coverage —
/// working out what falls inside an absence and who is looking after it — belongs
/// to the Jungle, and building it later would mean revisiting every plant screen.
@Model
final class SDPlantTravelCoverage {
    var id: UUID = UUID()
    var tripID: UUID = UUID()
    var plantID: UUID = UUID()
    /// `selfManaged`, `caretaker`, or `unresolved`. Stored as a string plus an
    /// optional ID rather than an encoded enum, so the assignment stays queryable.
    var assignmentRaw: String = "unresolved"
    var caretakerID: UUID?
    var instructions: String?
    var lastCareBeforeDeparture: Date?
    var caretakerUpdateNote: String?
    var caretakerUpdatedAt: Date?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        tripID: UUID = UUID(),
        plantID: UUID = UUID(),
        assignmentRaw: String = "unresolved",
        caretakerID: UUID? = nil,
        instructions: String? = nil,
        lastCareBeforeDeparture: Date? = nil,
        caretakerUpdateNote: String? = nil,
        caretakerUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.plantID = plantID
        self.assignmentRaw = assignmentRaw
        self.caretakerID = caretakerID
        self.instructions = instructions
        self.lastCareBeforeDeparture = lastCareBeforeDeparture
        self.caretakerUpdateNote = caretakerUpdateNote
        self.caretakerUpdatedAt = caretakerUpdatedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Corrections

/// "This care event replaced that one."
///
/// A separate record rather than a field on `SDPlantCareEvent`, for the reason
/// given on `SunnieSchemaV3`: the care log has been append-only since V1 and its
/// row shape must stay exactly as it was. It is also the more honest model — the
/// supersession is a fact about the pair, and neither event is changed by it.
@Model
final class SDCareEventSupersession {
    var id: UUID = UUID()
    var plantID: UUID = UUID()
    /// The event that was corrected.
    var supersededEventID: UUID = UUID()
    /// The event that corrected it.
    var replacementEventID: UUID = UUID()
    var recordedAt: Date = Date()

    init(
        id: UUID = UUID(),
        plantID: UUID = UUID(),
        supersededEventID: UUID = UUID(),
        replacementEventID: UUID = UUID(),
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.plantID = plantID
        self.supersededEventID = supersededEventID
        self.replacementEventID = replacementEventID
        self.recordedAt = recordedAt
    }
}
