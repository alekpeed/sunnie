import Foundation
import Testing
@testable import SunnieShared

/// The audio layer, verified without a speaker.
///
/// That is the point of the whole Phase 10 design, and it is worth stating why:
/// `AUDIO_MIDI_AND_SOUNDSCAPES.md` §12 asks for phone calls, Siri, Bluetooth
/// disconnects, headphones being pulled, route changes, backgrounding, loop gaps,
/// and other audio playing. Written as branches inside notification handlers,
/// none of that is reachable from a test. Written as values — a manifest, a
/// director, a session table, a state machine, and a DSP chain with no
/// AVFoundation in it — every one of them is an assertion below.
///
/// The one thing these cannot check is that iOS posts the notifications we think
/// it does. That mapping is a handful of lines per observer, and it is the only
/// part left for a device.
@Suite("Audio")
struct AudioTests {

    // MARK: - Manifest

    @Test("The shipped manifest has no problems")
    func shippedManifestValidates() {
        let issues = AudioManifestValidator.validate(BuiltInAudioContent.manifest)
        #expect(issues.isEmpty, "\(issues.map(\.description))")
    }

    @Test("Every ambience voice has a track, and every track a voice")
    func everyVoiceIsRegistered() {
        let manifest = BuiltInAudioContent.manifest
        for voice in AmbienceVoice.allCases {
            let track = manifest.track(id: voice.cueID)
            #expect(track != nil, "No manifest entry for \(voice.rawValue)")
            #expect(track?.proceduralVoice == voice)
            #expect(track?.layer == .ambience)
            #expect(track?.loops == true)
        }
        for preset in BellPreset.allCases {
            let track = manifest.track(id: preset.cueID)
            #expect(track?.bell == preset)
            #expect(track?.layer == .meditationBell)
            // A bell that looped would ring forever.
            #expect(track?.loops == false)
        }
    }

    @Test("Synthesised tracks are playable with nothing in the bundle")
    func proceduralTracksNeedNoAsset() {
        for track in BuiltInAudioContent.ambienceTracks + BuiltInAudioContent.bellTracks {
            #expect(track.isPlayable(assetExists: { _ in false }))
            #expect(track.runtimeAsset == nil)
        }
    }

    /// The declared-but-absent state the music entries are in today. It is
    /// deliberate, and it is the thing most likely to be "fixed" by someone who
    /// reads it as a bug — hence a test that says so.
    @Test("Declared music is not playable until its file exists")
    func renderedTracksWaitForTheirAsset() {
        for track in BuiltInAudioContent.musicTracks {
            #expect(!track.isPlayable(assetExists: { _ in false }))
            #expect(track.isPlayable(assetExists: { _ in true }))
            #expect(track.runtimeAsset != nil)
        }
    }

    @Test("Runtime MIDI is rejected rather than quietly played")
    func runtimeMIDIIsRejected() {
        let manifest = AudioManifest(version: 1, tracks: [
            AudioTrackDefinition(
                id: "sunnie.music.adaptive",
                titleKey: "k",
                runtimeAsset: "adaptive.mid",
                sourceType: .runtimeMIDI,
                loops: true,
                layer: .music,
                contexts: [.today],
                defaultGain: 0.5
            )
        ])
        let issues = AudioManifestValidator.validate(manifest)
        #expect(issues.contains(.runtimeMIDIWithoutApproval("sunnie.music.adaptive")))
        #expect(!manifest.tracks[0].isPlayable(assetExists: { _ in true }))
    }

