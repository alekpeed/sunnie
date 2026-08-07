import Foundation
import SunnieShared
#if canImport(AVFAudio)
import AVFAudio
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The one place the app's sound is decided
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §6, §7).
///
/// Almost nothing here is a decision. The director works out what should play,
/// the session policy works out what category that needs, and the interruption
/// machine works out what to do when a phone call arrives — all in
/// `SunnieShared`, all without a device. This actor is the part that cannot be
/// pure: it owns the players, translates `AVAudioSession` notifications into
/// domain events, and holds the current plan.
///
/// That split is the whole design. Everything about sound that can be got wrong
/// quietly — resuming over a phone call, playing out loud when headphones come
/// out, a bed that restarts every time the volume slider moves — is a rule in a
/// tested value type rather than a branch in a notification handler nobody can
/// reach from a test.
///
/// **Two paths, one interface.** Synthesised beds and bells go to the procedural
/// engine, which mixes and crossfades them inside its own render block. Rendered
/// files go to an `AVAudioPlayer` per layer, swapped with an equal-power ramp.
/// The caller never knows which it got — a track's `sourceType` decides, and the
/// manifest is where that changes.
///
/// **Vanessa never sees MIDI.** Source MIDI is creator-side only and does not
/// appear in the app or its bundle (ADR-006, CLAUDE.md).
actor AudioService: AudioPlaying {

    private let log = SunnieLog(category: .audio)
    private let director: AudioDirector
    private let manifest: AudioManifest
    private let procedural: any ProceduralAudioPlaying

    private var preferences = AudioPreferences()
    private var machine = AudioInterruptionMachine()
    private var contexts: [AudioContextTag] = []
    /// An explicit choice from the sound library, which outranks the context.
    private var pinnedAmbienceID: ContentID?
    private var plan = AudioPlan.silent
    private var appliedSessionPlan: AudioSessionPlan?
    private var sleepTimer: Task<Void, Never>?
    private var isObserving = false

    #if canImport(AVFAudio)
    /// The looping file player per layer.
    ///
    /// Keyed by layer rather than being a single field, because music and a
    /// rendered ambience are allowed to sound at once — `AudioLayer` says so —
    /// and a shared slot would mean stopping one silently stopped the other. No
    /// rendered ambience ships yet; that is exactly why this is worth getting
    /// right now rather than when the first one arrives.
    private var loopingPlayers: [AudioLayer: AVAudioPlayer] = [:]
    private var cuePlayers: [AVAudioPlayer] = []
    private var observers: [any NSObjectProtocol] = []
    private var fadeTasks: [AudioLayer: Task<Void, Never>] = [:]
    #endif

    init(
        manifest: AudioManifest = BuiltInAudioContent.manifest,
        procedural: any ProceduralAudioPlaying = SilentProceduralAudio()
    ) {
        self.manifest = manifest
        self.director = AudioDirector(manifest: manifest)
        self.procedural = procedural
    }

    // MARK: - Preferences

    func apply(preferences: AudioPreferences) async {
        self.preferences = preferences
        machine.setBackgroundPlaybackEnabled(preferences.backgroundPlaybackEnabled)
        // Re-resolve rather than only adjusting the level: turning ambience off
        // has to actually stop it, and turning it back on must not require
        // navigating away and back.
        await reconcile()
    }

    /// The current level for whatever is playing, for the sound library's slider.
    func currentGain() -> Double {
        plan.ambience?.gain ?? plan.music?.gain ?? preferences.masterGain
    }

    // MARK: - Contexts

    func setContexts(_ contexts: [AudioContextTag]) async {
        guard self.contexts != contexts else { return }
        self.contexts = contexts
        await reconcile()
    }

    /// Convenience for the commonest call: a screen plus the branded cycle.
    func setContexts(
        _ contexts: [AudioContextTag],
        cycle: DayCyclePresentation,
        themeID: ContentID?
    ) async {
        var resolved = contexts
        resolved.append(.cycle(cycle))
        if let themeID, themeID == ThemeCatalog.lushTropicalJungleID {
            resolved.append(.jungle)
        }

        // A per-theme ambience the user chose outranks the context match (§9).
        // Tracked separately from the contexts because the pin can change while
        // the contexts do not — switching theme on the same screen — and the
        // early-out below would otherwise swallow it.
        var didChange = self.contexts != resolved
        if let themeID, let chosen = preferences.ambienceID(forTheme: themeID),
           chosen != pinnedAmbienceID {
            pinnedAmbienceID = chosen
            didChange = true
        }

        self.contexts = resolved
        guard didChange else { return }
        await reconcile()
    }

    // MARK: - Ambience

    /// Starts a specific ambience, by cue id.
    ///
    /// This is the sound library's path: an explicit tap, which plays whether or
    /// not autoplay is on. The pin persists until it is stopped, so walking to
    /// another screen does not swap the sound out from under someone who chose
    /// it deliberately.
    func startAmbience(_ cueID: ContentID) async {
        pinnedAmbienceID = cueID
        await reconcile()
    }

    func stopAmbience() async {
        cancelSleepTimer()
        pinnedAmbienceID = nil
        await reconcile()
    }

    /// What is currently selected, so the sound library can show it.
    func playingCueID() -> ContentID? { plan.ambience?.trackID }

    // MARK: - Cues and bells

    func playCue(_ cueID: ContentID) async {
        guard let assignment = director.cue(cueID, preferences: preferences) else {
            log.debug("No audio track for cue \(cueID.rawValue); nothing to play.")
            return
        }
        if let bell = assignment.track.bell {
            await procedural.strike(bell, gain: assignment.gain)
            return
        }
        await playFile(assignment, on: assignment.track.layer)
    }

    func playBell(_ preset: BellPreset) async {
        guard let assignment = director.bell(preset, preferences: preferences) else { return }
        await applySession(for: .meditation)
        await procedural.strike(preset, gain: assignment.gain)
    }

    // MARK: - Sleep timer

    /// Fades whatever is playing out after a number of minutes.
    ///
    /// Fading rather than cutting, because the usual reason for a sleep timer is
    /// that someone is falling asleep and a hard stop would wake them.
    func startSleepTimer(minutes: Int) {
        sleepTimer?.cancel()
        guard minutes > 0 else { return }

        sleepTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndStop()
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = nil
    }

    private func fadeOutAndStop() async {
        await procedural.stop(fadeOver: AmbienceTuning.crossfadeSeconds)
        #if canImport(AVFAudio)
        await fadeOutFilePlayers()
        #endif
        pinnedAmbienceID = nil
        plan = .silent
        machine.setPlaying(false)
    }

    // MARK: - Reconciliation

    /// Works out the new plan and moves to it, one layer at a time.
    ///
    /// Everything funnels through here — preference changes, context changes, an
    /// explicit tap — so there is exactly one place where "what is playing"
    /// changes, and exactly one place a bug in that could live.
    private func reconcile() async {
        // Cheap after the first call, and this is the one path every change to
        // playback goes through — so observation starts the first time the app
        // could make a sound, and never before.
        beginObservingInterruptions()

        let next = director.plan(
            contexts: contexts,
            preferences: preferences,
            pinnedAmbienceID: pinnedAmbienceID,
            assetExists: Self.assetExists
        )
        guard next != plan else { return }

        let ambienceMove = AudioTransition.between(
            current: plan.ambience, next: next.ambience
        )
        let musicMove = AudioTransition.between(current: plan.music, next: next.music)
        plan = next

        if !next.isSilent {
            await applySession(for: next.ambience?.track.layer == .ambience ? .ambience : .music)
        }

        await perform(ambienceMove, on: .ambience)
        await perform(musicMove, on: .music)
        machine.setPlaying(!next.isSilent)
    }

    private func perform(_ transition: AudioTransition, on layer: AudioLayer) async {
        switch transition {
        case .none:
            break
        case .start(let assignment):
            await start(assignment, on: layer, crossfading: false)
        case .crossfade(_, let assignment):
            await start(assignment, on: layer, crossfading: true)
        case .adjustGain(let gain):
            await setGain(gain, on: layer)
        case .stop:
            await stop(layer)
        }
    }

    private func start(
        _ assignment: AudioAssignment,
        on layer: AudioLayer,
        crossfading: Bool
    ) async {
        if let voice = assignment.track.proceduralVoice {
            if crossfading {
                await procedural.crossfade(
                    to: voice, gain: assignment.gain, over: AmbienceTuning.crossfadeSeconds
                )
            } else {
                await procedural.start(voice, gain: assignment.gain)
            }
            return
        }
        await playFile(
            assignment, on: layer,
            looping: assignment.track.loops, crossfade: crossfading
        )
    }

    private func setGain(_ gain: Double, on layer: AudioLayer) async {
        if layer == .ambience { await procedural.setGain(gain) }
        #if canImport(AVFAudio)
        loopingPlayers[layer]?.volume = Float(gain)
        #endif
    }

    /// Stops one layer, leaving the other alone.
    private func stop(_ layer: AudioLayer) async {
        if layer == .ambience { await procedural.stop(fadeOver: 0.5) }
        #if canImport(AVFAudio)
        fadeTasks[layer]?.cancel()
        fadeTasks[layer] = nil
        loopingPlayers[layer]?.stop()
        loopingPlayers[layer] = nil
        #endif
    }

    private func stopEverything() async {
        await stop(.ambience)
        await stop(.music)
    }

    // MARK: - File playback

    /// Plays a rendered track, optionally fading out whatever it replaces.
    ///
    /// No-ops when the asset is absent, which is the normal state today: the
    /// music entries in the manifest name files the creator has not delivered
    /// yet, and the director already filters them out. This second guard exists
    /// because a cue can be requested by id directly.
    private func playFile(
        _ assignment: AudioAssignment,
        on layer: AudioLayer = .effects,
        looping: Bool = false,
        crossfade: Bool = false
    ) async {
        #if canImport(AVFAudio)
        guard let asset = assignment.track.runtimeAsset,
              let url = Self.assetURL(named: asset) else {
            log.debug("No file for track \(assignment.trackID.rawValue); nothing to play.")
            return
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = looping ? -1 : 0

        guard looping else {
            // A one-shot. Held in a small list so ARC does not deallocate it
            // mid-sound, and pruned on the next cue rather than with a timer.
            player.volume = Float(assignment.gain)
            player.play()
            cuePlayers.removeAll { !$0.isPlaying }
            cuePlayers.append(player)
            return
        }

        guard crossfade, let outgoing = loopingPlayers[layer] else {
            player.volume = Float(assignment.gain)
            player.play()
            loopingPlayers[layer] = player
            return
        }

        player.volume = 0
        player.play()
        await rampBetween(
            outgoing: outgoing, incoming: player, target: assignment.gain, on: layer
        )
        #endif
    }

    #if canImport(AVFAudio)
    /// Equal-power ramp between two file players.
    ///
    /// The synthesised path does this per sample inside its render block; a file
    /// player can only be stepped from outside, so this is the closest
    /// equivalent — forty steps a second, which is well under the threshold
    /// where a level change is heard as a step rather than a slide.
    private func rampBetween(
        outgoing: AVAudioPlayer,
        incoming: AVAudioPlayer,
        target: Double,
        on layer: AudioLayer
    ) async {
        fadeTasks[layer]?.cancel()
        let fade = CrossfadePlan()
        let startVolume = outgoing.volume

        let task = Task { [weak self] in
            for step in 0...fade.steps {
                guard !Task.isCancelled else { return }
                let gains = fade.gains(atStep: step)
                outgoing.volume = startVolume * Float(gains.outgoing)
                incoming.volume = Float(target * gains.incoming)
                try? await Task.sleep(nanoseconds: fade.stepNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.finishRamp(stopping: outgoing, keeping: incoming, on: layer)
        }
        fadeTasks[layer] = task
        await task.value
    }

    private func finishRamp(
        stopping outgoing: AVAudioPlayer,
        keeping incoming: AVAudioPlayer,
        on layer: AudioLayer
    ) {
        outgoing.stop()
        loopingPlayers[layer] = incoming
        fadeTasks[layer] = nil
    }

    private func fadeOutFilePlayers() async {
        let fade = CrossfadePlan()
        let players = loopingPlayers
        guard !players.isEmpty else { return }

        let startVolumes = players.mapValues(\.volume)
        for step in 0...fade.steps {
            for (layer, player) in players {
                player.volume = (startVolumes[layer] ?? 0)
                    * Float(fade.gains(atStep: step).outgoing)
            }
            try? await Task.sleep(nanoseconds: fade.stepNanoseconds)
        }
        for player in players.values { player.stop() }
        loopingPlayers.removeAll()
    }
    #endif

    /// Resolves a manifest asset name to a bundled file.
    ///
    /// Static — and so implicitly outside the actor's isolation — because the
    /// director takes it as a plain function. An instance method would have to
    /// capture `self`, and a closure that hops back into the actor is not
    /// something a synchronous selection routine can call.
    static func assetURL(named asset: String) -> URL? {
        let name = (asset as NSString).deletingPathExtension
        let ext = (asset as NSString).pathExtension
        if !ext.isEmpty, let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // The manifest names a file; the bundle may hold either encoding (§3).
        return Bundle.main.url(forResource: name, withExtension: "m4a")
            ?? Bundle.main.url(forResource: name, withExtension: "caf")
    }

    static func assetExists(_ asset: String) -> Bool {
        assetURL(named: asset) != nil
    }

    // MARK: - Session

    private func applySession(for useCase: AudioUseCase) async {
        let sessionPlan = AudioSessionPolicy.plan(
            for: useCase,
            backgroundPlaybackEnabled: preferences.backgroundPlaybackEnabled
        )
        machine.setPlaying(machine.state.isPlaying, useCase: useCase)
        guard AudioSessionPolicy.requiresReconfiguration(
            from: appliedSessionPlan, to: sessionPlan
        ) else { return }
        appliedSessionPlan = sessionPlan
        await procedural.apply(sessionPlan: sessionPlan)
        configureSession(sessionPlan)
    }

    #if canImport(AVFAudio)
    private func configureSession(_ sessionPlan: AudioSessionPlan) {
        var options: AVAudioSession.CategoryOptions = []
        if sessionPlan.options.contains(.mixWithOthers) { options.insert(.mixWithOthers) }
        if sessionPlan.options.contains(.duckOthers) { options.insert(.duckOthers) }

        let category: AVAudioSession.Category = switch sessionPlan.category {
        case .ambient: .ambient
        case .playback: .playback
        case .playAndRecord: .playAndRecord
        }

        let mode: AVAudioSession.Mode =
            sessionPlan.mode == .spokenAudio ? .spokenAudio : .default

        do {
            try AVAudioSession.sharedInstance().setCategory(
                category, mode: mode, options: options
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.debug("Audio session could not be configured.")
        }
    }
    #else
    private func configureSession(_ sessionPlan: AudioSessionPlan) {}
    #endif

    // MARK: - Interruptions and routes

    /// Feeds a platform event to the policy and carries out what it decides.
    ///
    /// The decision is `AudioInterruptionMachine`'s, which is why §12's whole
    /// list is a unit test rather than a device checklist.
    func handle(_ event: AudioEvent) async {
        let action = machine.handle(event)
        guard action != .none else { return }

        await procedural.handle(action)

        #if canImport(AVFAudio)
        switch action {
        case .pause:
            for player in loopingPlayers.values { player.pause() }
        case .resume:
            if let sessionPlan = appliedSessionPlan { configureSession(sessionPlan) }
            for player in loopingPlayers.values { player.play() }
        case .stop:
            await stopEverything()
            pinnedAmbienceID = nil
            plan = .silent
        case .restart:
            // Every player is invalid after a media services reset. Rebuild from
            // the plan, which is the only state that survived.
            let target = plan
            plan = .silent
            loopingPlayers.removeAll()
            cuePlayers.removeAll()
            appliedSessionPlan = nil
            if let ambience = target.ambience {
                await start(ambience, on: .ambience, crossfading: false)
            }
            if let music = target.music {
                await start(music, on: .music, crossfading: false)
            }
            plan = target
        case .duck:
            for player in loopingPlayers.values {
                player.volume *= Float(Self.duckedFraction)
            }
        case .unduck:
            for player in loopingPlayers.values {
                player.volume /= Float(Self.duckedFraction)
            }
        case .none:
            break
        }
        #endif
    }

    private static let duckedFraction = 0.35

    /// Starts listening for interruptions, route changes, and backgrounding.
    ///
    /// Every handler does exactly one thing: turn a platform notification into a
    /// domain event. No decisions here — that is the point.
    func beginObservingInterruptions() {
        #if canImport(AVFAudio)
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            let event: AudioEvent
            switch type {
            case .began:
                event = .interruptionBegan
            case .ended:
                let shouldResume: Bool
                if let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                    shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                        .contains(.shouldResume)
                } else {
                    shouldResume = false
                }
                event = .interruptionEnded(shouldResume: shouldResume)
            @unknown default:
                return
            }
            Task { await self?.handle(event) }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            let route = Self.currentRoute()
            Task {
                await self?.handle(
                    .routeChanged(reason: Self.mapped(reason), newRoute: route)
                )
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handle(.mediaServicesReset) }
        })

        #if canImport(UIKit)
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handle(.enteredBackground) }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handle(.enteredForeground) }
        })
        #endif
        #endif
    }

    #if canImport(AVFAudio)
    private static func mapped(
        _ reason: AVAudioSession.RouteChangeReason
    ) -> AudioRouteChangeReason {
        switch reason {
        case .newDeviceAvailable: .newDeviceAvailable
        case .oldDeviceUnavailable: .oldDeviceUnavailable
        case .categoryChange: .categoryChange
        case .override: .override
        default: .other
        }
    }

    private static func currentRoute() -> AudioRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else { return .other }
        switch port.portType {
        case .headphones, .headsetMic: return .headphones
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return .bluetooth
        case .carAudio: return .carPlay
        case .airPlay: return .airPlay
        case .builtInSpeaker, .builtInReceiver: return .builtInSpeaker
        default: return .other
        }
    }
    #endif
}

/// Silent stand-in for previews and tests.
struct SilentAudioService: AudioPlaying {
    func playCue(_ cueID: ContentID) async {}
    func startAmbience(_ cueID: ContentID) async {}
    func stopAmbience() async {}
    func apply(preferences: AudioPreferences) async {}
    func playBell(_ preset: BellPreset) async {}
    func setContexts(_ contexts: [AudioContextTag]) async {}
    func handle(_ event: AudioEvent) async {}
}
