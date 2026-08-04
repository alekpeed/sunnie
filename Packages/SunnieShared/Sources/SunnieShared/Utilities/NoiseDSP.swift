import Foundation

/// White, pink, and brown noise, generated rather than played from a file
/// (NOISE_IMPLEMENTATION.md).
///
/// This file is the whole signal chain and is deliberately platform-neutral: no
/// AVFoundation, no imports beyond Foundation. That is what lets the spectral
/// slope, the loudness match, the headroom, and the channel decorrelation all be
/// verified offline, with no audio hardware and no device
/// (NOISE_IMPLEMENTATION.md §8). The iOS engine that feeds a render block from
/// this lives in the app target.
///
/// Four things carry most of the perceived quality, and each is easy to get
/// wrong in a way that still "works":
///
/// 1. **The two channels must be independent generators.** Copying one mono
///    stream to both sounds identical to mono — it collapses to a point inside
///    the head. Independence is what makes noise sound wide.
/// 2. **The top end is voiced down.** A mathematically correct colour carries far
///    more high-frequency energy than people expect of that colour. Untreated
///    white hisses; untreated pink reads as hiss sitting on a low end.
/// 3. **Colours are matched by K-weighted loudness, not RMS.** Brown's energy
///    sits where the ear is least sensitive, so equal RMS leaves it much quieter.
/// 4. Continuous playback is a platform problem, not a DSP one.
public enum NoiseColor: String, Hashable, Sendable, Codable, CaseIterable {
    case white
    case pink
    case brown

    public var localizationKey: String { "noise.\(rawValue)" }

    /// Content ID, so generated noise sits in the calm-sound library alongside
    /// the recorded ambiences rather than being a separate kind of thing.
    public var contentID: ContentID { ContentID(rawValue: "sunnie.calm.noise.\(rawValue)") }

    /// Resolves a calm sound back to a colour. Nil for a recorded ambience.
    public static func from(contentID: ContentID) -> NoiseColor? {
        allCases.first { $0.contentID == contentID }
    }
}

// MARK: - Random

/// xorshift64*, used because nothing may allocate or lock inside an audio render
/// block and `SystemRandomNumberGenerator` does both. Deterministic, so the
/// calibration below is reproducible and the tests are not flaky.
public struct XorShift64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Any non-zero state works; mixing means small seeds still decorrelate
        // immediately rather than producing correlated early samples.
        self.state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    /// Uniform in [-1, 1).
    public mutating func nextUniform() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 2_685_821_657_736_338_717
        // Top 53 bits → [0, 1), then mapped to [-1, 1).
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0) * 2.0 - 1.0
    }
}

// MARK: - Biquad

/// Direct-form 1 biquad. Stateful, so one instance per filter *per channel* —
/// sharing one between channels would correlate them, which is the one thing
/// this whole design is trying to avoid.
public struct Biquad: Sendable {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

/// RBJ cookbook coefficients, designed from the live sample rate so the filters
/// stay correct if the audio session lands somewhere other than 48 kHz.
public enum BiquadDesign {
    public static let butterworthQ = 0.707_106_781_186_547_6

    public static func highPass(
        _ fs: Double, _ f0: Double, q: Double = butterworthQ
    ) -> Biquad {
        let w0 = 2 * .pi * f0 / fs, cw = cos(w0), alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(
            b0: ((1 + cw) / 2) / a0, b1: (-(1 + cw)) / a0, b2: ((1 + cw) / 2) / a0,
            a1: (-2 * cw) / a0, a2: (1 - alpha) / a0
        )
    }

    public static func lowPass(
        _ fs: Double, _ f0: Double, q: Double = butterworthQ
    ) -> Biquad {
        let w0 = 2 * .pi * f0 / fs, cw = cos(w0), alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(
            b0: ((1 - cw) / 2) / a0, b1: (1 - cw) / a0, b2: ((1 - cw) / 2) / a0,
            a1: (-2 * cw) / a0, a2: (1 - alpha) / a0
        )
    }

    public static func highShelf(
        _ fs: Double, _ f0: Double, gainDb: Double, q: Double = butterworthQ
    ) -> Biquad {
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2 * .pi * f0 / fs, cw = cos(w0)
        let alpha = sin(w0) / 2 * (((A + 1 / A) * (1 / q - 1) + 2)).squareRoot()
        let t = 2 * A.squareRoot() * alpha
        let a0 = (A + 1) - (A - 1) * cw + t
        return Biquad(
            b0: (A * ((A + 1) + (A - 1) * cw + t)) / a0,
            b1: (-2 * A * ((A - 1) + (A + 1) * cw)) / a0,
            b2: (A * ((A + 1) + (A - 1) * cw - t)) / a0,
            a1: (2 * ((A - 1) - (A + 1) * cw)) / a0,
            a2: ((A + 1) - (A - 1) * cw - t) / a0
        )
    }

