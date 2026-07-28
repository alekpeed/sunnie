import Foundation

/// Chooses an affirmation.
///
/// Selection narrows the same way message selection does — most specific first,
/// then broader — with two extra filters the wellness spec requires: hidden lines
/// never return, and a harder moment excludes anything bright or congratulatory
/// (WELLNESS_JOURNAL_AND_CALM.md §4).
public struct AffirmationService: Sendable {

    private let pack: WellnessPack
    private let random: any RandomSource

    public init(pack: WellnessPack, random: any RandomSource = SystemRandomSource()) {
        self.pack = pack
        self.random = random
    }

    /// What the user has said about the affirmation library.
    public struct Preferences: Hashable, Sendable, Codable {
        public var favoriteIDs: Set<ContentID>
        /// Lines the user asked not to see again. Honoured absolutely.
        public var hiddenIDs: Set<ContentID>

        public static let none = Preferences(favoriteIDs: [], hiddenIDs: [])

        public init(favoriteIDs: Set<ContentID>, hiddenIDs: Set<ContentID>) {
            self.favoriteIDs = favoriteIDs
            self.hiddenIDs = hiddenIDs
        }
    }

    public struct Request: Hashable, Sendable {
        public let phase: TimePhase
        public let tags: [AffirmationTag]
        public let isSensitiveMoment: Bool
        public let recentlyShownIDs: [ContentID]
        public let preferences: Preferences

        public init(
            phase: TimePhase,
            tags: [AffirmationTag] = [],
            isSensitiveMoment: Bool = false,
            recentlyShownIDs: [ContentID] = [],
            preferences: Preferences = .none
        ) {
            self.phase = phase
            self.tags = tags
            self.isSensitiveMoment = isSensitiveMoment
            self.recentlyShownIDs = recentlyShownIDs
            self.preferences = preferences
        }
    }

    /// Returns nil only when every line is hidden — in which case showing nothing
    /// is correct, because the user asked for exactly that.
    public func affirmation(for request: Request) -> AffirmationDefinition? {
        let candidates = candidates(for: request)
        guard !candidates.isEmpty else { return nil }
        return candidates[random.nextIndex(upperBound: candidates.count)]
    }

    func candidates(for request: Request) -> [AffirmationDefinition] {
        // Hidden lines are removed first and never come back, whatever else runs
        // out. This filter is the only one with no fallback.
        let permitted = pack.affirmations.filter {
            !request.preferences.hiddenIDs.contains($0.id)
        }
        guard !permitted.isEmpty else { return [] }

        // A harder moment rules out anything bright, also without fallback: a
        // congratulatory line is worse than a plain one here.
        let suitable = request.isSensitiveMoment
            ? permitted.filter(\.suitsSensitiveMoments)
            : permitted
        guard !suitable.isEmpty else { return [] }

        let recent = Set(request.recentlyShownIDs)
        let requestedTags = Set(request.tags)

        // Most specific: matches a requested tag and this phase, not shown lately.
        if !requestedTags.isEmpty {
            let tagged = suitable.filter {
                !Set($0.tags).isDisjoint(with: requestedTags) && $0.matches(phase: request.phase)
            }
            let fresh = tagged.filter { !recent.contains($0.id) }
            if !fresh.isEmpty { return fresh }
            if !tagged.isEmpty { return tagged }
        }

        // Then anything suited to the phase.
        let phaseMatched = suitable.filter { $0.matches(phase: request.phase) }
        let freshPhase = phaseMatched.filter { !recent.contains($0.id) }
        if !freshPhase.isEmpty { return freshPhase }

        // Then anything at all that has not just been shown.
        let fresh = suitable.filter { !recent.contains($0.id) }
        if !fresh.isEmpty { return fresh }

        // Everything has been seen recently. Repeating beats going quiet.
        return suitable
    }

    public func breathingPattern(id: ContentID) -> BreathingPattern? {
        pack.breathingPatterns.first { $0.id == id }
    }

    /// Patterns suitable as a default suggestion — the advanced ones are offered
    /// only when the user goes looking.
    public var suggestedBreathingPatterns: [BreathingPattern] {
        pack.breathingPatterns.filter { !$0.isAdvanced }
    }

    public func meditation(id: ContentID) -> MeditationDefinition? {
        pack.meditations.first { $0.id == id }
    }

    public func calmSounds(in category: CalmSoundCategory) -> [CalmSoundDefinition] {
        pack.calmSounds.filter { $0.category == category }
    }
}
