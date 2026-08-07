import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// Phase 10 behaviour through the real `AudioService`, with the synthesiser
/// replaced by something that records what it was asked to do.
///
/// The rules being checked here are the ones that live in the *service* rather
/// than in a pure value: that a preference change actually reaches the engine,
/// that an explicit tap outranks a context, that a phone call and a pulled pair
/// of headphones produce different outcomes, and that a practice's bells go to
/// the bell path rather than the file path.
///
/// The selection rules themselves are tested in `AudioTests` against the
/// director, and the DSP in the same place against the sample stream. Nothing
/// here needs a speaker either.
@Suite("Audio flows")
struct AudioFlowTests {

    // MARK: - Recording double

    /// Records calls in order. An actor because `ProceduralAudioPlaying` is
    /// `Sendable` and the service calls it from its own isolation.
    private actor Recorder: ProceduralAudioPlaying {
        enum Call: Hashable {
            case start(AmbienceVoice, gain: Double)
            case crossfade(AmbienceVoice, gain: Double)
            case setGain(Double)
            case stop
            case strike(BellPreset, gain: Double)
            case session(AudioSessionCategory)
            case action(AudioAction)
        }

        private(set) var calls: [Call] = []
        private var voice: AmbienceVoice?

        var currentVoice: AmbienceVoice? { voice }

        func start(_ voice: AmbienceVoice, gain: Double) {
            self.voice = voice
            calls.append(.start(voice, gain: gain))
        }

        func crossfade(to voice: AmbienceVoice, gain: Double, over seconds: TimeInterval) {
            self.voice = voice
            calls.append(.crossfade(voice, gain: gain))
        }

        func setGain(_ gain: Double) { calls.append(.setGain(gain)) }

        func stop(fadeOver seconds: TimeInterval) {
            voice = nil
            calls.append(.stop)
        }

        func strike(_ bell: BellPreset, gain: Double) {
            calls.append(.strike(bell, gain: gain))
        }

        func apply(sessionPlan: AudioSessionPlan) {
            calls.append(.session(sessionPlan.category))
        }

        func handle(_ action: AudioAction) { calls.append(.action(action)) }

        func started() -> [AmbienceVoice] {
            calls.compactMap { (call: Call) -> AmbienceVoice? in
                switch call {
                case .start(let voice, _), .crossfade(let voice, _): voice
                default: nil
                }
            }
        }

        func struck() -> [BellPreset] {
            calls.compactMap { (call: Call) -> BellPreset? in
                if case .strike(let bell, _) = call { bell } else { nil }
            }
        }

        func contains(_ call: Call) -> Bool { calls.contains(call) }
        func stopCount() -> Int { calls.filter { $0 == .stop }.count }
    }

    private func makeService(
        _ preferences: AudioPreferences
    ) async -> (AudioService, Recorder) {
        let recorder = Recorder()
        let service = AudioService(procedural: recorder)
        await service.apply(preferences: preferences)
        return (service, recorder)
    }

    private var autoplaying: AudioPreferences {
        var preferences = AudioPreferences()
        preferences.autoPlayAmbience = true
        return preferences
    }

    // MARK: - Explicit playback

    @Test("Tapping a sound in the library plays it, autoplay or not")
    func tappingASoundPlaysIt() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.startAmbience(AmbienceVoice.oceanWaves.cueID)

