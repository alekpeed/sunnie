import Foundation

/// One authored thing Sunnie can say.
///
/// The text is a whole sentence with an optional `{name}` placeholder — never a
/// fragment to be assembled at runtime, because fragment assembly does not
/// survive translation (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §8).
public struct SunnieMessageDefinition: Hashable, Sendable, Codable, Identifiable {
    public let id: ContentID
    public let category: SunnieMessageCategory
    /// English source text. Localized builds resolve `localizationKey` instead.
    public let template: String
    public let localizationKey: String
    public let expression: SunnieExpression
    public let pose: SunniePose
    /// Phases this message suits. Empty means any phase.
    public let phases: [TimePhase]

    public init(
        id: ContentID,
        category: SunnieMessageCategory,
        template: String,
        localizationKey: String,
        expression: SunnieExpression,
        pose: SunniePose,
        phases: [TimePhase] = []
    ) {
        self.id = id
        self.category = category
        self.template = template
        self.localizationKey = localizationKey
        self.expression = expression
        self.pose = pose
        self.phases = phases
    }

    public func matches(phase: TimePhase) -> Bool {
        phases.isEmpty || phases.contains(phase)
    }

    public var usesNamePlaceholder: Bool {
        template.contains("{name}")
    }
}
