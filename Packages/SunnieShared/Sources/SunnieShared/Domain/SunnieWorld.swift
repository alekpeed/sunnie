import Foundation

/// Read-only cross-feature world state for Sunnie Home, collections, memories,
/// widgets, and other ambient surfaces. It is derived from authoritative app
/// records and never becomes a second persistence layer.
public struct SunnieWorldSnapshot: Hashable, Sendable {
    public let generatedAt: Date
    public let environment: WorldEnvironment
    public let curios: [CurioItem]
    public let memories: [MemoryChapter]
    public let languageMoment: LanguageMoment?
    public let preferenceHint: WorldPreferenceHint?
    public let presentationPacks: [PresentationPack]
    public let surprise: WorldSurprise?

    public init(
        generatedAt: Date,
        environment: WorldEnvironment = .ordinary,
        curios: [CurioItem] = [],
        memories: [MemoryChapter] = [],
        languageMoment: LanguageMoment? = nil,
        preferenceHint: WorldPreferenceHint? = nil,
        presentationPacks: [PresentationPack] = [],
        surprise: WorldSurprise? = nil
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
        self.languageMoment = languageMoment
        self.preferenceHint = preferenceHint
        self.presentationPacks = presentationPacks.sorted { left, right in
            if left.unlockedAtLevel != right.unlockedAtLevel {
                return left.unlockedAtLevel < right.unlockedAtLevel
            }
            return left.id < right.id
        }
        self.surprise = surprise
    }

    public static func empty(at date: Date) -> SunnieWorldSnapshot {
        SunnieWorldSnapshot(generatedAt: date)
    }

