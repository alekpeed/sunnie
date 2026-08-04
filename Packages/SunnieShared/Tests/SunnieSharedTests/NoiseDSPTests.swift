import Foundation
import Testing
@testable import SunnieShared

/// The tests NOISE_IMPLEMENTATION.md §8 asks for, which caught real problems in
/// the reference implementation and cost nothing to run: no audio hardware, no
/// device, no listening.
///
/// Band energy is measured with a constant-Q band-pass, which widens with
/// frequency and so reads +3 dB per octave of bandwidth on its own. Flat white
/// reads as *rising* in this analysis. `slopeDbPerOctave` subtracts that
/// correction; forgetting it is the classic way to conclude the filters are
/// broken when they are fine.
@Suite("Noise DSP")
struct NoiseDSPTests {

    private let sampleCount = 48_000

    private func channel(
        _ color: NoiseColor,
        seed: UInt64 = 1,
        gain: Double = 1,
        voiced: Bool = true
    ) -> NoiseChannel {
        NoiseChannel(color: color, seed: seed, gain: gain, voiced: voiced)
    }

    private func band(
        _ color: NoiseColor,
        at frequency: Double,
        voiced: Bool = true,
        seed: UInt64 = 1
    ) -> Double {
        var source = channel(color, seed: seed, voiced: voiced)
        return Loudness.bandEnergy(frequency, sampleCount) { source.next() }
    }

    private func db(_ value: Double) -> Double { 20 * log10(max(value, 1e-12)) }

    /// Slope between two bands, corrected for the analysis bandwidth.
    private func slopeDbPerOctave(
        _ color: NoiseColor,
        from low: Double,
        to high: Double,
        voiced: Bool
    ) -> Double {
        let lowEnergy = band(color, at: low, voiced: voiced)
        let highEnergy = band(color, at: high, voiced: voiced)
        let octaves = log2(high / low)
        let corrected = db(highEnergy) - db(lowEnergy)
            - Loudness.constantQCorrectionDb(from: low, to: high)
        return corrected / octaves
    }

    // MARK: - Slope

    @Test("Unvoiced, white is flat, pink is -3 dB/oct, and brown is -6 dB/oct")
    func rawSlopesAreCorrect() {
        // Voicing is bypassed here on purpose. Without that switch, a change to
        // the taste settings would silently break this assertion and the colour
        // maths would stop being verifiable at all (NOISE_IMPLEMENTATION.md §8).
        let white = slopeDbPerOctave(.white, from: 500, to: 4_000, voiced: false)
        let pink = slopeDbPerOctave(.pink, from: 500, to: 4_000, voiced: false)
        let brown = slopeDbPerOctave(.brown, from: 500, to: 4_000, voiced: false)

        #expect(abs(white) < 1.0, "white slope \(white)")
        #expect(abs(pink - -3.0) < 1.0, "pink slope \(pink)")
        #expect(abs(brown - -6.0) < 1.0, "brown slope \(brown)")
    }

    // MARK: - Voicing

    @Test("White's top is pulled down while its presence survives")
    func whiteVoicingTiltsTheTop() {
        let reference = db(band(.white, at: 500))
        let twoK = db(band(.white, at: 2_000)) - reference
        let eightK = db(band(.white, at: 8_000)) - reference

        // 8 kHz well down relative to its unvoiced position…
        #expect(eightK < 0, "8 kHz at \(eightK) dB re 500 Hz")
        // …but 2 kHz still present, so it does not turn into brown noise.
        #expect(twoK > eightK, "2 kHz \(twoK) should sit above 8 kHz \(eightK)")
    }

    @Test("Pink loses its top without losing its body")
    func pinkVoicingKeepsTheLowEnd() {
        let reference = db(band(.pink, at: 500))
        let low = db(band(.pink, at: 125)) - reference
        let fourK = db(band(.pink, at: 4_000)) - reference
        let eightK = db(band(.pink, at: 8_000)) - reference

        // The specific fix for pink reading as "white noise on top of brown":
        // everything below ~500 Hz is untouched, so it keeps its weight.
        #expect(low > -3, "125 Hz at \(low) dB should be essentially intact")
        #expect(fourK < -8, "4 kHz at \(fourK) dB")
        #expect(eightK < fourK, "8 kHz should continue falling")
    }

