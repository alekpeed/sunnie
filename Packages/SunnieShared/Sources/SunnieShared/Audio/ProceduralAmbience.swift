import Foundation

/// Ambience and bells, computed rather than played from a file (ADR-029).
///
/// The whole signal chain lives here, with no AVFoundation and no imports beyond
/// Foundation — the same discipline `NoiseDSP.swift` follows, and for the same
/// reason: the level, the headroom, the spectral balance, and the determinism can
/// all be verified offline with no audio hardware
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §12). The iOS engine that feeds a render block
/// from this lives in the app target.
///
/// **These are impressions, not recordings.** Nothing here is trying to fool
/// anyone into thinking they are hearing a real forest. The goal is a bed that is
/// pleasant for twenty minutes, that never repeats, and that costs a few
/// multiplies per sample. When the creator's rendered ambiences arrive they take
/// precedence, and the manifest is where that switch happens — no caller changes.
///
/// Everything is built from three ideas:
///
/// 1. **A coloured bed.** Filtered noise from `NoiseChannel`, unvoiced so the
///    recipe applies its own shaping rather than fighting the noise library's.
/// 2. **A slow swell.** One low-frequency oscillator on the bed's amplitude. This
///    is what separates ocean from static: waves are brown noise with a period.
/// 3. **Sparse events.** Droplets, chirps, clinks — short decaying tones fired at
///    random intervals. They are what stops a bed sounding like a machine.
///
/// The render block must not allocate or lock, so the event voices are a
/// fixed-size array sized once in `init` and only ever mutated in place, the RNG
/// is the same xorshift the noise engine uses, and every oscillator is a
/// two-multiply recurrence rather than a `sin` call.

// MARK: - Voices

/// The ambiences that ship.
///
/// One case per `audioCueID` already declared in the wellness content pack, so
/// turning these on required no content change — the sound library has been
/// listing them since Phase 3 and they simply started making sound.
public enum AmbienceVoice: String, Hashable, Sendable, Codable, CaseIterable {
    case rainSoft
    case rainWindow
    case jungleDay
    case jungleNight
    case oceanWaves
    case cafeQuiet
    case nightCrickets
    case roomToneWarm

    /// The cue ID the content pack refers to this by.
    public var cueID: ContentID { ContentID(rawValue: "sunnie.audio.ambience.\(rawValue)") }

    public static func from(cueID: ContentID) -> AmbienceVoice? {
        allCases.first { $0.cueID == cueID }
    }
}

// MARK: - Recipes

/// One ambience's settings, all in one place (§11 of NOISE_IMPLEMENTATION.md's
/// convention, applied here).
///
/// A table rather than eight bespoke synths. Everything that distinguishes rain
/// from crickets is a number in this struct, which means retuning is editing a
/// literal and the tests can assert on the table itself.
public struct AmbienceRecipe: Hashable, Sendable {
    /// The noise colour underneath everything.
    public var bedColor: NoiseColor
    /// How much bed there is *relative to this voice's events*, applied after the
    /// shaping filters and before the swell.
    ///
    /// A balance control, not a level: `AmbienceCalibration` decides how loud the
    /// finished voice plays, by matching every voice's K-weighted loudness. Two
    /// recipes with very different `bedGain` end up equally loud — what differs
    /// is how much of that loudness is bed and how much is events.
    public var bedGain: Double
    public var bedHighPassHz: Double
    public var bedLowPassHz: Double
    /// Negative tilts the top down. A shelf rather than a cut, for the reason
    /// `NoiseTuning` gives: a steep cut leaves a separate hissy layer above the
    /// corner where a shelf blends it into the body.
    public var bedTiltHz: Double
    public var bedTiltDb: Double

    /// Cycles per second of the amplitude swell. 0.08 Hz is a wave about every
    /// twelve seconds, which is roughly ocean.
    public var swellHz: Double
    /// 0 = steady, 1 = the bed falls to silence at the trough.
    public var swellDepth: Double

