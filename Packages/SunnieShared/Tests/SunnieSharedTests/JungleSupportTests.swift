import Foundation
import Testing
@testable import SunnieShared

/// QR identity, coverage projection, growth comparison, bulk-care results, and
/// export writing. All pure, all testable without a device.
@Suite("Jungle support")
struct JungleSupportTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private var timeZone: TimeZone { TimeZone(identifier: "UTC")! }

    // MARK: - QR identity

    @Test("A generated token is well formed and a payload round-trips")
    func tokenRoundTrips() {
        let token = PlantQRIdentity.makeToken()
        #expect(PlantQRIdentity.isWellFormed(token))
        #expect(token.count == PlantQRIdentity.tokenLength)

        let payload = PlantQRIdentity.payload(token: token)
        #expect(PlantQRIdentity.token(fromScanned: payload) == token)
    }

    @Test("A scanned code that isn't ours resolves to nothing")
    func foreignCodesAreRejected() {
        // Pointing the camera at a Wi-Fi code or a product barcode must do
        // nothing at all — not guess, and not complain.
        let strangers = [
            "https://example.com/plant/abc",
            "WIFI:S:MyNetwork;T:WPA;P:hunter2;;",
            "0123456789012",
            "sunniedays://plant/not-a-token",
            "",
            "sunniedays://tag/short"
        ]
        for stranger in strangers {
            #expect(PlantQRIdentity.token(fromScanned: stranger) == nil, "\(stranger)")
        }
    }

    @Test("A bare token is accepted without the URL wrapper")
    func bareTokenIsAccepted() {
        let token = PlantQRIdentity.makeToken()
        #expect(PlantQRIdentity.token(fromScanned: "  \(token)  ") == token)
    }

    @Test("Uppercase hex is not a valid token")
    func uppercaseIsRejected() {
        // Tokens are generated lowercase. Accepting both would mean two strings
        // could name the same plant, and a lookup by exact match would miss one.
        let upper = String(repeating: "AB", count: PlantQRIdentity.tokenLength / 2)
        #expect(!PlantQRIdentity.isWellFormed(upper))
    }

    // MARK: - Coverage projection

    private func schedule(
        everyDays days: Int,
        nextDue: Date,
        seasonal: SeasonalModifier = .none,
        enabled: Bool = true
    ) -> PlantCareSchedule {
        PlantCareSchedule(
            plantID: UUID(),
            careType: .water,
            recurrence: .everyDays(days),
            seasonalModifier: seasonal,
            isEnabled: enabled,
            nextDueDate: nextDue
        )
    }

    private func plant(difficulty: CareDifficulty = .moderate) -> Plant {
        Plant(
            name: "Fern",
            difficulty: difficulty,
            qrToken: PlantQRIdentity.makeToken(),
            createdAt: now,
            modifiedAt: now
        )
    }

    @Test("Coverage projects every occurrence inside the absence, not just the next")
    func coverageProjectsRepeats() {
        // A plant watered every four days needs attention three times across a
        // fortnight. Reporting only the next due date would understate the ask.
        let start = now
        let end = now.addingTimeInterval(86_400 * 14)

        let need = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 4, nextDue: now.addingTimeInterval(86_400))],
            absenceStart: start,
            absenceEnd: end,
            calendar: calendar,
            timeZone: timeZone
        )

        #expect(need.needsAnything)
        #expect(need.dueDuringAbsence.count == 4)
        #expect(need.dueDuringAbsence.allSatisfy { $0.dueDate >= start && $0.dueDate <= end })
        // Sorted soonest first, so the caretaker list reads in order.
        let dates = need.dueDuringAbsence.map(\.dueDate)
        #expect(dates == dates.sorted())
    }

    @Test("A task already waiting when the trip starts is still covered")
    func alreadyWaitingTasksAreCovered() {
        let need = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 30, nextDue: now.addingTimeInterval(-86_400 * 2))],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 7),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(need.needsAnything)
    }

    @Test("Disabled schedules and plants that need nothing are reported as such")
    func nothingDueIsReportedAsNothing() {
        let disabled = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 2, nextDue: now, enabled: false)],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 7),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(!disabled.needsAnything)

        let farOff = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 90, nextDue: now.addingTimeInterval(86_400 * 60))],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 7),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(!farOff.needsAnything)
    }

    @Test("A manual schedule never projects and cannot loop forever")
    func manualScheduleTerminates() {
        // A schedule with no interval has nothing to advance by. Without the
        // guard this would spin on a non-advancing cursor.
        let manual = PlantCareSchedule(
            plantID: UUID(),
            careType: .water,
            recurrence: .manual,
            nextDueDate: now
        )

        let need = CoveragePlanner.need(
            plant: plant(),
            schedules: [manual],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 365),
            calendar: calendar,
            timeZone: timeZone
        )
        // The one already-due occurrence is reported; nothing follows it.
        #expect(need.dueDuringAbsence.count <= 1)
    }

    @Test("Projection is capped so a one-day interval cannot explode")
    func projectionIsCapped() {
        let need = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 1, nextDue: now)],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 365),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(need.dueDuringAbsence.count == CoveragePlanner.maximumProjectedOccurrences)
    }

    @Test("An absence that ends before it starts needs nothing")
    func invertedWindowNeedsNothing() {
        let need = CoveragePlanner.need(
            plant: plant(),
            schedules: [schedule(everyDays: 1, nextDue: now)],
            absenceStart: now.addingTimeInterval(86_400),
            absenceEnd: now,
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(!need.needsAnything)
    }

    @Test("A demanding plant wants more attention even with one task")
    func demandingPlantsAreOrderedUp() {
        let need = CoveragePlanner.need(
            plant: plant(difficulty: .demanding),
            schedules: [schedule(everyDays: 30, nextDue: now.addingTimeInterval(86_400))],
            absenceStart: now,
            absenceEnd: now.addingTimeInterval(86_400 * 7),
            calendar: calendar,
            timeZone: timeZone
        )
        #expect(need.wantsMoreAttention)
    }

    @Test("Coverage assignment: self-managed is a real decision")
    func selfManagedIsDecided() {
        // "This plant is fine on its own" must close the question rather than
        // leaving it looking unresolved.
        #expect(CoverageAssignment.selfManaged.isDecided)
        #expect(CoverageAssignment.caretaker(UUID()).isDecided)
        #expect(!CoverageAssignment.unresolved.isDecided)
    }

    // MARK: - Growth comparison

    private func growth(
        metric: GrowthMetric?,
        value: Double?,
        unit: String?
    ) -> GrowthEntry {
        GrowthEntry(
            plantID: UUID(),
            recordedAt: now,
            metric: metric,
            value: value,
            unit: unit,
            sourceDeviceID: DeviceID(rawValue: "test"),
            createdAt: now
        )
    }

    @Test("Entries are comparable only on the same metric and unit")
    func comparabilityRules() {
        let cmA = growth(metric: .height, value: 30, unit: "cm")
        let cmB = growth(metric: .height, value: 42, unit: "CM ")
        // Unit matching is case- and whitespace-insensitive, because it is free
        // text the user typed.
        #expect(cmA.isComparable(with: cmB))

        let inches = growth(metric: .height, value: 12, unit: "in")
        // 30cm against 12in would produce a nonsense delta. Not comparable rather
        // than silently converted.
        #expect(!cmA.isComparable(with: inches))

        let width = growth(metric: .width, value: 30, unit: "cm")
        #expect(!cmA.isComparable(with: width))

        let noValue = growth(metric: .height, value: nil, unit: "cm")
        #expect(!cmA.isComparable(with: noValue))

        // A count has no unit, so two counts are always comparable.
        let leavesA = growth(metric: .leafCount, value: 4, unit: nil)
        let leavesB = growth(metric: .leafCount, value: 9, unit: nil)
        #expect(leavesA.isComparable(with: leavesB))
    }

    @Test("An entry with nothing in it is empty")
    func emptyGrowthEntry() {
        var entry = growth(metric: nil, value: nil, unit: nil)
        #expect(entry.isEmpty)

        entry.note = "   "
        #expect(entry.isEmpty)

        entry.isMilestone = true
        // A milestone on its own is a real entry — "repotted today" needs no
        // measurement.
        #expect(!entry.isEmpty)
    }

    // MARK: - Bulk care results

    @Test("A partial failure is a partial success")
    func partialFailureKeepsSuccesses() {
        let ok = UUID(), duplicate = UUID(), bad = UUID()
        let result = BulkCareResult(outcomes: [
            ok: .recorded,
            duplicate: .alreadyRecorded,
            bad: .failed("boom")
        ])

        // Fifteen watered and one failed is fifteen watered.
        #expect(result.recordedCount == 2)
        #expect(result.failedPlantIDs == [bad])
        #expect(result.hasFailures)
        #expect(!result.isCompleteFailure)
    }

    @Test("A duplicate counts as recorded")
    func duplicatesCountAsSuccess() {
        // From the user's point of view a repeated tap did work, so it must not
        // appear in the retry list (ADR-013).
        let result = BulkCareResult(outcomes: [UUID(): .alreadyRecorded])
        #expect(result.recordedCount == 1)
        #expect(!result.hasFailures)
    }

    @Test("Everything failing is the only complete failure")
    func completeFailureIsDistinct() {
        let result = BulkCareResult(outcomes: [UUID(): .failed("boom")])
        #expect(result.isCompleteFailure)
        #expect(BulkCareResult(outcomes: [:]).isCompleteFailure == false)
    }

    // MARK: - Export

    private func makeExport() -> JungleExport {
        let plant = Plant(
            name: "Monstera, big",
            speciesName: "Monstera \"deliciosa\"",
            notes: "Line one\nLine two",
            qrToken: PlantQRIdentity.makeToken(),
            createdAt: now,
            modifiedAt: now
        )
        return JungleExport(
            exportedAt: now,
            plants: [plant],
            careEvents: [PlantCareEvent(
                plantID: plant.id,
                careType: .water,
                performedAt: now,
                sourceDeviceID: DeviceID(rawValue: "phone"),
                note: "A good, long drink",
                actionKey: ActionKey(rawValue: "k"),
                createdAt: now
            )]
        )
    }

    @Test("CSV quotes commas, quotes, and newlines")
    func csvEscaping() throws {
        // A plant note with a comma in it must not silently become two columns,
        // and one with a newline must not become two rows.
        let files = JungleExportWriter.csvFiles(makeExport())
        let plants = try #require(files["plants.csv"])

        #expect(plants.contains("\"Monstera, big\""))
        #expect(plants.contains("\"Monstera \"\"deliciosa\"\"\""))
        #expect(plants.contains("\"Line one\nLine two\""))
        // CRLF, which is what RFC 4180 specifies and Excel expects.
        #expect(plants.contains("\r\n"))
    }

    @Test("Every CSV row has the same column count as its header")
    func csvColumnCountsMatch() {
        for (name, contents) in JungleExportWriter.csvFiles(makeExport()) {
            let rows = contents.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            guard let header = rows.first else { continue }
            let expected = countColumns(header)
            for row in rows.dropFirst() {
                #expect(countColumns(row) == expected, "\(name): \(row)")
            }
        }
    }

    /// Counts commas outside quoted fields — the same rule a reader applies.
    private func countColumns(_ row: String) -> Int {
        var columns = 1
        var inQuotes = false
        var previousWasQuote = false

        for character in row {
            if character == "\"" {
                // A doubled quote is an escaped quote, not a delimiter change.
                if previousWasQuote {
                    previousWasQuote = false
                } else {
                    inQuotes.toggle()
                    previousWasQuote = true
                }
                continue
            }
            previousWasQuote = false
            if character == ",", !inQuotes { columns += 1 }
        }
        return columns
    }

    @Test("JSON export round-trips")
    func jsonRoundTrips() throws {
        let export = makeExport()
        let data = try JungleExportWriter.json(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JungleExport.self, from: data)

        #expect(decoded.formatVersion == JungleExport.currentFormatVersion)
        #expect(decoded.plants.count == export.plants.count)
        #expect(decoded.plants.first?.name == export.plants.first?.name)
        #expect(decoded.careEvents.first?.note == export.careEvents.first?.note)
    }

    // MARK: - Seasonal intervals

    @Test("The seasonal interval is shared by scheduling and coverage")
    func seasonalIntervalIsShared() {
        // A fortnight in winter must mean the same number of days to both, or a
        // coverage plan would disagree with the schedule it was built from.
        let winterHeavy = SeasonalModifier(
            springMultiplier: 1, summerMultiplier: 1,
            autumnMultiplier: 1, winterMultiplier: 2
        )
        let schedule = PlantCareSchedule(
            plantID: UUID(),
            careType: .water,
            recurrence: .everyDays(7),
            seasonalModifier: winterHeavy
        )

        var zoned = calendar
        zoned.timeZone = timeZone

        // 15 January 2024, firmly winter in the northern hemisphere.
        let january = Date(timeIntervalSince1970: 1_705_276_800)
        let july = Date(timeIntervalSince1970: 1_720_828_800)

        #expect(CareScheduleCalculator.effectiveIntervalDays(
            for: schedule, at: january, calendar: zoned
        ) == 14)
        #expect(CareScheduleCalculator.effectiveIntervalDays(
            for: schedule, at: july, calendar: zoned
        ) == 7)
    }

    @Test("A seasonal multiplier can never collapse an interval to zero")
    func intervalNeverCollapses() {
        // A zero interval would make a task perpetually due, which is the worst
        // possible failure for a tone that never nags.
        let collapsing = SeasonalModifier(
            springMultiplier: 0, summerMultiplier: 0,
            autumnMultiplier: 0, winterMultiplier: 0
        )
        let schedule = PlantCareSchedule(
            plantID: UUID(),
            careType: .water,
            recurrence: .everyDays(7),
            seasonalModifier: collapsing
        )

        var zoned = calendar
        zoned.timeZone = timeZone
        #expect(CareScheduleCalculator.effectiveIntervalDays(
            for: schedule, at: now, calendar: zoned
        ) == 1)
    }

    @Test("A manual schedule has no effective interval")
    func manualHasNoInterval() {
        let manual = PlantCareSchedule(
            plantID: UUID(), careType: .water, recurrence: .manual
        )
        var zoned = calendar
        zoned.timeZone = timeZone
        #expect(CareScheduleCalculator.effectiveIntervalDays(
            for: manual, at: now, calendar: zoned
        ) == nil)
    }
}
