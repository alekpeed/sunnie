import Foundation

/// Tags used to choose an affirmation for the moment
/// (WELLNESS_JOURNAL_AND_CALM.md §4).
///
/// Note what these are *not*: they describe the situation, never the person.
/// There is no `anxious` or `struggling` tag, because the app does not label
/// anyone's state — it only knows what they chose to record.
public enum AffirmationTag: String, Hashable, Sendable, Codable, CaseIterable {
    case morning
    case evening
    case rest
    case travel
    case home
    case plants
    case gentle
    case encouragement
    case selfCompassion
}

/// One affirmation.
///
/// Affirmations promise nothing. No outcome, no medical claim, and no spiritual
/// assumption — a line that says "this will fix your day" would be both untrue
/// and unkind on the day it does not.
public struct AffirmationDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let text: String
    public let localizationKey: String
    public let tags: [AffirmationTag]
    /// Phases this line suits. Empty means any.
    public let phases: [TimePhase]
    /// Suitable when the user has recorded a harder moment. Lines that are bright
    /// or congratulatory should set this false.
    public let suitsSensitiveMoments: Bool

    public init(
        id: ContentID,
        text: String,
        localizationKey: String,
        tags: [AffirmationTag] = [],
        phases: [TimePhase] = [],
        suitsSensitiveMoments: Bool = true
    ) {
        self.id = id
        self.text = text
        self.localizationKey = localizationKey
        self.tags = tags
        self.phases = phases
        self.suitsSensitiveMoments = suitsSensitiveMoments
    }

    public func matches(phase: TimePhase) -> Bool {
        phases.isEmpty || phases.contains(phase)
    }
}

/// One breathing practice, described as a repeating cycle.
///
/// Durations are data so a custom practice needs no new code. Box breathing is
/// included but flagged, because it is markedly harder than equal breathing and
/// should be presented as clearly optional (WELLNESS_JOURNAL_AND_CALM.md §7).
public struct BreathingPattern: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let displayNameKey: String
    public let descriptionKey: String
    public let inhaleSeconds: Double
    public let holdAfterInhaleSeconds: Double
    public let exhaleSeconds: Double
    public let holdAfterExhaleSeconds: Double
    public let defaultCycles: Int
    /// Present this as an advanced option rather than a default suggestion.
    public let isAdvanced: Bool

    public init(
        id: ContentID,
        displayNameKey: String,
        descriptionKey: String,
        inhaleSeconds: Double,
        holdAfterInhaleSeconds: Double,
        exhaleSeconds: Double,
        holdAfterExhaleSeconds: Double,
        defaultCycles: Int,
        isAdvanced: Bool = false
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.descriptionKey = descriptionKey
        self.inhaleSeconds = inhaleSeconds
        self.holdAfterInhaleSeconds = holdAfterInhaleSeconds
        self.exhaleSeconds = exhaleSeconds
        self.holdAfterExhaleSeconds = holdAfterExhaleSeconds
        self.defaultCycles = defaultCycles
        self.isAdvanced = isAdvanced
    }

    public var cycleDuration: TimeInterval {
        inhaleSeconds + holdAfterInhaleSeconds + exhaleSeconds + holdAfterExhaleSeconds
    }

    public func totalDuration(cycles: Int) -> TimeInterval {
        cycleDuration * Double(max(0, cycles))
    }

    /// A pattern with a zero-length cycle would loop forever without advancing.
    public var isWellFormed: Bool {
        cycleDuration > 0
            && inhaleSeconds > 0
            && exhaleSeconds > 0
            && defaultCycles > 0
            && holdAfterInhaleSeconds >= 0
            && holdAfterExhaleSeconds >= 0
    }
}

/// A meditation the app can run. Voice recordings are deferred, so the initial
/// set is timed silence, text guidance, and ambience.
public struct MeditationDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let displayNameKey: String
    public let type: WellnessSessionType
    public let defaultDuration: TimeInterval
    public let availableDurations: [TimeInterval]
    /// Localization keys for on-screen guidance, shown in order across the session.
    public let guidanceKeys: [String]
    public let startCueID: ContentID?
    public let endCueID: ContentID?
    public let ambienceCueID: ContentID?

    public init(
        id: ContentID,
        displayNameKey: String,
        type: WellnessSessionType,
        defaultDuration: TimeInterval,
        availableDurations: [TimeInterval],
        guidanceKeys: [String] = [],
        startCueID: ContentID? = nil,
        endCueID: ContentID? = nil,
        ambienceCueID: ContentID? = nil
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.type = type
        self.defaultDuration = defaultDuration
        self.availableDurations = availableDurations
        self.guidanceKeys = guidanceKeys
        self.startCueID = startCueID
        self.endCueID = endCueID
        self.ambienceCueID = ambienceCueID
    }
}

public enum CalmSoundCategory: String, Hashable, Sendable, Codable, CaseIterable {
    /// White, pink, and brown noise, computed sample by sample
    /// (NOISE_IMPLEMENTATION.md). First in the list because it is the plainest
    /// thing here, not because it is the only one that works: since Phase 10
    /// every category below is synthesised too (ADR-029).
    case noise
    case rain
    case jungle
    case ocean
    case cafe
    case night
    case roomTone
    case creatorMusic

    /// Whether this category is played by the *noise* engine specifically.
    ///
    /// Not "is it synthesised" — since Phase 10 almost everything here is
    /// (ADR-029). This is the routing question: noise has its own engine and its
    /// own audio-session policy (ADR-018), so the sound library needs to know
    /// which of the two players a selection belongs to.
    public var isGenerated: Bool { self == .noise }
}

/// A loopable ambience track.
///
/// The `audioCueID` resolves through the audio manifest, which decides whether
/// it is synthesised or played from a rendered file. That indirection is why
/// these definitions did not change when Phase 10 gave them sound.
public struct CalmSoundDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let displayNameKey: String
    public let category: CalmSoundCategory
    public let audioCueID: ContentID
    /// Music and ambience can play together; two tracks that both count as music
    /// should not.
    public let isMixable: Bool

    public init(
        id: ContentID,
        displayNameKey: String,
        category: CalmSoundCategory,
        audioCueID: ContentID,
        isMixable: Bool = true
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.category = category
        self.audioCueID = audioCueID
        self.isMixable = isMixable
    }
}

/// The Phase 3 content pack.
public struct WellnessPack: Hashable, Sendable, Codable {
    public let manifest: ContentPackManifest
    public let affirmations: [AffirmationDefinition]
    public let breathingPatterns: [BreathingPattern]
    public let meditations: [MeditationDefinition]
    public let calmSounds: [CalmSoundDefinition]

    public init(
        manifest: ContentPackManifest,
        affirmations: [AffirmationDefinition],
        breathingPatterns: [BreathingPattern],
        meditations: [MeditationDefinition],
        calmSounds: [CalmSoundDefinition]
    ) {
        self.manifest = manifest
        self.affirmations = affirmations
        self.breathingPatterns = breathingPatterns
        self.meditations = meditations
        self.calmSounds = calmSounds
    }
}
