import AVFoundation

/// Plays the room you are standing in and the sounds laid over it. Every buffer is made ahead of
/// time by `Synth` and handed to player nodes, so no code of ours runs on the audio thread.
final class Soundscape {
    static let shared = Soundscape()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
    private let beds = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let stings = (0..<8).map { _ in AVAudioPlayerNode() }
    private var bedBuffers: [Bed: AVAudioPCMBuffer] = [:]
    private var stingBuffers: [Sting: AVAudioPCMBuffer] = [:]
    private var front = 0
    private var nextSting = 0
    /// The room that should be playing, whether or not it is audible yet.
    private var wanted: Bed?
    private var playing: Bed?
    private var level: Float = 1
    private var fade: Task<Void, Never>?
    private var wired = false

    private init() {}

    // MARK: - Control

    /// Cross-fades to another room, or to silence. `level` lowers it under something louder.
    func setBed(_ bed: Bed?, level: Float = 1) {
        wanted = bed
        self.level = level
        guard Senses.sound, let bed else { fadeTo(nil); return }
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

    func play(_ sting: Sting, volume: Float = 1) {
        guard Senses.sound, start() else { return }
        guard let buffer = stingBuffers[sting] else {
            Task {
                let samples = await Task.detached(priority: .userInitiated) { Synth.render(sting) }.value
                self.stingBuffers[sting] = self.buffer(samples)
                self.play(sting, volume: volume)
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

    /// Plays a buffer somebody else made, once. It must be mono at `Synth.rate`, as `makeBuffer` returns.
    func playOneShot(_ buffer: AVAudioPCMBuffer, volume: Float = 1) {
        guard Senses.sound, start() else { return }
        let node = stings[nextSting]
        nextSting = (nextSting + 1) % stings.count
        node.stop()
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
    }

    /// Wraps samples from `Synth` (mono, `Synth.rate`) for `playOneShot`.
    func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? { buffer(samples) }

    /// Makes the short sounds ahead of the first time they are needed.
    func warmUp() {
        guard Senses.sound else { return }
        for sting in Sting.allCases where stingBuffers[sting] == nil {
            Task {
                let samples = await Task.detached(priority: .utility) { Synth.render(sting) }.value
                if self.stingBuffers[sting] == nil { self.stingBuffers[sting] = self.buffer(samples) }
            }
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
        if Senses.sound { setBed(bed, level: level) } else { suspend() }
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
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
                let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
                Task { @MainActor in
                    if ended { Soundscape.shared.resume() } else { Soundscape.shared.suspend() }
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