    /// Only used by the offline verification helpers.
    public static func bandPass(_ fs: Double, _ f0: Double, q: Double) -> Biquad {
        let w0 = 2 * .pi * f0 / fs, cw = cos(w0), alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(
            b0: alpha / a0, b1: 0, b2: -alpha / a0,
            a1: (-2 * cw) / a0, a2: (1 - alpha) / a0
        )
    }
}

// MARK: - Colour filters

/// Paul Kellett's pink approximation: about −3 dB per octave, accurate to well
/// within a dB across the audible band. The `0.11` output scale is load-bearing —
/// the calibration assumes it.
public struct PinkFilter: Sendable {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0

    public init() {}

    public mutating func process(_ w: Double) -> Double {
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return pink * 0.11
    }
}

/// Leaky integrator: about −6 dB per octave above its corner.
///
/// The corner sits *below* the audible band so brown keeps its deep weight, and
/// the shared 30 Hz high-pass deals with the subsonic energy. Raising the corner
/// to control rumble audibly thins the low end — it is the wrong fix.
public struct BrownFilter: Sendable {
    private let pole: Double
    private let drive: Double
    private var state = 0.0

    public init(pole: Double) {
        self.pole = pole
        self.drive = 1 - pole
    }

    public mutating func process(_ w: Double) -> Double {
        state = pole * state + drive * w
        return state
    }
}

// MARK: - Tuning

/// Every tuned constant in one place (NOISE_IMPLEMENTATION.md §11).
public enum NoiseTuning {
    /// 48 kHz is native on iOS hardware, so nothing resamples on the way out, and
    /// it is the rate the K-weighting coefficients are defined at.
    public static let sampleRate = 48_000.0

    /// Removes inaudible subsonic energy that otherwise eats headroom and moves
    /// speakers for nothing.
    public static let highPassHz = 30.0
    public static let lowPassHz = 18_000.0

    public static let brownCornerHz = 18.0
    public static var brownPole: Double { exp(-2 * .pi * brownCornerHz / sampleRate) }

    // Voicing — taste settings, not definitions of the colours. Every one exists
    // because the mathematically correct version was judged too bright. Raise the
    // shelf gain (towards −6) for brighter, lower it for darker.
    //
    // A shelf rather than a cut alone for white and pink: a steep cut leaves
    // whatever survives above the corner audible as a separate hissy layer, where
    // a shelf tilts the whole top down so it blends into the body of the sound.
    public static let whiteShelfHz = 2_000.0
    public static let whiteShelfDb = -12.0
    public static let whiteTopHz = 8_000.0

    public static let pinkShelfHz = 1_200.0
    public static let pinkShelfDb = -18.0
    public static let pinkTopHz = 9_000.0

    public static let brownTopHz = 1_600.0   // applied twice

    /// Headroom the calibration guarantees, so the limiter only ever catches
    /// occasional transients rather than working continuously.
    public static let peakCeiling = 0.80

    public static let limiterThreshold = 0.97
    public static let limiterReleaseSeconds = 0.25
}

// MARK: - One channel

/// One channel of shaped noise: colour, shared filters, voicing, calibrated gain.
///
/// A value type with no allocation after construction, so a render block can hold
/// two of these and call `next()` per frame without touching the heap.
public struct NoiseChannel: Sendable {
    private let color: NoiseColor
    private var rng: XorShift64
    private var pink = PinkFilter()
    private var brown: BrownFilter
    private var highPass: Biquad
    private var lowPass: Biquad
    /// Fixed-size rather than an array, so `next()` cannot touch the heap and the
    /// per-sample cost is a pair of predictable branches. No colour needs more
    /// than two voicing stages.
    private var voicing1: Biquad?
    private var voicing2: Biquad?
    private let gain: Double

