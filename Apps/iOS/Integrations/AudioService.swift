import Foundation
import SunnieShared
#if canImport(AVFAudio)
import AVFAudio
#endif

/// Audio playback boundary.
///
/// A shell for Phase 1. It owns the audio session and honours preferences, but
/// no rendered assets ship yet — the creator's music arrives in Phase 10. Calls
/// resolve a content ID against the audio manifest and no-op when the asset is
/// absent, so features can wire up cues now and gain sound later without change.
///
/// Vanessa never sees MIDI. Source MIDI is creator-side only and does not appear
/// in the app or its bundle (ADR-006).
actor AudioService: AudioPlaying {

    private let log = SunnieLog(category: .audio)
    private var preferences = AudioPreferences()
    private var isSessionConfigured = false
    private var sleepTimer: Task<Void, Never>?
    /// What was playing when an interruption arrived, so it can resume.
    private var interruptedAmbienceID: ContentID?

    #if canImport(AVFAudio)
    private var ambiencePlayer: AVAudioPlayer?
    private var observers: [any NSObjectProtocol] = []
    #endif

    /// Starts listening for interruptions and route changes.
    ///
    /// A phone call should pause ambience and resume it afterwards; unplugging
    /// headphones should stop it rather than suddenly playing rain out loud in a
    /// quiet room (WELLNESS_JOURNAL_AND_CALM.md §9, interruption handling).
    func beginObservingInterruptions() {
        #if canImport(AVFAudio)
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil
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
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                reason == .oldDeviceUnavailable
            else { return }
            // Headphones came out. Stop rather than switch to the speaker.
            Task { await self?.stopAmbience() }
        })
        #endif
    }

    #if canImport(AVFAudio)
    private func handleInterruption(
        type: AVAudioSession.InterruptionType,
        shouldResume: Bool
    ) async {
        switch type {
        case .began:
            interruptedAmbienceID = currentAmbienceID
            ambiencePlayer?.pause()
        case .ended:
            guard shouldResume, let resumeID = interruptedAmbienceID else {
                interruptedAmbienceID = nil
                return
            }
            interruptedAmbienceID = nil
            await startAmbience(resumeID)
        @unknown default:
            break
        }
    }
    #endif

    private var currentAmbienceID: ContentID?

    /// Fades ambience out after a number of minutes.
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
        #if canImport(AVFAudio)
        guard let player = ambiencePlayer else { return }
        let steps = 20
        let startVolume = player.volume
        for step in 0..<steps {
            guard !Task.isCancelled else { return }
            player.volume = startVolume * Float(steps - step - 1) / Float(steps)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        #endif
        await stopAmbience()
    }

    func apply(preferences: AudioPreferences) async {
        self.preferences = preferences
        #if canImport(AVFAudio)
        ambiencePlayer?.volume = Float(preferences.masterGain)
        if !preferences.ambienceEnabled {
            await stopAmbience()
        }
        #endif
    }

    func playCue(_ cueID: ContentID) async {
        guard preferences.effectsEnabled else { return }
        guard let url = assetURL(for: cueID) else {
            log.debug("No audio asset for cue \(cueID.rawValue); skipping playback.")
            return
        }
        #if canImport(AVFAudio)
        configureSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(preferences.masterGain)
        player.play()
        #endif
    }

    func startAmbience(_ cueID: ContentID) async {
        guard preferences.ambienceEnabled else { return }
        currentAmbienceID = cueID
        guard let url = assetURL(for: cueID) else {
            // No asset yet — Phase 10 supplies these. The selection is still
            // recorded so the UI can show what is chosen.
            return
        }
        #if canImport(AVFAudio)
        configureSessionIfNeeded()
        beginObservingInterruptions()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = Float(preferences.masterGain)
        player.play()
        ambiencePlayer = player
        #endif
    }

    func stopAmbience() async {
        cancelSleepTimer()
        currentAmbienceID = nil
        #if canImport(AVFAudio)
        ambiencePlayer?.stop()
        ambiencePlayer = nil
        #endif
    }

    /// What is currently selected, so the sound library can show it.
    func playingCueID() -> ContentID? { currentAmbienceID }

    /// Resolves a content ID to a bundled asset. Returns nil until Phase 10
    /// populates the audio manifest.
    private func assetURL(for cueID: ContentID) -> URL? {
        Bundle.main.url(forResource: cueID.rawValue, withExtension: "caf")
            ?? Bundle.main.url(forResource: cueID.rawValue, withExtension: "m4a")
    }

    #if canImport(AVFAudio)
    /// `.ambient` means Sunnie's audio never interrupts the user's music or
    /// podcast, and respects the ring/silent switch.
    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionConfigured = true
        } catch {
            log.debug("Audio session could not be configured.")
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
}