    @Test("Brown is far darker than its raw slope alone")
    func brownVoicingGoesFurtherThanTheSlope() {
        let voiced = db(band(.brown, at: 4_000)) - db(band(.brown, at: 500))
        let raw = db(band(.brown, at: 4_000, voiced: false))
            - db(band(.brown, at: 500, voiced: false))

        #expect(voiced < raw - 3, "voiced \(voiced) dB vs raw \(raw) dB")
    }

    @Test("The three colours stay audibly distinct")
    func coloursRemainDistinct() {
        // Stops retuning from collapsing all three into the same sound, which is
        // the failure mode of adjusting voicing by ear one colour at a time.
        func brightness(_ color: NoiseColor) -> Double {
            db(band(color, at: 4_000)) - db(band(color, at: 500))
        }

        let white = brightness(.white)
        let pink = brightness(.pink)
        let brown = brightness(.brown)

        #expect(white > pink + 3, "white \(white) vs pink \(pink)")
        #expect(pink > brown + 6, "pink \(pink) vs brown \(brown)")
    }

    // MARK: - Loudness and headroom

    @Test("All three colours land within a decibel of the shared target")
    func loudnessIsMatched() {
        // Matched by K-weighted loudness, not RMS: brown's energy sits where the
        // ear is least sensitive, so equal RMS would leave it much quieter.
        for color in NoiseColor.allCases {
            var source = NoiseCalibration.channel(color, seed: 7)
            let measured = Loudness.kWeightedRms(sampleCount) { source.next() }
            let difference = db(measured) - db(NoiseCalibration.targetLoudness)
            #expect(abs(difference) < 1.0, "\(color): \(difference) dB off target")
        }
    }

    @Test("Every colour keeps headroom below the ceiling")
    func headroomIsPreserved() {
        // The point of calibrating against peaks as well as loudness: the limiter
        // should only ever catch occasional transients, not work continuously.
        for color in NoiseColor.allCases {
            var source = NoiseCalibration.channel(color, seed: 11)
            let peak = Loudness.peak(sampleCount) { source.next() }
            #expect(peak < 0.98, "\(color) peaked at \(peak)")
        }
    }

    @Test("Brown needs far more gain than white to sound as loud")
    func brownIsElectricallyHotter() {
        // Counterintuitive but correct, and worth pinning: if this ever inverts,
        // the loudness weighting has been dropped somewhere.
        #expect(NoiseCalibration.gain(for: .brown) > NoiseCalibration.gain(for: .white) * 3)
    }

    @Test("Calibration is deterministic across runs")
    func calibrationIsStable() {
        // The reference seeded calibration from `hashValue`, which Swift seeds
        // per process — so the gains drifted slightly on every launch. Fixed
        // seeds make it reproducible, which is also what makes these tests
        // non-flaky.
        let first = NoiseColor.allCases.map { NoiseCalibration.gain(for: $0) }
        let second = NoiseColor.allCases.map { NoiseCalibration.gain(for: $0) }
        #expect(first == second)
    }

    // MARK: - Stereo

    @Test("The two playback channels are decorrelated")
    func channelsAreIndependent() {
        // The single biggest factor in how wide the noise sounds. Two copies of
        // one stream collapse to a point inside the head.
        var left = NoiseCalibration.channel(.pink, seed: NoiseCalibration.PlaybackSeed.left)
        var right = NoiseCalibration.channel(.pink, seed: NoiseCalibration.PlaybackSeed.right)

        var sumLR = 0.0, sumLL = 0.0, sumRR = 0.0
        for _ in 0..<sampleCount {
            let l = left.next(), r = right.next()
            sumLR += l * r
            sumLL += l * l
            sumRR += r * r
        }

        let correlation = sumLR / (sumLL.squareRoot() * sumRR.squareRoot())
        #expect(abs(correlation) < 0.1, "correlation \(correlation)")
    }

