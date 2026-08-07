import Foundation
import SunnieShared
#if canImport(AVFAudio)
import AVFAudio
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Plays the synthesised ambiences and bells (ADR-029).
///
/// All the DSP lives in `SunnieShared/Audio/ProceduralAmbience.swift`, which has
/// no platform dependencies and is verified offline. This is only the plumbing —
/// deliberately the same shape as `NoiseEngine`, because the constraints are the
/// same and having two audio engines that solve them differently would be one
/// engine too many to reason about.
///
/// **One source node, not several.** The render block mixes the outgoing bed, the
/// incoming bed, and any ringing bells itself. That is what makes the crossfade
/// sample-accurate and free: a fade between two `AVAudioPlayer`s can only be as
/// smooth as the timer driving it, where a fade computed per sample has no seam
/// at all. It also means one engine start, one session configuration, and one
/// place where the level is decided.
///
/// **The render block allocates nothing and locks nothing.** Same discipline as
/// the noise engine, same reasons, and the same failure mode if it is broken:
/// audible breakup under load rather than a crash.
final class ProceduralAudioEngine: ProceduralAudioPlaying, @unchecked Sendable {

    private let log = SunnieLog(category: .audio)

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    #endif

    private let lock = NSLock()
    private var mix: MixState?
    private var voice: AmbienceVoice?
    private var sessionPlan: AudioSessionPlan?
    private var fadeTask: Task<Void, Never>?
    private var sampleRate = NoiseTuning.sampleRate

    /// Enough bells for a start and an end overlapping, plus room for a reward
    /// chime on top. Bells ring for seconds, so this is not a theoretical worry.
    private static let bellVoiceCount = 4

    // MARK: - Render state

    /// Everything the render block owns.
    ///
    /// A class so the block can mutate it without capturing `self`, exactly as
    /// the noise engine does. `@unchecked Sendable` for the same reason and with
    /// the same discipline: the scalars below are written from outside and read
    /// on the render thread, and a torn `Double` read is not a real hazard on
    /// any platform this ships to. The channels and bells are touched only by
    /// the render thread.
    private final class MixState: @unchecked Sendable {
        /// The bed that is playing.
        var currentLeft: AmbienceChannel
        var currentRight: AmbienceChannel
        /// The bed fading in, during a crossfade.
        var incomingLeft: AmbienceChannel?
        var incomingRight: AmbienceChannel?

        var limiter: PeakLimiter
        var gain: Double
        var incomingGain: Double = 0

        /// Crossfade progress in samples. `total` of zero means no fade running.
        var fadeSample = 0
        var fadeTotal = 0
        /// Set when the fade is to silence rather than to another bed.
        var fadingOut = false
        var isSilent = false

        var bells: [BellVoice?]
        /// Bells are mixed even when the beds are gone, so a bell can ring out
        /// after a practice ends without the bed being held open for it.
        var bellGain: Double = 0.55

        init(voice: AmbienceVoice, gain: Double, sampleRate: Double, bellCount: Int) {
            // Calibrated, so switching beds never changes the perceived level
            // and no voice clips.
            currentLeft = AmbienceCalibration.channel(
                voice, seed: AmbienceTuning.PlaybackSeed.left, sampleRate: sampleRate
            )
            currentRight = AmbienceCalibration.channel(
                voice, seed: AmbienceTuning.PlaybackSeed.right, sampleRate: sampleRate
            )
            limiter = PeakLimiter(sampleRate: sampleRate)
            self.gain = gain
            bells = Array(repeating: nil, count: bellCount)
        }
    }

    // MARK: - Lifecycle

