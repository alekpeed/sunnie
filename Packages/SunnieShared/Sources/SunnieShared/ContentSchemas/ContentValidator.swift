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
        case medicalOrOutcomeClaim(contentID: String, phrase: String)
        case malformedBreathingPattern(contentID: String)
        case emptyCategory(String)

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
            case .medicalOrOutcomeClaim(let contentID, let phrase):
                "\(contentID) makes a medical or outcome claim: \"\(phrase)\""
            case .malformedBreathingPattern(let contentID):
                "Breathing pattern \(contentID) has a zero or negative phase, so it would never advance"
            case .emptyCategory(let description):
                "No content exists for: \(description)"
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

    /// Claims the app must never make.
    ///
    /// Two families, both from WELLNESS_JOURNAL_AND_CALM.md: medical or
    /// diagnostic statements about the user (§10, §12), and promises about what a
    /// practice will achieve (§4). The phrases are deliberately assertive
    /// constructions rather than bare words, so ordinary copy that mentions
    /// health or treatment honestly — "this isn't medical advice", "pest
    /// treatment" — passes cleanly.
    public static let prohibitedClaims: [String] = [
        "proves you",
        "you are depressed",
        "you are anxious",
        "you have anxiety",
        "you must be feeling",
        "is a symptom of",
        "diagnoses your",
        "medically proven",
        "clinically proven",
        "will cure",
        "cures your",
        "guaranteed to",
        "this will fix",
        "will make you happy",
        "will make you calm"
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

    /// Validates the wellness content pack.
    public static func validate(_ pack: WellnessPack) -> [ContentIssue] {
        var issues: [ContentIssue] = []

        if pack.manifest.schemaVersion != ContentPackManifest.supportedSchemaVersion {
            issues.append(.init(kind: .unsupportedSchemaVersion(
                pack: pack.manifest.packID.rawValue,
                found: pack.manifest.schemaVersion
            )))
        }

        var seen = Set<String>()
        func checkID(_ id: ContentID) {
            if !id.isWellFormed {
                issues.append(.init(kind: .malformedID(id.rawValue)))
            }
            if !seen.insert(id.rawValue).inserted {
                issues.append(.init(kind: .duplicateID(id.rawValue)))
            }
        }

        for affirmation in pack.affirmations {
            checkID(affirmation.id)
            if affirmation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(kind: .emptyTemplate(affirmation.id.rawValue)))
            }
            if affirmation.localizationKey.isEmpty {
                issues.append(.init(kind: .missingLocalizationKey(affirmation.id.rawValue)))
            }
            issues.append(contentsOf: toneIssues(
                in: affirmation.text, contentID: affirmation.id.rawValue
            ))
            issues.append(contentsOf: claimIssues(
                in: affirmation.text, contentID: affirmation.id.rawValue
            ))
        }

        for pattern in pack.breathingPatterns {
            checkID(pattern.id)
            if !pattern.isWellFormed {
                issues.append(.init(kind: .malformedBreathingPattern(contentID: pattern.id.rawValue)))
            }
        }

        for meditation in pack.meditations {
            checkID(meditation.id)
            if meditation.defaultDuration <= 0 {
                issues.append(.init(kind: .malformedID(meditation.id.rawValue)))
            }
        }

        for sound in pack.calmSounds {
            checkID(sound.id)
        }

        // A harder moment filters the library down; if nothing survives, the
        // affirmation card would be blank exactly when it matters most.
        if !pack.affirmations.contains(where: \.suitsSensitiveMoments) {
            issues.append(.init(kind: .emptyCategory("affirmations suitable for a harder moment")))
        }
        if pack.breathingPatterns.allSatisfy(\.isAdvanced) {
            issues.append(.init(kind: .emptyCategory("breathing patterns suitable as a default suggestion")))
        }

        return issues
    }

    /// Checks a string for medical, diagnostic, or outcome-promising claims.
    ///
    /// Separate from `toneIssues` because the two rules protect different things:
    /// tone protects the user from being blamed, claims protect them from being
    /// told something untrue about their own health.
    public static func claimIssues(in text: String, contentID: String) -> [ContentIssue] {
        let lowered = text.lowercased()
        return prohibitedClaims
            .filter { lowered.contains($0) }
            .map { ContentIssue(kind: .medicalOrOutcomeClaim(contentID: contentID, phrase: $0)) }
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
