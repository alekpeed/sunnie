import Foundation

/// Turns "the user is on the plants screen, it is a Sunnie Afternoonie" into
/// "play this track at this gain" (AUDIO_MIDI_AND_SOUNDSCAPES.md §5, §6).
///
/// Pure. No player, no session, no bundle — the availability of a rendered asset
/// arrives as a closure, because the shared package has nothing to look in. That
/// is what makes every selection rule testable: the whole of cue routing can be
/// exercised with a manifest literal and no audio at all.
///
/// The one rule worth stating plainly: **nothing starts by itself.** A plan is
/// what *may* play, and a plan with autoplay off is empty (§6, "Do not surprise
/// the user with audible playback on app launch").

// MARK: - Plan

/// One resolved assignment: a track, and the gain it should actually play at.
public struct AudioAssignment: Hashable, Sendable {
    public let track: AudioTrackDefinition
    /// Track gain × layer gain × master gain, already multiplied out.
    public let gain: Double

    public init(track: AudioTrackDefinition, gain: Double) {
        self.track = track
        self.gain = gain
    }

    public var trackID: ContentID { track.id }
}

/// What should be sounding right now.
public struct AudioPlan: Hashable, Sendable {
    public var music: AudioAssignment?
    public var ambience: AudioAssignment?

    public init(music: AudioAssignment? = nil, ambience: AudioAssignment? = nil) {
        self.music = music
        self.ambience = ambience
    }

    public static let silent = AudioPlan()

    public var isSilent: Bool { music == nil && ambience == nil }
}

/// How to get from one plan to the next on a single layer.
public enum AudioTransition: Hashable, Sendable {
    case none
    case start(AudioAssignment)
    case stop
    /// Same track, different level — a gain ramp, not a restart. Restarting a
    /// loop because the volume slider moved is an audible seam for no reason.
    case adjustGain(Double)
    case crossfade(from: ContentID, to: AudioAssignment)

    /// Works out the transition for one layer.
    public static func between(
        current: AudioAssignment?,
        next: AudioAssignment?
    ) -> AudioTransition {
        switch (current, next) {
        case (nil, nil):
            .none
        case (nil, .some(let next)):
            .start(next)
        case (.some, nil):
            .stop
        case (.some(let current), .some(let next)):
            if current.trackID == next.trackID {
                current.gain == next.gain ? .none : .adjustGain(next.gain)
            } else {
                .crossfade(from: current.trackID, to: next)
            }
        }
    }
}

// MARK: - Director

public struct AudioDirector: Sendable {

    private let manifest: AudioManifest

    public init(manifest: AudioManifest = BuiltInAudioContent.manifest) {
        self.manifest = manifest
    }

    /// Resolves the contexts the app is currently in into a plan.
    ///
    /// - Parameters:
    ///   - contexts: what is on screen and what time it is, most specific first.
    ///     Order does not affect the result; it is a set in spirit.
    ///   - preferences: the user's toggles and gains.
    ///   - pinnedAmbienceID: an explicit choice from the sound library, which
    ///     always beats the context match. Someone who put the ocean on does not
    ///     want it swapped for crickets because the sun went down.
    ///   - assetExists: whether a named rendered file is in the bundle.
    public func plan(
        contexts: [AudioContextTag],
        preferences: AudioPreferences,
        pinnedAmbienceID: ContentID? = nil,
        assetExists: (String) -> Bool = { _ in false }
    ) -> AudioPlan {
        var plan = AudioPlan()

        if preferences.isEnabled(.music), preferences.autoPlayAmbience {
            plan.music = best(
                on: .music, contexts: contexts,
                preferences: preferences, assetExists: assetExists
            )
        }

        guard preferences.isEnabled(.ambience) else { return plan }

        if let pinnedAmbienceID {
            // A pinned choice plays whether or not autoplay is on: the user
            // started it by hand, which is exactly the tap autoplay is about not
            // needing.
            plan.ambience = manifest.track(id: pinnedAmbienceID)
                .flatMap { track in
                    track.isPlayable(assetExists: assetExists)
                        ? assignment(track, preferences) : nil
                }
        } else if preferences.autoPlayAmbience {
            plan.ambience = best(
                on: .ambience, contexts: contexts,
                preferences: preferences, assetExists: assetExists
            )
        }

        return plan
    }