    /// `voiced: false` bypasses the taste settings so the colour maths can be
    /// verified separately. Without this switch, retuning the voicing would
    /// silently break the spectral-slope assertions
    /// (NOISE_IMPLEMENTATION.md §8).
    public init(
        color: NoiseColor,
        seed: UInt64,
        sampleRate: Double = NoiseTuning.sampleRate,
        gain: Double = 1.0,
        voiced: Bool = true
    ) {
        self.color = color
        self.rng = XorShift64(seed: seed)
        self.brown = BrownFilter(
            pole: exp(-2 * .pi * NoiseTuning.brownCornerHz / sampleRate)
        )
        self.highPass = BiquadDesign.highPass(sampleRate, NoiseTuning.highPassHz)
        // Never above Nyquist: a session that lands at 44.1 kHz would otherwise
        // design an 18 kHz low-pass against a 22.05 kHz Nyquist, which is fine,
        // but a lower rate would produce nonsense coefficients.
        self.lowPass = BiquadDesign.lowPass(
            sampleRate, min(NoiseTuning.lowPassHz, sampleRate * 0.45)
        )
        self.gain = gain

        guard voiced else {
            self.voicing1 = nil
            self.voicing2 = nil
            return
        }

        switch color {
        case .white:
            voicing1 = BiquadDesign.highShelf(
                sampleRate, NoiseTuning.whiteShelfHz, gainDb: NoiseTuning.whiteShelfDb
            )
            voicing2 = BiquadDesign.lowPass(sampleRate, NoiseTuning.whiteTopHz)
        case .pink:
            voicing1 = BiquadDesign.highShelf(
                sampleRate, NoiseTuning.pinkShelfHz, gainDb: NoiseTuning.pinkShelfDb
            )
            voicing2 = BiquadDesign.lowPass(sampleRate, NoiseTuning.pinkTopHz)
        case .brown:
            voicing1 = BiquadDesign.lowPass(sampleRate, NoiseTuning.brownTopHz)
            voicing2 = BiquadDesign.lowPass(sampleRate, NoiseTuning.brownTopHz)
        }
    }

    public mutating func next() -> Double {
        let white = rng.nextUniform()
        var s: Double
        switch color {
        case .white: s = white
        case .pink: s = pink.process(white)
        case .brown: s = brown.process(white)
        }
        s = highPass.process(s)
        s = lowPass.process(s)
        if voicing1 != nil { s = voicing1!.process(s) }
        if voicing2 != nil { s = voicing2!.process(s) }
        return s * gain
    }
}

// MARK: - Limiter

/// Instant attack, smooth release, applied from the larger of the two channel
/// peaks so gain reduction never shifts the stereo image.
///
/// Preferred over a per-sample `tanh` soft clip: `tanh` distorts continuously,
/// where a limiter is transparent until it is actually needed.
public struct PeakLimiter: Sendable {
    private let threshold: Double
    private let releaseCoeff: Double
    private var gain = 1.0

    public init(
        threshold: Double = NoiseTuning.limiterThreshold,
        sampleRate: Double = NoiseTuning.sampleRate,
        releaseSeconds: Double = NoiseTuning.limiterReleaseSeconds
    ) {
        self.threshold = threshold
        self.releaseCoeff = exp(-1.0 / (releaseSeconds * sampleRate))
    }

    public mutating func gainFor(_ peak: Double) -> Double {
        let needed = peak > threshold ? threshold / peak : 1.0
        gain = needed < gain ? needed : needed + (gain - needed) * releaseCoeff
        return gain
    }
}

// MARK: - Loudness

/// ITU-R BS.1770 K-weighting, plus the offline measurement helpers the tests use.
public enum Loudness {
    /// Published coefficients, defined at 48 kHz. A session that lands elsewhere
    /// makes the loudness match drift slightly; it does not break anything.
    private static func stage1() -> Biquad {
        Biquad(
            b0: 1.535_124_859_586_97, b1: -2.691_696_189_406_38, b2: 1.198_392_810_852_85,
            a1: -1.690_659_293_182_41, a2: 0.732_480_774_215_85
        )
    }

    private static func stage2() -> Biquad {
        Biquad(
            b0: 1.0, b1: -2.0, b2: 1.0,
            a1: -1.990_047_454_833_98, a2: 0.990_072_250_366_21
        )
    }

    /// The warm-up discards the filters' settling transient, which would
    /// otherwise dominate a short measurement.
    public static func kWeightedRms(
        _ count: Int, warmUp: Int = 4_800, _ next: () -> Double
    ) -> Double {
        var s1 = stage1(), s2 = stage2()
        for _ in 0..<warmUp { _ = s2.process(s1.process(next())) }
        var sum = 0.0
        for _ in 0..<count {
            let y = s2.process(s1.process(next()))
            sum += y * y
        }
        return (sum / Double(count)).squareRoot()
    }

