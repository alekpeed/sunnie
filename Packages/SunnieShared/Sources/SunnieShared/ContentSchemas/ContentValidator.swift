import Foundation

/// A problem found in shipped content.
public struct ContentIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        case malformedID(String)
        case duplicateID(String)
        case emptyTemplate(String)
        case missingLocalizationKey(String)
        case malformedColor(themeID: String, hex: String)
        case unsupportedSchemaVersion(pack: String, found: Int)
        case noMessagesForCategory(SunnieMessageCategory)
        case prohibitedPhrase(contentID: String, phrase: String)
        case prohibitedDayCycleName(contentID: String, name: String)
        case nicknamePlaceholderInIneligibleCategory(contentID: String)

        public var summary: String {
            switch self {
            case .malformedID(let id):
                "Content ID is not a dot-delimited alphanumeric string: \(id)"
            case .duplicateID(let id):
                "Duplicate content ID: \(id)"
            case .emptyTemplate(let id):
                "Message has empty text: \(id)"
            case .missingLocalizationKey(let id):
                "Message has no localization key: \(id)"
            case .malformedColor(let themeID, let hex):
                "Theme \(themeID) has an unreadable colour: \(hex)"
            case .unsupportedSchemaVersion(let pack, let found):
                "Pack \(pack) uses schema version \(found); this build reads \(ContentPackManifest.supportedSchemaVersion)"
            case .noMessagesForCategory(let category):
                "No messages exist for category: \(category.rawValue)"
            case .prohibitedPhrase(let contentID, let phrase):
                "\(contentID) contains prohibited language: \"\(phrase)\""
            case .prohibitedDayCycleName(let contentID, let name):
                "\(contentID) uses a forbidden day-cycle name: \"\(name)\""
            case .nicknamePlaceholderInIneligibleCategory(let contentID):
                "\(contentID) is in a category that may never use the nickname, but contains {name}"
            }
        }
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public var description: String { kind.summary }
}

/// Validates shipped content at test and build time
/// (TECHNICAL_ARCHITECTURE.md §11).
///
/// Beyond structural checks, this enforces the tone rules mechanically. Every
/// prohibited pattern in TONE_COPY_AND_BEHAVIOR.md is checked here, so shaming
/// or guilt-based copy cannot reach the app by being overlooked in review — the
/// content tests fail first.
public enum ContentValidator {

    /// Phrases that must never appear in user-facing content, matched
    /// case-insensitively as substrings.
    public static let prohibitedPhrases: [String] = [
        "you failed",
        "you broke your streak",
        "broke your streak",
        "sunnie is disappointed",
        "i'm disappointed",
        "im disappointed",
        "you ignored",
        "no excuses",
        "you must do this now",
        "you should have",
        "why didn't you",
        "dying because you",
        "don't lose your"
    ]

    /// Negative labels, matched as whole words so "badge" and "baddest" do not
    /// trip "bad".
    public static let prohibitedLabels: [String] = [
        "lazy", "careless", "irresponsible", "unhealthy", "sloppy", "pathetic"
    ]

    /// Day-cycle names that do not exist and must never be introduced (ADR-008).
    public static let prohibitedDayCycleNames: [String] = [
        "sunnie mornings", "sunnie evenings"
    ]

    public static func validate(_ pack: SunnieMessagePack) -> [ContentIssue] {
        var issues: [ContentIssue] = []

        if pack.manifest.schemaVersion != ContentPackManifest.supportedSchemaVersion {
            issues.append(.init(kind: .unsupportedSchemaVersion(
                pack: pack.manifest.packID.rawValue,
                found: pack.manifest.schemaVersion
            )))
        }

        var seen = Set<String>()
        for message in pack.messages {
            let id = message.id.rawValue

            if !message.id.isWellFormed {
                issues.append(.init(kind: .malformedID(id)))
            }
            if !seen.insert(id).inserted {
                issues.append(.init(kind: .duplicateID(id)))
            }
            if message.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(kind: .emptyTemplate(id)))
            }
            if message.localizationKey.isEmpty {
                issues.append(.init(kind: .missingLocalizationKey(id)))
            }
            // A nickname placeholder in a permission prompt or error would put
            // "Noonies" somewhere it must never appear.
            if message.usesNamePlaceholder, !message.category.isNicknameEligible {
                issues.append(.init(
                    kind: .nicknamePlaceholderInIneligibleCategory(contentID: id)
                ))
            }
            issues.append(contentsOf: toneIssues(in: message.template, contentID: id))
        }

        // Every category the app can ask for must have something to say. A
        // missing category is a blank screen at runtime.
        for category in SunnieMessageCategory.allCases
        where !pack.messages.contains(where: { $0.category == category }) {
            issues.append(.init(kind: .noMessagesForCategory(category)))
        }

        return issues
    }

    public static func validate(_ pack: ThemePack) -> [ContentIssue] {
        var issues: [ContentIssue] = []

        if pack.manifest.schemaVersion != ContentPackManifest.supportedSchemaVersion {
            issues.append(.init(kind: .unsupportedSchemaVersion(
                pack: pack.manifest.packID.rawValue,
                found: pack.manifest.schemaVersion
            )))
        }

        var seen = Set<String>()
        for theme in pack.themes {
            let id = theme.id.rawValue

            if !theme.id.isWellFormed {
                issues.append(.init(kind: .malformedID(id)))
            }
            if !seen.insert(id).inserted {
                issues.append(.init(kind: .duplicateID(id)))
            }

            var colors = theme.basePalette.allValues
            colors.append(contentsOf: theme.highContrastPalette?.allValues ?? [])
            for variant in theme.phaseVariants {
                colors.append(contentsOf: [
                    variant.canvas, variant.surface,
                    variant.textPrimary, variant.textSecondary
                ].compactMap { $0 })
            }
            for color in colors where !color.isWellFormed {
                issues.append(.init(kind: .malformedColor(themeID: id, hex: color.hex)))
            }
        }

        return issues
    }

    /// Runs the tone rules over an arbitrary user-facing string.
    ///
    /// Exposed so feature tests can check copy that does not live in a content
    /// pack, such as localized UI strings.
    public static func toneIssues(in text: String, contentID: String) -> [ContentIssue] {
        var issues: [ContentIssue] = []
        let lowered = text.lowercased()

        for phrase in prohibitedPhrases where lowered.contains(phrase) {
            issues.append(.init(kind: .prohibitedPhrase(contentID: contentID, phrase: phrase)))
        }
        for name in prohibitedDayCycleNames where lowered.contains(name) {
            issues.append(.init(kind: .prohibitedDayCycleName(contentID: contentID, name: name)))
        }

        let words = Set(
            lowered
                .split(whereSeparator: { !$0.isLetter && $0 != "'" })
                .map(String.init)
        )
        for label in prohibitedLabels where words.contains(label) {
            issues.append(.init(kind: .prohibitedPhrase(contentID: contentID, phrase: label)))
        }

        return issues
    }
}
