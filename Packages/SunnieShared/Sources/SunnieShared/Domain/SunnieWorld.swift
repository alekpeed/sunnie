import Foundation

/// Read-only cross-feature world state for Sunnie Home, collections, memories,
/// widgets, and other ambient surfaces. It is derived from authoritative app
/// records and never becomes a second persistence layer.
public struct SunnieWorldSnapshot: Hashable, Sendable {
    public let generatedAt: Date
    public let environment: WorldEnvironment
    public let curios: [CurioItem]
    public let memories: [MemoryChapter]

    public init(
        generatedAt: Date,
        environment: WorldEnvironment = .ordinary,
        curios: [CurioItem] = [],
        memories: [MemoryChapter] = []
    ) {
        self.generatedAt = generatedAt
        self.environment = environment
        self.curios = curios.sorted { left, right in
            if left.unlockedAtLevel != right.unlockedAtLevel {
                return left.unlockedAtLevel < right.unlockedAtLevel
            }
            return left.id < right.id
        }
        self.memories = memories.sorted { left, right in
            left.occurredAt > right.occurredAt
        }
    }

    public static func empty(at date: Date) -> SunnieWorldSnapshot {
        SunnieWorldSnapshot(generatedAt: date)
    }
}

public enum WorldEnvironment: Hashable, Sendable {
    case ordinary
    case plantDay
    case tripPreparing(destination: String?)
    case tripAway(destination: String?)
    case tripReturning(destination: String?)

    public var title: String {
        switch self {
        case .ordinary: return "Sunnie's world"
        case .plantDay: return "A greener day"
        case .tripPreparing(let destination):
            return destination.map { "Getting ready for \($0)" } ?? "Getting ready to travel"
        case .tripAway(let destination):
            return destination.map { "Sunnie in \($0)" } ?? "Sunnie away"
        case .tripReturning(let destination):
            return destination.map { "Coming home from \($0)" } ?? "Coming home"
        }
    }
}

public enum CurioKind: String, Hashable, Sendable, Codable {
    case keepsake
    case plant
    case travel
    case game
    case seasonal
}

/// A permanent positive unlock represented inside Sunnie's world.
/// Unlocks are monotonic because they derive only from durable progression.
public struct CurioItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let kind: CurioKind
    public let unlockedAtLevel: Int

    public init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        kind: CurioKind,
        unlockedAtLevel: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.kind = kind
        self.unlockedAtLevel = unlockedAtLevel
    }
}

public struct MemoryChapter: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let occurredAt: Date
    public let symbol: String

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        occurredAt: Date,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.occurredAt = occurredAt
        self.symbol = symbol
    }
}

public enum CurioCatalog {
    private static let catalog: [CurioItem] = [
        CurioItem(
            id: "curio.first-leaf",
            title: "Little Leaf",
            detail: "A tiny plant for Sunnie's shelf.",
            symbol: "leaf.fill",
            kind: .plant,
            unlockedAtLevel: 1
        ),
        CurioItem(
            id: "curio.postcard",
            title: "Postcard Stand",
            detail: "A place for memories from the road.",
            symbol: "postcard.fill",
            kind: .travel,
            unlockedAtLevel: 3
        ),
        CurioItem(
            id: "curio-teacup",
            title: "Favorite Cup",
            detail: "A permanent cozy object for Sunnie's home.",
            symbol: "cup.and.saucer.fill",
            kind: .keepsake,
            unlockedAtLevel: 5
        ),
        CurioItem(
            id: "curio-mini-plane",
            title: "Tiny Airplane",
            detail: "A miniature travel keepsake.",
            symbol: "airplane",
            kind: .travel,
            unlockedAtLevel: 8
        ),
        CurioItem(
            id: "curio-game-star",
            title: "Puzzle Star",
            detail: "A small trophy for Sunnie's cabinet.",
            symbol: "star.fill",
            kind: .game,
            unlockedAtLevel: 12
        )
    ]

    public static func unlocked(atLevel level: Int) -> [CurioItem] {
        catalog.filter { $0.unlockedAtLevel <= level }
    }
}
