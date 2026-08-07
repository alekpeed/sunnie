import Foundation

/// What to do when the world interrupts
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §6, §12).
///
/// A pure state machine, which is the only reason §12's test list can be honoured
/// at all in this repository. "Phone call, Siri, Bluetooth disconnect, headphone
/// removal, route change, background and foreground, simultaneous timer and
/// audio, other audio playing" is eight scenarios that normally need a device,
/// two pairs of headphones, and someone willing to ring you mid-test. Modelled as
/// events into a value, every one of them is a unit test, and the app target is
/// left with the part that genuinely needs a device: turning an
/// `AVAudioSession` notification into one of these cases.
///
/// The rules it encodes, in one place:
///
/// - **Pause on interruption, resume only when the system says so.** Resuming on
///   our own initiative is how an app ends up talking over the second half of a
///   phone call.
/// - **A private route disappearing stops playback.** Headphones out means the
///   sound stops, not that it moves to the speaker. Rain suddenly playing out
///   loud in a quiet room is the failure this exists to prevent, and it is the
///   one people actually remember.
/// - **A route appearing starts nothing.** Plugging headphones in is not consent.
/// - **Background only pauses what was never meant to survive it.** A sleep sound
///   or a running practice keeps going; a screen's decorative bed does not.
/// - **Media services resetting invalidates everything.** The only correct
///   response is to rebuild, and the only wrong one is to assume the players are
///   still valid.

/// Everything the machine needs to remember.
public struct AudioInterruptionState: Hashable, Sendable {
    public var isPlaying: Bool
    /// Paused by a phone call or Siri, and eligible to resume when it ends.
    public var isInterrupted: Bool
    /// Paused by the app going to the background, which resumes on return —
    /// unlike an interruption, which waits for the system's say-so.
    public var isPausedForBackground: Bool
    public var isDucked: Bool
    public var useCase: AudioUseCase
    public var backgroundPlaybackEnabled: Bool
    public var route: AudioRoute

    public init(
        isPlaying: Bool = false,
        isInterrupted: Bool = false,
        isPausedForBackground: Bool = false,
        isDucked: Bool = false,
        useCase: AudioUseCase = .ambience,
        backgroundPlaybackEnabled: Bool = false,
        route: AudioRoute = .builtInSpeaker
    ) {
        self.isPlaying = isPlaying
        self.isInterrupted = isInterrupted
        self.isPausedForBackground = isPausedForBackground
        self.isDucked = isDucked
        self.useCase = useCase
        self.backgroundPlaybackEnabled = backgroundPlaybackEnabled
        self.route = route
    }

    /// Whether this sound is one that should keep going off-screen.
    var survivesBackgrounding: Bool {
        switch useCase {
        case .generatedNoise: true
        case .meditation: backgroundPlaybackEnabled
        case .cue, .ambience, .music, .voiceNote: false
        }
    }
}

/// Decides, and remembers.
///
/// A struct with `mutating func handle` rather than a static function, because
/// half the rules depend on how playback was stopped: "resume" means different
/// things after a phone call and after a trip to the home screen, and an app that
/// cannot tell them apart resumes at the wrong times in both directions.
public struct AudioInterruptionMachine: Sendable {

    public private(set) var state: AudioInterruptionState

    public init(state: AudioInterruptionState = AudioInterruptionState()) {
        self.state = state
    }

    public mutating func setPlaying(_ isPlaying: Bool, useCase: AudioUseCase? = nil) {
        state.isPlaying = isPlaying
        if let useCase { state.useCase = useCase }
        if !isPlaying {
            state.isInterrupted = false
            state.isPausedForBackground = false
            state.isDucked = false
        }
    }

    public mutating func setBackgroundPlaybackEnabled(_ enabled: Bool) {
        state.backgroundPlaybackEnabled = enabled
    }

    public mutating func handle(_ event: AudioEvent) -> AudioAction {
        switch event {
        case .interruptionBegan:
            guard state.isPlaying else { return .none }
            state.isPlaying = false
            state.isInterrupted = true
            return .pause

        case .interruptionEnded(let shouldResume):
            guard state.isInterrupted else { return .none }
            state.isInterrupted = false
            // The system's hint is the whole decision. Without it, the
            // interruption is over but the user's attention is elsewhere —
            // another app took the session and kept it.
            guard shouldResume else { return .none }
            // Still in the background with nothing that survives it: staying
            // paused is correct, and `enteredForeground` will pick it up.
            if state.isPausedForBackground { return .none }
            state.isPlaying = true
            return .resume

        case .routeChanged(let reason, let newRoute):
            let previous = state.route
            state.route = newRoute
            switch reason {
            case .oldDeviceUnavailable:
                // Headphones out, Bluetooth gone. Only stop if what went away
                // was actually private — a route change from one speaker to
                // another is not a reason to stop a sleep sound.
                guard state.isPlaying, previous.isPrivate else { return .none }
                state.isPlaying = false
                state.isInterrupted = false
                state.isPausedForBackground = false
                return .stop
            case .newDeviceAvailable, .categoryChange, .override, .other:
                // Never a reason to start. Plugging in headphones is not consent
                // to hear something.
                return .none
            }

        case .enteredBackground:
            guard state.isPlaying, !state.survivesBackgrounding else { return .none }
            state.isPlaying = false
            state.isPausedForBackground = true
            return .pause

        case .enteredForeground:
            guard state.isPausedForBackground else { return .none }
            state.isPausedForBackground = false
            // A phone call that arrived while backgrounded outranks coming back:
            // the interruption has not ended yet, so nothing resumes here.
            guard !state.isInterrupted else { return .none }
            state.isPlaying = true
            return .resume

        case .otherAudioStarted:
            // Sunnie's own sound steps back; the user's does not. Ducking
            // *their* audio would be the hostile version of this, and the
            // session policy is what makes it impossible (no `.duckOthers`).
            guard state.isPlaying, !state.isDucked else { return .none }
            // A bell is over before ducking would take effect, and a practice
            // that has ducked itself into inaudibility is not a practice.
            guard state.useCase == .ambience || state.useCase == .music else { return .none }
            state.isDucked = true
            return .duck

        case .otherAudioStopped:
            guard state.isDucked else { return .none }
            state.isDucked = false
            return .unduck

        case .mediaServicesReset:
            // Every player and engine is now invalid, whatever they claim. The
            // only safe answer is to rebuild — and to resume only what was
            // genuinely sounding a moment ago.
            let wasPlaying = state.isPlaying
            state.isDucked = false
            state.isInterrupted = false
            state.isPausedForBackground = false
            return wasPlaying ? .restart : .none
        }
    }
}
