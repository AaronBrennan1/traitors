import Foundation

/// The looping sound of a room.
nonisolated enum Bed: String, Sendable {
    case hall, morning, grounds, table, turret, chamber, fire
}

/// A single sound laid over the room.
nonisolated enum Sting: String, Sendable, CaseIterable {
    case knock, door, bell, boom, heartbeat, footstep, dread, relief, quill, snuff
}

/// Every sound in the game, made from arithmetic. Nothing here touches the audio engine or the
/// main actor: each function just returns samples, so it can run on any thread ahead of time.
nonisolated enum Synth {
    static let rate = 44_100.0
    private static let bedSeconds = 8.0

    static func render(_ bed: Bed) -> [Float] {
        let n = Int(bedSeconds * rate)
        var out = [Float](repeating: 0, count: n)
        switch bed {
        case .hall:
            mix(&out, wind(n, seed: 11, low: 0.010, high: 0.030), 0.25)
            mix(&out, drone(n, [55, 82.5, 110.25]), 0.16)
            mix(&out, crackle(n, seed: 12, perSecond: 2), 0.20)
        case .morning:
            mix(&out, wind(n, seed: 21, low: 0.015, high: 0.035), 0.12)
            mix(&out, birds(n, seed: 22, perSecond: 1.6), 0.22)
            mix(&out, ticks(n, every: 1.0), 0.10)
        case .grounds:
            mix(&out, wind(n, seed: 31, low: 0.020, high: 0.080), 0.38)
            mix(&out, birds(n, seed: 32, perSecond: 0.7), 0.14)
        case .table:
            mix(&out, drone(n, [49, 73.5, 98.25]), 0.22)
            mix(&out, crackle(n, seed: 41, perSecond: 5), 0.26)
            mix(&out, ticks(n, every: 1.0), 0.14)
        case .turret:
            mix(&out, wind(n, seed: 51, low: 0.008, high: 0.050), 0.40)
            mix(&out, drone(n, [41.25, 61.875, 87.375]), 0.26)
        case .chamber:
            mix(&out, wind(n, seed: 61, low: 0.006, high: 0.022), 0.22)
            mix(&out, ticks(n, every: 1.0), 0.20)
        case .fire:
            mix(&out, rumble(n, seed: 71), 0.40)
            mix(&out, crackle(n, seed: 72, perSecond: 14), 0.34)
            mix(&out, wind(n, seed: 73, low: 0.010, high: 0.040), 0.18)
        }
        return limited(out)
    }

    static func render(_ sting: Sting) -> [Float] {
        switch sting {
        case .knock:
            var out = tone(0.18, 190, decay: 22, drop: 0.3)
            mix(&out, burst(0.18, seed: 5, decay: 60, colour: 0.25), 0.7)
            return limited(out)
        case .door:
            // A low creak that rises as the hinge gives, then the latch.
            let n = Int(0.9 * rate)
            var out = [Float](repeating: 0, count: n)
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / rate
                let f = 70 + 90 * t + 14 * sin(2 * .pi * 9 * t)
                phase += f / rate
                let saw = 2 * (phase - floor(phase)) - 1
                let env = t < 0.6 ? sin(.pi * t / 0.6) * 0.5 : 0
                out[i] = Float(saw * env * 0.5)
            }
            out = lowpassed(out, 0.08)
            var latch = tone(0.2, 120, decay: 30, drop: 0.4)
            mix(&latch, burst(0.2, seed: 9, decay: 45, colour: 0.2), 0.6)
            for (i, s) in latch.enumerated() where Int(0.62 * rate) + i < n { out[Int(0.62 * rate) + i] += s }
            return limited(out)
        case .bell:
            // Partials of a struck bell: they are not harmonics, which is what makes it a bell.
            let n = Int(3.2 * rate)
            var out = [Float](repeating: 0, count: n)
            let partials: [(Double, Double, Double)] = [(1, 1, 1.1), (2.0, 0.6, 1.6), (2.4, 0.45, 2.0), (3.0, 0.3, 2.6), (4.2, 0.2, 3.4), (5.4, 0.12, 4.5)]
            for i in 0..<n {
                let t = Double(i) / rate
                var s = 0.0
                for (ratio, gain, decay) in partials { s += gain * exp(-decay * t) * sin(2 * .pi * 196 * ratio * t) }
                out[i] = Float(s * 0.3 * min(1, t * 400))
            }
            return limited(out)
        case .boom:
            var out = tone(1.6, 62, decay: 3.2, drop: 0.45)
            mix(&out, burst(0.5, seed: 3, decay: 14, colour: 0.04), 0.9)
            return limited(out)
        case .heartbeat:
            let n = Int(0.75 * rate)
            var out = [Float](repeating: 0, count: n)
            let lub = tone(0.3, 58, decay: 16, drop: 0.3)
            let dub = tone(0.3, 50, decay: 20, drop: 0.3)
            for (i, s) in lub.enumerated() { out[i] += s }
            for (i, s) in dub.enumerated() where Int(0.24 * rate) + i < n { out[Int(0.24 * rate) + i] += s * 0.7 }
            return limited(out)
        case .footstep:
            var out = tone(0.22, 95, decay: 26, drop: 0.5)
            mix(&out, burst(0.22, seed: 17, decay: 38, colour: 0.10), 0.8)
            return limited(out)
        case .dread:
            return chord(2.8, [73.42, 87.31, 110.0, 146.83], bright: 0.05)
        case .relief:
            return chord(2.8, [98.0, 146.83, 196.0, 246.94], bright: 0.09)
        case .quill:
            // Scratches of a nib, in short strokes.
            let n = Int(1.1 * rate)
            var out = [Float](repeating: 0, count: n)
            var noise = Noise(seed: 77)
            var last = 0.0
            for i in 0..<n {
                let t = Double(i) / rate
                let stroke = pow(max(0, sin(2 * .pi * 3.2 * t)), 0.6) * (t < 1.0 ? 1 : 0)
                let white = noise.next()
                let high = white - last
                last = white
                out[i] = Float(high * stroke * 0.22)
            }
            return limited(out)
        case .snuff:
            var out = burst(0.5, seed: 91, decay: 9, colour: 0.5)
            for i in out.indices { out[i] *= Float(min(1, Double(i) / (0.04 * rate))) * 0.5 }
            mix(&out, tone(0.5, 70, decay: 9, drop: 0.2), 0.5)
            return limited(out)
        }
    }

    // MARK: - Layers

    private struct Noise {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
        /// White noise in -1...1.
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 30) - 1
        }
        mutating func unit() -> Double { (next() + 1) / 2 }
    }

    private static func mix(_ out: inout [Float], _ layer: [Float], _ gain: Float) {
        for i in 0..<min(out.count, layer.count) { out[i] += layer[i] * gain }
    }

    /// Filtered noise whose brightness and loudness drift, with the end folded back into the
    /// start so the loop has no seam.
    private static func wind(_ n: Int, seed: UInt64, low: Double, high: Double) -> [Float] {
        let tail = Int(1.0 * rate)
        var noise = Noise(seed: seed)
        var raw = [Float](repeating: 0, count: n + tail)
        var a = 0.0, b = 0.0
        for i in 0..<(n + tail) {
            let t = Double(i) / rate
            // Whole numbers of cycles over the loop, so the gusts line up when it comes round.
            let gust = 0.5 + 0.5 * sin(2 * .pi * t / bedSeconds * 2 + 1.3) * sin(2 * .pi * t / bedSeconds * 3)
            let k = low + (high - low) * gust
            a += k * (noise.next() - a)
            b += k * (a - b)
            raw[i] = Float(b * (0.55 + 0.45 * gust) * 6)
        }
        return looped(raw, n: n, tail: tail)
    }

    private static func rumble(_ n: Int, seed: UInt64) -> [Float] {
        let tail = Int(1.0 * rate)
        var noise = Noise(seed: seed)
        var raw = [Float](repeating: 0, count: n + tail)
        var a = 0.0
        for i in 0..<(n + tail) {
            a += 0.004 * (noise.next() - a)
            raw[i] = Float(a * 9)
        }
        return looped(raw, n: n, tail: tail)
    }

    /// Cross-fades the extra second at the end over the first second.
    private static func looped(_ raw: [Float], n: Int, tail: Int) -> [Float] {
        var out = Array(raw.prefix(n))
        for i in 0..<tail {
            let x = Float(i) / Float(tail)
            out[i] = out[i] * x + raw[n + i] * (1 - x)
        }
        return out
    }

    /// Sines that fit the loop exactly, each with a slow swell.
    private static func drone(_ n: Int, _ freqs: [Double]) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        for (k, f) in freqs.enumerated() {
            let cycles = (f * bedSeconds).rounded()
            let swell = Double(k + 1)
            for i in 0..<n {
                let x = Double(i) / Double(n)
                let amp = 0.6 + 0.4 * sin(2 * .pi * swell * x + Double(k))
                out[i] += Float(sin(2 * .pi * cycles * x) * amp / Double(freqs.count))
            }
        }
        return out
    }

    /// Pops of burning wood at random moments, kept clear of the loop point.
    private static func crackle(_ n: Int, seed: UInt64, perSecond: Double) -> [Float] {
        var noise = Noise(seed: seed)
        var out = [Float](repeating: 0, count: n)
        let pops = Int(perSecond * bedSeconds)
        for _ in 0..<pops {
            let at = Int(noise.unit() * Double(n - 4_000))
            let length = 200 + Int(noise.unit() * 1_600)
            let gain = 0.25 + 0.75 * noise.unit()
            var last = 0.0
            for j in 0..<length {
                let white = noise.next()
                let sharp = white - last * 0.6
                last = white
                out[at + j] += Float(sharp * exp(-Double(j) / Double(length) * 7) * gain)
            }
        }
        return out
    }

    /// A clock: a tick each interval, alternating slightly in pitch.
    private static func ticks(_ n: Int, every: Double) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        let step = Int(every * rate)
        var k = 0
        var at = step / 2
        while at + 2_000 < n {
            let f = k % 2 == 0 ? 2_100.0 : 1_750.0
            for j in 0..<2_000 {
                let t = Double(j) / rate
                out[at + j] += Float(sin(2 * .pi * f * t) * exp(-t * 180) * 0.6)
            }
            at += step
            k += 1
        }
        return out
    }

    /// Short falling and rising whistles.
    private static func birds(_ n: Int, seed: UInt64, perSecond: Double) -> [Float] {
        var noise = Noise(seed: seed)
        var out = [Float](repeating: 0, count: n)
        let calls = Int(perSecond * bedSeconds)
        for _ in 0..<calls {
            var at = Int(noise.unit() * Double(n - 30_000))
            let base = 2_600 + 2_200 * noise.unit()
            let notes = 2 + Int(noise.unit() * 3)
            let gain = 0.3 + 0.7 * noise.unit()
            for _ in 0..<notes {
                let length = Int((0.05 + 0.06 * noise.unit()) * rate)
                let sweep = (noise.unit() - 0.4) * 1_400
                var phase = 0.0
                for j in 0..<length {
                    let x = Double(j) / Double(length)
                    phase += (base + sweep * x) / rate
                    out[at + j] += Float(sin(2 * .pi * phase) * sin(.pi * x) * gain)
                }
                at += length + Int(0.03 * rate)
            }
        }
        return out
    }

    /// A struck low note whose pitch sags as it dies away.
    private static func tone(_ seconds: Double, _ freq: Double, decay: Double, drop: Double) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            phase += freq * (1 - drop * min(1, t * 4)) / rate
            out[i] = Float(sin(2 * .pi * phase) * exp(-decay * t) * min(1, t * 900))
        }
        return out
    }

    private static func burst(_ seconds: Double, seed: UInt64, decay: Double, colour: Double) -> [Float] {
        let n = Int(seconds * rate)
        var noise = Noise(seed: seed)
        var out = [Float](repeating: 0, count: n)
        var a = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            a += colour * (noise.next() - a)
            out[i] = Float(a * exp(-decay * t) * 2)
        }
        return out
    }

    /// Bowed-sounding notes swelling in and dying away together.
    private static func chord(_ seconds: Double, _ freqs: [Double], bright: Double) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        for (k, f) in freqs.enumerated() {
            var phase = 0.0
            let detune = 1 + 0.003 * Double(k % 2 == 0 ? 1 : -1)
            for i in 0..<n {
                let t = Double(i) / rate
                phase += f * detune / rate
                let saw = 2 * (phase - floor(phase)) - 1
                let env = min(1, t / 0.5) * exp(-max(0, t - 0.8) * 1.5)
                out[i] += Float(saw * env / Double(freqs.count))
            }
        }
        return limited(lowpassed(lowpassed(out, bright), bright).map { $0 * 3 })
    }

    private static func lowpassed(_ x: [Float], _ k: Double) -> [Float] {
        var out = x
        var a: Float = 0
        let kf = Float(k)
        for i in out.indices {
            a += kf * (out[i] - a)
            out[i] = a
        }
        return out
    }

    /// Soft clipping, so stacked layers never crack.
    private static func limited(_ x: [Float]) -> [Float] {
        x.map { tanhf($0) }
    }
}
