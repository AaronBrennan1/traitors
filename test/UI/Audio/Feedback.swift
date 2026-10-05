import UIKit

/// Everything the game says back to the hand and the ear. One call per moment; the settings decide
/// what of it is felt or heard.
enum Feedback {
    enum Event {
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

    /// Wakes the haptics up, so the next one lands on time and not a beat late.
    static func prepare() {
        guard settings.haptics, !muted else { return }
        light.prepare()
        heavy.prepare()
        soft.prepare()
        notice.prepare()
    }

    private static func haptic(_ event: Event) {
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
}
