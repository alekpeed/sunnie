import Foundation

/// Header for a versioned bundle of non-user content
/// (CONTENT_PACK_AND_EXPANSION_ARCHITECTURE.md, TECHNICAL_ARCHITECTURE.md §11).
///
/// Everything Sunnie says, every theme, reward, and audio cue ships as content
/// rather than code, so new material can be added without touching feature
/// logic. Packs are validated at test time; a malformed pack fails the build
/// rather than degrading the app at runtime.
public struct ContentPackManifest: Hashable, Sendable, Codable {
    public let packID: ContentID
    public let version: Int
    public let schemaVersion: Int
    public let displayNameKey: String
    public let minimumAppVersion: String

    public init(
        packID: ContentID,
        version: Int,
        schemaVersion: Int,
        displayNameKey: String,
        minimumAppVersion: String
    ) {
        self.packID = packID
        self.version = version
        self.schemaVersion = schemaVersion
        self.displayNameKey = displayNameKey
        self.minimumAppVersion = minimumAppVersion
    }

    /// The schema version this build knows how to read.
    public static let supportedSchemaVersion = 1
}

/// Installation state for an optional pack.
public struct ContentPackState: Hashable, Sendable, Codable {
    public let packID: ContentID
    public var installedVersion: Int
    public var installedAt: Date
    public var isEnabled: Bool
    public var validationState: ValidationState

    public enum ValidationState: String, Hashable, Sendable, Codable {
        case valid
        case invalid
        case notValidated
    }

    public init(
        packID: ContentID,
        installedVersion: Int,
        installedAt: Date,
        isEnabled: Bool,
        validationState: ValidationState
    ) {
        self.packID = packID
        self.installedVersion = installedVersion
        self.installedAt = installedAt
        self.isEnabled = isEnabled
        self.validationState = validationState
    }
}

/// A decoded message pack.
public struct SunnieMessagePack: Hashable, Sendable, Codable {
    public let manifest: ContentPackManifest
    public let messages: [SunnieMessageDefinition]

    public init(manifest: ContentPackManifest, messages: [SunnieMessageDefinition]) {
        self.manifest = manifest
        self.messages = messages
    }
}

/// A decoded theme pack.
public struct ThemePack: Hashable, Sendable, Codable {
    public let manifest: ContentPackManifest
    public let themes: [ThemeDefinition]

    public init(manifest: ContentPackManifest, themes: [ThemeDefinition]) {
        self.manifest = manifest
        self.themes = themes
    }
}
