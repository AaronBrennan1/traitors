import AVFoundation
import QuartzCore

/// The sounds of the mini-games and the buttons round them. Every one is worked out from sines and
/// noise the first time it is wanted and kept; there are no audio files. They play through the
/// castle's own `Soundscape`, which is also where the sound setting is honoured.
enum ArenaSounds {
    private static var cache: [String: AVAudioPCMBuffer] = [:]
    private static var lastQuiet = 0.0

    static func play(_ event: Feedback.Event) {
        guard Feedback.settings.sound, !Feedback.muted else { return }
        let (key, volume): (String, Float)
        switch event {
        case .countdown: (key, volume) = ("countdown", 0.7)
        case .go: (key, volume) = ("go", 0.8)
        case .score(let n): (key, volume) = ("score\(min(max(n, 0), 16))", 0.75)
        case .penalty: (key, volume) = ("penalty", 0.8)
        case .otherScore:
            // Seven others scoring at once should be a patter, not a din.
            let now = CACurrentMediaTime()
            guard now - lastQuiet > 0.14 else { return }
            lastQuiet = now
            (key, volume) = ("other", 0.22)
        case .teamBonus: (key, volume) = ("bonus", 0.5)
        case .banner: (key, volume) = ("banner", 0.55)
        case .shake: (key, volume) = ("shake", 0.8)
        case .burst: (key, volume) = ("burst", 0.6)
        case .holdTick: (key, volume) = ("holdTick", 0.3)
        case .holdDone: (key, volume) = ("holdDone", 0.5)
        case .par: (key, volume) = ("par", 0.75)
        case .teamGoal: (key, volume) = ("teamGoal", 0.75)
        case .questStep: (key, volume) = ("questStep", 0.55)
        case .questDone: (key, volume) = ("questDone", 0.7)
        case .lastSeconds: (key, volume) = ("heartbeat", 0.7)
        case .time: (key, volume) = ("time", 0.85)
        case .tap: (key, volume) = ("tap", 0.4)
        case .toggle: (key, volume) = ("toggle", 0.4)
        case .row: (key, volume) = ("row", 0.25)
        case .pause: (key, volume) = ("pause", 0.45)
        }
        if cache[key] == nil { cache[key] = Soundscape.shared.makeBuffer(ArenaSynth.render(key)) }
        if let buffer = cache[key] { Soundscape.shared.playOneShot(buffer, volume: volume) }
    }
}

