import AVFoundation
import QuartzCore
import TraitorsEngine

/// Plays the room you are standing in and the sounds laid over it. Every buffer is made ahead of
/// time by `Synth` and handed to player nodes, so no code of ours runs on the audio thread.
final class Soundscape {
    /// Whether anything should be heard. Set by whoever owns the settings.
    var enabled = true

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
    private let beds = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let stings = (0..<8).map { _ in AVAudioPlayerNode() }
    private var bedBuffers: [Bed: AVAudioPCMBuffer] = [:]
    /// Every short sound made so far, by name, whichever synth made it.
    private var shots: [String: AVAudioPCMBuffer] = [:]
    private var making: Set<String> = []
    private var front = 0
    private var nextSting = 0
    /// The room that should be playing, whether or not it is audible yet.
    private var wanted: Bed?
    private var playing: Bed?
    private var level: Float = 1
    private var fade: Task<Void, Never>?
    private var wired = false

    init() {}

    // MARK: - Control

    /// Cross-fades to another room, or to silence. `level` lowers it under something louder.
    func setBed(_ bed: Bed?, level: Float = 1) {
        wanted = bed
        self.level = level
        guard enabled, let bed else { fadeTo(nil); return }
        if let buffer = bedBuffers[bed] {
            fadeTo((bed, buffer))
        } else {
            Task {
                let samples = await Task.detached(priority: .utility) { Synth.render(bed) }.value
                self.bedBuffers[bed] = self.buffer(samples)
                // Somewhere else may have been asked for while this was being made.
                if self.wanted == bed, let made = self.bedBuffers[bed] { self.fadeTo((bed, made)) }
            }
        }
    }

    /// Plays a short sound by name. The first time one is wanted it is made off the main thread
    /// by `render`, and played only if that was quick enough for it still to belong to its moment.
    func play(_ name: String, volume: Float = 1, render: @escaping @Sendable () -> [Float]) {
        guard enabled, start() else { return }
        guard let buffer = shots[name] else {
            let asked = CACurrentMediaTime()
            make(name, render: render) { [weak self] in
                if CACurrentMediaTime() - asked < 0.25 { self?.play(name, volume: volume, render: render) }
            }
            return
        }
        let node = stings[nextSting]
        nextSting = (nextSting + 1) % stings.count
        node.stop()
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
    }

    /// Makes a short sound ahead of the first time it is needed. Never on the main thread.
    func make(_ name: String, render: @escaping @Sendable () -> [Float], then: (() -> Void)? = nil) {
        guard shots[name] == nil, making.insert(name).inserted else { return }
        Task {
            let samples = await Task.detached(priority: .userInitiated) { render() }.value
            self.shots[name] = self.buffer(samples)
            self.making.remove(name)
            then?()
        }
    }

    /// The app has left the screen, or sound was switched off.
    func suspend() {
        fade?.cancel()
        for node in beds + stings { node.stop() }
        playing = nil
        engine.pause()
    }

    /// Picks the room back up after `suspend`, or after the setting changes.
    func resume() {
        let bed = wanted
        playing = nil
        if enabled { setBed(bed, level: level) } else { suspend() }
    }

    // MARK: - Engine

    private func start() -> Bool {
        if !wired {
            wired = true
            for node in beds + stings {
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
            }
            // Ambient: the mute switch silences it and other audio keeps playing.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
                Task { @MainActor in
                    if ended { self?.resume() } else { self?.suspend() }
                }
            }
        }
        if engine.isRunning { return true }
        try? AVAudioSession.sharedInstance().setActive(true)
        do { try engine.start() } catch { return false }
        return true
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func fadeTo(_ target: (Bed, AVAudioPCMBuffer)?) {
        let goal = level * 0.55
        var rising: AVAudioPlayerNode?
        var falling: AVAudioPlayerNode?
        if let target, target.0 == playing {
            // Same room: only the level may have changed.
            rising = beds[front]
        } else {
            guard target == nil || start() else { return }
            falling = beds[front]
            if let (_, buffer) = target {
                front = 1 - front
                let new = beds[front]
                new.stop()
                new.volume = 0
                new.scheduleBuffer(buffer, at: nil, options: [.loops])
                new.play()
                rising = new
            }
            playing = target?.0
        }
        fade?.cancel()
        fade = Task {
            let up = rising?.volume ?? 0, down = falling?.volume ?? 0
            for step in 1...20 {
                try? await Task.sleep(for: .seconds(0.06))
                if Task.isCancelled { return }
                let x = Float(step) / 20
                rising?.volume = up + (goal - up) * x
                falling?.volume = down * (1 - x)
            }
            falling?.stop()
        }
    }
}

extension Place {
    var bed: Bed {
        switch self {
        case .hall: return .hall
        case .breakfastRoom: return .morning
        case .grounds: return .grounds
        case .roundTable: return .table
        case .turret: return .turret
        case .bedchamber: return .chamber
        case .fireOfTruth: return .fire
        }
    }
}