    public static func peak(_ count: Int, _ next: () -> Double) -> Double {
        var p = 0.0
        for _ in 0..<count { p = max(p, abs(next())) }
        return p
    }

    /// Energy in a narrow band, for verifying spectral slope offline.
    ///
    /// Constant-Q analysis widens with frequency, so a reading gains
    /// 3 dB/octave of bandwidth: flat white reads as *rising* here. Subtract
    /// `3 * log2(fHigh/fLow)` before reading a slope.
    public static func bandEnergy(
        _ centreHz: Double,
        _ count: Int,
        sampleRate: Double = NoiseTuning.sampleRate,
        _ next: () -> Double
    ) -> Double {
        var bp = BiquadDesign.bandPass(sampleRate, centreHz, q: 4.0)
        for _ in 0..<4_800 { _ = bp.process(next()) }
        var sum = 0.0
        for _ in 0..<count {
            let y = bp.process(next())
            sum += y * y
        }
        return (sum / Double(count)).squareRoot()
    }

    /// Bandwidth correction for constant-Q analysis, in decibels.
    public static func constantQCorrectionDb(from low: Double, to high: Double) -> Double {
        3 * log2(high / low)
    }
}

// MARK: - Calibration

/// Derives each colour's gain from the real chain rather than hard-coding it, so
/// the gains can never drift out of step with the filters
/// (NOISE_IMPLEMENTATION.md §6).
///
/// Brown's gain is large (10–20×) and white's small. That is correct: brown must
/// be electrically much hotter to sound equally loud, because its energy sits
/// where the ear is least sensitive. A consequence worth knowing is that white
/// and pink end up measurably quieter than an RMS-matched implementation at the
/// same volume setting.
public enum NoiseCalibration {
    private static let measureSamples = 24_000

    /// Fixed per-colour seeds rather than `hashValue`.
    ///
    /// Swift hashing is seeded per process, so `hashValue` would give different
    /// calibration measurements on every launch — a tiny, invisible drift in
    /// loudness between runs. It can also trap: `abs(Int.min)` overflows.
    private static func seeds(for color: NoiseColor) -> (loudness: UInt64, peak: UInt64) {
        switch color {
        case .white: (0x0000_0001, 0x0000_0002)
        case .pink: (0x0000_0011, 0x0000_0012)
        case .brown: (0x0000_0021, 0x0000_0022)
        }
    }

    private struct Unity: Sendable {
        let loudness: Double
        let peak: Double
    }

    /// Measured once, lazily, in a few milliseconds. Deterministic, because the
    /// generator is.
    private static let unity: [NoiseColor: Unity] = {
        var result = [NoiseColor: Unity]()
        for color in NoiseColor.allCases {
            let seed = seeds(for: color)

            var loudChannel = NoiseChannel(color: color, seed: seed.loudness, gain: 1.0)
            let loudness = Loudness.kWeightedRms(measureSamples) { loudChannel.next() }

            var peakChannel = NoiseChannel(color: color, seed: seed.peak, gain: 1.0)
            let peak = Loudness.peak(measureSamples) { peakChannel.next() }

            result[color] = Unity(loudness: loudness, peak: peak)
        }
        return result
    }()

    /// The loudest shared level at which *every* colour still peaks below the
    /// ceiling.
    public static let targetLoudness: Double = unity.values
        .map { NoiseTuning.peakCeiling * $0.loudness / $0.peak }
        .min() ?? 0.1

    public static func gain(for color: NoiseColor) -> Double {
        guard let measured = unity[color] else { return 1.0 }
        return targetLoudness / measured.loudness
    }

    /// A playback-ready, calibrated channel.
    public static func channel(
        _ color: NoiseColor,
        seed: UInt64,
        sampleRate: Double = NoiseTuning.sampleRate
    ) -> NoiseChannel {
        NoiseChannel(color: color, seed: seed, sampleRate: sampleRate, gain: gain(for: color))
    }

    /// Seeds for the two playback channels.
    ///
    /// Independent, which is the single biggest factor in how wide the noise
    /// sounds. Two copies of one stream collapse to a point inside the head.
    public enum PlaybackSeed {
        public static let left: UInt64 = 0x2545_F491_4F6C_DD1D
        public static let right: UInt64 = 0x9E37_79B9_7F4A_7C15
    }
}
