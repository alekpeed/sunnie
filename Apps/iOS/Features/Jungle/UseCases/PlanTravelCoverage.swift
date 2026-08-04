import Foundation
import SunnieShared

/// Works out which plants need attention during an absence, and records who is
/// looking after them (PLANT_CARE.md §10).
///
/// Trips arrive in Phase 5; this is the plant side, and it takes a date range
/// rather than a trip object so it does not depend on a feature that does not
/// exist yet. When trips land they supply the range and the ID.
///
/// **Nothing here is alarmist.** The word "risk" appears in the spec's section
/// title and nowhere in the copy. A plant with unresolved coverage is described
/// as undecided, not endangered, and no output of this type may be presented as
/// a warning about a plant's survival.
struct PlanTravelCoverage: Sendable {

    /// One plant's row on the coverage screen: what it needs, and what has been
    /// decided about it.
    struct CoverageRow: Sendable, Identifiable {
        let plant: Plant
        let need: CoverageNeed
        let coverage: PlantTravelCoverage?

        var id: UUID { plant.id }

        var assignment: CoverageAssignment { coverage?.assignment ?? .unresolved }

        /// Needs a decision: something falls inside the absence and nobody has
        /// said what happens about it.
        var isUndecided: Bool { need.needsAnything && !assignment.isDecided }
    }

    private let plantRepository: any PlantRepository
    private let careEventRepository: any PlantCareEventRepository
    private let healthRepository: any PlantHealthRepository
    private let progressionEngine: ProgressionEngine
    private let clock: any SunnieClock

    init(
        plantRepository: any PlantRepository,
        careEventRepository: any PlantCareEventRepository,
        healthRepository: any PlantHealthRepository,
        progressionEngine: ProgressionEngine,
        clock: any SunnieClock
    ) {
        self.plantRepository = plantRepository
        self.careEventRepository = careEventRepository
        self.healthRepository = healthRepository
        self.progressionEngine = progressionEngine
        self.clock = clock
    }

