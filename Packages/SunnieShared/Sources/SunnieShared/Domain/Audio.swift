import Foundation

/// The vocabulary the audio system is described in
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §4, §5, §6, §7).
///
/// Everything here is platform-neutral on purpose. The decisions that are easy
/// to get wrong — which layer a sound belongs to, which session category it
/// needs, what to do when a phone call arrives — are values and functions in
/// this package, so they can be exercised without a device, a speaker, or an
/// audio session. The app target's job is reduced to translating between these
/// values and AVFAudio.
///
/// Vanessa never sees any of this. She sees toggles and a volume slider (§9).
/// The manifest, the contexts, and the source types are creator-side machinery.

// MARK: - Layers

/// The five layers, each with its own gain and enable state (§4).
///
/// Separate from `CalmSoundCategory`, which describes what a sound *is* to the
/// person choosing it. A layer describes what a sound is to the mixer: two
/// things that both count as music should not play at once, where music and
/// ambience happily can.
public enum AudioLayer: String, Hashable, Sendable, Codable, CaseIterable {
    case music
    case ambience
    case effects
    case meditationBell
    /// Reserved. Nothing ships on this layer yet, and the setting for it stays
    /// off until something does (§4, "Future narration/voice").
    case narration

    public var localizationKey: String { "audio.layer.\(rawValue)" }

    /// Whether this layer has any content today.
    ///
    /// The narration control exists in the model so the manifest and the mixer
    /// need no change when voice arrives, but a toggle for a layer with nothing
    /// on it would be a promise the app cannot keep, so the settings screen
    /// filters on this.
    public var isAvailable: Bool { self != .narration }

    /// Whether a second track on this layer may start while one is playing.
    ///
    /// Ambience and effects overlap by design — rain under a bell is the point.
    /// Two pieces of music at once is always a mistake.
    public var allowsSimultaneousTracks: Bool {
        switch self {
        case .music, .narration: false
        case .ambience, .effects, .meditationBell: true
        }
    }
}

// MARK: - Contexts

/// A semantic tag a track is registered against (§5, §8).
///
/// A string namespace rather than a closed enum, because the manifest example in
/// the specification uses free strings (`"theme.jungle"`, `"time.day"`) and
/// because destinations are content: a new destination must be taggable without
/// editing this file. The constants below cover §5's list; the validator warns
/// about tags that match nothing, which is what stops a typo from silently
/// meaning "never plays".
public struct AudioContextTag: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension AudioContextTag: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension AudioContextTag: CustomStringConvertible {
    public var description: String { rawValue }
}

extension AudioContextTag {
    // The three branded day cycles. These are the only three, and they are named
    // for the phase rather than the label so a rename of the presentation never
    // silently orphans a track (CLAUDE.md, day-cycle labels).
    public static let day: AudioContextTag = "time.day"
    public static let afternoon: AudioContextTag = "time.afternoon"
    public static let night: AudioContextTag = "time.night"

    public static let jungle: AudioContextTag = "theme.jungle"
    public static let travelScrapbook: AudioContextTag = "screen.travelScrapbook"
    public static let today: AudioContextTag = "screen.today"
    public static let plantCare: AudioContextTag = "screen.plantCare"
    public static let wellness: AudioContextTag = "screen.wellness"
    public static let sunnieHome: AudioContextTag = "screen.sunnieHome"
    public static let meditation: AudioContextTag = "practice.meditation"
    public static let breathing: AudioContextTag = "practice.breathing"
    public static let game: AudioContextTag = "screen.game"
    public static let reward: AudioContextTag = "moment.reward"

    /// A specific place. `destination.jp` rather than a shared `destination`
    /// tag, so a track written for one country never plays for another.
    public static func destination(_ code: String) -> AudioContextTag {
        AudioContextTag("destination.\(code.lowercased())")
    }

