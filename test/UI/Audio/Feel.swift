import UIKit

enum Haptics {
    static func tap() { if Senses.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func knock() { if Senses.haptics { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() } }
    static func thud() { if Senses.haptics { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    static func good() { if Senses.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func bad() { if Senses.haptics { UINotificationFeedbackGenerator().notificationOccurred(.error) } }

    /// Two beats, the second softer.
    static func heartbeat() {
        guard Senses.haptics else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
        Task {
            try? await Task.sleep(for: .seconds(0.22))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        }
    }
}

/// One thing happening in a scene: its sound and what the hand feels, fired together.
enum Cue {
    case slate, lateSlate, door, bell, boom, heartbeat, footstep, shoulder, declare(Role?), letter, snuff, curtain

    func play() {
        switch self {
        case .slate: Soundscape.shared.play(.knock, volume: 0.5); Haptics.tap()
        case .lateSlate: Soundscape.shared.play(.knock, volume: 0.8); Haptics.knock()
        case .door: Soundscape.shared.play(.door, volume: 0.5); Haptics.tap()
        case .bell: Soundscape.shared.play(.bell, volume: 0.55)
        case .boom: Soundscape.shared.play(.boom, volume: 0.8); Haptics.thud()
        case .heartbeat: Soundscape.shared.play(.heartbeat, volume: 0.8); Haptics.heartbeat()
        case .footstep: Soundscape.shared.play(.footstep, volume: 0.45); Haptics.tap()
        case .shoulder: Soundscape.shared.play(.boom, volume: 0.9); Haptics.thud()
        case .declare(let role):
            Soundscape.shared.play(role == .traitor ? .dread : role == .faithful ? .relief : .boom, volume: 0.7)
            if role == .traitor { Haptics.bad() } else if role == .faithful { Haptics.good() } else { Haptics.thud() }
        case .letter: Soundscape.shared.play(.quill, volume: 0.6); Haptics.tap()
        case .snuff: Soundscape.shared.play(.snuff, volume: 0.6); Haptics.tap()
        case .curtain: Soundscape.shared.play(.bell, volume: 0.35)
        }
    }
}