        #expect(await recorder.started() == [.oceanWaves])
        #expect(await service.playingCueID() == AmbienceVoice.oceanWaves.cueID)
    }

    @Test("Choosing a second sound crossfades rather than restarting")
    func secondSoundCrossfades() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        await service.startAmbience(AmbienceVoice.nightCrickets.cueID)

        let calls = await recorder.calls
        #expect(calls.contains { if case .start(.rainSoft, _) = $0 { true } else { false } })
        #expect(calls.contains {
            if case .crossfade(.nightCrickets, _) = $0 { true } else { false }
        })
    }

    @Test("Stopping stops, and stays stopped")
    func stoppingStops() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        await service.stopAmbience()

        #expect(await service.playingCueID() == nil)
        #expect(await recorder.stopCount() == 1)

        // A second stop is not an error and does not stop twice.
        await service.stopAmbience()
        #expect(await recorder.stopCount() == 1)
    }

    @Test("Turning the ambience layer off silences what is playing")
    func disablingTheLayerStopsPlayback() async {
        var preferences = AudioPreferences()
        let (service, recorder) = await makeService(preferences)

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        #expect(await service.playingCueID() != nil)

        preferences.ambienceEnabled = false
        await service.apply(preferences: preferences)

        #expect(await service.playingCueID() == nil)
        #expect(await recorder.stopCount() == 1)
    }

    /// The bug this prevents is small and very annoying: a bed that restarts from
    /// the top every time the volume slider moves.
    @Test("Changing the volume does not restart the sound")
    func volumeChangeDoesNotRestart() async {
        var preferences = AudioPreferences(masterGain: 0.8)
        let (service, recorder) = await makeService(preferences)

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        preferences.masterGain = 0.4
        await service.apply(preferences: preferences)

        #expect(await recorder.started() == [.rainSoft])
        let calls = await recorder.calls
        #expect(calls.contains { if case .setGain = $0 { true } else { false } })
    }

    // MARK: - Contexts

    @Test("A screen alone starts nothing by default")
    func screensAreSilentByDefault() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.setContexts([.jungle, .night])

        #expect(await recorder.started().isEmpty)
        #expect(await service.playingCueID() == nil)
    }

    @Test("With autoplay on, a screen selects a bed")
    func screensSelectABedWhenAutoplayIsOn() async {
        let (service, recorder) = await makeService(autoplaying)

        await service.setContexts([.jungle, .night])

        #expect(await recorder.started() == [.jungleNight])
        #expect(await service.playingCueID() == AmbienceVoice.jungleNight.cueID)
    }

    @Test("Walking to another screen crossfades")
    func changingScreensCrossfades() async {
        let (service, recorder) = await makeService(autoplaying)

        await service.setContexts([.jungle, .day])
        await service.setContexts([.jungle, .night])

        #expect(await recorder.started() == [.jungleDay, .jungleNight])
    }

    /// Someone who deliberately put the ocean on should not have it swapped for
    /// crickets because they opened another screen.
    @Test("An explicit choice outranks the screen")
    func pinnedSoundSurvivesNavigation() async {
        let (service, recorder) = await makeService(autoplaying)

        await service.startAmbience(AmbienceVoice.oceanWaves.cueID)
        await service.setContexts([.jungle, .night])

        #expect(await service.playingCueID() == AmbienceVoice.oceanWaves.cueID)
        #expect(await recorder.started() == [.oceanWaves])
    }

    // MARK: - Bells

    @Test("A meditation's cues ring rather than looking for a file")
    func meditationCuesRing() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.playCue(BellPreset.start.cueID)
        await service.playBell(.end)

        #expect(await recorder.struck() == [.start, .end])
    }

    @Test("Turning sounds off silences the bells")
    func disablingEffectsSilencesBells() async {
        var preferences = AudioPreferences()
        preferences.effectsEnabled = false
        let (service, recorder) = await makeService(preferences)

        await service.playBell(.start)
        await service.playCue(BellPreset.end.cueID)

        #expect(await recorder.struck().isEmpty)
    }

    @Test("A cue with no track does nothing rather than failing")
    func unknownCuesAreIgnored() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.playCue("sunnie.audio.cue.doesNotExist")

        #expect(await recorder.calls.isEmpty)
    }

    // MARK: - Interruptions

    @Test("A phone call pauses and its end resumes")
    func phoneCallPausesAndResumes() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        await service.handle(.interruptionBegan)
        await service.handle(.interruptionEnded(shouldResume: true))

        #expect(await recorder.contains(.action(.pause)))
        #expect(await recorder.contains(.action(.resume)))
    }

    @Test("Headphones coming out stops playback and clears the selection")
    func headphonesOutStops() async {
        let (service, recorder) = await makeService(AudioPreferences())

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        // The machine has to believe a private route was in use, which is what
        // the service's own observer would have told it.
        await service.handle(
            .routeChanged(reason: .newDeviceAvailable, newRoute: .headphones)
        )
        await service.handle(
            .routeChanged(reason: .oldDeviceUnavailable, newRoute: .builtInSpeaker)
        )

        #expect(await recorder.contains(.action(.stop)))
        #expect(await service.playingCueID() == nil)
    }

    @Test("Plugging headphones in starts nothing")
    func headphonesInStartNothing() async {
        let (service, recorder) = await makeService(autoplaying)

        await service.handle(
            .routeChanged(reason: .newDeviceAvailable, newRoute: .headphones)
        )

        #expect(await recorder.started().isEmpty)
    }

    // MARK: - Session policy

    @Test("Ambience uses the decoration session, and a practice may not")
    func sessionFollowsTheUseCase() async {
        var preferences = AudioPreferences()
        preferences.backgroundPlaybackEnabled = true
        let (service, recorder) = await makeService(preferences)

        await service.startAmbience(AmbienceVoice.rainSoft.cueID)
        #expect(await recorder.contains(.session(.ambient)))

        await service.playBell(.start)
        // Background playback is on, so a practice's session keeps sounding with
        // the screen locked — which decoration's never does.
        #expect(await recorder.contains(.session(.playback)))
    }

    // MARK: - Preferences persistence

    /// Audio preferences live inside one encoded blob. A new field added without
    /// a lenient decoder makes the whole record unreadable, and the repository's
    /// catch then quietly hands back defaults — resetting every setting the user
    /// had chosen. This is that path, through the real store.
    @Test("New audio settings survive a save and reload")
    @MainActor
    func audioPreferencesRoundTripThroughTheStore() async throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let repository = SwiftDataPreferencesRepository(modelContainer: container)

        var preferences = UserPreferences.default
        preferences.audio.autoPlayAmbience = true
        preferences.audio.backgroundPlaybackEnabled = true
        preferences.audio.masterGain = 0.33
        preferences.audio.setGain(0.5, for: .ambience)
        preferences.audio.setAmbienceID(
            AmbienceVoice.oceanWaves.cueID, forTheme: preferences.activeThemeID
        )
        try await repository.save(preferences)

        let reloaded = try await repository.preferences()
        #expect(reloaded.audio.autoPlayAmbience)
        #expect(reloaded.audio.backgroundPlaybackEnabled)
        #expect(abs(reloaded.audio.masterGain - 0.33) < 0.000_1)
        #expect(reloaded.audio.gain(for: .ambience) == 0.5)
        #expect(
            reloaded.audio.ambienceID(forTheme: reloaded.activeThemeID)
                == AmbienceVoice.oceanWaves.cueID
        )
    }

    /// The reverse: a record written before these fields existed must load with
    /// everything else intact, not reset to defaults.
    @Test("Preferences written by an older build keep their settings")
    @MainActor
    func olderStoredPreferencesSurvive() async throws {
        let container = try ModelContainerFactory.make(storage: .inMemory)
        let context = ModelContext(container)
        let legacy = """
        {"activeThemeID": "sunnie.theme.lushTropicalJungle",
         "automaticDayCycle": false,
         "quietHours": {"isEnabled": true, "startHour": 22, "endHour": 7},
         "audio": {"musicEnabled": false, "ambienceEnabled": true,
                   "effectsEnabled": true, "masterGain": 0.61},
         "hapticsEnabled": true,
         "accessibility": {"forceHighContrast": false, "forceReducedMotion": false,
                           "nightBrightnessReduction": 0},
         "nicknameProbability": 0.05,
         "dietaryRuleIDs": ["sunnie.diet.noEggs"],
         "useSolarTimes": false}
        """
        context.insert(SDUserPreferences(encoded: Data(legacy.utf8)))
        try context.save()

        let repository = SwiftDataPreferencesRepository(modelContainer: container)
        let loaded = try await repository.preferences()

        // The old settings survived...
        #expect(loaded.automaticDayCycle == false)
        #expect(loaded.audio.musicEnabled == false)
        #expect(abs(loaded.audio.masterGain - 0.61) < 0.000_1)
        // ...and the new ones took their defaults, which are off.
        #expect(!loaded.audio.autoPlayAmbience)
        #expect(!loaded.audio.backgroundPlaybackEnabled)
        #expect(loaded.audio.themeAmbienceIDs.isEmpty)
    }

    // MARK: - Content

    @Test("Every calm sound in the pack resolves to a track that can play")
    @MainActor
    func everyCalmSoundHasATrack() {
        let registry = ContentRegistry.builtIn()
        let manifest = registry.audioManifest

        for sound in registry.wellnessPack.calmSounds {
            if sound.category.isGenerated {
                // Noise has its own engine and is deliberately not in the
                // manifest (ADR-018).
                #expect(NoiseColor.from(contentID: sound.id) != nil)
                continue
            }
            guard let track = manifest.track(id: sound.audioCueID) else {
                Issue.record("No audio track for \(sound.id.rawValue)")
                continue
            }
            #expect(
                track.isPlayable(assetExists: { _ in false }),
                "\(sound.id.rawValue) cannot make a sound"
            )
        }
    }

    @Test("Every meditation's cues resolve")
    @MainActor
    func everyMeditationCueResolves() {
        let registry = ContentRegistry.builtIn()
        let manifest = registry.audioManifest

        for meditation in registry.wellnessPack.meditations {
            for cue in [meditation.startCueID, meditation.endCueID, meditation.ambienceCueID] {
                guard let cue else { continue }
                let track = manifest.track(id: cue)
                #expect(track != nil, "\(cue.rawValue) is not in the manifest")
                #expect(track?.isPlayable(assetExists: { _ in false }) ?? false)
            }
        }
    }

    @Test("The shipped manifest passes validation as loaded")
    @MainActor
    func loadedManifestValidates() {
        let issues = ContentRegistry.builtIn().audioIssues
        #expect(issues.isEmpty, "\(issues.map(\.description))")
    }
}
