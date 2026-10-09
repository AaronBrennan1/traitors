import SwiftUI
import UIKit
import QuartzCore
import TraitorsEngine

/// Everything the game does to the ear and the hand, behind one seam. The app plays it; a test
/// or a preview is handed one that only remembers what it was asked for.
protocol Effects: AnyObject {
    /// What the player has switched on. Sound and haptics both answer to it.
    var settings: Settings { get set }
    /// Silences everything whatever the settings say, for unattended runs.
    var muted: Bool { get set }

    /// A moment in a staged scene: its sound and what the hand feels, together.
    func play(_ cue: Cue)
    /// Something in a mini-game, or a button outside one.
    func play(_ event: Feedback.Event)
    /// Wakes the haptics, so the next one lands on time and not a beat late.
    func prepare()

    /// Cross-fades to another room's air, or to silence. `level` lowers it under something louder.
    func setBed(_ bed: Bed?, level: Float)
    /// Makes the short sounds ahead of the first time they are needed.
    func warmUp()
    /// The app has left the screen.
    func suspend()
    /// Back on screen, or the sound setting has changed.
    func resume()
}

/// One thing happening in a scene.
enum Cue: Equatable {
    case slate, lateSlate, door, bell, boom, heartbeat, footstep, shoulder, declare(Role?), letter, snuff, curtain

    func play() { Feedback.effects.play(self) }
}

/// Everything the game says back to the hand and the ear in a mini-game and on the buttons round
/// it. One call per moment; the settings decide what of it is felt or heard.
enum Feedback {
    enum Event: Equatable {
        /// The 3, 2, 1 before a round, and the bell that starts it.
        case countdown, go
        /// Your own gold going into the vault, with how far the company is towards its goal out of 16.
        case score(Int)
        case otherScore
        case dash, pickup, nearMiss
        /// Caught by a trap or over the edge, and a knock from somebody else.
        case hit, bump
        /// A trap showing itself, and going off.
        case warn, strike
        case lightsOut, lightsOn, spill
        case sealing, banner
        /// The shadow's hand, used. Only ever played to the traitor who used it.
        case hand
        case teamGoal
        case lastSeconds, time
        /// Buttons and switches outside the arena.
        case tap, toggle, row, pause
    }

    /// The effects in use. Views get the same one through the environment; SpriteKit and the
    /// button styles, which have no environment to read, reach it here.
    static var effects: Effects = LiveEffects()

    static func play(_ event: Event) { effects.play(event) }
    static func prepare() { effects.prepare() }
}

private struct EffectsKey: EnvironmentKey {
    static var defaultValue: Effects { Feedback.effects }
}

extension EnvironmentValues {
    var effects: Effects {
        get { self[EffectsKey.self] }
        set { self[EffectsKey.self] = newValue }
    }
}

/// The real thing: the castle's `Soundscape` and one set of haptic generators.
final class LiveEffects: Effects {
    var settings = Settings() { didSet { apply() } }
    var muted = false { didSet { apply() } }

    private let sound = Soundscape()
    private var lastQuiet = 0.0

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notice = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private var hears: Bool { settings.sound && !muted }
    private var feels: Bool { settings.haptics && !muted }

    private func apply() {
        guard sound.enabled != hears else { return }
        sound.enabled = hears
        sound.resume()
    }

    func play(_ cue: Cue) {
        let (sting, volume): (Sting, Float)
        switch cue {
        case .slate: (sting, volume) = (.knock, 0.5)
        case .lateSlate: (sting, volume) = (.knock, 0.8)
        case .door: (sting, volume) = (.door, 0.5)
        case .bell: (sting, volume) = (.bell, 0.55)
        case .boom: (sting, volume) = (.boom, 0.8)
        case .heartbeat: (sting, volume) = (.heartbeat, 0.8)
        case .footstep: (sting, volume) = (.footstep, 0.45)
        case .shoulder: (sting, volume) = (.boom, 0.9)
        case .declare(let role): (sting, volume) = (role == .traitor ? .dread : role == .faithful ? .relief : .boom, 0.7)
        case .letter: (sting, volume) = (.quill, 0.6)
        case .snuff: (sting, volume) = (.snuff, 0.6)
        case .curtain: (sting, volume) = (.bell, 0.35)
        }
        sound.play("sting." + sting.rawValue, volume: volume) { Synth.render(sting) }
        guard feels else { return }
        switch cue {
        case .slate, .door, .footstep, .letter, .snuff: light.impactOccurred()
        case .lateSlate: rigid.impactOccurred()
        case .boom, .shoulder: heavy.impactOccurred()
        case .heartbeat:
            // Two beats, the second softer.
            heavy.impactOccurred(intensity: 0.9)
            Task {
                try? await Task.sleep(for: .seconds(0.22))
                self.medium.impactOccurred(intensity: 0.6)
            }
        case .declare(let role):
            if role == .traitor { notice.notificationOccurred(.error) } else if role == .faithful { notice.notificationOccurred(.success) } else { heavy.impactOccurred() }
        case .bell, .curtain: break
        }
    }

