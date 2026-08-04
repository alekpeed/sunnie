import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Phase 4 behaviour against a real in-memory store: the plant editor's rules,
/// bulk care, health observations, growth, coverage, QR resolution, export, and
/// performance at a realistic collection size.
@Suite("Jungle flows")
struct JungleFlowTests {

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeDependencies() throws -> AppDependencies {
        AppDependencies(
            modelContainer: try ModelContainerFactory.make(storage: .inMemory),
            clock: FixedClock(now: Self.referenceDate),
            enableWatchConnectivity: false
        )
    }

    @MainActor
    private func makePlant(
        _ dependencies: AppDependencies,
        name: String = "Monstera",
        species: String? = nil
    ) async throws -> Plant {
        var draft = dependencies.managePlant.newDraft()
        draft.name = name
        draft.speciesName = species
        return try await dependencies.managePlant.save(draft)
    }

    // MARK: - Editor rules

    @Test("A name is the only thing required to save")
    @MainActor
    func onlyNameIsRequired() async throws {
        // The editor's governing rule: never block saving because reference
        // content is missing. No species, no photo, no light profile, no problem.
        let dependencies = try makeDependencies()
        var draft = dependencies.managePlant.newDraft()
        draft.name = "Just a name"

        let saved = try await dependencies.managePlant.save(draft)
        #expect(saved.name == "Just a name")
        #expect(saved.speciesName == nil)
        #expect(try await dependencies.plantRepository.plant(id: saved.id) != nil)
    }