/// The arithmetic behind the arena's sounds. Pure functions of their arguments, so they can run anywhere.
nonisolated enum ArenaSynth {
    static let rate = Synth.rate

    static func render(_ key: String) -> [Float] {
        if key.hasPrefix("score"), let n = Int(key.dropFirst(5)) {
            // Two plucked notes a fifth apart, a semitone higher for every one you bring home.
            let base = 440.0 * pow(2, Double(n) / 12)
            return mix([(0, pluck(base, 0.22), 0.8), (0.07, pluck(base * 1.5, 0.3), 0.8)])
        }
        switch key {
        case "countdown": return mix([(0, noise(0.05, decay: 70, smooth: 0.5, seed: 3), 0.7), (0, tone(660, 0.12, decay: 38), 0.6)])
        case "go": return bell(392, 1.3)
        case "time": return mix([(0, bell(196, 1.9), 1), (0, tone(98, 1.2, decay: 3.5), 0.5)])
        case "penalty": return mix([(0, tone(150, 0.32, decay: 11, glide: -0.55), 0.9), (0, noise(0.14, decay: 26, smooth: 0.93, seed: 5), 0.8)])
        case "other": return tone(1320, 0.05, decay: 80)
        case "bonus": return mix([(0, pluck(1047, 0.4), 0.6), (0.05, pluck(1568, 0.5), 0.6)])
        case "banner": return horn([196, 294], 0.8)
        case "shake": return noise(0.55, decay: 6, smooth: 0.985, seed: 9).map { $0 * 3.2 }
        case "burst": return mix([(0, noise(0.09, decay: 45, smooth: 0.8, seed: 7), 0.9), (0, tone(190, 0.1, decay: 40, glide: -0.4), 0.7)])
        case "holdTick": return tone(520, 0.03, decay: 120)
        case "holdDone": return mix([(0, tone(1400, 0.06, decay: 70), 0.6), (0.02, tone(2100, 0.08, decay: 55), 0.5)])
        case "par": return mix([(0, pluck(1047, 0.5), 0.6), (0.08, pluck(1319, 0.5), 0.6), (0.16, pluck(1568, 0.8), 0.7)])
        case "teamGoal": return mix([(0, pluck(392, 0.3), 0.6), (0.12, pluck(523, 0.3), 0.6), (0.24, pluck(659, 0.3), 0.6), (0.36, bell(784, 1.1), 0.7)])
        case "questStep": return tone(147, 0.5, decay: 7, harmonics: [1, 0.4, 0.15])
        case "questDone": return mix([(0, tone(110, 1.2, decay: 3, harmonics: [1, 0.5, 0.2]), 0.7), (0, tone(131, 1.2, decay: 3), 0.45),
                                      (0.04, tone(165, 1.2, decay: 3), 0.4)])
        case "heartbeat": return mix([(0, tone(72, 0.16, decay: 26, glide: -0.3), 1), (0.17, tone(60, 0.2, decay: 22, glide: -0.3), 0.7)])
        case "tap": return mix([(0, noise(0.025, decay: 160, smooth: 0.6, seed: 11), 0.6), (0, tone(480, 0.05, decay: 70), 0.5)])
        case "toggle": return tone(740, 0.06, decay: 60)
        case "row": return mix([(0, noise(0.03, decay: 120, smooth: 0.3, seed: 13), 0.5), (0, tone(900, 0.04, decay: 90), 0.4)])
        case "pause": return mix([(0, pluck(587, 0.18), 0.6), (0.09, pluck(440, 0.3), 0.6)])
        default: return tone(440, 0.05, decay: 60)
        }
    }

    /// A decaying tone. `glide` bends the pitch over its length, as a fraction of the pitch.
    static func tone(_ freq: Double, _ seconds: Double, decay: Double, glide: Double = 0, harmonics: [Double] = [1]) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            let f = freq * (1 + glide * t / seconds)
            phase += 2 * .pi * f / rate
            var v = 0.0
            for (h, gain) in harmonics.enumerated() { v += sin(phase * Double(h + 1)) * gain }
            // A few milliseconds of fade at either end, so nothing clicks.
            let edge = min(1, t / 0.004) * min(1, (seconds - t) / 0.01)
            out[i] = Float(v * exp(-decay * t) * edge)
        }
        return out
    }

    /// A plucked string: bright at the start, and the brightness dies first.
    static func pluck(_ freq: Double, _ seconds: Double) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let p = 2 * Double.pi * freq * t
            let v = sin(p) + 0.5 * sin(2 * p) * exp(-14 * t) + 0.25 * sin(3 * p) * exp(-22 * t)
            out[i] = Float(v * exp(-9 * t / max(seconds, 0.2) * 0.5 - 6 * t) * min(1, t / 0.002) * min(1, (seconds - t) / 0.01) * 0.6)
        }
        return out
    }

    /// A bell: partials that are not quite in tune with each other, the high ones dying soonest.
    static func bell(_ freq: Double, _ seconds: Double) -> [Float] {
        let partials: [(Double, Double, Double)] = [(1, 1, 2.4), (2.0, 0.55, 3.4), (2.76, 0.38, 4.6), (5.4, 0.2, 7.5), (8.9, 0.1, 11)]
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for (ratio, gain, decay) in partials { v += sin(2 * .pi * freq * ratio * t) * gain * exp(-decay * t) }
            out[i] = Float(v * 0.45 * min(1, t / 0.003) * min(1, (seconds - t) / 0.05))
        }
        return out
    }

    /// A horn call: reedy, swelling in and dying away.
    static func horn(_ freqs: [Double], _ seconds: Double) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for f in freqs {
                for h in 1...5 { v += sin(2 * .pi * f * Double(h) * t) / Double(h * h) * (h % 2 == 1 ? 1 : 0.6) }
            }
            let swell = min(1, t / 0.14) * min(1, (seconds - t) / 0.3)
            out[i] = Float(v * swell * 0.3)
        }
        return out
    }

    /// Noise, smoothed towards a rumble as `smooth` nears one.
    static func noise(_ seconds: Double, decay: Double, smooth: Double, seed: UInt64) -> [Float] {
        let n = Int(seconds * rate)
        var out = [Float](repeating: 0, count: n)
        var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        var held = 0.0
        for i in 0..<n {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let white = Double(state % 20_001) / 10_000 - 1
            held = held * smooth + white * (1 - smooth)
            let t = Double(i) / rate
            out[i] = Float(held * exp(-decay * t) * min(1, t / 0.002) * min(1, (seconds - t) / 0.01))
        }
        return out
    }

    /// Lays sounds over one another, each starting `at` seconds in, and keeps the sum from clipping.
    static func mix(_ parts: [(at: Double, samples: [Float], gain: Float)]) -> [Float] {
        let length = parts.map { Int($0.at * rate) + $0.samples.count }.max() ?? 0
        var out = [Float](repeating: 0, count: length)
        for part in parts {
            let start = Int(part.at * rate)
            for (i, v) in part.samples.enumerated() { out[start + i] += v * part.gain }
        }
        let peak = out.map(abs).max() ?? 0
        if peak > 0.95 { out = out.map { $0 * 0.95 / peak } }
        return out
    }
}