    public var activePresentationPack: PresentationPack? {
        presentationPacks.last
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

    public var detail: String {
        switch self {
        case .ordinary:
            return "Your memories, plants, travel and keepsakes are all part of one world."
        case .plantDay:
            return "Plant care is part of today's world context."
        case .tripPreparing(let destination):
            return destination.map { "Travel, packing, plants and meals are gathering around your \($0) trip." }
                ?? "Travel, packing, plants and meals are gathering around your next trip."
        case .tripAway(let destination):
            return destination.map { "Sunnie Days is carrying your \($0) context across the app." }
                ?? "Your active trip is carrying across Sunnie Days."
        case .tripReturning(let destination):
            return destination.map { "Your \($0) trip is becoming part of your memory world." }
                ?? "Your trip is becoming part of your memory world."
        }
    }

    public var symbol: String {
        switch self {
        case .ordinary: return "house.fill"
        case .plantDay: return "leaf.fill"
        case .tripPreparing: return "suitcase.fill"
        case .tripAway: return "airplane"
        case .tripReturning: return "house.and.flag.fill"
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
    public let tripID: UUID?
    public let destinationName: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        occurredAt: Date,
        symbol: String,
        tripID: UUID? = nil,
        destinationName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.occurredAt = occurredAt
        self.symbol = symbol
        self.tripID = tripID
        self.destinationName = destinationName
    }
}

public struct LanguageMoment: Identifiable, Hashable, Sendable {
    public let id: String
    public let destination: String
    public let phrase: String
    public let translation: String
    public let note: String?

    public init(
        id: String,
        destination: String,
        phrase: String,
        translation: String,
        note: String? = nil
    ) {
        self.id = id
        self.destination = destination
        self.phrase = phrase
        self.translation = translation
        self.note = note
    }
}

/// Small deterministic phrase catalog. Destination aliases are matched as token
/// sequences, never arbitrary substrings, so places such as Venice cannot collide
/// with Nice.
public enum LanguageMomentCatalog {
    public static func moment(for destination: String?) -> LanguageMoment? {
        guard let destination else { return nil }

        if matches(destination, aliases: ["japan", "tokyo", "osaka", "kyoto", "fukuoka", "sapporo", "naha"]) {
            return LanguageMoment(
                id: "language.ja.otsukaresama",
                destination: destination,
                phrase: "おつかれさま",
                translation: "Good work / thanks for your effort",
                note: "A common, warm Japanese expression after work or effort."
            )
        }
        if matches(destination, aliases: ["brazil", "rio", "rio de janeiro", "sao paulo", "salvador", "recife"]) {
            return LanguageMoment(
                id: "language.pt.fica-a-vontade",
                destination: destination,
                phrase: "Fica à vontade",
                translation: "Make yourself at home",
                note: "A natural Brazilian Portuguese invitation to relax or help yourself."
            )
        }
        if matches(destination, aliases: ["portugal", "lisbon", "lisboa", "porto"]) {
            return LanguageMoment(
                id: "language.pt.obrigada",
                destination: destination,
                phrase: "Obrigada",
                translation: "Thank you",
                note: "The feminine form in Portuguese."
            )
        }
        if matches(destination, aliases: ["france", "paris", "lyon", "nice", "marseille"]) {
            return LanguageMoment(
                id: "language.fr.bonne-journee",
                destination: destination,
                phrase: "Bonne journée",
                translation: "Have a good day"
            )
        }
        if matches(destination, aliases: ["spain", "madrid", "barcelona", "sevilla", "seville"]) {
            return LanguageMoment(
                id: "language.es.que-aproveche",
                destination: destination,
                phrase: "Que aproveche",
                translation: "Enjoy your meal"
            )
        }
        if matches(destination, aliases: ["thailand", "bangkok", "chiang mai", "phuket"]) {
            return LanguageMoment(
                id: "language.th.sawasdee",
                destination: destination,
                phrase: "สวัสดีค่ะ",
                translation: "Hello",
                note: "A polite feminine greeting in Thai."
            )
        }
        if matches(destination, aliases: ["vietnam", "hanoi", "ho chi minh", "ho chi minh city", "saigon", "da nang"]) {
            return LanguageMoment(
                id: "language.vi.cam-on",
                destination: destination,
                phrase: "Cảm ơn",
                translation: "Thank you"
            )
        }
        return nil
    }

    private static func matches(_ destination: String, aliases: [String]) -> Bool {
        let haystack = tokens(destination)
        return aliases.map(tokens).contains { containsSequence(haystack, $0) }
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        if needle.count == 1 { return haystack.contains(needle[0]) }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}

public struct WorldPreferenceHint: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String

    public init(id: String, title: String, detail: String, symbol: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

public struct PresentationPack: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let unlockedAtLevel: Int

    public init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        unlockedAtLevel: Int
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.unlockedAtLevel = unlockedAtLevel
    }
}

public enum PresentationPackCatalog {
    private static let catalog: [PresentationPack] = [
        PresentationPack(
            id: "presentation.sunny-classic",
            title: "Sunnie Classic",
            detail: "The original warm greeting and home presentation.",
            symbol: "sun.max.fill",
            unlockedAtLevel: 1
        ),
        PresentationPack(
            id: "presentation-soft-evening",
            title: "Soft Evening",
            detail: "A quieter Sunnie presentation for slower moments.",
            symbol: "moon.stars.fill",
            unlockedAtLevel: 6
        ),
        PresentationPack(
            id: "presentation-traveler",
            title: "Little Traveler",
            detail: "Travel-aware presentation details for Sunnie's world.",
            symbol: "airplane.circle.fill",
            unlockedAtLevel: 10
        )
    ]

    public static func unlocked(atLevel level: Int) -> [PresentationPack] {
        catalog.filter { $0.unlockedAtLevel <= level }
    }
}

public struct WorldSurprise: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String

    public init(id: String, title: String, detail: String, symbol: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

public enum WorldSurpriseResolver {
    public static func resolve(
        environment: WorldEnvironment,
        curios: [CurioItem],
        memories: [MemoryChapter],
        languageMoment: LanguageMoment?
    ) -> WorldSurprise? {
        if case .tripAway(let destination) = environment,
           curios.contains(where: { $0.kind == .travel }) {
            return WorldSurprise(
                id: "surprise.travel.curio",
                title: "A tiny traveling companion",
                detail: destination.map { "One of Sunnie's travel keepsakes is along for \($0)." }
                    ?? "One of Sunnie's travel keepsakes is along for the trip.",
                symbol: "airplane.circle"
            )
        }

        if case .tripReturning = environment, let memory = memories.first {
            return WorldSurprise(
                id: "surprise.return.memory",
                title: "A new chapter is taking shape",
                detail: "\(memory.title) is now part of Sunnie's memory world.",
                symbol: "book.closed.fill"
            )
        }

        if languageMoment != nil, curios.count >= 3 {
            return WorldSurprise(
                id: "surprise.language.cabinet",
                title: "The cabinet learned a phrase",
                detail: "A travel phrase has found its way into Sunnie's world.",
                symbol: "character.bubble.fill"
            )
        }

        return nil
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