    /// Average events per second. Sparse by design — a droplet every couple of
    /// seconds reads as rain; forty a second reads as gravel.
    public var eventRate: Double
    public var event: AmbienceEvent?

    public init(
        bedColor: NoiseColor,
        bedGain: Double,
        bedHighPassHz: Double,
        bedLowPassHz: Double,
        bedTiltHz: Double,
        bedTiltDb: Double,
        swellHz: Double,
        swellDepth: Double,
        eventRate: Double,
        event: AmbienceEvent?
    ) {
        self.bedColor = bedColor
        self.bedGain = bedGain
        self.bedHighPassHz = bedHighPassHz
        self.bedLowPassHz = bedLowPassHz
        self.bedTiltHz = bedTiltHz
        self.bedTiltDb = bedTiltDb
        self.swellHz = swellHz
        self.swellDepth = swellDepth
        self.eventRate = eventRate
        self.event = event
    }
}

/// A sparse event: one short decaying tone, possibly repeated.
public struct AmbienceEvent: Hashable, Sendable {
    public var lowestHz: Double
    public var highestHz: Double
    public var shortestDecay: Double
    public var longestDecay: Double
    public var amplitude: Double
    /// A second partial at this ratio, at `partialLevel`. 1 means none. A ratio
    /// that is not a small whole number is what makes a clink sound metallic
    /// rather than musical.
    public var partialRatio: Double
    public var partialLevel: Double
    /// Semitones the pitch glides over the event's life. Negative falls. A
    /// falling glide is most of what makes a tone read as a bird rather than a
    /// beep.
    public var glideSemitones: Double
    /// Some events come in trills — a cricket is not one chirp.
    public var fewestRepeats: Int
    public var mostRepeats: Int
    /// Seconds between repeats within one trill.
    public var repeatGap: Double

    public init(
        lowestHz: Double,
        highestHz: Double,
        shortestDecay: Double,
        longestDecay: Double,
        amplitude: Double,
        partialRatio: Double = 1,
        partialLevel: Double = 0,
        glideSemitones: Double = 0,
        fewestRepeats: Int = 1,
        mostRepeats: Int = 1,
        repeatGap: Double = 0.1
    ) {
        self.lowestHz = lowestHz
        self.highestHz = highestHz
        self.shortestDecay = shortestDecay
        self.longestDecay = longestDecay
        self.amplitude = amplitude
        self.partialRatio = partialRatio
        self.partialLevel = partialLevel
        self.glideSemitones = glideSemitones
        self.fewestRepeats = fewestRepeats
        self.mostRepeats = mostRepeats
        self.repeatGap = repeatGap
    }
}

