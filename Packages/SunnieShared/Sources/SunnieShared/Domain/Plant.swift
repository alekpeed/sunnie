import Foundation

/// Where a plant lives. Kept separate from `Plant` so a room rename does not
/// rewrite every plant record.
public struct PlantLocation: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var room: String?
    public var lightNotes: String?
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        room: String? = nil,
        lightNotes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.lightNotes = lightNotes
        self.sortOrder = sortOrder
    }
}

public enum LightProfile: String, Hashable, Sendable, Codable, CaseIterable {
    case lowLight
    case indirectBright
    case directSun
    case dappled
    case unknown
}

public enum CareDifficulty: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case moderate
    case demanding
}

public enum PlantStatus: String, Hashable, Sendable, Codable, CaseIterable {
    case active
    case inactive
    case archived
}

/// A single plant in the jungle. A value type — the SwiftData `@Model` class
/// lives in the app target and maps to and from this (DATA_MODEL.md §1).
public struct Plant: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var nickname: String?
    public var speciesName: String?
    public var variety: String?
    public var locationID: UUID?
    public var lightProfile: LightProfile
    public var difficulty: CareDifficulty
    public var acquiredDate: Date?
    public var source: String?
    public var pot: String?
    public var soil: String?
    public var notes: String?
    public var status: PlantStatus
    /// Opaque token embedded in the plant's printed QR code. Resolves to the
    /// plant ID only — never carries notes or other private content
    /// (PLANT_CARE.md §11).
    public var qrToken: String
    public var primaryPhotoID: UUID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        nickname: String? = nil,
        speciesName: String? = nil,
        variety: String? = nil,
        locationID: UUID? = nil,
        lightProfile: LightProfile = .unknown,
        difficulty: CareDifficulty = .moderate,
        acquiredDate: Date? = nil,
        source: String? = nil,
        pot: String? = nil,
        soil: String? = nil,
        notes: String? = nil,
        status: PlantStatus = .active,
        qrToken: String,
        primaryPhotoID: UUID? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.speciesName = speciesName
        self.variety = variety
        self.locationID = locationID
        self.lightProfile = lightProfile
        self.difficulty = difficulty
        self.acquiredDate = acquiredDate
        self.source = source
        self.pot = pot
        self.soil = soil
        self.notes = notes
        self.status = status
        self.qrToken = qrToken
        self.primaryPhotoID = primaryPhotoID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// The name shown in lists and on cards.
    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return name
    }
}
