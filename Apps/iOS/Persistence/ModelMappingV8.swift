import Foundation
import SunnieShared

/// Mapping for the model added in schema V8.
extension ModelMapping {

    static func domain(_ model: SDHydrationLog) -> HydrationLog {
        HydrationLog(
            id: model.id,
            millilitres: model.millilitres,
            loggedAt: model.loggedAt,
            sourceDeviceID: DeviceID(rawValue: model.sourceDeviceID),
            actionKey: ActionKey(rawValue: model.actionKey),
            // Empty means "not written yet", which is different from a sample
            // identifier that happens to be empty — a distinction the domain type
            // makes with an optional and the store makes with a default.
            healthKitSampleID: model.healthKitSampleID.isEmpty
                ? nil : model.healthKitSampleID
        )
    }

    static func apply(_ entry: HydrationLog, to model: SDHydrationLog) {
        model.id = entry.id
        model.millilitres = entry.millilitres
        model.loggedAt = entry.loggedAt
        model.sourceDeviceID = entry.sourceDeviceID.rawValue
        model.actionKey = entry.actionKey.rawValue
        model.healthKitSampleID = entry.healthKitSampleID ?? ""
    }
}
