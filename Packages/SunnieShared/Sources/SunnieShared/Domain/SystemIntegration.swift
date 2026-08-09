import Foundation

// MARK: - Cross-process intent handoff

public struct IntentHandoffEnvelope: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let id: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let routeURL: URL
    public let tellSunnieText: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        lifetime: TimeInterval = 5 * 60,
        routeURL: URL,
        tellSunnieText: String? = nil
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(lifetime)
        self.routeURL = routeURL
        self.tellSunnieText = tellSunnieText
    }

    public func isConsumable(at date: Date, allowedScheme: String = DeepLinkScheme.scheme) -> Bool {
        version == Self.currentVersion
            && createdAt <= date
            && date < expiresAt
            && routeURL.scheme?.lowercased() == allowedScheme
    }
}

// MARK: - Capabilities

/// A stable vocabulary for optional system integrations. Features consume this
/// value instead of importing the framework that happens to provide it.
public enum SunnieCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case microphone, speechRecognition, photoLibrary, camera, notifications
    case health, calendar, location, weather, watchConnectivity, backgroundRefresh
    case widgets, foundationModels
}

public extension SunnieCapability {
    var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .speechRecognition: "Speech recognition"
        case .photoLibrary: "Photo library"
        case .camera: "Camera"
        case .notifications: "Notifications"
        case .health: "Health"
        case .calendar: "Calendar"
        case .location: "Location"
        case .weather: "Weather"
        case .watchConnectivity: "Apple Watch"
        case .backgroundRefresh: "Background refresh"
        case .widgets: "Widgets"
        case .foundationModels: "On-device intelligence"
        }
    }
}

public enum CapabilityState: String, Codable, Hashable, Sendable {
    case unavailable
    case notRequested
    case restricted
    case denied
    case limited
    case authorized

    public var canUse: Bool { self == .authorized || self == .limited }
    public var canRequest: Bool { self == .notRequested }
}

public struct CapabilitySnapshot: Hashable, Sendable {
    public let generatedAt: Date
    private let states: [SunnieCapability: CapabilityState]

    public init(generatedAt: Date, states: [SunnieCapability: CapabilityState]) {
        self.generatedAt = generatedAt
        self.states = states
    }

    public subscript(_ capability: SunnieCapability) -> CapabilityState {
        states[capability] ?? .unavailable
    }
}

public protocol CapabilityProviding: Sendable {
    func snapshot() async -> CapabilitySnapshot
}

// MARK: - Unified search

public enum SearchEntityKind: String, CaseIterable, Codable, Hashable, Sendable {
    case plant, trip, place, memory, recipe, game, curio
}

public enum SearchDestination: Codable, Hashable, Sendable {
    case plant(UUID)
    case trip(UUID)
    case travel
    case recipes
    case game(String)
    case collections

    public var routeURL: URL {
        switch self {
        case .plant(let id): URL(string: "sunniedays://plant/\(id)")!
        case .trip(let id): URL(string: "sunniedays://trip/\(id)")!
        case .travel: URL(string: "sunniedays://travel")!
        case .recipes: URL(string: "sunniedays://meals/recipes")!
        case .game(let id): URL(string: "sunniedays://games/\(id)")!
        case .collections: URL(string: "sunniedays://collections")!
        }
    }
}

/// Reconstructable search projection. It contains no journal or wellness kind
/// by design: adding either requires an explicit privacy-policy decision.
public struct SearchEntity: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: SearchEntityKind
    public let title: String
    public let subtitle: String?
    public let keywords: [String]
    public let destination: SearchDestination

    public init(
        id: String,
        kind: SearchEntityKind,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        destination: SearchDestination
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.keywords = Array(Set(keywords.map(Self.normalize))).sorted()
        self.destination = destination
    }

    public func matches(_ query: String) -> Bool {
        let tokens = Self.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = Self.normalize(([title, subtitle].compactMap { $0 } + keywords).joined(separator: " "))
        return tokens.allSatisfy(haystack.contains)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

public enum SearchRanking {
    public static func rank(_ entities: [SearchEntity], favorites: [FavoriteSignal]) -> [SearchEntity] {
        let strengths = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0.strength) })
        return entities.sorted { left, right in
            let leftStrength = strengths[left.id]?.rawValue ?? 0
            let rightStrength = strengths[right.id]?.rawValue ?? 0
            if leftStrength != rightStrength { return leftStrength > rightStrength }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }
}

// MARK: - Favorites intelligence

public enum PreferenceStrength: Int, Codable, Comparable, Hashable, Sendable {
    case inferred = 1
    case explicit = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct FavoriteSignal: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: SearchEntityKind
    public let entityID: String
    public let title: String
    public let strength: PreferenceStrength
    public let evidenceCount: Int

    public init(kind: SearchEntityKind, entityID: String, title: String, strength: PreferenceStrength, evidenceCount: Int) {
        self.id = "\(kind.rawValue).\(entityID)"
        self.kind = kind
        self.entityID = entityID
        self.title = title
        self.strength = strength
        self.evidenceCount = max(1, evidenceCount)
    }
}

public enum FavoritesResolver {
    /// Explicit choices always win. Inference requires repeated evidence and is
    /// deterministic, local, and safe to rebuild from authoritative records.
    public static func resolve(explicit: [FavoriteSignal], observations: [FavoriteSignal], minimumEvidence: Int = 2) -> [FavoriteSignal] {
        var winners = Dictionary(uniqueKeysWithValues: explicit.map { ($0.id, $0) })
        for candidate in observations where candidate.evidenceCount >= minimumEvidence {
            guard winners[candidate.id] == nil else { continue }
            winners[candidate.id] = FavoriteSignal(
                kind: candidate.kind,
                entityID: candidate.entityID,
                title: candidate.title,
                strength: .inferred,
                evidenceCount: candidate.evidenceCount
            )
        }
        return winners.values.sorted {
            if $0.strength != $1.strength { return $0.strength > $1.strength }
            if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

// MARK: - Background maintenance

public enum MaintenanceOperation: String, CaseIterable, Hashable, Sendable {
    case context, world, widgets, rewards, searchIndex, housekeeping
}

public struct MaintenancePlan: Hashable, Sendable {
    public let operations: [MaintenanceOperation]
    public init(operations: [MaintenanceOperation] = MaintenanceOperation.allCases) {
        var seen: Set<MaintenanceOperation> = []
        self.operations = operations.filter { seen.insert($0).inserted }
    }
}

public struct MaintenanceReport: Hashable, Sendable {
    public let completed: [MaintenanceOperation]
    public let failed: [MaintenanceOperation]
    public let wasCancelled: Bool

    public init(completed: [MaintenanceOperation], failed: [MaintenanceOperation], wasCancelled: Bool) {
        self.completed = completed
        self.failed = failed
        self.wasCancelled = wasCancelled
    }
}
