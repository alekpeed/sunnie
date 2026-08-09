import Foundation

// MARK: - Unified context

/// A read-only snapshot of what matters across Sunnie Days right now.
///
/// This is deliberately presentation-friendly but mutation-free. Consumers such
/// as Today, Sunnie Home, Watch, widgets, and Tell Sunnie can all read the same
/// picture of the world without gaining the ability to edit another feature's
/// data behind the user's back.
public struct CurrentContext: Sendable {
    public let generatedAt: Date
    public let plantSummary: PlantTodaySummary?
    public let wellnessSummary: WellnessSummary?
    public let progression: ProgressionProfile
    public let flightMode: FlightContext?
    public let items: [ContextItem]

    public init(
        generatedAt: Date,
        plantSummary: PlantTodaySummary? = nil,
        wellnessSummary: WellnessSummary? = nil,
        progression: ProgressionProfile = ProgressionProfile(),
        flightMode: FlightContext? = nil,
        items: [ContextItem] = []
    ) {
        self.generatedAt = generatedAt
        self.plantSummary = plantSummary
        self.wellnessSummary = wellnessSummary
        self.progression = progression
        self.flightMode = flightMode
        self.items = items.sorted { left, right in
            if left.priority != right.priority { return left.priority > right.priority }
            return left.id < right.id
        }
    }

    public static func empty(at date: Date) -> CurrentContext {
        CurrentContext(generatedAt: date)
    }
}

public enum ContextItemKind: String, Hashable, Sendable, Codable {
    case informational
    case actionable
    case celebratory
    case ambient
}

/// Semantic actions rather than screen names. The iPhone, Watch, widgets and
/// future system integrations can each decide how to present the same action.
public enum ContextAction: Hashable, Sendable, Codable {
    case openTravel
    case openTrip(UUID)
    case openPacking(UUID)
    case openChecklist(UUID, ChecklistKind.Phase)
    case openPlantCoverage(UUID)
    case openJungle
    case openJungleDue
    case openMeals
    case openGames
    case openWellness
    case openJournal
    case openSunnieHome
    case openCollections
    case tellSunnie
}

public struct ContextItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let kind: ContextItemKind
    public let priority: Int
    public let title: String
    public let detail: String?
    public let primaryAction: ContextAction?
    public let secondaryAction: ContextAction?
    public let expiresAt: Date?

    public init(
        id: String,
        kind: ContextItemKind,
        priority: Int,
        title: String,
        detail: String? = nil,
        primaryAction: ContextAction? = nil,
        secondaryAction: ContextAction? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.title = title
        self.detail = detail
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.expiresAt = expiresAt
    }

    public func isRelevant(at date: Date) -> Bool {
        guard let expiresAt else { return true }
        return date <= expiresAt
    }
}

// MARK: - Flight Mode

public enum FlightModePhase: String, Hashable, Sendable, Codable {
    case preparing
    case away
    case returning
}

/// Whole-app context for an explicitly marked work trip.
///
/// This is personal travel context, not airline operations data. Counts are
/// facts about the user's own lists and are never interpreted as compliance,
/// readiness, failure, or a requirement to finish them.
public struct FlightContext: Sendable {
    public let tripID: UUID
    public let tripTitle: String
    public let phase: FlightModePhase
    public let destinationName: String?
    public let destinationTimeZoneID: String?
    public let startsAt: Date?
    public let endsAt: Date?
    public let daysUntilDeparture: Int?
    public let packedCount: Int
    public let packingCount: Int
    public let checklistDoneCount: Int
    public let checklistCount: Int
    public let plantCoverageUndecidedCount: Int
    public let plantsNeedingTripCareCount: Int
    public let plannedMealsTodayCount: Int
    public let weather: WeatherSummary?