    @Test("A manifest with obvious defects reports each of them")
    func validatorCatchesDefects() {
        let manifest = AudioManifest(version: 1, tracks: [
            AudioTrackDefinition(
                id: "a", titleKey: "k", sourceType: .renderedAudio,
                loops: true, layer: .music, contexts: [.today], defaultGain: 1.4
            ),
            AudioTrackDefinition(
                id: "a", titleKey: "k", sourceType: .procedural,
                loops: true, layer: .ambience, contexts: [], defaultGain: 0.5
            ),
            AudioTrackDefinition(
                id: "b", titleKey: "k", runtimeAsset: "x.m4a", sourceType: .procedural,
                proceduralVoice: .rainSoft, loops: true, layer: .ambience,
                contexts: [.today], defaultGain: 0.5
            ),
            AudioTrackDefinition(
                id: "c", titleKey: "k", sourceType: .procedural, bell: .start,
                loops: false, layer: .effects, contexts: [.today], defaultGain: 0.5
            )
        ])
        let issues = AudioManifestValidator.validate(manifest)
        #expect(issues.contains(.duplicateTrackID("a")))
        #expect(issues.contains(.gainOutOfRange("a", 1.4)))
        #expect(issues.contains(.renderedTrackWithoutAsset("a")))
        #expect(issues.contains(.trackWithoutContexts("a")))
        #expect(issues.contains(.proceduralTrackWithoutVoice("a")))
        #expect(issues.contains(.proceduralTrackWithAsset("b")))
        #expect(issues.contains(.bellTrackOnWrongLayer("c")))
    }