extension AmbienceVoice {
    /// The tuning table. Every number is taste, and every number is here rather
    /// than scattered through the synth.
    public var recipe: AmbienceRecipe {
        switch self {
        case .rainSoft:
            // Broadband hiss with the very top rolled off, plus frequent
            // droplets high up. Rain is mostly bed; the droplets only need to be
            // present, not prominent.
            AmbienceRecipe(
                bedColor: .pink, bedGain: 0.34,
                bedHighPassHz: 120, bedLowPassHz: 9_000,
                bedTiltHz: 1_400, bedTiltDb: -8,
                swellHz: 0.05, swellDepth: 0.18,
                eventRate: 7.0,
                event: AmbienceEvent(
                    lowestHz: 1_400, highestHz: 4_200,
                    shortestDecay: 0.012, longestDecay: 0.045,
                    amplitude: 0.10, partialRatio: 2.7, partialLevel: 0.3
                )
            )

        case .rainWindow:
            // Heard through glass: the top end is gone and the droplets are
            // fewer, lower, and longer — the glass is what is ringing.
            AmbienceRecipe(
                bedColor: .pink, bedGain: 0.30,
                bedHighPassHz: 80, bedLowPassHz: 2_600,
                bedTiltHz: 700, bedTiltDb: -10,
                swellHz: 0.04, swellDepth: 0.26,
                eventRate: 2.6,
                event: AmbienceEvent(
                    lowestHz: 320, highestHz: 900,
                    shortestDecay: 0.05, longestDecay: 0.16,
                    amplitude: 0.16, partialRatio: 3.4, partialLevel: 0.22,
                    glideSemitones: -2
                )
            )

        case .jungleDay:
            // A warm mid bed with occasional falling bird calls. The glide is
            // load-bearing: a flat tone at these frequencies is a smoke alarm.
            AmbienceRecipe(
                bedColor: .pink, bedGain: 0.24,
                bedHighPassHz: 200, bedLowPassHz: 5_500,
                bedTiltHz: 1_800, bedTiltDb: -6,
                swellHz: 0.06, swellDepth: 0.22,
                eventRate: 0.55,
                event: AmbienceEvent(
                    lowestHz: 1_100, highestHz: 2_800,
                    shortestDecay: 0.08, longestDecay: 0.22,
                    amplitude: 0.20, partialRatio: 2.02, partialLevel: 0.18,
                    glideSemitones: -5,
                    fewestRepeats: 1, mostRepeats: 3, repeatGap: 0.17
                )
            )

        case .jungleNight:
            // Darker and quieter, with lower, slower calls than the day.
            AmbienceRecipe(
                bedColor: .brown, bedGain: 0.30,
                bedHighPassHz: 60, bedLowPassHz: 2_200,
                bedTiltHz: 900, bedTiltDb: -9,
                swellHz: 0.035, swellDepth: 0.24,
                eventRate: 0.9,
                event: AmbienceEvent(
                    lowestHz: 500, highestHz: 1_500,
                    shortestDecay: 0.10, longestDecay: 0.30,
                    amplitude: 0.14, partialRatio: 1.51, partialLevel: 0.24,
                    glideSemitones: -3,
                    fewestRepeats: 1, mostRepeats: 4, repeatGap: 0.24
                )
            )

        case .oceanWaves:
            // Brown noise with a deep, slow swell and no events at all. The
            // swell is the entire sound: at depth 0 this is just brown noise.
            AmbienceRecipe(
                bedColor: .brown, bedGain: 0.46,
                bedHighPassHz: 40, bedLowPassHz: 3_200,
                bedTiltHz: 800, bedTiltDb: -4,
                swellHz: 0.085, swellDepth: 0.62,
                eventRate: 0,
                event: nil
            )

        case .cafeQuiet:
            // A murmur, not a conversation. Heavily filtered noise for the room
            // and the voices, with rare high clinks for cups. Deliberately
            // abstract — synthesised speech babble would be uncanny, and this
            // only has to read as "somewhere with people in it".
            AmbienceRecipe(
                bedColor: .brown, bedGain: 0.28,
                bedHighPassHz: 90, bedLowPassHz: 1_100,
                bedTiltHz: 500, bedTiltDb: -6,
                swellHz: 0.14, swellDepth: 0.34,
                eventRate: 0.28,
                event: AmbienceEvent(
                    lowestHz: 2_200, highestHz: 4_800,
                    shortestDecay: 0.09, longestDecay: 0.26,
                    amplitude: 0.09, partialRatio: 3.77, partialLevel: 0.45
                )
            )

        case .nightCrickets:
            // Almost no bed, and trills rather than single chirps. Crickets are
            // the one voice where the events carry the sound and the bed is only
            // there so the gaps are not digital silence.
            AmbienceRecipe(
                bedColor: .brown, bedGain: 0.14,
                bedHighPassHz: 50, bedLowPassHz: 900,
                bedTiltHz: 400, bedTiltDb: -8,
                swellHz: 0.03, swellDepth: 0.20,
                eventRate: 1.4,
                event: AmbienceEvent(
                    lowestHz: 3_600, highestHz: 4_800,
                    shortestDecay: 0.018, longestDecay: 0.035,
                    amplitude: 0.13, partialRatio: 2.0, partialLevel: 0.35,
                    fewestRepeats: 3, mostRepeats: 7, repeatGap: 0.055
                )
            )

        case .roomToneWarm:
            // The quietest thing here on purpose. A room that is not silent, for
            // people who find silence loud.
            AmbienceRecipe(
                bedColor: .brown, bedGain: 0.26,
                bedHighPassHz: 45, bedLowPassHz: 700,
                bedTiltHz: 300, bedTiltDb: -5,
                swellHz: 0.02, swellDepth: 0.12,
                eventRate: 0,
                event: nil
            )
        }
    }
}