    public init(
        tripID: UUID,
        tripTitle: String,
        phase: FlightModePhase,
        destinationName: String? = nil,
        destinationTimeZoneID: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        daysUntilDeparture: Int? = nil,
        packedCount: Int = 0,
        packingCount: Int = 0,
        checklistDoneCount: Int = 0,
        checklistCount: Int = 0,
        plantCoverageUndecidedCount: Int = 0,
        plantsNeedingTripCareCount: Int = 0,
        plannedMealsTodayCount: Int = 0,
        weather: WeatherSummary? = nil
    ) {
        self.tripID = tripID
        self.tripTitle = tripTitle
        self.phase = phase
        self.destinationName = destinationName
        self.destinationTimeZoneID = destinationTimeZoneID
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.daysUntilDeparture = daysUntilDeparture
        self.packedCount = packedCount
        self.packingCount = packingCount
        self.checklistDoneCount = checklistDoneCount
        self.checklistCount = checklistCount
        self.plantCoverageUndecidedCount = plantCoverageUndecidedCount
        self.plantsNeedingTripCareCount = plantsNeedingTripCareCount
        self.plannedMealsTodayCount = plannedMealsTodayCount
        self.weather = weather
    }
}

public struct FlightModeSelection: Hashable, Sendable {
    public let trip: Trip
    public let phase: FlightModePhase

    public init(trip: Trip, phase: FlightModePhase) {
        self.trip = trip
        self.phase = phase
    }
}

/// Conservative Flight Mode selection.
///
/// Automatic activation requires the user to have explicitly classified the
/// trip as `.work`. A current work trip wins; otherwise an upcoming work trip is
/// selected only inside the preparation window. A vague calendar clue or an
/// ordinary personal trip can never put the app into work mode.
public enum FlightModeSelector {
    public static let defaultPreparationDays = 3

    public static func select(
        from trips: [Trip],
        now: Date,
        calendar: Calendar,
        preparationDays: Int = defaultPreparationDays
    ) -> FlightModeSelection? {
        let work = trips.filter { $0.type == .work }

        let classified = work.map { trip in
            (trip, TripStatusCalculator.status(for: trip, now: now, calendar: calendar))
        }

        if let current = classified
            .filter({ $0.1 == .active || $0.1 == .returning })
            .sorted(by: { ($0.0.startsAt ?? .distantPast) > ($1.0.startsAt ?? .distantPast) })
            .first {
            return FlightModeSelection(
                trip: current.0,
                phase: current.1 == .returning ? .returning : .away
            )
        }

        let upcoming = classified
            .filter { $0.1 == .upcoming }
            .compactMap { pair -> (Trip, Int)? in
                guard let days = TripStatusCalculator.daysUntilDeparture(
                    pair.0, now: now, calendar: calendar
                ), days >= 0, days <= preparationDays else { return nil }
                return (pair.0, days)
            }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 < right.1 }
                return (left.0.startsAt ?? .distantFuture) < (right.0.startsAt ?? .distantFuture)
            }
            .first

        return upcoming.map { FlightModeSelection(trip: $0.0, phase: .preparing) }
    }
}

// MARK: - Tell Sunnie

public enum AssistantDestination: String, Hashable, Sendable, Codable {
    case travel
    case plants
    case meals
    case games
    case wellness
    case journal
    case home
    case collections
}

public enum TellSunnieIntent: Hashable, Sendable {
    case open(AssistantDestination)
    case recordPlantCare(careType: CareType, plantQuery: String)
    case addPackingItem(name: String, category: PackingCategory)
    case askTripPreparation
    case askPlantCare
    case unknown
}

/// Deterministic first-pass parser for common, high-confidence requests.
///
/// A future Foundation Models layer can handle freer language, but it plugs in
/// after these contracts. Core capture therefore works offline and never needs a
/// model to understand the most common commands.
public enum TellSunnieParser {
    public static func parse(_ input: String) -> TellSunnieIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        let normalized = normalize(trimmed)

        if isTripPreparationQuestion(normalized) {
            return .askTripPreparation
        }
        if normalized.contains("how many plant") && normalized.contains("care") {
            return .askPlantCare
        }

        if let care = parseCare(normalized) {
            return care
        }
        if let packing = parsePacking(trimmed, normalized: normalized) {
            return packing
        }
        if let destination = parseDestination(normalized) {
            return .open(destination)
        }

