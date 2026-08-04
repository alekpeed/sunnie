import Foundation
import SunnieShared
#if canImport(AVFAudio)
import AVFAudio
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Plays generated white, pink, and brown noise.
///
/// All the DSP lives in `SunnieShared/NoiseDSP.swift`, which has no platform
/// dependencies and is verified offline. This is only the plumbing: an
/// `AVAudioSourceNode` whose render block pulls samples from two independent
/// channels, plus the session policy that lets it keep playing.
///
/// **The render block allocates nothing and locks nothing.** That constraint
/// shapes the whole type — the noise channels live in a reference-type box the
/// block captures directly, the RNG is a plain xorshift rather than
/// `SystemRandomNumberGenerator`, and volume changes are stored as a `Double`
/// the block reads rather than being applied through a node graph. Breaking any
/// of those produces audible glitching under load, not a crash, which is why it
/// is worth stating.
///
/// **Session policy differs from the rest of the app's audio** (ADR-018). Sunnie's
/// cues and ambience use `.ambient`, which respects the ring/silent switch and
/// never interrupts anything. Noise uses `.playback` with `.mixWithOthers`,
/// because a sleep sound must keep going with the phone on silent and the screen
/// off. It still mixes rather than interrupting, so it never silences the user's
/// own music, and phone calls still interrupt it.
///
/// **Background playback needs `UIBackgroundModes = audio`** in Info.plist.
/// Without it iOS suspends the app on leaving and playback stops, which looks
/// exactly like an audio bug and is not one.
final class NoiseEngine: NoiseGenerating, @unchecked Sendable {

    private let log = SunnieLog(category: .audio)

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    #endif

    private var state: RenderState?
    private var fadeTask: Task<Void, Never>?
    private var color: NoiseColor?
    /// Guards the non-render-thread state. The render block never takes it — it
    /// only reads and mutates through the `RenderState` box it captured.
    private let lock = NSLock()

    /// Mutable state the render block owns.
    ///
    /// A class so the block can mutate it without capturing `self` and without
    /// the closure context being reallocated. `@unchecked Sendable` because the
    /// discipline is by convention, not by the type system: `volume` is written
    /// from the main actor and read on the render thread, and a torn `Double`
    /// read is not a real hazard on any platform this ships to. Everything else
    /// is touched by the render thread alone.
    private final class RenderState: @unchecked Sendable {
        var left: NoiseChannel
        var right: NoiseChannel
        var limiter: PeakLimiter
        var volume: Double = 0.7

        init(color: NoiseColor, sampleRate: Double) {
            // Independent seeds — this is what makes the noise sound wide.
            left = NoiseCalibration.channel(
                color, seed: NoiseCalibration.PlaybackSeed.left, sampleRate: sampleRate
            )
            right = NoiseCalibration.channel(
                color, seed: NoiseCalibration.PlaybackSeed.right, sampleRate: sampleRate
            )
            limiter = PeakLimiter(sampleRate: sampleRate)
        }
    }

    init() {
        beginObservingInterruptions()
    }

