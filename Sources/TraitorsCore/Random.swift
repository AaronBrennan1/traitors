import Foundation

/// Deterministic SplitMix64 generator. Every random choice in a game flows from
/// one seed so a game can be replayed, saved mid-way and simulated in bulk.
public struct SeededRNG: Codable {
    package var state: UInt64

    public init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    package mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    package mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }

    package mutating func int(_ n: Int) -> Int {
        n <= 1 ? 0 : Int(next() % UInt64(n))
    }

    public mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    package mutating func gaussian() -> Double {
        let u1 = max(unit(), 1e-12)
        let u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    package mutating func pick<T>(_ items: [T]) -> T {
        items[int(items.count)]
    }

    package mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            a.swapAt(i, int(i + 1))
        }
        return a
    }

    /// Index sampled in proportion to non-negative weights.
    package mutating func weighted(_ weights: [Double]) -> Int {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return int(weights.count) }
        var r = unit() * total
        for (i, w) in weights.enumerated() {
            r -= max(0, w)
            if r < 0 { return i }
        }
        return weights.count - 1
    }

    /// Index sampled from softmax(scores / temperature).
    package mutating func softmax(_ scores: [Double], temperature: Double) -> Int {
        guard let top = scores.max() else { return 0 }
        let t = max(temperature, 1e-3)
        return weighted(scores.map { exp(($0 - top) / t) })
    }

    package mutating func fork() -> SeededRNG {
        SeededRNG(seed: next())
    }

    /// A stream that depends only on its inputs. Bots use it to look ahead, so that
    /// planning never moves any of the game's own streams.
    public static func derived(_ seed: UInt64, _ salts: UInt64...) -> SeededRNG {
        var r = SeededRNG(seed: seed)
        for s in salts { r = SeededRNG(seed: r.next() ^ (s &* 0xD6E8_FEB8_6659_FD93)) }
        return r
    }
}

public func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    min(hi, max(lo, x))
}
