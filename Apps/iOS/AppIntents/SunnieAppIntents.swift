import AppIntents
import Foundation
import SwiftUI
import SunnieShared

/// The intents Sunnie Days exposes to Shortcuts, Siri, and the Action button
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §9).
///
/// §9 ends with the rule that governs this whole file: **App Intents call the
/// same use cases as the app UI.** Not a parallel implementation, not a
/// simplified one. Logging a watering through Shortcuts goes through
/// `LogPlantCare`, gets the same action key, earns the same progression once,
/// and reaches the Watch the same way — because it is the same call.
///
/// Intents run in a separate process from the app. `IntentDependencies` builds
/// what it needs on demand rather than reaching for a running app's composition
/// root, which does not exist here.
@MainActor
enum IntentDependencies {

    /// The composition an intent runs against.
    ///
    /// Built once per process and held, because an intent process can serve
    /// several invocations and re-opening the store for each would be slow and
    /// would risk two containers over one file.
    private static var shared: AppDependencies?

    static func resolve() -> AppDependencies? {
        if let shared { return shared }
        guard let container = try? ModelContainerFactory.make(
            storage: .onDisk(cloudKit: false)
        ) else {
            // No store means no intent. Reporting failure is better than
            // silently doing nothing, which would look like the shortcut worked.
            return nil
        }
        let dependencies = AppDependencies(
            modelContainer: container,
            // The intent process is not the app: it has no Watch session of its
            // own, and activating one here would fight the app's.
            enableWatchConnectivity: false
        )
        shared = dependencies
        return dependencies
    }
}

/// Thrown when the app's own storage cannot be opened.
///
/// A distinct error rather than a silent no-op, so Shortcuts shows the user that
/// nothing happened instead of a green tick over a watering that was never
/// recorded.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case storageUnavailable
    case notFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable:
            "Sunnie couldn't open your things just now. Nothing has been changed."
        case .notFound:
            "Sunnie couldn't find that. Nothing has been changed."
        }
    }
}

// MARK: - Shared context and Tell Sunnie

struct TellSunnieIntentEntry: AppIntent {
    static var title: LocalizedStringResource { "Tell Sunnie" }
    static var description: IntentDescription { IntentDescription("Opens Sunnie's safe, local-first command router with your words ready.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "What would you like to do?") var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentHandoffStore.live.save(
            routeURL: URL(string: "sunniedays://today")!,
            tellSunnieText: text
        )
        return .result()
    }
}

struct ShowCurrentContextIntent: AppIntent {
    static var title: LocalizedStringResource { "What's happening in Sunnie Days?" }
    static var description: IntentDescription { IntentDescription("Summarizes the most relevant current context without changing anything.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependencies = IntentDependencies.resolve() else { throw IntentFailure.storageUnavailable }
        let context = await ContextEngine(dependencies: dependencies).currentContext()
        guard let item = context.items.first else { return .result(dialog: "Everything is quietly in place.") }
        return .result(dialog: "\(item.title): \(item.detail)")
    }
}

struct AddFlightPackingItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Add to Flight Mode packing" }
    static var description: IntentDescription { IntentDescription("Adds an item only when one unambiguous work trip is in Flight Mode.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Item") var itemName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependencies = IntentDependencies.resolve() else { throw IntentFailure.storageUnavailable }
        let context = await ContextEngine(dependencies: dependencies).currentContext()
        guard let flight = context.flightMode else {
            return .result(dialog: "There isn't a work trip in Flight Mode, so nothing was changed.")
        }
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw IntentFailure.notFound }
        _ = try await dependencies.managePacking.save(PackingItem(tripID: flight.tripID, name: name, category: .other))
        await dependencies.publishWidgetSnapshot()
        return .result(dialog: "Added \(name) to \(flight.tripTitle) packing.")
    }
}

@MainActor
enum TellSunnieCaptureBox {
    static var pendingText: String?
    static func take() -> String? { defer { pendingText = nil }; return pendingText }
}

// MARK: - Plants

/// One of the user's plants, as Shortcuts sees it.
struct PlantEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Plant" }
    // `let`, not `var`. `AppEntity` only requires a getter, and a mutable
    // non-isolated static is exactly the shape strict concurrency objects to —
    // a warning in Swift 5 mode today and an error the moment this moves to
    // Swift 6 (ADR-010 says that move is deliberate, not hypothetical).
    static let defaultQuery = PlantEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlantEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlantEntity] {
        guard let dependencies = IntentDependencies.resolve() else { return [] }
        var found: [PlantEntity] = []
        for id in identifiers {
            if let plant = try? await dependencies.plantRepository.plant(id: id) {
                found.append(PlantEntity(id: plant.id, name: plant.name))
            }
        }
        return found
    }

    @MainActor
    func suggestedEntities() async throws -> [PlantEntity] {
        guard let dependencies = IntentDependencies.resolve() else { return [] }
        let plants = (try? await dependencies.plantRepository.allPlants(
            includingArchived: false
        )) ?? []
        return plants.map { PlantEntity(id: $0.id, name: $0.name) }
    }
}

/// Care types, so a shortcut can say "water" rather than guess.
enum CareTypeAppValue: String, AppEnum {
    // Raw values are the domain's own storage keys, so `careType` is a lookup
    // rather than a mapping table that can drift. British spelling stays in the
    // display representation below, where it belongs.
    case water
    case mist
    case fertilize
    case rotate
    case repot
    case prune

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Kind of care" }