    var currentVoice: AmbienceVoice? {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return voice
        }
    }

    func apply(sessionPlan: AudioSessionPlan) async {
        lock.lock()
        let needsChange = AudioSessionPolicy.requiresReconfiguration(
            from: self.sessionPlan, to: sessionPlan
        )
        self.sessionPlan = sessionPlan
        lock.unlock()

        guard needsChange else { return }
        configureSession(sessionPlan)
    }

    func start(_ voice: AmbienceVoice, gain: Double) async {
        cancelFade()
        #if canImport(AVFoundation)
        // Already on this bed: change the level rather than rebuilding, so
        // nudging a slider does not restart the sound.
        lock.lock()
        let alreadyPlaying = self.voice == voice && mix != nil
        lock.unlock()
        if alreadyPlaying {
            await setGain(gain)
            return
        }

        await tearDown()
        ensureSessionConfigured()

        let rate = liveSampleRate()
        let state = MixState(
            voice: voice, gain: gain, sampleRate: rate, bellCount: Self.bellVoiceCount
        )

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            log.error("Could not create an audio format for ambience playback.")
            return
        }

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Resolved once per render call rather than per frame, for the
            // reason the noise engine gives: a rebind per sample is exactly the
            // kind of thing that turns into audible breakup under load.
            let leftBuffer = buffers.count > 0
                ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
            let rightBuffer = buffers.count > 1
                ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

            for frame in 0..<Int(frameCount) {
                var left = 0.0
                var right = 0.0

                if !state.isSilent {
                    // Equal power, computed per sample. `cos`/`sin` here rather
                    // than a table because the fade runs for a couple of seconds
                    // every few minutes at most, and correctness beats a
                    // micro-optimisation nobody would hear.
                    var outgoingGain = state.gain
                    var incomingGain = 0.0

                    if state.fadeTotal > 0 {
                        let progress = min(
                            1.0, Double(state.fadeSample) / Double(state.fadeTotal)
                        )
                        let angle = progress * Double.pi / 2
                        outgoingGain = state.gain * cos(angle)
                        incomingGain = state.incomingGain * sin(angle)
                    }

                    left = state.currentLeft.next() * outgoingGain
                    right = state.currentRight.next() * outgoingGain

                    if state.incomingLeft != nil {
                        left += state.incomingLeft!.next() * incomingGain
                        right += state.incomingRight!.next() * incomingGain
                    }

                    // Advanced and promoted *after* the sample is written, not
                    // before. Doing it first means the frame where progress
                    // reaches one is rendered from the outgoing bed at a gain of
                    // exactly zero — a one-sample hole in the middle of a fade
                    // whose entire job is not having holes in it.
                    if state.fadeTotal > 0 {
                        state.fadeSample += 1
                        if state.fadeSample >= state.fadeTotal {
                            // The fade finished inside this buffer. Promote the
                            // incoming bed here rather than on another thread, so
                            // there is never a sample where neither is current.
                            state.fadeTotal = 0
                            state.fadeSample = 0
                            if state.fadingOut {
                                state.isSilent = true
                                state.fadingOut = false
                            } else if let nextLeft = state.incomingLeft,
                                      let nextRight = state.incomingRight {
                                state.currentLeft = nextLeft
                                state.currentRight = nextRight
                                state.gain = state.incomingGain
                                state.incomingLeft = nil
                                state.incomingRight = nil
                            }
                        }
                    }
                }

                for index in state.bells.indices {
                    guard state.bells[index] != nil else { continue }
                    if state.bells[index]!.isActive {
                        let sample = state.bells[index]!.next() * state.bellGain
                        left += sample
                        right += sample
                    } else {
                        state.bells[index] = nil
                    }
                }

                // One reduction from the larger peak, applied to both, so gain
                // reduction never shifts the stereo image.
                let reduction = state.limiter.gainFor(max(abs(left), abs(right)))
                leftBuffer?[frame] = Float(left * reduction)
                rightBuffer?[frame] = Float(right * reduction)
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            log.error("The ambience engine could not start.")
            engine.detach(node)
            return
        }

        lock.lock()
        sourceNode = node
        mix = state
        self.voice = voice
        sampleRate = rate
        lock.unlock()
        #endif
    }

    func crossfade(to voice: AmbienceVoice, gain: Double, over seconds: TimeInterval) async {
        cancelFade()

        lock.lock()
        let state = mix
        let current = self.voice
        let rate = sampleRate
        lock.unlock()

        // Nothing playing, or the engine was torn down: this is just a start,
        // and starting with a fade would only delay the sound by two seconds.
        guard let state, current != nil else {
            await start(voice, gain: gain)
            return
        }
        guard current != voice else {
            await setGain(gain)
            return
        }

        // Building the channels here rather than in the render block is what
        // keeps that block allocation-free — construction is where the arrays
        // and filters are made.
        let left = AmbienceCalibration.channel(
            voice, seed: AmbienceTuning.PlaybackSeed.left, sampleRate: rate
        )
        let right = AmbienceCalibration.channel(
            voice, seed: AmbienceTuning.PlaybackSeed.right, sampleRate: rate
        )

        lock.lock()
        // If the bed had already faded to silence, bring it back as the incoming
        // one at full progress rather than fading up from a bed nobody can hear.
        if state.isSilent {
            state.currentLeft = left
            state.currentRight = right
            state.gain = gain
            state.incomingLeft = nil
            state.incomingRight = nil
            state.fadeTotal = 0
            state.fadeSample = 0
            state.isSilent = false
        } else {
            state.incomingLeft = left
            state.incomingRight = right
            state.incomingGain = gain
            state.fadeSample = 0
            state.fadingOut = false
            state.fadeTotal = max(1, Int(max(seconds, 0) * rate))
        }
        self.voice = voice
        lock.unlock()
    }

    func setGain(_ gain: Double) async {
        let clamped = min(max(gain, 0), 1)
        lock.lock()
        // During a fade the target is the incoming bed's level; setting the
        // outgoing one would make the fade jump.
        if let mix {
            if mix.fadeTotal > 0 {
                mix.incomingGain = clamped
            } else {
                mix.gain = clamped
            }
            mix.bellGain = clamped
        }
        lock.unlock()
    }

    func stop(fadeOver seconds: TimeInterval) async {
        cancelFade()

        lock.lock()
        let state = mix
        let rate = sampleRate
        lock.unlock()

        guard let state, seconds > 0 else {
            await tearDown()
            return
        }

        lock.lock()
        state.incomingLeft = nil
        state.incomingRight = nil
        state.incomingGain = 0
        state.fadeSample = 0
        state.fadingOut = true
        state.fadeTotal = max(1, Int(seconds * rate))
        voice = nil
        lock.unlock()

        // Tear down only once the render block has actually reached silence.
        // Stopping the engine at the same moment the fade starts is a hard cut
        // with extra steps, which is precisely what a fade is for avoiding.
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000) + 100_000_000)
            guard !Task.isCancelled else { return }
            await self?.tearDown()
        }
        lock.lock()
        fadeTask = task
        lock.unlock()
        await task.value
    }

    func strike(_ bell: BellPreset, gain: Double) async {
        #if canImport(AVFoundation)
        lock.lock()
        let hasMix = mix != nil
        lock.unlock()

        // A bell with no bed running still has to sound — the commonest case is
        // a silent meditation, which has no ambience at all. Start a silent mix
        // so the render block exists to ring it.
        if !hasMix {
            await startSilentMix(gain: gain)
        }

        lock.lock()
        defer { lock.unlock() }
        guard let mix else { return }
        mix.bellGain = min(max(gain, 0), 1)
        let rate = sampleRate
        // First free slot. Four bells at once has never happened; dropping the
        // fifth is inaudible and is the only allocation-free answer.
        guard let index = mix.bells.firstIndex(where: { $0 == nil }) else { return }
        mix.bells[index] = BellVoice(preset: bell, sampleRate: rate)
        #endif
    }

    func handle(_ action: AudioAction) async {
        switch action {
        case .pause:
            #if canImport(AVFoundation)
            engine.pause()
            #endif
        case .resume:
            #if canImport(AVFoundation)
            if let plan = currentSessionPlan() { configureSession(plan) }
            try? engine.start()
            #endif
        case .stop:
            await stop(fadeOver: 0.4)
        case .restart:
            // Media services reset: every node is invalid. Rebuild on the voice
            // that was playing, which is the only state worth preserving.
            let voice = await currentVoice
            let gain = currentGain()
            await tearDown()
            if let voice { await start(voice, gain: gain) }
        case .duck:
            await rampGain(to: currentGain() * Self.duckedFraction)
        case .unduck:
            await rampGain(to: currentGain() / Self.duckedFraction)
        case .none:
            break
        }
    }

    /// How far Sunnie's own sound steps back when the user starts something
    /// else. Their audio is never touched — only ours moves.
    private static let duckedFraction = 0.35

    // MARK: - Internals

    private func currentGain() -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let mix else { return 0 }
        return mix.fadeTotal > 0 ? mix.incomingGain : mix.gain
    }

    private func currentSessionPlan() -> AudioSessionPlan? {
        lock.lock()
        defer { lock.unlock() }
        return sessionPlan
    }

    /// Steps the level rather than jumping, so ducking is a fade and not a click.
    private func rampGain(to target: Double) async {
        let start = currentGain()
        let clamped = min(max(target, 0), 1)
        let steps = 12
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            await setGain(start + (clamped - start) * progress)
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    /// A mix with no bed, so a bell can ring on its own.
    private func startSilentMix(gain: Double) async {
        #if canImport(AVFoundation)
        // Any voice will do — it is immediately silenced. Room tone is chosen
        // because it is the cheapest to construct.
        await start(.roomToneWarm, gain: gain)
        lock.lock()
        mix?.isSilent = true
        // The bed is silent, but a bell is still playing, so the voice must not
        // read as "room tone is on" to the rest of the app.
        voice = nil
        lock.unlock()
        #endif
    }

    private func cancelFade() {
        lock.lock()
        let task = fadeTask
        fadeTask = nil
        lock.unlock()
        task?.cancel()
    }

    private func tearDown() async {
        #if canImport(AVFoundation)
        engine.stop()
        lock.lock()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        mix = nil
        voice = nil
        lock.unlock()
        #endif
    }

    private func liveSampleRate() -> Double {
        #if canImport(AVFAudio)
        let rate = AVAudioSession.sharedInstance().sampleRate
        return rate > 0 ? rate : NoiseTuning.sampleRate
        #else
        return NoiseTuning.sampleRate
        #endif
    }

    private func ensureSessionConfigured() {
        guard let plan = currentSessionPlan() else {
            // No policy has been applied yet, which means nobody asked for
            // anything unusual. Decoration's policy is the safe default.
            configureSession(AudioSessionPolicy.plan(for: .ambience))
            return
        }
        configureSession(plan)
    }

    #if canImport(AVFAudio)
    /// Translates a plan into AVFAudio. The *decision* is
    /// `AudioSessionPolicy`'s; this only speaks the platform's dialect, which is
    /// what keeps the policy testable (§7).
    private func configureSession(_ plan: AudioSessionPlan) {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if plan.options.contains(.mixWithOthers) { options.insert(.mixWithOthers) }
        if plan.options.contains(.duckOthers) { options.insert(.duckOthers) }
        let category: AVAudioSession.Category = switch plan.category {
        case .ambient: .ambient
        case .playback: .playback
        case .playAndRecord: .playAndRecord
        }

        let mode: AVAudioSession.Mode = plan.mode == .spokenAudio ? .spokenAudio : .default

        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            log.debug("The audio session could not be configured for ambience.")
        }
    }
    #else
    private func configureSession(_ plan: AudioSessionPlan) {}
    #endif
}