        return .unknown
    }

    private static func isTripPreparationQuestion(_ text: String) -> Bool {
        let tripWords = text.contains("flight") || text.contains("trip") || text.contains("leave")
        let prepWords = text.contains("what do i still")
            || text.contains("what is left")
            || text.contains("what's left")
            || text.contains("before i")
            || text.contains("ready for")
            || text.contains("trip prep")
        return tripWords && prepWords
    }

    private static func parseCare(_ text: String) -> TellSunnieIntent? {
        let patterns: [(words: [String], type: CareType)] = [
            (["watered", "watered the", "i watered"], .water),
            (["fertilized", "fertilised", "i fertilized", "i fertilised"], .fertilize),
            (["misted", "i misted"], .mist),
            (["rotated", "i rotated"], .rotate),
            (["pruned", "i pruned"], .prune),
            (["repotted", "i repotted"], .repot)
        ]

        for pattern in patterns {
            for word in pattern.words where text.contains(word) {
                let remainder = text
                    .replacingOccurrences(of: "i ", with: "")
                    .replacingOccurrences(of: word, with: "")
                let query = cleanPlantQuery(remainder)
                if !query.isEmpty {
                    return .recordPlantCare(careType: pattern.type, plantQuery: query)
                }
            }
        }
        return nil
    }

    private static func parsePacking(
        _ original: String,
        normalized: String
    ) -> TellSunnieIntent? {
        let prefixes = [
            "remind me to pack ",
            "add to packing ",
            "add to my packing ",
            "add "
        ]

        var item: String?
        if normalized.hasPrefix("pack ") {
            item = String(original.dropFirst(5))
        } else {
            for prefix in prefixes where normalized.hasPrefix(prefix) {
                let count = prefix.count
                item = String(original.dropFirst(min(count, original.count)))
                break
            }
        }

        guard var item else { return nil }
        if normalized.hasPrefix("add ") && !normalized.contains("packing") {
            return nil
        }

        item = item
            .replacingOccurrences(of: " to my packing list", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: " to packing", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard !item.isEmpty else { return nil }
        return .addPackingItem(name: item, category: packingCategory(for: normalize(item)))
    }

    private static func parseDestination(_ text: String) -> AssistantDestination? {
        let pairs: [(AssistantDestination, [String])] = [
            (.travel, ["travel", "trip"]),
            (.plants, ["plants", "jungle"]),
            (.meals, ["meals", "recipes", "grocery", "food"]),
            (.games, ["games", "game", "puzzle"]),
            (.wellness, ["wellness", "check in", "check-in", "calm"]),
            (.journal, ["journal", "write"]),
            (.home, ["sunnie's home", "sunnie home", "home"]),
            (.collections, ["collection", "rewards", "outfits"])
        ]

        let opensSomething = text.hasPrefix("open ")
            || text.hasPrefix("show ")
            || text.hasPrefix("go to ")
            || text.hasPrefix("take me to ")
        guard opensSomething else { return nil }

        return pairs.first { pair in pair.1.contains { text.contains($0) } }?.0
    }

    private static func packingCategory(for item: String) -> PackingCategory {
        if ["charger", "cable", "adapter", "headphones", "ipad", "laptop", "phone"]
            .contains(where: item.contains) { return .technology }
        if ["passport", "badge", "id", "license", "document"]
            .contains(where: item.contains) { return .documents }
        if ["uniform", "work shoes"].contains(where: item.contains) { return .uniform }
        if ["snack", "food", "meal", "water bottle"].contains(where: item.contains) { return .food }
        if ["tooth", "shampoo", "conditioner", "makeup", "toiletr"]
            .contains(where: item.contains) { return .toiletries }
        return .personal
    }

    private static func cleanPlantQuery(_ text: String) -> String {
        var result = text
        for removable in [
            " this morning", " this afternoon", " this evening", " tonight",
            " today", " just now", " yesterday", " the "
        ] {
            result = result.replacingOccurrences(of: removable, with: " ")
        }
        return result
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