    static var caseDisplayRepresentations: [CareTypeAppValue: DisplayRepresentation] {
        [
            .water: "Water",
            .mist: "Mist",
            .fertilize: "Feed",
            .rotate: "Turn",
            .repot: "Repot",
            .prune: "Prune"
        ]
    }

    /// Resolves against the domain's own storage keys.
    ///
    /// Returns nil rather than defaulting to watering: a shortcut that quietly
    /// records the wrong kind of care is worse than one that says it could not.
    var careType: CareType? { CareType(storageKey: rawValue) }
}

struct LogPlantCareIntent: AppIntent {
    static var title: LocalizedStringResource { "Log plant care" }
    static var description: IntentDescription {
        IntentDescription("Records that you looked after a plant.")
    }
    /// No app launch: the point of this intent is doing it without opening
    /// anything.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Plant")
    var plant: PlantEntity

    @Parameter(title: "Kind of care", default: .water)
    var kind: CareTypeAppValue

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kind) for \(\.$plant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependencies = IntentDependencies.resolve() else {
            throw IntentFailure.storageUnavailable
        }
        guard let careType = kind.careType else { throw IntentFailure.notFound }

        // The same call the app's own button makes. Idempotent on its action
        // key, so running the shortcut twice in a minute records one watering.
        _ = try await dependencies.logPlantCare(plantID: plant.id, careType: careType)
        await dependencies.publishWidgetSnapshot()

        return .result(dialog: "Noted for \(plant.name).")
    }
}

// MARK: - Wellness

struct StartCheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a check-in" }
    static var description: IntentDescription {
        IntentDescription("Opens Sunnie Days on the check-in screen.")
    }
    /// This one does open the app: a check-in is a few considered taps, not a
    /// value a shortcut can supply on someone's behalf.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentHandoffStore.live.save(routeURL: URL(string: "sunniedays://wellness/checkin")!)
        return .result()
    }
}

struct StartBreathingIntent: AppIntent {
    static var title: LocalizedStringResource { "Start breathing" }
    static var description: IntentDescription {
        IntentDescription("Opens Sunnie Days and begins a breathing practice.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentHandoffStore.live.save(routeURL: URL(string: "sunniedays://wellness")!)
        return .result()
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "Log water" }
    static var description: IntentDescription {
        IntentDescription("Records a drink of water.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Millilitres", default: 250)
    var millilitres: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$millilitres) ml of water")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dependencies = IntentDependencies.resolve() else {
            throw IntentFailure.storageUnavailable
        }
        let entry = try await dependencies.manageHealth.logWater(millilitres: millilitres)
        return .result(dialog: "\(entry.millilitres) ml noted.")
    }
}

// MARK: - Travel, journal, games

struct OpenCurrentTripIntent: AppIntent {
    static var title: LocalizedStringResource { "Open current trip" }
    static var description: IntentDescription {
        IntentDescription("Opens the trip you're on, or the next one coming up.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependencies = IntentDependencies.resolve() else {
            throw IntentFailure.storageUnavailable
        }
        let now = dependencies.clock.now
        let calendar = dependencies.clock.calendar
        let trips = (try? await dependencies.travelRepository.trips(
            includingArchived: false
        )) ?? []

        let candidate = trips
            .map { ($0, TripStatusCalculator.status(for: $0, now: now, calendar: calendar)) }
            .filter { $0.1.isCurrent || $0.1 == .upcoming }
            .sorted { ($0.0.startsAt ?? .distantFuture) < ($1.0.startsAt ?? .distantFuture) }
            .first

        // No trip opens the travel tab rather than failing: "there isn't one"
        // is better said by the screen than by an error dialog.
        let route = candidate.map { "sunniedays://trip/\($0.0.id)" } ?? "sunniedays://travel"
        try IntentHandoffStore.live.save(routeURL: URL(string: route)!)
        return .result()
    }
}

struct AddJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource { "Add a journal entry" }
    static var description: IntentDescription {
        IntentDescription("Opens Sunnie Days on the journal.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentHandoffStore.live.save(routeURL: URL(string: "sunniedays://journal")!)
        return .result()
    }
}

struct ShowDailyPuzzleIntent: AppIntent {
    static var title: LocalizedStringResource { "Show today's puzzle" }
    static var description: IntentDescription {
        IntentDescription("Opens today's puzzle.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentHandoffStore.live.save(routeURL: URL(string: "sunniedays://games")!)
        return .result()
    }
}

/// The shortcuts offered without the user having to build one.
struct SunnieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TellSunnieIntentEntry(),
            phrases: ["Tell \(.applicationName) something"],
            shortTitle: "Tell Sunnie",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: ShowCurrentContextIntent(),
            phrases: ["What's happening in \(.applicationName)"],
            shortTitle: "Current context",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: StartCheckInIntent(),
            phrases: ["Check in with \(.applicationName)"],
            shortTitle: "Check in",
            systemImageName: "heart"
        )
        AppShortcut(
            intent: StartBreathingIntent(),
            phrases: ["Start breathing with \(.applicationName)"],
            shortTitle: "Breathe",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: ShowDailyPuzzleIntent(),
            phrases: ["Show today's puzzle in \(.applicationName)"],
            shortTitle: "Today's puzzle",
            systemImageName: "puzzlepiece"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: ["Log water in \(.applicationName)"],
            shortTitle: "Log water",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: OpenCurrentTripIntent(),
            phrases: ["Open my trip in \(.applicationName)"],
            shortTitle: "Current trip",
            systemImageName: "airplane"
        )
    }
}