// MARK: - Oscillator

/// A sine, as a two-multiply recurrence rather than a `sin` call.
///
/// The "magic circle" form: two state variables rotating around the origin. It
/// stays stable indefinitely at these frequencies, retunes by assigning `k`, and
/// costs nothing — which matters because a render block may hold a dozen of
/// these and must not call into libm per sample.
public struct SineOscillator: Sendable {
    private var sinState: Double
    private var cosState: Double
    private var k: Double

    public init(frequency: Double, sampleRate: Double, phase: Double = 0) {
        self.sinState = sin(phase)
        self.cosState = cos(phase)
        self.k = 2 * sin(.pi * max(frequency, 0) / sampleRate)
    }

    public mutating func setFrequency(_ frequency: Double, sampleRate: Double) {
        k = 2 * sin(.pi * max(frequency, 0) / sampleRate)
    }

    public mutating func next() -> Double {
        sinState += k * cosState
        cosState -= k * sinState
        return sinState
    }
}

// MARK: - Event voice

/// One decaying tone. Silent until triggered, and silent again afterwards.
///
/// Two partials rather than one because a single sine reads as electronic. The
/// second partial's ratio is what carries the character: 2.0 is musical, 2.7 and
/// 3.77 are metallic, and that difference is most of what separates a cup being
/// set down from a note.
public struct AmbienceEventVoice: Sendable {
    private var fundamental = SineOscillator(frequency: 0, sampleRate: 48_000)
    private var partial = SineOscillator(frequency: 0, sampleRate: 48_000)
    private var partialLevel = 0.0
    private var amplitude = 0.0
    private var decayCoefficient = 0.0
    private var glidePerSample = 1.0
    private var frequency = 0.0
    private var partialRatio = 1.0
    private var sampleRate = 48_000.0
    private var samplesLeft = 0

    public init() {}

    public var isActive: Bool { samplesLeft > 0 }

    public mutating func trigger(
        frequency: Double,
        amplitude: Double,
        decaySeconds: Double,
        partialRatio: Double,
        partialLevel: Double,
        glideSemitones: Double,
        sampleRate: Double
    ) {
        self.sampleRate = sampleRate
        self.frequency = max(frequency, 1)
        self.partialRatio = max(partialRatio, 1)
        self.partialLevel = max(partialLevel, 0)
        self.amplitude = amplitude
        // A phase of a quarter turn starts the recurrence at its peak, so the
        // event begins with a transient rather than fading up from zero.
        fundamental = SineOscillator(
            frequency: self.frequency, sampleRate: sampleRate, phase: .pi / 2
        )
        partial = SineOscillator(
            frequency: self.frequency * self.partialRatio,
            sampleRate: sampleRate, phase: .pi / 2
        )

        let decay = max(decaySeconds, 0.001)
        // Exponential decay reaching about −60 dB at the stated duration, which
        // is what makes "decay seconds" mean the audible length rather than a
        // time constant.
        decayCoefficient = exp(-6.9078 / (decay * sampleRate))
        // The glide is applied to the frequency each sample, so the total shift
        // over the event's life is the stated interval.
        let ratio = pow(2.0, glideSemitones / 12.0)
        glidePerSample = glideSemitones == 0 ? 1 : pow(ratio, 1.0 / (decay * sampleRate))
        samplesLeft = Int(decay * sampleRate)
    }