    @Test("The same seed reproduces the same stream")
    func generationIsDeterministic() {
        var a = channel(.white, seed: 12_345)
        var b = channel(.white, seed: 12_345)
        for _ in 0..<1_000 {
            #expect(a.next() == b.next())
        }
    }

    // MARK: - Limiter

    @Test("The limiter holds the output at its threshold")
    func limiterCatchesOverload() {
        var limiter = PeakLimiter()
        // Deliberately over full scale.
        for _ in 0..<1_000 {
            let reduction = limiter.gainFor(2.0)
            #expect(2.0 * reduction <= NoiseTuning.limiterThreshold + 1e-9)
        }
    }

    @Test("The limiter is transparent below its threshold")
    func limiterIsTransparentWhenIdle() {
        // Preferred over a tanh soft clip precisely because it does nothing until
        // it is needed.
        var limiter = PeakLimiter()
        for _ in 0..<100 {
            #expect(limiter.gainFor(0.5) == 1.0)
        }
    }

    @Test("The limiter recovers smoothly rather than jumping back")
    func limiterReleasesGradually() {
        var limiter = PeakLimiter()
        _ = limiter.gainFor(2.0)
        let immediatelyAfter = limiter.gainFor(0.1)
        #expect(immediatelyAfter < 1.0, "should still be recovering, got \(immediatelyAfter)")

        // A quarter-second release at 48 kHz is thousands of samples.
        for _ in 0..<48_000 { _ = limiter.gainFor(0.1) }
        #expect(limiter.gainFor(0.1) > 0.99)
    }

    // MARK: - Robustness

    @Test("Output stays finite at any supported sample rate")
    func filtersAreStableAcrossRates() {
        // The filters are designed from the live rate because the session may not
        // grant 48 kHz. A rate that produced NaN would be silent-but-broken.
        for rate in [44_100.0, 48_000.0, 96_000.0] {
            for color in NoiseColor.allCases {
                var source = NoiseChannel(color: color, seed: 3, sampleRate: rate)
                var peak = 0.0
                for _ in 0..<10_000 {
                    let sample = source.next()
                    #expect(sample.isFinite, "\(color) at \(rate) produced \(sample)")
                    peak = max(peak, abs(sample))
                }
                #expect(peak > 0, "\(color) at \(rate) produced silence")
            }
        }
    }

    @Test("A zero seed still produces noise")
    func zeroSeedIsHandled() {
        // xorshift locks to zero from a zero state; the constructor's mix is what
        // prevents it. Worth pinning, because the failure is total silence.
        var source = channel(.white, seed: 0)
        var peak = 0.0
        for _ in 0..<10_000 { peak = max(peak, abs(source.next())) }
        #expect(peak > 0.01, "zero seed produced \(peak)")
    }

    @Test("Noise colours resolve to and from their content IDs")
    func contentIDsRoundTrip() {
        for color in NoiseColor.allCases {
            #expect(NoiseColor.from(contentID: color.contentID) == color)
        }
        // A recorded ambience is not a noise colour.
        #expect(NoiseColor.from(contentID: "sunnie.calm.rain.soft") == nil)
    }

    @Test("The content pack lists all three colours in the generated category")
    func contentPackMatchesTheColours() {
        // The library is content-driven, so a colour with no entry would exist in
        // code and be unreachable in the app.
        let pack = ContentRegistry.builtIn().wellnessPack
        let generated = pack.calmSounds.filter { $0.category.isGenerated }

        #expect(generated.count == NoiseColor.allCases.count)
        for color in NoiseColor.allCases {
            #expect(
                generated.contains { $0.id == color.contentID },
                "no calm sound for \(color)"
            )
        }
        // Nothing generated should claim to be mixable — two noise streams at
        // once is not a combination the player offers.
        #expect(generated.allSatisfy { !$0.isMixable })
    }
}
