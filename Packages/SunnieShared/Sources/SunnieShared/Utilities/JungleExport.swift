import Foundation

/// Everything exported about the jungle (PLANT_CARE.md §12).
///
/// The user's data is theirs, and export is how they can take it somewhere else
/// or keep a copy the app cannot lose. Structured rather than flat so a
/// round-trip stays possible later — import is explicitly deferred until the
/// model is stable, but exporting a shape that could never be read back would
/// make that decision for us.
public struct JungleExport: Hashable, Sendable, Codable {
    /// Bumped when the shape changes, so a reader can tell what it has.
    public let formatVersion: Int
    public let exportedAt: Date
    public let plants: [Plant]
    public let locations: [PlantLocation]
    public let schedules: [PlantCareSchedule]
    public let careEvents: [PlantCareEvent]
    public let observations: [PlantHealthObservation]
    public let growthEntries: [GrowthEntry]
    public let caretakers: [Caretaker]

    public static let currentFormatVersion = 1

    public init(
        formatVersion: Int = JungleExport.currentFormatVersion,
        exportedAt: Date,
        plants: [Plant],
        locations: [PlantLocation] = [],
        schedules: [PlantCareSchedule] = [],
        careEvents: [PlantCareEvent] = [],
        observations: [PlantHealthObservation] = [],
        growthEntries: [GrowthEntry] = [],
        caretakers: [Caretaker] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.plants = plants
        self.locations = locations
        self.schedules = schedules
        self.careEvents = careEvents
        self.observations = observations
        self.growthEntries = growthEntries
        self.caretakers = caretakers
    }
}

/// Serialises an export to JSON or CSV.
///
/// Both are required. JSON keeps the structure; CSV is what actually opens in a
/// spreadsheet, which is what someone means when they say they want their data.
public enum JungleExportWriter {

    public enum Format: String, Hashable, Sendable, CaseIterable {
        case json
        case csv

        public var fileExtension: String { rawValue }

        public var localizationKey: String { "export.format.\(rawValue)" }
    }

    public static func json(_ export: JungleExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // ISO 8601 rather than a floating number of seconds: an export is read by
        // people and by other software, and neither should have to guess an epoch.
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// CSV has no way to express several tables, so the export becomes several
    /// files. Returns them keyed by filename.
    public static func csvFiles(_ export: JungleExport) -> [String: String] {
        [
            "plants.csv": plantsCSV(export),
            "care_events.csv": careEventsCSV(export),
            "schedules.csv": schedulesCSV(export),
            "observations.csv": observationsCSV(export),
            "growth.csv": growthCSV(export)
        ]
    }

    // MARK: - Tables

    private static func plantsCSV(_ export: JungleExport) -> String {
        let locationsByID = Dictionary(
            uniqueKeysWithValues: export.locations.map { ($0.id, $0.name) }
        )
        return table(
            header: [
                "id", "name", "nickname", "species", "variety", "location",
                "light", "difficulty", "acquired", "source", "pot", "soil",
                "status", "notes", "created"
            ],
            rows: export.plants.map { plant in
                [
                    plant.id.uuidString,
                    plant.name,
                    plant.nickname ?? "",
                    plant.speciesName ?? "",
                    plant.variety ?? "",
                    plant.locationID.flatMap { locationsByID[$0] } ?? "",
                    plant.lightProfile.rawValue,
                    plant.difficulty.rawValue,
                    date(plant.acquiredDate),
                    plant.source ?? "",
                    plant.pot ?? "",
                    plant.soil ?? "",
                    plant.status.rawValue,
                    plant.notes ?? "",
                    date(plant.createdAt)
                ]
            }
        )
    }

    private static func careEventsCSV(_ export: JungleExport) -> String {
        let plantNames = Dictionary(
            uniqueKeysWithValues: export.plants.map { ($0.id, $0.displayName) }
        )
        return table(
            header: [
                "id", "plant_id", "plant", "care_type", "performed_at",
                "note", "measurement", "unit"
            ],
            rows: export.careEvents.map { event in
                [
                    event.id.uuidString,
                    event.plantID.uuidString,
                    plantNames[event.plantID] ?? "",
                    event.careType.storageKey,
                    date(event.performedAt),
                    event.note ?? "",
                    event.measurement.map { String($0) } ?? "",
                    event.measurementUnit ?? ""
                ]
            }
        )
    }

    private static func schedulesCSV(_ export: JungleExport) -> String {
        let plantNames = Dictionary(
            uniqueKeysWithValues: export.plants.map { ($0.id, $0.displayName) }
        )
        return table(
            header: [
                "id", "plant_id", "plant", "care_type", "interval_days",
                "preferred_hour", "enabled", "last_completed", "next_due"
            ],
            rows: export.schedules.map { schedule in
                [
                    schedule.id.uuidString,
                    schedule.plantID.uuidString,
                    plantNames[schedule.plantID] ?? "",
                    schedule.careType.storageKey,
                    schedule.recurrence.intervalDays.map(String.init) ?? "",
                    String(schedule.preferredHour),
                    schedule.isEnabled ? "yes" : "no",
                    date(schedule.lastCompletedAt),
                    date(schedule.nextDueDate)
                ]
            }
        )
    }

    private static func observationsCSV(_ export: JungleExport) -> String {
        let plantNames = Dictionary(
            uniqueKeysWithValues: export.plants.map { ($0.id, $0.displayName) }
        )
        return table(
            header: [
                "id", "plant_id", "plant", "observed_at", "category", "severity",
                "notes", "suspected_cause", "treatment", "follow_up", "resolved"
            ],
            rows: export.observations.map { observation in
                [
                    observation.id.uuidString,
                    observation.plantID.uuidString,
                    plantNames[observation.plantID] ?? "",
                    date(observation.observedAt),
                    observation.category.rawValue,
                    observation.severity.rawValue,
                    observation.notes ?? "",
                    observation.suspectedCause ?? "",
                    observation.treatment ?? "",
                    date(observation.followUpDate),
                    date(observation.resolvedAt)
                ]
            }
        )
    }

    private static func growthCSV(_ export: JungleExport) -> String {
        let plantNames = Dictionary(
            uniqueKeysWithValues: export.plants.map { ($0.id, $0.displayName) }
        )
        return table(
            header: [
                "id", "plant_id", "plant", "recorded_at", "metric", "value",
                "unit", "note", "milestone", "milestone_label", "has_photo"
            ],
            rows: export.growthEntries.map { entry in
                [
                    entry.id.uuidString,
                    entry.plantID.uuidString,
                    plantNames[entry.plantID] ?? "",
                    date(entry.recordedAt),
                    entry.metric?.rawValue ?? "",
                    entry.value.map { String($0) } ?? "",
                    entry.unit ?? "",
                    entry.note ?? "",
                    entry.isMilestone ? "yes" : "no",
                    entry.milestoneLabel ?? "",
                    entry.photoAttachmentID == nil ? "no" : "yes"
                ]
            }
        )
    }

    // MARK: - CSV mechanics

    private static func table(header: [String], rows: [[String]]) -> String {
        // CRLF, which is what RFC 4180 specifies and what Excel expects. A file
        // that opens wrong in the one program most people will use is not an
        // export.
        ([header] + rows)
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\r\n")
            + "\r\n"
    }

    /// Quotes a field when it contains a comma, a quote, or a newline, doubling
    /// any quotes inside. A plant note with a comma in it must not silently
    /// become two columns.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func date(_ value: Date?) -> String {
        guard let value else { return "" }
        return ISO8601DateFormatter().string(from: value)
    }
}