    public mutating func next() -> Double {
        guard samplesLeft > 0 else { return 0 }
        samplesLeft -= 1

        if glidePerSample != 1 {
            frequency *= glidePerSample
            fundamental.setFrequency(frequency, sampleRate: sampleRate)
            partial.setFrequency(frequency * partialRatio, sampleRate: sampleRate)
        }

        let value = (fundamental.next() + partial.next() * partialLevel) * amplitude
        amplitude *= decayCoefficient
        return value
    }
}

// MARK: - Channel

/// One channel of one ambience: bed, shaping, swell, and sparse events.
///
/// A value type sized once at construction, so a render block can hold two — one
/// per channel, with independent seeds — and call `next()` per frame. The voice
/// array is allocated in `init` and only ever mutated in place afterwards; it is
/// uniquely referenced, so the copy-on-write check is a branch rather than a
/// heap touch. Independence between the channels is what makes the result sound
/// wide rather than collapsing to a point inside the head, which is the same
/// lesson `NoiseChannel` documents.
public struct AmbienceChannel: Sendable {
    /// Enough for the densest recipe's trills without ever allocating. Rain at
    /// seven events a second with a 45 ms decay needs one; crickets in a
    /// seven-chirp trill need a handful. Twelve is comfortable headroom, and an
    /// overflowing event is simply not fired rather than stealing a voice
    /// mid-decay.
    public static let voiceCount = 12

    private let recipe: AmbienceRecipe
    private let sampleRate: Double
    private var rng: XorShift64
    private var bed: NoiseChannel
    private var highPass: Biquad
    private var lowPass: Biquad
    private var tilt: Biquad
    private var swell: SineOscillator
    private var voices: [AmbienceEventVoice]
    /// Samples until the next event fires.
    private var samplesToNextEvent: Int
    /// Repeats left in the current trill, and the gap between them.
    private var repeatsLeft = 0
    private var repeatGapSamples = 0
    private var trillFrequency = 0.0
    private var trillDecay = 0.0
    /// Applied last. 1 during calibration, the measured figure in playback.
    private let outputGain: Double

    public init(
        voice: AmbienceVoice,
        seed: UInt64,
        sampleRate: Double = NoiseTuning.sampleRate,
        gain: Double = 1.0
    ) {
        self.outputGain = gain
        let recipe = voice.recipe
        self.recipe = recipe
        self.sampleRate = sampleRate
        self.rng = XorShift64(seed: seed)
        // Unvoiced: the recipe below applies its own shaping, and the noise
        // library's taste settings would fight it.
        self.bed = NoiseChannel(
            color: recipe.bedColor, seed: seed &+ 0x5EED, sampleRate: sampleRate, voiced: false
        )
        self.highPass = BiquadDesign.highPass(sampleRate, recipe.bedHighPassHz)
        self.lowPass = BiquadDesign.lowPass(
            sampleRate, min(recipe.bedLowPassHz, sampleRate * 0.45)
        )
        self.tilt = BiquadDesign.highShelf(
            sampleRate, recipe.bedTiltHz, gainDb: recipe.bedTiltDb
        )
        // A quarter turn back, so the swell starts at its trough and rises.
        // Starting at a peak would make every ambience begin at full level,
        // which reads as a click.
        self.swell = SineOscillator(
            frequency: recipe.swellHz, sampleRate: sampleRate, phase: -.pi / 2
        )
        self.voices = Array(repeating: AmbienceEventVoice(), count: Self.voiceCount)
        self.samplesToNextEvent = 0
        // Seeded here rather than at zero so two channels do not fire their
        // first event on the same sample.
        self.samplesToNextEvent = nextInterval()
    }