    @Test("A blank or whitespace-only name is refused")
    @MainActor
    func blankNameIsRefused() async throws {
        let dependencies = try makeDependencies()
        var draft = dependencies.managePlant.newDraft()

        draft.name = "   "
        await #expect(throws: DomainError.self) {
            _ = try await dependencies.managePlant.save(draft)
        }
    }

    @Test("Emptied optional fields become nil rather than empty strings")
    @MainActor
    func emptiedFieldsBecomeNil() async throws {
        // An empty string would later render as a blank line in the UI, which
        // looks like a bug rather than an unfilled field.
        let dependencies = try makeDependencies()
        var draft = dependencies.managePlant.newDraft()
        draft.name = "  Fern  "
        draft.speciesName = "   "
        draft.notes = ""

        let saved = try await dependencies.managePlant.save(draft)
        #expect(saved.name == "Fern")
        #expect(saved.speciesName == nil)
        #expect(saved.notes == nil)
    }

    @Test("A new plant gets a well-formed QR token that resolves")
    @MainActor
    func newPlantsGetResolvableTokens() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        #expect(PlantQRIdentity.isWellFormed(plant.qrToken))

        let payload = PlantQRIdentity.payload(token: plant.qrToken)
        let scanned = try await dependencies.managePlant.plant(forScannedCode: payload)
        #expect(scanned?.id == plant.id)
    }

    @Test("Regenerating a token invalidates the old label")
    @MainActor
    func regeneratingInvalidatesTheOldLabel() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)
        let oldPayload = PlantQRIdentity.payload(token: plant.qrToken)

        let updated = try await dependencies.managePlant.regenerateQRToken(plantID: plant.id)
        #expect(updated.qrToken != plant.qrToken)

        // The old sticker on the pot stops working. That is the point of the
        // confirmation the UI shows first.
        let old = try await dependencies.managePlant.plant(forScannedCode: oldPayload)
        #expect(old == nil)

        let new = try await dependencies.managePlant
            .plant(forScannedCode: PlantQRIdentity.payload(token: updated.qrToken))
        #expect(new?.id == plant.id)
    }

    @Test("Scanning something that isn't ours resolves to nothing")
    @MainActor
    func foreignScansResolveToNothing() async throws {
        let dependencies = try makeDependencies()
        _ = try await makePlant(dependencies)

        #expect(try await dependencies.managePlant
            .plant(forScannedCode: "https://example.com") == nil)
        #expect(try await dependencies.managePlant
            .plant(forScannedCode: "0123456789012") == nil)
    }

    // MARK: - Archiving and deleting

    @Test("Archiving keeps the history and disables the schedules")
    @MainActor
    func archivingKeepsHistory() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        _ = try await dependencies.managePlant.save(PlantCareSchedule(
            plantID: plant.id, careType: .water, recurrence: .everyDays(7)
        ))
        _ = try await dependencies.logPlantCare(plantID: plant.id, careType: .water)

        try await dependencies.managePlant.archive(plantID: plant.id)

        let archived = try await dependencies.plantRepository.plant(id: plant.id)
        #expect(archived?.status == .archived)

        // The history outlives the archiving — that is the whole reason archive
        // is the option the UI leads with.
        let events = try await dependencies.careEventRepository
            .events(forPlantID: plant.id, limit: 10)
        #expect(events.count == 1)

        // An archived plant stops producing due tasks.
        let schedules = try await dependencies.plantRepository.schedules(forPlantID: plant.id)
        #expect(schedules.allSatisfy { !$0.isEnabled })
    }

    @Test("Unarchiving brings a plant back")
    @MainActor
    func unarchivingRestores() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        try await dependencies.managePlant.archive(plantID: plant.id)
        try await dependencies.managePlant.unarchive(plantID: plant.id)

        #expect(try await dependencies.plantRepository.plant(id: plant.id)?.status == .active)
    }

    @Test("Deleting removes the plant and everything that belonged only to it")
    @MainActor
    func deletingRemovesEverything() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        _ = try await dependencies.managePlant.save(PlantCareSchedule(
            plantID: plant.id, careType: .water, recurrence: .everyDays(7)
        ))
        _ = try await dependencies.logPlantCare(plantID: plant.id, careType: .water)
        var observation = dependencies.managePlantHealth.newObservation(plantID: plant.id)
        observation.category = .yellowingLeaves
        _ = try await dependencies.managePlantHealth.save(observation)

        try await dependencies.managePlant.delete(plantID: plant.id)

        #expect(try await dependencies.plantRepository.plant(id: plant.id) == nil)
        #expect(try await dependencies.plantRepository.schedules(forPlantID: plant.id).isEmpty)
        #expect(try await dependencies.careEventRepository
            .events(forPlantID: plant.id, limit: 10).isEmpty)
        #expect(try await dependencies.managePlantHealth
            .observations(forPlantID: plant.id).isEmpty)
    }

    @Test("Deleting a location leaves its plants alone")
    @MainActor
    func deletingLocationKeepsPlants() async throws {
        // Cascading would destroy plants because a room was renamed away, which
        // is exactly why locations are a separate record.
        let dependencies = try makeDependencies()
        let location = try await dependencies.managePlant.save(PlantLocation(name: "Kitchen"))

        var draft = dependencies.managePlant.newDraft()
        draft.name = "Fern"
        draft.locationID = location.id
        let plant = try await dependencies.managePlant.save(draft)

        try await dependencies.managePlant.deleteLocation(id: location.id)

        let survivor = try await dependencies.plantRepository.plant(id: plant.id)
        #expect(survivor != nil)
        #expect(survivor?.locationID == nil)
    }

    // MARK: - Schedules

    @Test("Shortening an interval surfaces the task rather than granting a reprieve")
    @MainActor
    func shorteningAnIntervalRecomputesFromLastCompletion() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        let completed = Self.referenceDate.addingTimeInterval(-86_400 * 6)
        var schedule = PlantCareSchedule(
            plantID: plant.id,
            careType: .water,
            recurrence: .everyDays(30),
            lastCompletedAt: completed
        )
        schedule = try await dependencies.managePlant.save(schedule)

        // Due about 30 days after the last completion, so still a long way off.
        let longDue = try #require(schedule.nextDueDate)
        #expect(longDue > Self.referenceDate)

        schedule.recurrence = .everyDays(3)
        let shortened = try await dependencies.managePlant.save(schedule)

        // Recomputed from the last completion, not from now — so a task that
        // should already be waiting is waiting.
        let shortDue = try #require(shortened.nextDueDate)
        #expect(shortDue < longDue)
        #expect(shortDue < Self.referenceDate)
    }

    @Test("A manual or disabled schedule has no due date")
    @MainActor
    func manualSchedulesHaveNoDueDate() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        let manual = try await dependencies.managePlant.save(PlantCareSchedule(
            plantID: plant.id, careType: .prune, recurrence: .manual
        ))
        #expect(manual.nextDueDate == nil)

        // Disabling must clear a stale due date, or it would keep producing
        // tasks.
        var disabled = PlantCareSchedule(
            plantID: plant.id, careType: .water, recurrence: .everyDays(7)
        )
        disabled.isEnabled = false
        #expect(try await dependencies.managePlant.save(disabled).nextDueDate == nil)
    }

    // MARK: - Bulk care

    @Test("Bulk care records every included plant and skips the rest")
    @MainActor
    func bulkCareRecordsIncludedPlants() async throws {
        let dependencies = try makeDependencies()
        let a = try await makePlant(dependencies, name: "A")
        let b = try await makePlant(dependencies, name: "B")
        let c = try await makePlant(dependencies, name: "C")

        var excluded = BulkCareItem(plantID: c.id)
        excluded.isIncluded = false

        let result = await dependencies.logBulkCare(
            careType: .water,
            items: [BulkCareItem(plantID: a.id), BulkCareItem(plantID: b.id), excluded]
        )

        #expect(result.recordedCount == 2)
        #expect(!result.hasFailures)
        #expect(try await dependencies.careEventRepository
            .events(forPlantID: c.id, limit: 5).isEmpty)
    }

    @Test("A per-plant override changes only that plant")
    @MainActor
    func bulkCareOverridesApplyPerPlant() async throws {
        let dependencies = try makeDependencies()
        let a = try await makePlant(dependencies, name: "A")
        let b = try await makePlant(dependencies, name: "B")

        var override = BulkCareItem(plantID: b.id)
        override.careTypeOverride = .mist

        _ = await dependencies.logBulkCare(
            careType: .water,
            items: [BulkCareItem(plantID: a.id), override]
        )

        let aEvents = try await dependencies.careEventRepository.events(forPlantID: a.id, limit: 5)
        let bEvents = try await dependencies.careEventRepository.events(forPlantID: b.id, limit: 5)
        #expect(aEvents.first?.careType == .water)
        #expect(bEvents.first?.careType == .mist)
    }

    @Test("A missing plant fails alone and the others still record")
    @MainActor
    func bulkCarePartialFailureKeepsSuccesses() async throws {
        // Rolling the successes back to keep the operation atomic would destroy
        // real work (PLANT_CARE.md §15).
        let dependencies = try makeDependencies()
        let real = try await makePlant(dependencies, name: "Real")
        let ghost = UUID()

        let result = await dependencies.logBulkCare(
            careType: .water,
            items: [BulkCareItem(plantID: real.id), BulkCareItem(plantID: ghost)]
        )

        #expect(result.recordedCount == 1)
        #expect(result.failedPlantIDs == [ghost])
        #expect(!result.isCompleteFailure)
        #expect(try await dependencies.careEventRepository
            .events(forPlantID: real.id, limit: 5).count == 1)
    }

    @Test("Repeating a bulk action within the same minute records once")
    @MainActor
    func bulkCareIsIdempotent() async throws {
        // Bulk care goes through the same use case as a single tap, so it
        // inherits the minute-bucket action key (ADR-013).
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        _ = await dependencies.logBulkCare(
            careType: .water, items: [BulkCareItem(plantID: plant.id)]
        )
        let second = await dependencies.logBulkCare(
            careType: .water, items: [BulkCareItem(plantID: plant.id)]
        )

        #expect(second.outcomes[plant.id] == .alreadyRecorded)
        #expect(try await dependencies.careEventRepository
            .events(forPlantID: plant.id, limit: 10).count == 1)
    }

    // MARK: - Health observations

    @Test("Nothing but the user resolves an observation")
    @MainActor
    func resolutionIsAlwaysExplicit() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var observation = dependencies.managePlantHealth.newObservation(plantID: plant.id)
        observation.category = .yellowingLeaves
        observation.notes = "Two lower leaves"
        let saved = try await dependencies.managePlantHealth.save(observation)

        #expect(!saved.isResolved)
        #expect(try await dependencies.managePlantHealth.openObservations().count == 1)

        let resolved = try await dependencies.managePlantHealth.resolve(observationID: saved.id)
        #expect(resolved.isResolved)
        #expect(try await dependencies.managePlantHealth.openObservations().isEmpty)

        // Reopening loses nothing.
        let reopened = try await dependencies.managePlantHealth.reopen(observationID: saved.id)
        #expect(!reopened.isResolved)
        #expect(reopened.notes == "Two lower leaves")
    }

    @Test("Resolving repeatedly cannot earn progression twice")
    @MainActor
    func resolutionRewardIsKeyed() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var observation = dependencies.managePlantHealth.newObservation(plantID: plant.id)
        observation.category = .spots
        let saved = try await dependencies.managePlantHealth.save(observation)

        _ = try await dependencies.managePlantHealth.resolve(observationID: saved.id)
        let after = try await dependencies.progressionRepository.profile().experience

        // Toggling resolved off and on must not farm the reward.
        _ = try await dependencies.managePlantHealth.reopen(observationID: saved.id)
        _ = try await dependencies.managePlantHealth.resolve(observationID: saved.id)

        #expect(try await dependencies.progressionRepository.profile().experience == after)
    }

    // MARK: - Growth

    @Test("A growth entry needs something in it")
    @MainActor
    func emptyGrowthEntryIsRefused() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        let blank = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        await #expect(throws: DomainError.self) {
            _ = try await dependencies.managePlantHealth.save(blank)
        }
    }

    @Test("A milestone alone is a valid entry")
    @MainActor
    func milestoneAloneIsEnough() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var entry = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        entry.isMilestone = true
        entry.milestoneLabel = "Repotted"

        let saved = try await dependencies.managePlantHealth.save(entry)
        #expect(saved.isMilestone)
        #expect(try await dependencies.managePlantHealth
            .growthEntries(forPlantID: plant.id).count == 1)
    }

    @Test("A value with no metric is stored as a note, not a measurement")
    @MainActor
    func valueWithoutMetricIsDropped() async throws {
        // A number with nothing to say what it measures cannot be compared or
        // labelled, so it is not a measurement.
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var entry = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        entry.value = 42
        entry.unit = "cm"
        entry.note = "Getting big"

        let saved = try await dependencies.managePlantHealth.save(entry)
        #expect(saved.value == nil)
        #expect(saved.unit == nil)
        #expect(saved.note == "Getting big")
    }

    @Test("A leaf count carries no unit")
    @MainActor
    func countsHaveNoUnit() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var entry = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        entry.metric = .leafCount
        entry.value = 9
        entry.unit = "cm"

        #expect(try await dependencies.managePlantHealth.save(entry).unit == nil)
    }

    @Test("Comparison needs two genuinely comparable entries")
    @MainActor
    func comparisonRequiresTwoComparableEntries() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        var first = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        first.metric = .height
        first.value = 30
        first.unit = "cm"
        first.recordedAt = Self.referenceDate.addingTimeInterval(-86_400 * 90)
        _ = try await dependencies.managePlantHealth.save(first)

        // One entry cannot be compared against itself.
        #expect(try await dependencies.managePlantHealth
            .comparisonPair(forPlantID: plant.id) == nil)

        var second = dependencies.managePlantHealth.newGrowthEntry(plantID: plant.id)
        second.metric = .height
        second.value = 46
        second.unit = "cm"
        _ = try await dependencies.managePlantHealth.save(second)

        let pair = try #require(
            try await dependencies.managePlantHealth.comparisonPair(forPlantID: plant.id)
        )
        #expect(pair.earliest.value == 30)
        #expect(pair.latest.value == 46)
    }

    // MARK: - Coverage

    @Test("Coverage lists every plant, including the ones needing nothing")
    @MainActor
    func coverageIncludesPlantsThatNeedNothing() async throws {
        // Leaving them out would make the screen read as a list of problems,
        // when most of the answer is usually "these are fine".
        let dependencies = try makeDependencies()
        let thirsty = try await makePlant(dependencies, name: "Thirsty")
        _ = try await makePlant(dependencies, name: "Fine")

        _ = try await dependencies.managePlant.save(PlantCareSchedule(
            plantID: thirsty.id, careType: .water, recurrence: .everyDays(3)
        ))

        let rows = try await dependencies.planTravelCoverage.rows(
            tripID: UUID(),
            absenceStart: Self.referenceDate,
            absenceEnd: Self.referenceDate.addingTimeInterval(86_400 * 10)
        )

        #expect(rows.count == 2)
        #expect(rows.contains { $0.plant.id == thirsty.id && $0.need.needsAnything })
        #expect(rows.contains { $0.plant.name == "Fine" && !$0.need.needsAnything })
        // Undecided sorts first, so the screen opens on what still needs a
        // decision.
        #expect(rows.first?.isUndecided == true)
    }

    @Test("Self-managed settles a plant without a caretaker")
    @MainActor
    func selfManagedSettlesCoverage() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)
        let tripID = UUID()

        _ = try await dependencies.managePlant.save(PlantCareSchedule(
            plantID: plant.id, careType: .water, recurrence: .everyDays(3)
        ))

        let rows = try await dependencies.planTravelCoverage.rows(
            tripID: tripID,
            absenceStart: Self.referenceDate,
            absenceEnd: Self.referenceDate.addingTimeInterval(86_400 * 10)
        )
        let row = try #require(rows.first)

        _ = try await dependencies.planTravelCoverage.assign(
            .selfManaged,
            plantID: plant.id,
            tripID: tripID,
            need: row.need,
            plantName: plant.displayName
        )

        let after = try await dependencies.planTravelCoverage.rows(
            tripID: tripID,
            absenceStart: Self.referenceDate,
            absenceEnd: Self.referenceDate.addingTimeInterval(86_400 * 10)
        )
        #expect(after.first?.isUndecided == false)
        #expect(after.first?.assignment == .selfManaged)
    }

    @Test("Assigning twice updates one row rather than creating a second")
    @MainActor
    func coverageIsOneRowPerPlantPerTrip() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)
        let tripID = UUID()
        let need = CoverageNeed(plantID: plant.id, dueDuringAbsence: [], difficulty: .easy)

        _ = try await dependencies.planTravelCoverage.assign(
            .selfManaged, plantID: plant.id, tripID: tripID,
            need: need, plantName: plant.displayName
        )
        _ = try await dependencies.planTravelCoverage.assign(
            .unresolved, plantID: plant.id, tripID: tripID,
            need: need, plantName: plant.displayName
        )

        let stored = try await dependencies.plantHealthRepository.coverage(forTripID: tripID)
        #expect(stored.count == 1)
        #expect(stored.first?.assignment == .unresolved)
    }

    @Test("Edited instructions are never overwritten by a regeneration")
    @MainActor
    func editedInstructionsSurvive() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)
        let tripID = UUID()
        let need = CoverageNeed(plantID: plant.id, dueDuringAbsence: [], difficulty: .easy)

        _ = try await dependencies.planTravelCoverage.assign(
            .selfManaged, plantID: plant.id, tripID: tripID,
            need: need, plantName: plant.displayName,
            instructionsOverride: "Please just say hello to it"
        )
        _ = try await dependencies.planTravelCoverage.assign(
            .selfManaged, plantID: plant.id, tripID: tripID,
            need: need, plantName: plant.displayName
        )

        let stored = try await dependencies.plantHealthRepository.coverage(forTripID: tripID)
        #expect(stored.first?.instructions == "Please just say hello to it")
    }

    // MARK: - History corrections

    @Test("A correction adds a record and marks the old one superseded")
    @MainActor
    func correctionsAreAppendOnly() async throws {
        // The log is append-only, which is what makes it trustworthy after the
        // fact (PLANT_CARE.md §7).
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        let original = try await dependencies.logPlantCare(
            plantID: plant.id, careType: .water, note: "Wrong note"
        )

        let replacement = PlantCareEvent(
            plantID: plant.id,
            careType: .water,
            performedAt: Self.referenceDate.addingTimeInterval(-3600),
            sourceDeviceID: dependencies.deviceID,
            note: "The right note",
            actionKey: ActionKeyFactory.plantCare(
                plantID: plant.id,
                careType: .water,
                performedAt: Self.referenceDate.addingTimeInterval(-3600)
            ),
            createdAt: Self.referenceDate
        )
        _ = try await dependencies.careEventRepository.replace(
            eventID: original.event.id, with: replacement
        )

        let history = try await dependencies.managePlant.history(plantID: plant.id)
        // Both records survive: the original is marked, not erased.
        #expect(history.total == 2)
        #expect(history.superseded.contains(original.event.id))
    }

    @Test("Correcting the same event twice records one link")
    @MainActor
    func correctionsAreIdempotent() async throws {
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        let original = try await dependencies.logPlantCare(plantID: plant.id, careType: .water)
        let performedAt = Self.referenceDate.addingTimeInterval(-3600)
        let replacement = PlantCareEvent(
            plantID: plant.id,
            careType: .water,
            performedAt: performedAt,
            sourceDeviceID: dependencies.deviceID,
            actionKey: ActionKeyFactory.plantCare(
                plantID: plant.id, careType: .water, performedAt: performedAt
            ),
            createdAt: Self.referenceDate
        )

        _ = try await dependencies.careEventRepository.replace(
            eventID: original.event.id, with: replacement
        )
        _ = try await dependencies.careEventRepository.replace(
            eventID: original.event.id, with: replacement
        )

        let history = try await dependencies.managePlant.history(plantID: plant.id)
        #expect(history.total == 2)
        #expect(history.superseded.count == 1)
    }

    // MARK: - Export

    @Test("Export includes archived plants and every jungle record")
    @MainActor
    func exportIsComplete() async throws {
        // Silently dropping archived plants would make it a partial copy.
        let dependencies = try makeDependencies()
        let kept = try await makePlant(dependencies, name: "Kept")
        let gone = try await makePlant(dependencies, name: "Gone")
        try await dependencies.managePlant.archive(plantID: gone.id)

        _ = try await dependencies.logPlantCare(plantID: kept.id, careType: .water)

        var observation = dependencies.managePlantHealth.newObservation(plantID: kept.id)
        observation.category = .brownTips
        _ = try await dependencies.managePlantHealth.save(observation)

        let export = try await dependencies.exportJungle.build()
        #expect(export.plants.count == 2)
        #expect(export.careEvents.count == 1)
        #expect(export.observations.count == 1)
        #expect(export.formatVersion == JungleExport.currentFormatVersion)
    }

    @Test("Export writes files that exist and parse")
    @MainActor
    func exportWritesReadableFiles() async throws {
        let dependencies = try makeDependencies()
        _ = try await makePlant(dependencies, name: "Monstera")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieExportTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let export = try await dependencies.exportJungle.build()

        let jsonFiles = try dependencies.exportJungle.write(
            export, format: .json, to: directory
        )
        let jsonURL = try #require(jsonFiles.first)
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JungleExport.self, from: try Data(contentsOf: jsonURL))
        #expect(decoded.plants.first?.name == "Monstera")

        let csvFiles = try dependencies.exportJungle.write(
            export, format: .csv, to: directory
        )
        #expect(csvFiles.count >= 5)

        // A UTF-8 BOM, because Excel opens a plain UTF-8 CSV as Latin-1 and
        // mangles every accented plant name.
        let plantsCSV = try #require(csvFiles.first { $0.lastPathComponent == "plants.csv" })
        let bytes = try Data(contentsOf: plantsCSV).prefix(3)
        #expect(Array(bytes) == [0xEF, 0xBB, 0xBF])
    }

    // MARK: - Scale

    @Test("A hundred-plant collection assembles in one pass", .timeLimit(.minutes(1)))
    @MainActor
    func collectionScalesToAHundredPlants() async throws {
        // The target is "more than 50 plants stays easy to understand"
        // (PLANT_CARE.md §1). The thing being asserted is that assembling the
        // collection is a fixed number of queries rather than one per plant.
        let dependencies = try makeDependencies()

        for index in 0..<100 {
            var draft = dependencies.managePlant.newDraft()
            draft.name = "Plant \(index)"
            draft.speciesName = index.isMultiple(of: 2) ? "Monstera" : "Ficus"
            let plant = try await dependencies.managePlant.save(draft)

            _ = try await dependencies.managePlant.save(PlantCareSchedule(
                plantID: plant.id,
                careType: .water,
                recurrence: .everyDays(index % 14 + 1)
            ))
        }

        let items = try await dependencies.plantRepository.collectionItems(includingArchived: true)
        #expect(items.count == 100)
        #expect(items.allSatisfy { $0.nextDueDate != nil })
        #expect(items.allSatisfy { $0.scheduledCareTypes.contains(.water) })

        // Filtering the assembled list is pure and in memory, so it stays cheap
        // however the user narrows it.
        var query = PlantCollectionQuery.default
        query.species = ["Monstera"]
        let filtered = PlantCollectionFilter.apply(
            query,
            to: items,
            now: Self.referenceDate,
            calendar: dependencies.clock.calendar,
            timeZone: dependencies.clock.timeZone
        )
        #expect(filtered.count == 50)
    }

    @Test("A long care history pages instead of loading whole", .timeLimit(.minutes(1)))
    @MainActor
    func longHistoryPages() async throws {
        // 500+ history records is a listed edge case (PLANT_CARE.md §15).
        let dependencies = try makeDependencies()
        let plant = try await makePlant(dependencies)

        for index in 0..<500 {
            let performedAt = Self.referenceDate.addingTimeInterval(-Double(index) * 3600)
            _ = try await dependencies.careEventRepository.save(PlantCareEvent(
                plantID: plant.id,
                careType: .water,
                performedAt: performedAt,
                sourceDeviceID: dependencies.deviceID,
                actionKey: ActionKey(rawValue: "history.\(index)"),
                createdAt: Self.referenceDate
            ))
        }

        let count = try await dependencies.careEventRepository.eventCount(forPlantID: plant.id)
        #expect(count == 500)

        let firstPage = try await dependencies.careEventRepository
            .events(forPlantID: plant.id, limit: 20, offset: 0)
        let secondPage = try await dependencies.careEventRepository
            .events(forPlantID: plant.id, limit: 20, offset: 20)

        #expect(firstPage.count == 20)
        #expect(secondPage.count == 20)
        // Newest first, and the pages do not overlap.
        #expect(firstPage.first!.performedAt > secondPage.first!.performedAt)
        #expect(Set(firstPage.map(\.id)).isDisjoint(with: Set(secondPage.map(\.id))))
    }
}
