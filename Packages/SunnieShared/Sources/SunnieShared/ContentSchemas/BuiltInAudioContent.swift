import Foundation

/// The shipping audio manifest.
///
/// Swift rather than JSON, for the reason ADR-022 gives about game content: these
/// entries reference `AmbienceVoice` and `BellPreset`, which are code. A JSON
/// manifest naming a voice that no longer exists would fail at runtime, where
/// this fails to compile. The creator's own manifest — the one in
/// `CreatorAudioSource/` — is JSON, because it describes files rather than code,
/// and the JSON decoder path exists so an added pack can extend this one.
///
/// **What actually makes sound today.** The eight ambiences and the two bells,
/// all synthesised (ADR-029). The music entries are declared and deliberately
/// unplayable: they name the files the creator's rendered tracks will arrive as,
/// and `isPlayable` returns false until those files are in the bundle. That is
/// what lets the theme, destination, and game cue wiring be built and tested now
/// and gain music later with no code change.
///
/// **Noise is deliberately absent.** White, pink, and brown live in
/// `NoiseDSP.swift` behind their own engine because they need a different audio
/// session from everything here (ADR-018). Registering them would put one sound
/// under two owners, and the second owner would be the one with the wrong session
/// policy.
public enum BuiltInAudioContent {

    public static let manifest = AudioManifest(
        version: 1,
        tracks: ambienceTracks + bellTracks + musicTracks
    )

    // MARK: - Ambience

    /// One track per voice, tagged with the screens and cycles it suits.
    ///
    /// The gains differ per voice because the recipes are calibrated to different
    /// peaks — crickets are almost all transient, room tone is almost all bed —
    /// and a single figure would make one of them too quiet to hear and another
    /// too loud to sit under a screen.
    public static let ambienceTracks: [AudioTrackDefinition] = [
        ambience(
            .rainSoft, titleKey: "calm.rain.soft", gain: 0.55,
            contexts: [.wellness, .breathing, .meditation, .afternoon]
        ),
        ambience(
            .rainWindow, titleKey: "calm.rain.window", gain: 0.60,
            contexts: [.wellness, .today, .night]
        ),
        ambience(
            .jungleDay, titleKey: "calm.jungle.day", gain: 0.50,
            contexts: [.jungle, .day, .plantCare, .sunnieHome]
        ),
        ambience(
            .jungleNight, titleKey: "calm.jungle.night", gain: 0.55,
            contexts: [.jungle, .night, .sunnieHome]
        ),
        ambience(
            .oceanWaves, titleKey: "calm.ocean.waves", gain: 0.50,
            contexts: [.wellness, .breathing, .travelScrapbook, .afternoon]
        ),
        ambience(
            .cafeQuiet, titleKey: "calm.cafe.quiet", gain: 0.55,
            contexts: [.game, .travelScrapbook, .afternoon]
        ),
        ambience(
            .nightCrickets, titleKey: "calm.night.crickets", gain: 0.45,
            contexts: [.night, .sunnieHome]
        ),
        ambience(
            .roomToneWarm, titleKey: "calm.roomTone.warm", gain: 0.60,
            contexts: [.today, .game, .meditation]
        )
    ]

    private static func ambience(
        _ voice: AmbienceVoice,
        titleKey: String,
        gain: Double,
        contexts: [AudioContextTag]
    ) -> AudioTrackDefinition {
        AudioTrackDefinition(
            id: voice.cueID,
            titleKey: titleKey,
            sourceType: .procedural,
            proceduralVoice: voice,
            loops: true,
            layer: .ambience,
            contexts: contexts,
            defaultGain: gain
        )
    }

    // MARK: - Bells

    /// The meditation bells (§10). On their own layer so someone who wants the
    /// bells but no ambience — or the reverse — can have exactly that.
    public static let bellTracks: [AudioTrackDefinition] = [
        AudioTrackDefinition(
            id: BellPreset.start.cueID,
            titleKey: "audio.bell.start",
            sourceType: .procedural,
            bell: .start,
            loops: false,
            layer: .meditationBell,
            contexts: [.meditation, .breathing],
            defaultGain: 0.55
        ),
        AudioTrackDefinition(
            id: BellPreset.end.cueID,
            titleKey: "audio.bell.end",
            sourceType: .procedural,
            bell: .end,
            loops: false,
            layer: .meditationBell,
            contexts: [.meditation, .breathing],
            defaultGain: 0.55
        )
    ]

    // MARK: - Music

    /// The creator's rendered tracks.
    ///
    /// Declared before the files exist, on purpose. Each entry is the contract
    /// the creator renders against: this id, this filename, these contexts, this
    /// gain. Dropping `tropical_morning_v1.m4a` into the bundle is the entire
    /// remaining step — no manifest edit, no code change, no rebuild of anything
    /// downstream.
    ///
    /// Until then `isPlayable` is false for all of them and the director skips
    /// them, so the app is silent rather than selecting a track that cannot play.
    /// A selection that makes no sound is worse than no selection: it looks like
    /// a broken speaker.
    public static let musicTracks: [AudioTrackDefinition] = [
        music(
            "sunnie.music.theme.jungle.day",
            asset: "tropical_morning_v1.m4a",
            titleKey: "audio.music.tropicalMorning",
            contexts: [.jungle, .day, .today]
        ),
        music(
            "sunnie.music.theme.jungle.afternoon",
            asset: "long_afternoon_v1.m4a",
            titleKey: "audio.music.longAfternoon",
            contexts: [.jungle, .afternoon]
        ),
        music(
            "sunnie.music.theme.jungle.night",
            asset: "quiet_canopy_v1.m4a",
            titleKey: "audio.music.quietCanopy",
            contexts: [.jungle, .night],
            gain: 0.45
        ),
        music(
            "sunnie.music.screen.game",
            asset: "thinking_room_v1.m4a",
            titleKey: "audio.music.thinkingRoom",
            contexts: [.game],
            gain: 0.40
        ),
        music(
            "sunnie.music.screen.travel",
            asset: "somewhere_else_v1.m4a",
            titleKey: "audio.music.somewhereElse",
            contexts: [.travelScrapbook],
            gain: 0.45
        ),
        music(
            "sunnie.music.moment.reward",
            asset: "small_good_thing_v1.m4a",
            titleKey: "audio.music.smallGoodThing",
            contexts: [.reward],
            gain: 0.50
        ),
        music(
            "sunnie.music.screen.sunnieHome",
            asset: "his_own_place_v1.m4a",
            titleKey: "audio.music.hisOwnPlace",
            contexts: [.sunnieHome],
            gain: 0.45
        )
    ]

    private static func music(
        _ id: ContentID,
        asset: String,
        titleKey: String,
        contexts: [AudioContextTag],
        gain: Double = 0.55
    ) -> AudioTrackDefinition {
        AudioTrackDefinition(
            id: id,
            titleKey: titleKey,
            runtimeAsset: asset,
            sourceType: .renderedAudio,
            loops: true,
            layer: .music,
            contexts: contexts,
            defaultGain: gain
        )
    }
}