    /// Poisson-ish spacing: an exponential draw, so events cluster the way real
    /// ones do instead of arriving on a grid. A grid is instantly recognisable
    /// as artificial even at seven events a second.
    private mutating func nextInterval() -> Int {
        guard recipe.eventRate > 0 else { return .max }
        // `nextUniform` is in [-1, 1); mapped to (0, 1] so the log is finite.
        let u = max((rng.nextUniform() + 1) / 2, 1e-9)
        let seconds = -log(u) / recipe.eventRate
        return max(1, Int(seconds * sampleRate))
    }

    private mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * (rng.nextUniform() + 1) / 2
    }

    private mutating func fireEvent(frequency: Double, decay: Double) {
        guard let event = recipe.event else { return }
        // First free voice. If every one is busy the event is dropped, which is
        // inaudible at these densities and is the only allocation-free answer.
        guard let index = voices.firstIndex(where: { !$0.isActive }) else { return }
        voices[index].trigger(
            frequency: frequency,
            amplitude: event.amplitude,
            decaySeconds: decay,
            partialRatio: event.partialRatio,
            partialLevel: event.partialLevel,
            glideSemitones: event.glideSemitones,
            sampleRate: sampleRate
        )
    }

    public mutating func next() -> Double {
        // Bed: colour, shaping, tilt.
        var sample = bed.next()
        sample = highPass.process(sample)
        sample = lowPass.process(sample)
        sample = tilt.process(sample)

        // Swell: a unipolar 0…1 multiplier at the stated depth. At depth 0 the
        // bed is steady; at depth 1 it reaches silence at the trough.
        let lfo = (swell.next() + 1) / 2
        let envelope = 1 - recipe.swellDepth + recipe.swellDepth * lfo
        sample *= recipe.bedGain * envelope

        // Events.
        if let event = recipe.event {
            if repeatsLeft > 0 {
                repeatGapSamples -= 1
                if repeatGapSamples <= 0 {
                    repeatsLeft -= 1
                    fireEvent(frequency: trillFrequency, decay: trillDecay)
                    repeatGapSamples = max(1, Int(event.repeatGap * sampleRate))
                }
            } else {
                samplesToNextEvent -= 1
                if samplesToNextEvent <= 0 {
                    // One pitch and one decay for the whole trill: a cricket
                    // repeats the same chirp, it does not play a scale.
                    trillFrequency = uniform(event.lowestHz, event.highestHz)
                    trillDecay = uniform(event.shortestDecay, event.longestDecay)
                    let span = max(0, event.mostRepeats - event.fewestRepeats)
                    let extra = span == 0 ? 0 : Int(uniform(0, Double(span) + 0.999))
                    repeatsLeft = max(0, event.fewestRepeats + min(extra, span) - 1)
                    repeatGapSamples = max(1, Int(event.repeatGap * sampleRate))
                    fireEvent(frequency: trillFrequency, decay: trillDecay)
                    samplesToNextEvent = nextInterval()
                }
            }

            for index in voices.indices where voices[index].isActive {
                sample += voices[index].next()
            }
        }

        return sample * outputGain
    }
}

// MARK: - Calibration

/// Matches the voices to one another by loudness, and to the headroom by peak.
///
/// Exactly the algorithm `NoiseCalibration` uses, for exactly the same reasons —
/// and the reasons are worth repeating, because both are easy to get wrong in a
/// way that still "works":
///
/// 1. **Match loudness, not RMS or peak.** Crickets are almost all transient and
///    room tone is almost all bed; matched by peak, the crickets would be far too
///    quiet, and matched by RMS the ocean's low end would be, because the ear is
///    least sensitive exactly where its energy sits.
/// 2. **Derive the shared level from the *worst* peak.** One target loudness at
///    which every voice still fits under the ceiling, so switching beds never
///    changes the perceived level and never clips.
///
/// This is what makes `AmbienceRecipe.bedGain` a *balance* control — how much bed
/// there is relative to that voice's events — rather than a level. Retuning it
/// changes the character; the overall level is decided here.
public enum AmbienceCalibration {

