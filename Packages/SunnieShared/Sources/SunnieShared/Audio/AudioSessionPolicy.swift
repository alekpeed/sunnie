import Foundation

/// One place that decides what audio session the app needs
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §7, "Centralize category changes in one
/// service rather than feature code").
///
/// Expressed as plain values rather than AVFAudio types so the table is a thing
/// that can be asserted on. The session category is the setting most likely to be
/// changed by whichever feature touched the audio last, and the most likely to be
/// wrong in a way nobody notices until someone is on a plane with headphones in
/// — so the decision lives here, and the app target does nothing but translate.

/// The categories this app uses. Deliberately three, not all of AVFAudio's.
public enum AudioSessionCategory: String, Hashable, Sendable {
    /// Respects the ring/silent switch, stops at the lock screen, never
    /// interrupts anything. The right default for decoration.
    case ambient
    /// Keeps playing with the screen off and the ring switch on. Needed by
    /// anything with a timer or a sleep purpose.
    case playback
    /// Needs the microphone.
    case playAndRecord
}

public struct AudioSessionOptions: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Plays underneath the user's own music rather than silencing it.
    public static let mixWithOthers = AudioSessionOptions(rawValue: 1 << 0)
    /// Quietens the user's own audio while ours plays. Used only while
    /// recording — see the note on `plan(for:backgroundPlaybackEnabled:)`.
    public static let duckOthers = AudioSessionOptions(rawValue: 1 << 1)
}

/// The two modes this app has a use for. Spoken audio tunes the signal chain
/// for speech, which matters for a voice note and for nothing else here.
public enum AudioSessionMode: String, Hashable, Sendable {
    case `default`
    case spokenAudio
}

public struct AudioSessionPlan: Hashable, Sendable {
    public let category: AudioSessionCategory
    public let mode: AudioSessionMode
    public let options: AudioSessionOptions
    /// Whether this configuration keeps sounding once the app leaves the screen.
    /// Requires `UIBackgroundModes = audio`, which the app declares (ADR-018).
    public let continuesInBackground: Bool

    public init(
        category: AudioSessionCategory,
        mode: AudioSessionMode = .default,
        options: AudioSessionOptions,
        continuesInBackground: Bool
    ) {
        self.category = category
        self.mode = mode
        self.options = options
        self.continuesInBackground = continuesInBackground
    }
}

public enum AudioSessionPolicy {

    /// The whole table, in one function.
    ///
    /// - `cue`, `ambience`, `music` are decoration: `.ambient`, so they respect
    ///   the ring switch, stop at the lock screen, and never take over from a
    ///   podcast. Someone who silenced their phone silenced Sunnie too.
    /// - `generatedNoise` is the documented exception (ADR-018): `.playback`
    ///   with `.mixWithOthers`, because a sleep sound that stops when the screen
    ///   locks is not a sleep sound. It still mixes, so it never silences the
    ///   user's own audio.
    /// - `meditation` follows noise *only when the user asked for background
    ///   playback*. A practice with a timer should survive the screen locking, but
    ///   turning that on for someone who did not ask means the ring switch stops
    ///   working, which is a surprise nobody wants from a calm feature.
    /// - `voiceNote` needs the input, so `.playAndRecord`.
    ///
    /// `.duckOthers` appears on exactly one line, and it is the recording one.
    /// Quietening the user's own music so Sunnie can be heard over it is a small
    /// hostility and no cue here is important enough to earn it — but a voice
    /// note with someone's playlist bleeding into it is a recording they cannot
    /// use, so the microphone gets the exception.
    public static func plan(
        for useCase: AudioUseCase,
        backgroundPlaybackEnabled: Bool = false
    ) -> AudioSessionPlan {
        switch useCase {
        case .cue, .ambience, .music:
            AudioSessionPlan(
                category: .ambient,
                options: [],
                continuesInBackground: false
            )
        case .generatedNoise:
            AudioSessionPlan(
                category: .playback,
                options: [.mixWithOthers],
                continuesInBackground: true
            )
        case .meditation:
            backgroundPlaybackEnabled
                ? AudioSessionPlan(
                    category: .playback,
                    options: [.mixWithOthers],
                    continuesInBackground: true
                )
                : AudioSessionPlan(
                    category: .ambient,
                    options: [],
                    continuesInBackground: false
                )
        case .voiceNote:
            AudioSessionPlan(
                category: .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers],
                continuesInBackground: false
            )
        }
    }

    /// Whether moving from one plan to another actually requires touching the
    /// session.
    ///
    /// Setting the category is not free and can glitch playback, so the service
    /// asks this before reconfiguring. It is also why the service holds the last
    /// plan rather than a bare `isConfigured` flag.
    public static func requiresReconfiguration(
        from current: AudioSessionPlan?,
        to next: AudioSessionPlan
    ) -> Bool {
        current != next
    }
}
