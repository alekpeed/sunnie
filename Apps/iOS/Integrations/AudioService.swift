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

    #if canImport(AVFAudio)
    private var ambiencePlayer: AVAudioPlayer?
    #endif

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
        guard let url = assetURL(for: cueID) else { return }
        #if canImport(AVFAudio)
        configureSessionIfNeeded()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = Float(preferences.masterGain)
        player.play()
        ambiencePlayer = player
        #endif
    }

    func stopAmbience() async {
        #if canImport(AVFAudio)
        ambiencePlayer?.stop()
        ambiencePlayer = nil
        #endif
    }

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