    var currentColor: NoiseColor? {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return color
        }
    }

    // MARK: - Playback

    func start(_ color: NoiseColor) async {
        #if canImport(AVFoundation)
        await stop()
        configureSession()

        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        let renderState = RenderState(color: color, sampleRate: sampleRate)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 2
        ) else {
            log.error("Could not create an audio format for noise playback.")
            return
        }

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Pointers are resolved once per render call rather than per frame.
            // Doing it inside the sample loop costs a bounds check and a rebind
            // per sample, which is exactly the kind of thing that turns into
            // audible breakup under load.
            let leftBuffer = buffers.count > 0
                ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
            let rightBuffer = buffers.count > 1
                ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

            let volume = renderState.volume

            for frame in 0..<Int(frameCount) {
                let l = renderState.left.next() * volume
                let r = renderState.right.next() * volume
                // One reduction from the larger peak, applied to both, so gain
                // reduction never shifts the stereo image.
                let reduction = renderState.limiter.gainFor(max(abs(l), abs(r)))
                leftBuffer?[frame] = Float(l * reduction)
                rightBuffer?[frame] = Float(r * reduction)
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            log.error("The noise engine could not start.")
            engine.detach(node)
            return
        }

        lock.lock()
        self.sourceNode = node
        self.state = renderState
        self.color = color
        lock.unlock()

        if abs(sampleRate - NoiseTuning.sampleRate) > 1 {
            // Not a failure: the filters are designed from the live rate. Only
            // the K-weighted loudness match drifts slightly, because those
            // coefficients are 48 kHz-specific.
            log.debug("Noise is running at a rate other than 48 kHz; loudness match may drift.")
        }
        #endif
    }

    func stop() async {
        cancelFade()
        await tearDown()
    }

    /// Stops without cancelling the fade, so the fade task can call it without
    /// cancelling itself partway through its own final step.
    private func tearDown() async {
        #if canImport(AVFoundation)
        engine.stop()
        lock.lock()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        state = nil
        color = nil
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

    func setVolume(_ volume: Double) async {
        lock.lock()
        state?.volume = min(max(volume, 0), 1)
        lock.unlock()
    }

    /// Ramps to silence, then stops.
    ///
    /// Stepped rather than continuous because the render block reads a plain
    /// `Double`; twenty steps a second is smooth enough to be inaudible and
    /// costs nothing.
    func fadeOutAndStop(over seconds: Double) async {
        cancelFade()

        lock.lock()
        let startVolume = state?.volume ?? 0
        lock.unlock()

        guard seconds > 0, startVolume > 0 else {
            await stop()
            return
        }

        let steps = max(1, Int(seconds * 20))
        let stepNanoseconds = UInt64(seconds / Double(steps) * 1_000_000_000)

        let task = Task { [weak self] in
            for step in 0..<steps {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: stepNanoseconds)
                guard !Task.isCancelled, let self else { return }
                let remaining = Double(steps - step - 1) / Double(steps)
                await self.setVolume(startVolume * remaining)
            }
            guard !Task.isCancelled else { return }
            // `tearDown`, not `stop`: `stop` would cancel this very task and the
            // teardown would never run. The volume is not restored because the
            // render state goes with it — the next `start` builds a fresh one and
            // the caller sets the level again.
            await self?.tearDown()
        }

        lock.lock()
        fadeTask = task
        lock.unlock()

        await task.value
    }

    // MARK: - Session

    #if canImport(AVFAudio)
    /// `.playback` with `.mixWithOthers`, which is the combination a sleep sound
    /// needs and the rest of the app's audio deliberately avoids (ADR-018):
    ///
    /// - `.playback` keeps playing with the screen off and the ring/silent switch
    ///   on. `.ambient` does neither, which would make a sleep timer pointless.
    /// - `.mixWithOthers` means it never silences the user's own music or
    ///   podcast. It plays underneath rather than taking over.
    ///
    /// Phone calls still interrupt, which is handled below.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            // The K-weighting coefficients are defined at 48 kHz. The device may
            // still choose another rate; the filters adapt because they are
            // designed from the live rate.
            try session.setPreferredSampleRate(NoiseTuning.sampleRate)
            try session.setActive(true)
        } catch {
            log.debug("The audio session could not be configured for noise.")
        }
    }

    private func beginObservingInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            let shouldResume: Bool
            if let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    .contains(.shouldResume)
            } else {
                shouldResume = false
            }

            Task { await self?.handleInterruption(type: type, shouldResume: shouldResume) }
        }
    }

    private func handleInterruption(
        type: AVAudioSession.InterruptionType,
        shouldResume: Bool
    ) async {
        #if canImport(AVFoundation)
        switch type {
        case .began:
            engine.pause()
        case .ended:
            guard shouldResume else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        @unknown default:
            break
        }
        #endif
    }
    #else
    private func configureSession() {}
    private func beginObservingInterruptions() {}
    #endif
}
