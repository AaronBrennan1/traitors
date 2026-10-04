import UIKit

/// Everything the game says back to the hand and the ear. One call per moment; the settings decide
/// what of it is felt or heard.
enum Feedback {
    enum Event {
        /// The 3, 2, 1 before a round, and the bell that starts it.
        case countdown, go
        /// Your own count going up, to the given number, and your own penalty.
        case score(Int), penalty
        case otherScore, teamBonus
        case banner, shake, burst
        case holdTick, holdDone
        case par, teamGoal
        case questStep, questDone
        case lastSeconds, time
        /// Buttons and switches outside the arena.
        case tap, toggle, row, pause
    }

    static var settings = Settings()
    /// Set by `-mute 1`, so unattended runs stay quiet whatever the settings say.
    static var muted = false

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func play(_ event: Event) {
        if settings.haptics, !muted { haptic(event) }
        ArenaSounds.play(event)
    }

    private static func haptic(_ event: Event) {
        switch event {
        case .countdown, .score, .holdDone, .tap: light.impactOccurred()
        case .go, .time, .shake: heavy.impactOccurred()
        case .penalty: notice.notificationOccurred(.error)
        case .par, .teamGoal, .questDone: notice.notificationOccurred(.success)
        case .banner, .burst, .questStep, .pause: soft.impactOccurred()
        case .lastSeconds: soft.impactOccurred(intensity: 0.6)
        case .toggle: selection.selectionChanged()
        case .otherScore, .teamBonus, .holdTick, .row: break
        }
    }
}