    /// The day-cycle tag for a branded presentation, so callers never spell one
    /// by hand.
    ///
    /// Keyed on the presentation rather than the underlying `TimePhase` because
    /// there are six phases and only three things the app is ever allowed to
    /// call them. Tagging per phase would invite a track that plays only in the
    /// evening, which is a cycle the product does not have.
    public static func cycle(_ presentation: DayCyclePresentation) -> AudioContextTag {
        switch presentation {
        case .sunnieDays: .day
        case .sunnieAfternoonies: .afternoon
        case .sunnieNights: .night
        }
    }

    public static func phase(_ phase: TimePhase) -> AudioContextTag {
        cycle(phase.brandedPresentation)
    }
}

// MARK: - Source

/// Where a track's sound comes from (§3).
public enum AudioSourceType: String, Hashable, Sendable, Codable {
    /// A rendered file in the bundle — the preferred form (§3, "Preferred").
    /// Exact instrumentation, predictable across devices, cheap to play.
    case renderedAudio
    /// Computed sample by sample, like the noise colours already are. Needs no
    /// asset, so it works on a fresh clone and cannot ship out of sync with the
    /// manifest (ADR-029).
    case procedural
    /// Reserved for adaptive arrangement (§3, "Optional"). Nothing ships on this
    /// path, and the validator rejects a track that claims it without an
    /// approval record, so it cannot arrive by accident.
    case runtimeMIDI
}

/// Licensing metadata, validated before a track ships (§2 step 7).
///
/// One case today. It exists as an enum rather than a free string so a licensed
/// third-party track cannot be added without someone writing down which licence
/// it arrived under.
public enum AudioLicence: String, Hashable, Sendable, Codable {
    /// Written by the creator for this app. Nothing else is currently permitted.
    case createdForThisApp
}

// MARK: - Routes and interruptions

/// Where the sound is coming out (§6, §12).
public enum AudioRoute: String, Hashable, Sendable, Codable, CaseIterable {
    case builtInSpeaker
    case headphones
    case bluetooth
    case carPlay
    case airPlay
    case other

    /// Whether the sound is reaching only this person.
    ///
    /// Used for one decision and one only: when a private route disappears, the
    /// sound stops rather than moving to the speaker. Rain suddenly playing out
    /// loud in a quiet room is the failure this prevents.
    public var isPrivate: Bool {
        switch self {
        case .headphones, .bluetooth: true
        case .builtInSpeaker, .carPlay, .airPlay, .other: false
        }
    }
}

public enum AudioRouteChangeReason: String, Hashable, Sendable, Codable {
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case other
}

/// Everything that can happen to playback from outside the app (§6, §12).
public enum AudioEvent: Hashable, Sendable {
    case interruptionBegan
    /// `shouldResume` is the system's own hint. Resuming without it is how an
    /// app ends up talking over a phone call that has not finished.
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: AudioRouteChangeReason, newRoute: AudioRoute)
    case enteredBackground
    case enteredForeground
    case otherAudioStarted
    case otherAudioStopped
    /// The media daemon restarted. Every engine and player is invalid.
    case mediaServicesReset
}

/// What the audio layer should do about it.
public enum AudioAction: Hashable, Sendable {
    case none
    case pause
    case resume
    case stop
    /// Tear the engine down and build it again from scratch.
    case restart
    case duck
    case unduck
}

// MARK: - Use cases

/// What the sound is *for*, which is what decides its session policy (§7).
///
/// Not the same as its layer. A meditation bell and a reward chime are both
/// short effects, but only one of them has to be audible with the phone locked
/// and the ring switch on.
public enum AudioUseCase: String, Hashable, Sendable, CaseIterable {
    /// A short sound tied to something the user just did.
    case cue
    /// A looping bed under a screen.
    case ambience
    /// The creator's music.
    case music
    /// Generated white/pink/brown noise, which has its own policy (ADR-018).
    case generatedNoise
    /// A practice with a timer, which must survive the screen locking.
    case meditation
    /// Recording a voice note, which needs the input.
    case voiceNote
}