    /// The cue for a bell, if that layer is on.
    ///
    /// Bells are not part of the plan because they are not a state — they are a
    /// single strike at a moment. Modelling them as "what is playing" would make
    /// a second bell in the same session look like a no-op.
    public func bell(_ preset: BellPreset, preferences: AudioPreferences) -> AudioAssignment? {
        guard preferences.isEnabled(.meditationBell) else { return nil }
        guard let track = manifest.track(id: preset.cueID) else { return nil }
        return assignment(track, preferences)
    }

    /// The cue for a short effect, by id.
    public func cue(_ id: ContentID, preferences: AudioPreferences) -> AudioAssignment? {
        guard let track = manifest.track(id: id) else { return nil }
        guard preferences.isEnabled(track.layer) else { return nil }
        return assignment(track, preferences)
    }

    /// The best-matching playable track on a layer.
    ///
    /// Scored by how many of the requested contexts a track claims, so a track
    /// tagged `theme.jungle` *and* `time.night` beats one tagged only
    /// `theme.jungle` when both are asked for. Ties break on the id, which makes
    /// the result deterministic — a soundtrack that changed on every launch
    /// because two tracks tied would be a maddening bug to chase.
    private func best(
        on layer: AudioLayer,
        contexts: [AudioContextTag],
        preferences: AudioPreferences,
        assetExists: (String) -> Bool
    ) -> AudioAssignment? {
        let requested = Set(contexts)
        guard !requested.isEmpty else { return nil }

        let candidates = manifest.tracks(on: layer)
            .filter { $0.isPlayable(assetExists: assetExists) }
            .map { track in (track: track, score: requested.intersection(track.contexts).count) }
            .filter { $0.score > 0 }

        guard let winner = candidates.min(by: { left, right in
            left.score == right.score
                ? left.track.id.rawValue < right.track.id.rawValue
                : left.score > right.score
        }) else { return nil }

        return assignment(winner.track, preferences)
    }

    private func assignment(
        _ track: AudioTrackDefinition,
        _ preferences: AudioPreferences
    ) -> AudioAssignment {
        AudioAssignment(
            track: track,
            gain: preferences.effectiveGain(for: track.layer, trackGain: track.defaultGain)
        )
    }
}

// MARK: - Crossfade

/// The shape of a crossfade (§6).
///
/// Equal power, not equal amplitude. Two uncorrelated sounds — which two
/// different ambience beds always are — sum in power, not in amplitude, so a
/// linear fade dips audibly in the middle. `cos`/`sin` keeps the sum of squares
/// at one throughout, which is why the seam disappears.
public struct CrossfadePlan: Hashable, Sendable {
    public let duration: TimeInterval
    public let steps: Int

    public init(duration: TimeInterval = AmbienceTuning.crossfadeSeconds, stepsPerSecond: Int = 40) {
        self.duration = max(duration, 0)
        self.steps = max(1, Int(max(duration, 0) * Double(stepsPerSecond)))
    }

    /// Seconds between steps.
    public var stepInterval: TimeInterval { duration / Double(steps) }

    public var stepNanoseconds: UInt64 {
        UInt64(max(stepInterval, 0) * 1_000_000_000)
    }

    /// Gains at a point through the fade, `progress` in 0…1.
    public func gains(at progress: Double) -> (outgoing: Double, incoming: Double) {
        let t = min(max(progress, 0), 1)
        let angle = t * .pi / 2
        return (cos(angle), sin(angle))
    }

    public func gains(atStep step: Int) -> (outgoing: Double, incoming: Double) {
        gains(at: Double(min(max(step, 0), steps)) / Double(steps))
    }
}
