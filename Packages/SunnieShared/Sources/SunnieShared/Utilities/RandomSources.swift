import Foundation

/// Production randomness.
public struct SystemRandomSource: RandomSource {
    public init() {}

    public func nextUnitValue() -> Double {
        Double.random(in: 0..<1)
    }

    public func nextIndex(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int.random(in: 0..<upperBound)
    }
}

/// Deterministic randomness for tests and for any content selection that must
/// reproduce — a daily puzzle seed, a message choice being verified.
///
/// SplitMix64: small, well-distributed, and identical across platforms and Swift
/// versions, which matters because `SystemRandomNumberGenerator` is not
/// reproducible.
public final class SeededRandomSource: RandomSource, @unchecked Sendable {
    private var state: UInt64
    private let lock = NSLock()

    public init(seed: UInt64) {
        self.state = seed
    }

    private func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public func nextUnitValue() -> Double {
        // Take the top 53 bits: exactly the mantissa width of Double, so every
        // value is representable and the distribution stays uniform.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public func nextIndex(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUnitValue() * Double(upperBound)) % upperBound
    }
}

/// Always returns a fixed value. Useful for asserting the "nickname was used"
/// and "nickname was not used" branches directly.
public struct FixedRandomSource: RandomSource {
    private let value: Double
    private let index: Int

    public init(value: Double, index: Int = 0) {
        self.value = value
        self.index = index
    }

    public func nextUnitValue() -> Double { value }
    public func nextIndex(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return min(index, upperBound - 1)
    }
}
