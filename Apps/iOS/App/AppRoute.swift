import Foundation

/// The five primary destinations. The order is locked
/// (INFORMATION_ARCHITECTURE.md §1).
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case today
    case jungle
    case travel
    case wellness
    case more

    var id: String { rawValue }

    var titleKey: String { "tab.\(rawValue)" }

    /// SF Symbols for functional navigation. Illustrated icons replace these
    /// during the visual design pass; the names live here rather than in the
    /// view so that swap is one edit.
    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .jungle: "leaf"
        case .travel: "airplane"
        case .wellness: "heart"
        case .more: "square.grid.2x2"
        }
    }
}

/// Typed routes. Notifications, widgets, Watch handoff, and App Intents all
/// resolve into these rather than constructing views directly
/// (TECHNICAL_ARCHITECTURE.md §9).
enum AppRoute: Hashable {
    case today
    case jungle
    case jungleDue
    case collection
    case plant(UUID)
    case plantHealth(UUID)
    case plantGrowth(UUID)
    case travel
    case trip(UUID)
    case packing(UUID)
    /// The phase is carried as its raw value so the route stays `Hashable` and
    /// `Codable`-friendly without the enum leaking into navigation state.
    case tripChecklist(UUID, String)
    case itinerary(UUID)
    case plantCoverage(UUID)
    case worldMap
    case wellness
    case checkIn
    case meals
    case mealPlanner
    case recipes
    case grocery
    case pantry
    case games
    case game(String)
    case journal
    case collections
    case sunnieHome
    case themes
    case settings

    /// The tab this route belongs to, so a deep link switches tabs before
    /// pushing.
    var tab: AppTab {
        switch self {
        case .today: .today
        case .jungle, .jungleDue, .collection, .plant, .plantHealth, .plantGrowth: .jungle
        case .travel, .trip, .packing, .tripChecklist, .itinerary,
             .plantCoverage, .worldMap: .travel
        case .wellness, .checkIn: .wellness
        case .meals, .mealPlanner, .recipes, .grocery, .pantry,
             .games, .game, .journal,
             .collections, .sunnieHome, .themes, .settings: .more
        }
    }

    /// Whether this route is a tab root rather than something to push.
    var isTabRoot: Bool {
        switch self {
        case .today, .jungle, .travel, .wellness: true
        default: false
        }
    }
}

/// Parses `sunniedays://` links into typed routes
/// (INFORMATION_ARCHITECTURE.md §13).
///
/// Unrecognised links resolve to nil rather than to a default screen: silently
/// landing somewhere unexpected is more confusing than doing nothing.
enum DeepLinkParser {
    /// Taken from the shared constant so the parser and the QR payload cannot
    /// drift apart — a printed label uses the same scheme.
    static let scheme = DeepLinkScheme.scheme

    static func route(from url: URL) -> AppRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // In sunniedays://plant/{uuid}, "plant" is the host and the id is the
        // first path component.
        var components = [url.host].compactMap { $0 }
        components.append(contentsOf: url.pathComponents.filter { $0 != "/" })

        guard let first = components.first?.lowercased() else { return nil }
        let second = components.count > 1 ? components[1] : nil

        switch (first, second) {
        case ("today", _): return .today
        case ("jungle", "due"): return .jungleDue
        case ("jungle", "collection"): return .collection
        case ("jungle", _): return .jungle
        case ("plant", let id?): return UUID(uuidString: id).map(AppRoute.plant)
        case ("travel", _): return .travel
        case ("trip", let id?): return UUID(uuidString: id).map(AppRoute.trip)
        case ("map", _): return .worldMap
        case ("wellness", "checkin"): return .checkIn
        case ("wellness", _): return .wellness
        case ("meals", "grocery"): return .grocery
        case ("meals", "pantry"): return .pantry
        case ("meals", "recipes"): return .recipes
        case ("meals", _): return .meals
        case ("games", "daily"): return .games
        case ("games", let id?): return .game(id)
        case ("games", nil): return .games
        case ("journal", _): return .journal
        case ("collections", _): return .collections
        case ("home", _): return .sunnieHome
        case ("themes", _): return .themes
        case ("settings", _): return .settings
        default: return nil
        }
    }
}
