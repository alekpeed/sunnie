import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 8 — hydration.
///
/// **Additive, like V2 through V7.** One new model.
///
/// Hydration is stored locally as well as written to Health rather than only in
/// Health, for the reason §1 gives: the app must work without HealthKit. A log
/// that lived only in Health would vanish for anyone who declined the
/// permission, which would make an ordinary feature silently conditional on an
/// optional integration.
enum SunnieSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SunnieSchemaV7.models + [SDHydrationLog.self]
    }
}

/// One deliberate hydration entry.
///
/// `healthKitSampleID` is empty until the sample is written, and never cleared
/// afterwards. That is what stops a retry — a permission granted later, an app
/// relaunch mid-write — from writing the same glass of water into Health twice.
@Model
final class SDHydrationLog {
    var id: UUID = UUID()
    var millilitres: Int = 0
    var loggedAt: Date = Date()
    var sourceDeviceID: String = ""
    var actionKey: String = ""
    var healthKitSampleID: String = ""

    init(
        id: UUID = UUID(),
        millilitres: Int = 0,
        loggedAt: Date = Date(),
        sourceDeviceID: String = "",
        actionKey: String = "",
        healthKitSampleID: String = ""
    ) {
        self.id = id
        self.millilitres = millilitres
        self.loggedAt = loggedAt
        self.sourceDeviceID = sourceDeviceID
        self.actionKey = actionKey
        self.healthKitSampleID = healthKitSampleID
    }
}