    func play(_ event: Feedback.Event) {
        if feels { feel(event) }
        guard hears else { return }
        let (key, volume): (String, Float)
        switch event {
        case .countdown: (key, volume) = ("countdown", 0.7)
        case .go: (key, volume) = ("go", 0.8)
        case .score(let n): (key, volume) = ("score\(min(max(n, 0), 16))", 0.75)
        case .otherScore:
            // Seven others scoring at once should be a patter, not a din.
            let now = CACurrentMediaTime()
            guard now - lastQuiet > 0.14 else { return }
            lastQuiet = now
            (key, volume) = ("other", 0.22)
        case .dash: (key, volume) = ("dash", 0.5)
        case .pickup: (key, volume) = ("pickup", 0.45)
        case .nearMiss: (key, volume) = ("near", 0.5)
        case .hit: (key, volume) = ("penalty", 0.85)
        case .bump: (key, volume) = ("bump", 0.35)
        case .warn: (key, volume) = ("warn", 0.3)
        case .strike: (key, volume) = ("burst", 0.45)
        case .lightsOut: (key, volume) = ("lightsOut", 0.6)
        case .lightsOn: (key, volume) = ("lightsOn", 0.4)
        case .spill: (key, volume) = ("spill", 0.8)
        case .sealing: (key, volume) = ("sealing", 0.6)
        case .banner: (key, volume) = ("banner", 0.55)
        case .hand: (key, volume) = ("hand", 0.5)
        case .teamGoal: (key, volume) = ("teamGoal", 0.75)
        case .lastSeconds: (key, volume) = ("heartbeat", 0.7)
        case .time: (key, volume) = ("time", 0.85)
        case .tap: (key, volume) = ("tap", 0.4)
        case .toggle: (key, volume) = ("toggle", 0.4)
        case .row: (key, volume) = ("row", 0.25)
        case .pause: (key, volume) = ("pause", 0.45)
        }
        sound.play("arena." + key, volume: volume) { ArenaSynth.render(key) }
    }

    /// Every sound a mini-game can ask for, by the name `ArenaSynth` knows it by.
    private static let arenaKeys = ["countdown", "go", "other", "dash", "pickup", "near", "penalty", "bump", "warn", "burst", "lightsOut",
                                    "lightsOn", "spill", "sealing", "banner", "hand", "teamGoal", "heartbeat", "time", "tap", "toggle",
                                    "row", "pause"] + (0...16).map { "score\($0)" }

    func prepare() {
        guard feels else { return }
        light.prepare()
        heavy.prepare()
        soft.prepare()
        notice.prepare()
    }

    private func feel(_ event: Feedback.Event) {
        switch event {
        case .countdown, .score, .tap, .dash: light.impactOccurred()
        case .go, .time, .spill: heavy.impactOccurred()
        case .hit:
            heavy.impactOccurred()
            notice.notificationOccurred(.error)
        case .teamGoal: notice.notificationOccurred(.success)
        case .banner, .pause, .bump, .nearMiss, .sealing: soft.impactOccurred()
        case .lastSeconds: soft.impactOccurred(intensity: 0.6)
        case .toggle, .pickup, .hand: selection.selectionChanged()
        case .otherScore, .row, .warn, .strike, .lightsOut, .lightsOn: break
        }
    }

    func setBed(_ bed: Bed?, level: Float) { sound.setBed(bed, level: level) }

    func warmUp() {
        for sting in Sting.allCases { sound.make("sting." + sting.rawValue) { Synth.render(sting) } }
        for key in Self.arenaKeys { sound.make("arena." + key) { ArenaSynth.render(key) } }
    }

    func suspend() { sound.suspend() }
    func resume() { sound.resume() }
}

/// Plays nothing and remembers everything it was asked for, in order.
final class RecordingEffects: Effects {
    enum Asked: Equatable {
        case cue(Cue)
        case event(Feedback.Event)
        case bed(Bed?)
    }

    var settings = Settings()
    var muted = false
    private(set) var asked: [Asked] = []

    var cues: [Cue] { asked.compactMap { if case .cue(let c) = $0 { return c } else { return nil } } }
    var events: [Feedback.Event] { asked.compactMap { if case .event(let e) = $0 { return e } else { return nil } } }

    func play(_ cue: Cue) { asked.append(.cue(cue)) }
    func play(_ event: Feedback.Event) { asked.append(.event(event)) }
    func prepare() {}
    func setBed(_ bed: Bed?, level: Float) { asked.append(.bed(bed)) }
    func warmUp() {}
    func suspend() {}
    func resume() {}
}
