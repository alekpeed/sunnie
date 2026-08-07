import Foundation

/// Who is looking after a plant during an absence.
///
/// "Self-managed" is a real, chosen answer, not the absence of one — plenty of
/// plants are fine for two weeks and saying so should close the question rather
/// than leave it open (PLANT_CARE.md §10).
public enum CoverageAssignment: Hashable, Sendable, Codable {
    /// The user decided this plant needs nothing while they are away.
    case selfManaged
    case caretaker(UUID)
    /// Not decided yet. Surfaced calmly, never as an alarm.
    case unresolved

    public var caretakerID: UUID? {
        if case .caretaker(let id) = self { return id }
        return nil
    }

    public var isDecided: Bool { self != .unresolved }
}

/// A plant's coverage plan for one trip (PLANT_CARE.md §10).
public struct PlantTravelCoverage: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let tripID: UUID
    public let plantID: UUID
    public var assignment: CoverageAssignment
    /// What the caretaker is asked to do, in plain language. Generated from the
    /// schedules that fall inside the absence, then editable — the generated
    /// text is a starting point, not the record.
    public var instructions: String?
    /// The last care given before leaving, so the caretaker knows where things
    /// stood.
    public var lastCareBeforeDeparture: Date?
    /// Filled in later if the caretaker reports back.
    public var caretakerUpdateNote: String?
    public var caretakerUpdatedAt: Date?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        plantID: UUID,
        assignment: CoverageAssignment = .unresolved,
        instructions: String? = nil,
        lastCareBeforeDeparture: Date? = nil,
        caretakerUpdateNote: String? = nil,
        caretakerUpdatedAt: Date? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.tripID = tripID
        self.plantID = plantID
        self.assignment = assignment
        self.instructions = instructions
        self.lastCareBeforeDeparture = lastCareBeforeDeparture
        self.caretakerUpdateNote = caretakerUpdateNote
        self.caretakerUpdatedAt = caretakerUpdatedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// What a plant will need during an absence, worked out from its schedules.
public struct CoverageNeed: Hashable, Sendable, Identifiable {
    public let plantID: UUID
    /// Care that falls inside the absence window, soonest first.
    public let dueDuringAbsence: [DueDuringAbsence]
    /// The user's difficulty rating, carried through so the UI can order by it
    /// without a second lookup.
    public let difficulty: CareDifficulty

    public var id: UUID { plantID }

    public struct DueDuringAbsence: Hashable, Sendable {
        public let scheduleID: UUID
        public let careType: CareType
        public let dueDate: Date

        public init(scheduleID: UUID, careType: CareType, dueDate: Date) {
            self.scheduleID = scheduleID
            self.careType = careType
            self.dueDate = dueDate
        }
    }

    public init(
        plantID: UUID,
        dueDuringAbsence: [DueDuringAbsence],
        difficulty: CareDifficulty
    ) {
        self.plantID = plantID
        self.dueDuringAbsence = dueDuringAbsence
        self.difficulty = difficulty
    }

    /// Whether anything at all falls inside the window.
    public var needsAnything: Bool { !dueDuringAbsence.isEmpty }

    /// Plants that will need attention more than once, or that the user rated
    /// demanding. Used to order the list, never to label a plant "at risk" —
    /// nothing in the UI tells someone their plant is in danger.
    public var wantsMoreAttention: Bool {
        dueDuringAbsence.count > 1 || difficulty == .demanding
    }
}

/// Works out what care falls inside an absence.
///
/// Pure and calendar-driven so the whole coverage feature can be tested without
/// a trip, a caretaker, or a device. Projects each schedule forward through the
/// window rather than reporting only the next due date, because a plant watered
/// every four days needs attention three times across a fortnight and reporting
/// it once would understate the ask.
public enum CoveragePlanner {

    /// The most repeats projected for one schedule. A guard against a schedule
    /// with an absurdly short interval producing thousands of entries; anything
    /// past this is still shown as "and more" rather than enumerated.
    public static let maximumProjectedOccurrences = 30

    public static func need(
        plant: Plant,
        schedules: [PlantCareSchedule],
        absenceStart: Date,
        absenceEnd: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> CoverageNeed {
        guard absenceEnd > absenceStart else {
            return CoverageNeed(
                plantID: plant.id, dueDuringAbsence: [], difficulty: plant.difficulty
            )
        }

        var occurrences: [CoverageNeed.DueDuringAbsence] = []

        for schedule in schedules where schedule.isEnabled {
            occurrences.append(contentsOf: project(
                schedule: schedule,
                from: absenceStart,
                to: absenceEnd,
                calendar: calendar,
                timeZone: timeZone
            ))
        }

        occurrences.sort { $0.dueDate < $1.dueDate }
        return CoverageNeed(
            plantID: plant.id,
            dueDuringAbsence: occurrences,
            difficulty: plant.difficulty
        )
    }

    private static func project(
        schedule: PlantCareSchedule,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> [CoverageNeed.DueDuringAbsence] {
        guard let firstDue = schedule.nextDueDate else { return [] }

        var working = calendar
        working.timeZone = timeZone

        var result: [CoverageNeed.DueDuringAbsence] = []
        var cursor = firstDue

        /// One entry dated to the first day of the absence.
        func outstandingAtDeparture() -> CoverageNeed.DueDuringAbsence {
            CoverageNeed.DueDuringAbsence(
                scheduleID: schedule.id,
                careType: schedule.careType,
                dueDate: start
            )
        }

        // A task already overdue when the trip starts still needs doing while the
        // user is away — so it is surfaced once, dated to the first day.
        //
        // Advancing past it instead, which is what this used to do, dropped it
        // entirely: a monthly watering two days late next falls due four weeks
        // out, long after a one-week trip has ended, so the caretaker was never
        // told about the one plant that actually needed water on day one. The
        // comment here already claimed the correct behaviour; the code did the
        // opposite.
        let wasOutstanding = cursor < start
        while cursor < start {
            guard let next = advance(cursor, schedule: schedule, calendar: working),
                  // A non-advancing recurrence would spin here forever.
                  next > cursor
            else {
                // The recurrence cannot move forward, but the task is still
                // outstanding. Report it rather than losing it.
                if wasOutstanding { result.append(outstandingAtDeparture()) }
                return result
            }
            cursor = next
        }

        // Skipped when the cadence lands exactly on the first day, because the
        // projection below produces that occurrence itself and two entries for
        // one task would read as twice the work.
        if wasOutstanding, cursor != start {
            result.append(outstandingAtDeparture())
        }

        while cursor <= end, result.count < maximumProjectedOccurrences {
            result.append(CoverageNeed.DueDuringAbsence(
                scheduleID: schedule.id,
                careType: schedule.careType,
                dueDate: cursor
            ))
            guard let next = advance(cursor, schedule: schedule, calendar: working),
                  next > cursor
            else { break }
            cursor = next
        }

        return result
    }

    /// Steps one occurrence forward, honouring the seasonal modifier for the
    /// season the occurrence falls in — a fortnight in spring and a fortnight in
    /// winter are not the same number of waterings.
    private static func advance(
        _ date: Date,
        schedule: PlantCareSchedule,
        calendar: Calendar
    ) -> Date? {
        guard let days = CareScheduleCalculator.effectiveIntervalDays(
            for: schedule, at: date, calendar: calendar
        ) else { return nil }
        guard days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: days, to: date)
    }
}