    /// Builds the coverage picture for an absence.
    ///
    /// Plants that need nothing are still returned. Leaving them out would make
    /// the screen look like a to-do list of problems, when most of the answer is
    /// usually "these are fine".
    func rows(
        tripID: UUID,
        absenceStart: Date,
        absenceEnd: Date
    ) async throws -> [CoverageRow] {
        let plants = try await plantRepository.allPlants(includingArchived: false)
        let existing = try await healthRepository.coverage(forTripID: tripID)
        let coverageByPlant = Dictionary(
            existing.map { ($0.plantID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var rows: [CoverageRow] = []
        for plant in plants {
            let schedules = try await plantRepository.schedules(forPlantID: plant.id)
            let need = CoveragePlanner.need(
                plant: plant,
                schedules: schedules,
                absenceStart: absenceStart,
                absenceEnd: absenceEnd,
                calendar: clock.calendar,
                timeZone: clock.timeZone
            )
            rows.append(CoverageRow(
                plant: plant, need: need, coverage: coverageByPlant[plant.id]
            ))
        }

        // Undecided first, then the ones wanting more attention, then by name —
        // so the screen opens on whatever still needs a decision.
        return rows.sorted { lhs, rhs in
            if lhs.isUndecided != rhs.isUndecided { return lhs.isUndecided }
            if lhs.need.wantsMoreAttention != rhs.need.wantsMoreAttention {
                return lhs.need.wantsMoreAttention
            }
            return lhs.plant.displayName
                .localizedStandardCompare(rhs.plant.displayName) == .orderedAscending
        }
    }

    /// Records who is covering a plant, and generates the instructions if there
    /// are none yet.
    ///
    /// Generated text is a starting point that the user can rewrite; once they
    /// have edited it, regenerating never overwrites their words.
    @discardableResult
    func assign(
        _ assignment: CoverageAssignment,
        plantID: UUID,
        tripID: UUID,
        need: CoverageNeed,
        plantName: String,
        instructionsOverride: String? = nil
    ) async throws -> PlantTravelCoverage {
        let now = clock.now
        let existing = try await healthRepository.coverage(forTripID: tripID)
            .first { $0.plantID == plantID }

        var coverage = existing ?? PlantTravelCoverage(
            tripID: tripID, plantID: plantID, createdAt: now, modifiedAt: now
        )
        coverage.assignment = assignment
        coverage.modifiedAt = now

        if let instructionsOverride {
            coverage.instructions = instructionsOverride
        } else if coverage.instructions == nil {
            coverage.instructions = instructions(for: need, plantName: plantName)
        }

        // What the caretaker most wants to know: when it was last seen to.
        coverage.lastCareBeforeDeparture = try await careEventRepository
            .events(forPlantID: plantID, limit: 1)
            .first?
            .performedAt

        try await healthRepository.save(coverage)
        await awardIfFullyCovered(tripID: tripID)
        return coverage
    }

    /// Records what a caretaker reported back.
    @discardableResult
    func recordCaretakerUpdate(
        note: String,
        plantID: UUID,
        tripID: UUID
    ) async throws -> PlantTravelCoverage? {
        guard var coverage = try await healthRepository.coverage(forTripID: tripID)
            .first(where: { $0.plantID == plantID })
        else { return nil }

        coverage.caretakerUpdateNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        coverage.caretakerUpdatedAt = clock.now
        coverage.modifiedAt = clock.now
        try await healthRepository.save(coverage)
        return coverage
    }

    /// Plain-language instructions built from what actually falls inside the
    /// absence.
    ///
    /// Deliberately non-prescriptive: "may be ready for water" rather than "must
    /// be watered", because the app schedules reminders and does not claim
    /// biological certainty (PLANT_CARE.md §4). The text is not localized here —
    /// it is a document the user hands to another person, and it is generated
    /// from `Localizable.strings` templates at the call site.
    func instructions(for need: CoverageNeed, plantName: String) -> String {
        guard need.needsAnything else {
            return String(
                localized: "coverage.instructions.none \(plantName)",
                defaultValue: "\(plantName) shouldn't need anything while you're away.",
                comment: "Caretaker instructions when nothing is due"
            )
        }

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = clock.timeZone

        for occurrence in need.dueDuringAbsence {
            let careName = String(
                localized: .init("care.\(occurrence.careType.storageKey)")
            )
            lines.append(String(
                localized: "coverage.instructions.line \(careName) \(formatter.string(from: occurrence.dueDate))",
                defaultValue: "\(careName) — may be ready around \(formatter.string(from: occurrence.dueDate))",
                comment: "One line of caretaker instructions: care type and approximate date"
            ))
        }

        return ([plantName] + lines).joined(separator: "\n")
    }

    /// "Travel coverage completed" is an eligible progression event
    /// (PLANT_CARE.md §13). Earned once per trip, when nothing is left undecided.
    private func awardIfFullyCovered(tripID: UUID) async {
        guard let rows = try? await healthRepository.coverage(forTripID: tripID),
              !rows.isEmpty,
              rows.allSatisfy({ $0.assignment.isDecided })
        else { return }

        _ = try? await progressionEngine.award(
            type: .travelCoverageCompleted,
            sourceEntityID: tripID,
            occurredAt: clock.now,
            deterministicKey: "travelCoverage.\(tripID.uuidString)"
        )
    }
}

/// Builds the jungle export (PLANT_CARE.md §12).
///
/// The user's data is theirs. This assembles every jungle record into one value
/// and hands it to `JungleExportWriter`, which knows about JSON and CSV and
/// nothing about storage.
struct ExportJungle: Sendable {

    /// Cap on exported care events. High enough that a real collection exports
    /// whole; low enough that a runaway store cannot exhaust memory building one
    /// string.
    static let careEventLimit = 50_000

    private let plantRepository: any PlantRepository
    private let careEventRepository: any PlantCareEventRepository
    private let healthRepository: any PlantHealthRepository
    private let clock: any SunnieClock

    init(
        plantRepository: any PlantRepository,
        careEventRepository: any PlantCareEventRepository,
        healthRepository: any PlantHealthRepository,
        clock: any SunnieClock
    ) {
        self.plantRepository = plantRepository
        self.careEventRepository = careEventRepository
        self.healthRepository = healthRepository
        self.clock = clock
    }

    /// Archived plants are included. An export is a copy of everything, and
    /// silently dropping the plants someone archived would make it a partial one.
    func build() async throws -> JungleExport {
        let plants = try await plantRepository.allPlants(includingArchived: true)

        var schedules: [PlantCareSchedule] = []
        var observations: [PlantHealthObservation] = []
        var growth: [GrowthEntry] = []
        for plant in plants {
            schedules.append(contentsOf: try await plantRepository.schedules(forPlantID: plant.id))
            observations.append(contentsOf: try await healthRepository.observations(forPlantID: plant.id))
            growth.append(contentsOf: try await healthRepository.growthEntries(forPlantID: plant.id))
        }

        return JungleExport(
            exportedAt: clock.now,
            plants: plants,
            locations: try await plantRepository.locations(),
            schedules: schedules,
            careEvents: try await careEventRepository.allEvents(limit: Self.careEventLimit),
            observations: observations,
            growthEntries: growth,
            caretakers: try await healthRepository.caretakers(includingInactive: true)
        )
    }

    /// Writes the export to a directory and returns the files created.
    ///
    /// Files go to a caller-supplied directory — usually a temporary one for the
    /// share sheet — so nothing is written into the app's own storage on the way
    /// out.
    func write(
        _ export: JungleExport,
        format: JungleExportWriter.Format,
        to directory: URL
    ) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        switch format {
        case .json:
            let url = directory.appendingPathComponent("sunnie-jungle.json")
            try JungleExportWriter.json(export).write(to: url, options: .atomic)
            return [url]

        case .csv:
            var urls: [URL] = []
            for (name, contents) in JungleExportWriter.csvFiles(export).sorted(by: { $0.key < $1.key }) {
                let url = directory.appendingPathComponent(name)
                // UTF-8 with a BOM, because Excel opens a plain UTF-8 CSV as
                // Latin-1 and turns every accented plant name into mojibake.
                var data = Data([0xEF, 0xBB, 0xBF])
                data.append(contentsOf: Array(contents.utf8))
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        }
    }
}