    /// Sharing *a* context is normal — the three jungle tracks all do. Sharing
    /// the whole set is the defect, because then no request can prefer one.
    @Test("Two music tracks a request cannot tell apart are reported")
    func identicalMusicContextsAreAmbiguous() {
        func music(_ id: ContentID, _ contexts: [AudioContextTag]) -> AudioTrackDefinition {
            AudioTrackDefinition(
                id: id, titleKey: "k", runtimeAsset: "\(id.rawValue).m4a",
                sourceType: .renderedAudio, loops: true, layer: .music,
                contexts: contexts, defaultGain: 0.5
            )
        }
        let distinguishable = AudioManifest(version: 1, tracks: [
            music("a", [.jungle, .day]), music("b", [.jungle, .night])
        ])
        #expect(!AudioManifestValidator.validate(distinguishable).contains {
            if case .ambiguousMusicForContext = $0 { return true } else { return false }
        })

        let identical = AudioManifest(version: 1, tracks: [
            music("a", [.jungle, .day]), music("b", [.day, .jungle])
        ])
        #expect(AudioManifestValidator.validate(identical).contains {
            if case .ambiguousMusicForContext = $0 { return true } else { return false }
        })
    }

    // MARK: - Director

    private var director: AudioDirector { AudioDirector() }

    /// The default. Nothing plays on its own, which is §6's whole rule.
    @Test("With autoplay off, a context selects nothing")
    func contextsDoNotAutoplayByDefault() {
        let plan = director.plan(
            contexts: [.today, .day], preferences: AudioPreferences()
        )
        #expect(plan.isSilent)
    }

    @Test("With autoplay on, a context selects an ambience")
    func contextsSelectAmbienceWhenAutoplayIsOn() {
        var preferences = AudioPreferences()
        preferences.autoPlayAmbience = true

        let plan = director.plan(contexts: [.today, .day], preferences: preferences)
        #expect(plan.ambience != nil)
        #expect(plan.ambience?.track.layer == .ambience)
        // No music: every music track's file is absent, and a selection that
        // cannot make a sound is worse than none.
        #expect(plan.music == nil)
    }

    @Test("An explicit choice plays even with autoplay off")
    func pinnedAmbiencePlaysWithoutAutoplay() {
        let plan = director.plan(
            contexts: [],
            preferences: AudioPreferences(),
            pinnedAmbienceID: AmbienceVoice.oceanWaves.cueID
        )
        #expect(plan.ambience?.trackID == AmbienceVoice.oceanWaves.cueID)
    }

    @Test("A more specific match wins")
    func moreContextMatchesWin() {
        var preferences = AudioPreferences()
        preferences.autoPlayAmbience = true

        // jungleNight claims both `theme.jungle` and `time.night`; jungleDay
        // claims jungle but the wrong cycle.
        let plan = director.plan(contexts: [.jungle, .night], preferences: preferences)
        #expect(plan.ambience?.trackID == AmbienceVoice.jungleNight.cueID)
    }

    @Test("Selection is deterministic")
    func selectionIsStable() {
        var preferences = AudioPreferences()
        preferences.autoPlayAmbience = true

        let first = director.plan(contexts: [.wellness], preferences: preferences)
        let second = director.plan(
            contexts: [.wellness], preferences: preferences
        )
        #expect(first == second)
        // Order of the requested contexts must not change the answer either.
        let reversed = director.plan(
            contexts: [.breathing, .wellness], preferences: preferences
        )
        let forward = director.plan(
            contexts: [.wellness, .breathing], preferences: preferences
        )
        #expect(reversed == forward)
    }

    @Test("Turning a layer off silences it")
    func disabledLayersSelectNothing() {
        var preferences = AudioPreferences()
        preferences.autoPlayAmbience = true
        preferences.ambienceEnabled = false

        #expect(director.plan(contexts: [.jungle, .day], preferences: preferences).ambience == nil)
        #expect(director.bell(.start, preferences: preferences) != nil)

        preferences.effectsEnabled = false
        #expect(director.bell(.start, preferences: preferences) == nil)
    }

    @Test("Gain is track times layer times master")
    func gainMultipliesThroughEveryStage() throws {
        var preferences = AudioPreferences(masterGain: 0.5)
        preferences.autoPlayAmbience = true
        preferences.setGain(0.5, for: .ambience)

        let plan = director.plan(contexts: [.wellness], preferences: preferences)
        let assignment = try #require(plan.ambience)
        #expect(
            abs(assignment.gain - assignment.track.defaultGain * 0.5 * 0.5) < 0.000_1
        )
    }

    @Test("A disabled layer's effective gain is zero, not merely quiet")
    func disabledLayerHasNoGain() {
        var preferences = AudioPreferences()
        preferences.musicEnabled = false
        #expect(preferences.effectiveGain(for: .music, trackGain: 1) == 0)
        #expect(preferences.effectiveGain(for: .ambience, trackGain: 1) > 0)
    }

    // MARK: - Transitions

    @Test("Same track at a new level is a gain change, not a restart")
    func gainChangeDoesNotRestart() {
        let track = BuiltInAudioContent.ambienceTracks[0]
        let quiet = AudioAssignment(track: track, gain: 0.3)
        let loud = AudioAssignment(track: track, gain: 0.6)

        #expect(AudioTransition.between(current: quiet, next: loud) == .adjustGain(0.6))
        #expect(AudioTransition.between(current: quiet, next: quiet) == .none)
    }

    @Test("A different track is a crossfade")
    func differentTracksCrossfade() {
        let first = AudioAssignment(track: BuiltInAudioContent.ambienceTracks[0], gain: 0.5)
        let second = AudioAssignment(track: BuiltInAudioContent.ambienceTracks[1], gain: 0.5)

        guard case .crossfade(let from, let to) = AudioTransition.between(
            current: first, next: second
        ) else {
            Issue.record("Expected a crossfade")
            return
        }
        #expect(from == first.trackID)
        #expect(to.trackID == second.trackID)

        #expect(AudioTransition.between(current: nil, next: first) == .start(first))
        #expect(AudioTransition.between(current: first, next: nil) == .stop)
        #expect(AudioTransition.between(current: nil, next: nil) == .none)
    }

    // MARK: - Crossfade

    /// The property that makes a fade between two beds inaudible. Linear gains
    /// sum to a power dip of about 3 dB in the middle, which is exactly the
    /// "swoosh" a bad crossfade has.
    @Test("A crossfade holds constant power throughout")
    func crossfadeIsEqualPower() {
        let fade = CrossfadePlan()
        for step in 0...fade.steps {
            let gains = fade.gains(atStep: step)
            let power = gains.outgoing * gains.outgoing + gains.incoming * gains.incoming
            #expect(abs(power - 1) < 0.000_001)
        }
    }

    @Test("A crossfade starts on the outgoing bed and ends on the incoming one")
    func crossfadeEndpointsAreClean() {
        let fade = CrossfadePlan(duration: 2)
        #expect(abs(fade.gains(at: 0).outgoing - 1) < 0.000_001)
        #expect(abs(fade.gains(at: 0).incoming) < 0.000_001)
        #expect(abs(fade.gains(at: 1).outgoing) < 0.000_001)
        #expect(abs(fade.gains(at: 1).incoming - 1) < 0.000_001)
        // Out-of-range progress clamps rather than producing a negative gain.
        #expect(fade.gains(at: -1) == fade.gains(at: 0))
        #expect(fade.gains(at: 2) == fade.gains(at: 1))
        #expect(fade.steps > 0)
        #expect(fade.stepNanoseconds > 0)
    }

    @Test("A zero-length crossfade is still a valid plan")
    func zeroLengthCrossfadeIsSafe() {
        let fade = CrossfadePlan(duration: 0)
        #expect(fade.steps == 1)
        #expect(fade.stepNanoseconds == 0)
    }

    // MARK: - Session policy

    @Test("Decoration never takes over from the user's own audio")
    func decorationUsesTheAmbientCategory() {
        for useCase in [AudioUseCase.cue, .ambience, .music] {
            let plan = AudioSessionPolicy.plan(for: useCase)
            #expect(plan.category == .ambient)
            #expect(!plan.continuesInBackground)
            #expect(!plan.options.contains(.duckOthers))
        }
    }

    @Test("Noise keeps its own policy")
    func noiseKeepsItsPolicy() {
        let plan = AudioSessionPolicy.plan(for: .generatedNoise)
        #expect(plan.category == .playback)
        #expect(plan.options.contains(.mixWithOthers))
        #expect(plan.continuesInBackground)
    }

    @Test("Meditation survives the lock screen only when the user asked")
    func meditationFollowsTheBackgroundSetting() {
        let off = AudioSessionPolicy.plan(for: .meditation, backgroundPlaybackEnabled: false)
        #expect(off.category == .ambient)
        #expect(!off.continuesInBackground)

        let on = AudioSessionPolicy.plan(for: .meditation, backgroundPlaybackEnabled: true)
        #expect(on.category == .playback)
        #expect(on.options.contains(.mixWithOthers))
        #expect(on.continuesInBackground)
    }

    @Test("Ducking happens only while recording")
    func onlyRecordingDucks() {
        for useCase in AudioUseCase.allCases where useCase != .voiceNote {
            #expect(!AudioSessionPolicy.plan(for: useCase).options.contains(.duckOthers))
        }
        let recording = AudioSessionPolicy.plan(for: .voiceNote)
        #expect(recording.category == .playAndRecord)
        #expect(recording.mode == .spokenAudio)
        #expect(recording.options.contains(.duckOthers))
    }

    @Test("An unchanged plan does not reconfigure the session")
    func identicalPlansSkipReconfiguration() {
        let plan = AudioSessionPolicy.plan(for: .ambience)
        #expect(!AudioSessionPolicy.requiresReconfiguration(from: plan, to: plan))
        #expect(AudioSessionPolicy.requiresReconfiguration(from: nil, to: plan))
        #expect(AudioSessionPolicy.requiresReconfiguration(
            from: plan, to: AudioSessionPolicy.plan(for: .generatedNoise)
        ))
    }

    // MARK: - Interruptions (§12)

    private func playing(
        _ useCase: AudioUseCase = .ambience,
        route: AudioRoute = .builtInSpeaker,
        background: Bool = false
    ) -> AudioInterruptionMachine {
        AudioInterruptionMachine(state: AudioInterruptionState(
            isPlaying: true,
            useCase: useCase,
            backgroundPlaybackEnabled: background,
            route: route
        ))
    }

    @Test("A phone call pauses, and its end resumes only on the system's say-so")
    func phoneCallPausesAndResumes() {
        var machine = playing()
        #expect(machine.handle(.interruptionBegan) == .pause)
        #expect(!machine.state.isPlaying)
        #expect(machine.handle(.interruptionEnded(shouldResume: true)) == .resume)
        #expect(machine.state.isPlaying)

        var declining = playing()
        #expect(declining.handle(.interruptionBegan) == .pause)
        #expect(declining.handle(.interruptionEnded(shouldResume: false)) == .none)
        #expect(!declining.state.isPlaying)
    }

    @Test("An interruption ending without one having begun changes nothing")
    func strayInterruptionEndIsIgnored() {
        var machine = playing()
        #expect(machine.handle(.interruptionEnded(shouldResume: true)) == .none)
        #expect(machine.state.isPlaying)
    }

    @Test("Headphones coming out stops playback rather than moving it to the speaker")
    func losingAPrivateRouteStops() {
        var machine = playing(route: .headphones)
        let action = machine.handle(
            .routeChanged(reason: .oldDeviceUnavailable, newRoute: .builtInSpeaker)
        )
        #expect(action == .stop)
        #expect(!machine.state.isPlaying)
    }

    @Test("Bluetooth disconnecting stops playback too")
    func losingBluetoothStops() {
        var machine = playing(route: .bluetooth)
        #expect(machine.handle(
            .routeChanged(reason: .oldDeviceUnavailable, newRoute: .builtInSpeaker)
        ) == .stop)
    }

    /// The mirror of the rule above, and the one that stops it overreaching: a
    /// speaker becoming another speaker is not a reason to end a sleep sound.
    @Test("Losing a route that was not private changes nothing")
    func losingAPublicRouteContinues() {
        var machine = playing(.generatedNoise, route: .builtInSpeaker)
        #expect(machine.handle(
            .routeChanged(reason: .oldDeviceUnavailable, newRoute: .other)
        ) == .none)
        #expect(machine.state.isPlaying)
    }

    @Test("Plugging headphones in starts nothing")
    func gainingARouteStartsNothing() {
        var machine = AudioInterruptionMachine()
        #expect(machine.handle(
            .routeChanged(reason: .newDeviceAvailable, newRoute: .headphones)
        ) == .none)
        #expect(!machine.state.isPlaying)
    }

    @Test("Backgrounding pauses decoration and spares a sleep sound")
    func backgroundingPausesOnlyDecoration() {
        var decoration = playing(.ambience)
        #expect(decoration.handle(.enteredBackground) == .pause)
        #expect(decoration.handle(.enteredForeground) == .resume)
        #expect(decoration.state.isPlaying)

        var noise = playing(.generatedNoise)
        #expect(noise.handle(.enteredBackground) == .none)
        #expect(noise.state.isPlaying)
    }

    @Test("A practice survives backgrounding only when the setting is on")
    func meditationBackgroundingFollowsTheSetting() {
        var withSetting = playing(.meditation, background: true)
        #expect(withSetting.handle(.enteredBackground) == .none)

        var without = playing(.meditation, background: false)
        #expect(without.handle(.enteredBackground) == .pause)
    }

    /// The sequence that is genuinely hard to stage by hand, and the reason the
    /// two paused-flags are separate: a call arrives while the app is in the
    /// background, and ends after the user has come back.
    @Test("A call during backgrounding resumes once, at the right moment")
    func callDuringBackgroundingResumesOnce() {
        var machine = playing(.ambience)
        #expect(machine.handle(.enteredBackground) == .pause)
        #expect(machine.handle(.interruptionBegan) == .none, "Already paused")

        // Coming back does not resume while the call is still in progress...
        machine = playing(.ambience)
        #expect(machine.handle(.interruptionBegan) == .pause)
        #expect(machine.handle(.enteredBackground) == .none)
        #expect(machine.handle(.enteredForeground) == .none)
        #expect(!machine.state.isPlaying)
        // ...it resumes when the call ends.
        #expect(machine.handle(.interruptionEnded(shouldResume: true)) == .resume)
        #expect(machine.state.isPlaying)
    }

    @Test("Other audio ducks ours, and only ours")
    func otherAudioDucksOurOwn() {
        var machine = playing(.ambience)
        #expect(machine.handle(.otherAudioStarted) == .duck)
        // A second notification does not duck twice.
        #expect(machine.handle(.otherAudioStarted) == .none)
        #expect(machine.handle(.otherAudioStopped) == .unduck)
        #expect(machine.handle(.otherAudioStopped) == .none)

        // A practice is not ducked into inaudibility.
        var practice = playing(.meditation)
        #expect(practice.handle(.otherAudioStarted) == .none)
    }

    @Test("Media services resetting rebuilds what was sounding, and only that")
    func mediaServicesResetRebuilds() {
        var playingMachine = playing()
        #expect(playingMachine.handle(.mediaServicesReset) == .restart)

        var idle = AudioInterruptionMachine()
        #expect(idle.handle(.mediaServicesReset) == .none)
    }

    @Test("Stopping clears every reason it might resume")
    func stoppingClearsPendingState() {
        var machine = playing()
        _ = machine.handle(.interruptionBegan)
        machine.setPlaying(false)
        #expect(!machine.state.isInterrupted)
        #expect(!machine.state.isPausedForBackground)
        #expect(machine.handle(.interruptionEnded(shouldResume: true)) == .none)
    }

    // MARK: - Preferences

    /// The bug this prevents is quiet and total: a new field added here without a
    /// lenient decoder makes the whole stored blob unreadable, and the
    /// repository's catch then hands back defaults — silently resetting every
    /// setting the user had chosen.
    @Test("Preferences saved by an older build still decode")
    func olderPreferencesDecodeLeniently() throws {
        let legacy = """
        {"musicEnabled": false, "ambienceEnabled": true,
         "effectsEnabled": true, "masterGain": 0.42}
        """
        let decoded = try JSONDecoder().decode(
            AudioPreferences.self, from: Data(legacy.utf8)
        )
        #expect(decoded.musicEnabled == false)
        #expect(abs(decoded.masterGain - 0.42) < 0.000_1)
        // The new fields take their defaults, which for both of these is off.
        #expect(!decoded.autoPlayAmbience)
        #expect(!decoded.backgroundPlaybackEnabled)
        #expect(decoded.gain(for: .ambience) == 1)
    }

    @Test("Preferences round-trip")
    func preferencesRoundTrip() throws {
        var original = AudioPreferences()
        original.setGain(0.25, for: .music)
        original.autoPlayAmbience = true
        original.backgroundPlaybackEnabled = true
        original.setAmbienceID(AmbienceVoice.oceanWaves.cueID, forTheme: "theme.a")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioPreferences.self, from: data)
        #expect(decoded == original)
        #expect(decoded.ambienceID(forTheme: "theme.a") == AmbienceVoice.oceanWaves.cueID)

        var cleared = decoded
        cleared.setAmbienceID(nil, forTheme: "theme.a")
        #expect(cleared.ambienceID(forTheme: "theme.a") == nil)
    }

    @Test("Gains clamp rather than being trusted")
    func gainsClamp() {
        var preferences = AudioPreferences(masterGain: 4)
        preferences.setGain(-1, for: .ambience)
        #expect(preferences.gain(for: .ambience) == 0)
        #expect(preferences.effectiveGain(for: .ambience, trackGain: 1) == 0)

        preferences.setGain(9, for: .ambience)
        #expect(preferences.gain(for: .ambience) == 1)
        #expect(preferences.effectiveGain(for: .ambience, trackGain: 1) == 1)
    }

    // MARK: - Contexts

    @Test("Cycle tags exist only for the three branded cycles")
    func onlyThreeCycleTags() {
        let tags = Set(DayCyclePresentation.allCases.map(AudioContextTag.cycle))
        #expect(tags == [.day, .afternoon, .night])
        // The six underlying phases collapse onto those three, so there is no
        // way to tag a track for a cycle the product does not have.
        #expect(Set(TimePhase.allCases.map(AudioContextTag.phase)) == tags)
    }

    @Test("Destination tags are per place")
    func destinationTagsAreSpecific() {
        #expect(AudioContextTag.destination("JP") == AudioContextTag.destination("jp"))
        #expect(AudioContextTag.destination("jp") != AudioContextTag.destination("it"))
    }

    // MARK: - Synthesis

    /// Determinism is what makes every assertion below meaningful. Without it the
    /// level and spectral checks would be flaky rather than wrong.
    @Test("A voice renders identically from the same seed")
    func synthesisIsDeterministic() {
        var first = AmbienceChannel(voice: .rainSoft, seed: 99)
        var second = AmbienceChannel(voice: .rainSoft, seed: 99)
        for index in 0..<20_000 {
            let a = first.next()
            let b = second.next()
            if a != b {
                Issue.record("Diverged at sample \(index)")
                return
            }
        }
    }

    /// Copying one channel to both outputs sounds like mono — it collapses to a
    /// point inside the head. Independence is what makes a bed sound wide.
    @Test("The two playback channels are independent")
    func channelsAreIndependent() {
        var left = AmbienceChannel(
            voice: .jungleDay, seed: AmbienceTuning.PlaybackSeed.left
        )
        var right = AmbienceChannel(
            voice: .jungleDay, seed: AmbienceTuning.PlaybackSeed.right
        )
        var identical = 0
        let count = 20_000
        for _ in 0..<count where left.next() == right.next() { identical += 1 }
        #expect(identical < count / 100)
    }

    /// Measured on the seeds playback actually uses, because the calibration
    /// measures one seed per voice and these are stochastic signals: a level that
    /// fits under the ceiling on the measured seed can drift past it on another.
    /// That drift is what `peakSafetyFactor` exists for, and this is the test
    /// that would catch it being removed.
    @Test("Every voice stays inside its headroom at playback level")
    func everyVoiceLeavesHeadroom() {
        for voice in AmbienceVoice.allCases {
            for seed in [
                AmbienceTuning.PlaybackSeed.left, AmbienceTuning.PlaybackSeed.right
            ] {
                var channel = AmbienceCalibration.channel(voice, seed: seed)
                // Long enough to cover several swell cycles and a good number of
                // events — a short window can miss the loudest moment entirely.
                let peak = Loudness.peak(48_000 * 15) { channel.next() }
                #expect(
                    peak <= AmbienceTuning.peakCeiling,
                    "\(voice.rawValue) peaked at \(peak)"
                )
                #expect(peak > 0.05, "\(voice.rawValue) is inaudible at \(peak)")
            }
        }
    }

    /// The designed property of the calibration, and the reason `bedGain` is a
    /// balance control rather than a level: switching beds must not change how
    /// loud the app is. Matched by peak instead, crickets — which are almost all
    /// transient — would be far too quiet next to room tone.
    @Test("Calibration matches the voices to one another by loudness")
    func calibrationEqualisesLoudness() {
        var quietest = Double.greatestFiniteMagnitude
        var loudest = 0.0
        for voice in AmbienceVoice.allCases {
            var channel = AmbienceCalibration.channel(
                voice, seed: AmbienceTuning.PlaybackSeed.left
            )
            let level = Loudness.kWeightedRms(48_000 * 10) { channel.next() }
            #expect(level > 0.001, "\(voice.rawValue) is inaudible")
            quietest = min(quietest, level)
            loudest = max(loudest, level)
        }
        // Within about 8 dB across every voice. Not tighter, because a
        // ten-second window of a sparse signal is itself a noisy measurement —
        // the calibration's own window is what the match is made on.
        #expect(loudest < quietest * 2.6, "spread \(quietest)…\(loudest)")
    }

    /// A sanity check on the recipe table rather than on the ear: rain is a
    /// broadband bed with a lot of top, ocean is deliberately dark. If these ever
    /// invert, a recipe has been edited into the wrong shape.
    @Test("Rain sits brighter than ocean")
    func spectralShapesDiffer() {
        var rain = AmbienceChannel(voice: .rainSoft, seed: 3)
        var ocean = AmbienceChannel(voice: .oceanWaves, seed: 3)
        let rainTop = Loudness.bandEnergy(4_000, 48_000 * 3) { rain.next() }
        let oceanTop = Loudness.bandEnergy(4_000, 48_000 * 3) { ocean.next() }
        #expect(rainTop > oceanTop)
    }

    @Test("The ocean swells rather than sitting still")
    func oceanHasASwell() {
        var channel = AmbienceChannel(voice: .oceanWaves, seed: 5)
        // Window the signal into half-second blocks and compare the loudest
        // block with the quietest. A steady bed varies barely at all; a swell at
        // depth 0.62 varies a great deal.
        var loudest = 0.0
        var quietest = Double.greatestFiniteMagnitude
        for _ in 0..<48 {
            var sum = 0.0
            for _ in 0..<24_000 {
                let sample = channel.next()
                sum += sample * sample
            }
            let rms = (sum / 24_000).squareRoot()
            loudest = max(loudest, rms)
            quietest = min(quietest, rms)
        }
        #expect(loudest > quietest * 2)
    }

    /// Before calibration the recipes sit at wildly different levels — room tone
    /// is a whisper and rain is a wall of sound. That is fine, and it is exactly
    /// why the calibration exists; this test pins the raw relationship so a
    /// recipe edit that inverts it is noticed.
    @Test("Room tone is the quietest recipe before calibration")
    func roomToneIsTheQuietestRecipe() {
        func level(_ voice: AmbienceVoice) -> Double {
            var channel = AmbienceChannel(voice: voice, seed: 13)
            return Loudness.kWeightedRms(48_000 * 5) { channel.next() }
        }
        let roomTone = level(.roomToneWarm)
        #expect(roomTone < level(.rainSoft))
        #expect(roomTone < level(.jungleDay))
        // And the calibration has to work hard to lift it, which is the point.
        #expect(AmbienceCalibration.gain(for: .roomToneWarm)
            > AmbienceCalibration.gain(for: .rainSoft))
    }

    // MARK: - Bells

    @Test("A bell rings and then stops")
    func bellsDecayToSilence() {
        for preset in BellPreset.allCases {
            var bell = BellVoice(preset: preset)
            #expect(bell.isActive)

            let strike = abs(bell.next())
            var sustained = strike
            for _ in 0..<1_000 { sustained = max(sustained, abs(bell.next())) }
            #expect(sustained > 0.01, "\(preset.rawValue) barely sounds")

            // Run past the stated decay; it must be finished, not merely quiet.
            let total = Int(preset.decaySeconds * NoiseTuning.sampleRate) + 10
            for _ in 0..<total { _ = bell.next() }
            #expect(!bell.isActive)
            #expect(bell.next() == 0)
        }
    }

    @Test("A bell peaks near its gain rather than at the sum of its partials")
    func bellsAreNormalised() {
        var bell = BellVoice(preset: .start, gain: 0.55)
        let peak = Loudness.peak(Int(NoiseTuning.sampleRate)) { bell.next() }
        #expect(peak <= 0.8)
        #expect(peak > 0.2)
    }

    @Test("The closing bell rings lower and longer than the opening one")
    func theTwoBellsDiffer() {
        #expect(BellPreset.end.frequency < BellPreset.start.frequency)
        #expect(BellPreset.end.decaySeconds > BellPreset.start.decaySeconds)
    }

    @Test("A bell drops partials that would alias rather than playing them")
    func bellsAvoidAliasing() {
        // At 8 kHz the upper partials of a 528 Hz bell sit above Nyquist. They
        // must be dropped, not folded back as tones that are not part of the
        // sound at all.
        var bell = BellVoice(preset: .start, sampleRate: 8_000)
        let peak = Loudness.peak(8_000) { bell.next() }
        #expect(peak > 0)
        #expect(peak <= 0.8)
    }

    // MARK: - Oscillator

    @Test("The oscillator stays bounded over a long run")
    func oscillatorDoesNotDrift() {
        var oscillator = SineOscillator(frequency: 440, sampleRate: 48_000)
        var peak = 0.0
        for _ in 0..<48_000 * 30 { peak = max(peak, abs(oscillator.next())) }
        // The recurrence is stable but not exactly unit-amplitude; what matters
        // is that it neither decays away nor grows without bound.
        #expect(peak > 0.9)
        #expect(peak < 1.2)
    }
}