    /// Ten seconds. Far longer than the noise calibration's half second, because
    /// these signals have slow structure: a twelve-second ocean swell or a
    /// cricket trill every few seconds is invisible in a short window, and a peak
    /// measured over one would be a serious underestimate.
    private static let measureSamples = 480_000

    /// Fixed seeds rather than `hashValue`, which is seeded per process and would
    /// make the calibration drift slightly on every launch.
    private static func seeds(for voice: AmbienceVoice) -> (loudness: UInt64, peak: UInt64) {
        // Derived from the case's position so a new voice needs no table entry,
        // and stable because `allCases` order is the declaration order.
        let index = UInt64(AmbienceVoice.allCases.firstIndex(of: voice) ?? 0)
        return (0x00A0_0001 &+ index &* 2, 0x00A0_0002 &+ index &* 2)
    }

    private struct Unity: Sendable {
        let loudness: Double
        let peak: Double
    }

    /// Measured once, lazily. Deterministic, because the generators are.
    private static let unity: [AmbienceVoice: Unity] = {
        var result = [AmbienceVoice: Unity]()
        for voice in AmbienceVoice.allCases {
            let seed = seeds(for: voice)

            var loudChannel = AmbienceChannel(voice: voice, seed: seed.loudness)
            let loudness = Loudness.kWeightedRms(measureSamples) { loudChannel.next() }

            var peakChannel = AmbienceChannel(voice: voice, seed: seed.peak)
            let peak = Loudness.peak(measureSamples) { peakChannel.next() }

            result[voice] = Unity(loudness: loudness, peak: max(peak, 1e-9))
        }
        return result
    }()

    /// The loudest shared level at which *every* voice still peaks below the
    /// ceiling, with a margin for seeds other than the measured one.
    ///
    /// The margin is not decoration. Calibration measures one seed per voice, and
    /// these are stochastic signals: an offline sweep of eight seeds found the
    /// worst peak drifting to about 0.89 against a 0.80 ceiling — nowhere near
    /// clipping, since the limiter sits at 0.97, but past the headroom the
    /// calibration is supposed to guarantee. Scaling by 0.85 brings the worst
    /// observed case back under the ceiling and costs about 1.4 dB, which is
    /// inaudible next to a limiter working continuously.
    public static let peakSafetyFactor = 0.85

    public static let targetLoudness: Double = (unity.values
        .map { AmbienceTuning.peakCeiling * $0.loudness / $0.peak }
        .min() ?? 0.1) * peakSafetyFactor

    public static func gain(for voice: AmbienceVoice) -> Double {
        guard let measured = unity[voice], measured.loudness > 0 else { return 1 }
        return targetLoudness / measured.loudness
    }

    /// A playback-ready, calibrated channel.
    public static func channel(
        _ voice: AmbienceVoice,
        seed: UInt64,
        sampleRate: Double = NoiseTuning.sampleRate
    ) -> AmbienceChannel {
        AmbienceChannel(
            voice: voice, seed: seed, sampleRate: sampleRate, gain: gain(for: voice)
        )
    }
}

// MARK: - Bells

/// The start and end bells of a meditation (§10).
///
/// Two presets rather than one sound played twice: the end bell sits lower and
/// rings longer, which is the difference between "begin" and "that is finished".
public enum BellPreset: String, Hashable, Sendable, Codable, CaseIterable {
    case start
    case end

    public var cueID: ContentID { ContentID(rawValue: "sunnie.audio.bell.\(rawValue)") }

    public static func from(cueID: ContentID) -> BellPreset? {
        allCases.first { $0.cueID == cueID }
    }

    /// Fundamental in hertz.
    public var frequency: Double {
        switch self {
        case .start: 528
        case .end: 396
        }
    }

    /// Seconds to inaudibility.
    public var decaySeconds: Double {
        switch self {
        case .start: 3.5
        case .end: 6.0
        }
    }
}

/// A struck bowl: inharmonic partials, each decaying at its own rate.
///
/// The two things that make it read as a bowl rather than an organ:
///
/// 1. **The partials are not whole-number multiples.** A harmonic series sounds
///    like a wind instrument. The ratios below are close to a real singing bowl's.
/// 2. **High partials die first.** A bell is bright at the strike and dark a
///    second later. Equal decay rates sound synthetic no matter how the partials
///    are tuned.
public struct BellVoice: Sendable {
    /// Ratio, level, and decay multiplier per partial.
    private static let partials: [(ratio: Double, level: Double, decay: Double)] = [
        (ratio: 1.00, level: 1.00, decay: 1.00),
        (ratio: 2.34, level: 0.42, decay: 0.55),
        (ratio: 3.77, level: 0.24, decay: 0.33),
        (ratio: 5.18, level: 0.13, decay: 0.20),
        (ratio: 6.94, level: 0.07, decay: 0.13)
    ]

    private var oscillators: [SineOscillator]
    private var amplitudes: [Double]
    private var decays: [Double]
    private var samplesLeft: Int
    private let gain: Double

    public init(
        preset: BellPreset,
        sampleRate: Double = NoiseTuning.sampleRate,
        gain: Double = 0.55
    ) {
        self.gain = gain
        let base = preset.frequency
        let decay = preset.decaySeconds
        var oscillators: [SineOscillator] = []
        var amplitudes: [Double] = []
        var decays: [Double] = []
        var levelSum = 0.0

        for partial in Self.partials {
            let frequency = base * partial.ratio
            // Above Nyquist a partial would alias into an audible tone that is
            // not part of the bell at all, so it is dropped instead.
            guard frequency < sampleRate * 0.45 else { continue }
            oscillators.append(
                SineOscillator(frequency: frequency, sampleRate: sampleRate, phase: .pi / 2)
            )
            amplitudes.append(partial.level)
            decays.append(exp(-6.9078 / (decay * partial.decay * sampleRate)))
            levelSum += partial.level
        }

        // Normalised by the sum of the partial levels, so the strike peaks near
        // `gain` rather than at whatever the partial table happens to add up to.
        // Without this, adding a partial makes every bell louder.
        let normalise = levelSum > 0 ? 1 / levelSum : 1
        self.oscillators = oscillators
        self.amplitudes = amplitudes.map { $0 * normalise }
        self.decays = decays
        self.samplesLeft = Int(decay * sampleRate)
    }

    public var isActive: Bool { samplesLeft > 0 }

    public mutating func next() -> Double {
        guard samplesLeft > 0 else { return 0 }
        samplesLeft -= 1

        var sample = 0.0
        for index in oscillators.indices {
            sample += oscillators[index].next() * amplitudes[index]
            amplitudes[index] *= decays[index]
        }
        return sample * gain
    }
}

// MARK: - Tuning

/// Levels and headroom for the procedural layer, in one place.
public enum AmbienceTuning {
    /// Peak the recipes are calibrated to leave, so the limiter only catches
    /// occasional transients rather than working continuously. The same figure
    /// the noise engine uses, for the same reason.
    public static let peakCeiling = NoiseTuning.peakCeiling

    /// Seeds for the two playback channels. Different from the noise engine's so
    /// that noise and ambience never accidentally correlate if both were ever
    /// audible at once.
    public enum PlaybackSeed {
        public static let left: UInt64 = 0x5A17_C0FF_EE01
        public static let right: UInt64 = 0xB0A7_D00D_5EED
    }

    /// Default crossfade between two ambiences, in seconds.
    public static let crossfadeSeconds = 2.5
}
