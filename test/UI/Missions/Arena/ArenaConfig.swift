import SpriteKit

/// One player as the screen needs to know them.
struct Contestant {
    let id: PlayerID
    let name: String
    let color: UIColor
    let isHuman: Bool
}

struct ArenaConfig {
    let setup: ArenaSetup
    /// Everyone playing, in seat order.
    let cast: [Contestant]
    /// True only for a living traitor, who has the shadow's hand. Nobody else is shown anything of it.
    let handVisible: Bool
    /// The human is out of the game and only watches the others play.
    let spectating: Bool

    func color(_ seat: PlayerID) -> UIColor { cast.first { $0.id == seat }?.color ?? Toon.cream }
}

/// The screen the gauntlet is drawn on. It is always 390 points wide, which is the width of a
/// course, so the whole corridor is in view. Only the height follows the device.
struct ArenaLayout {
    static let width: CGFloat = 390
    let height: CGFloat
    /// What the status bar and the home indicator take, in the same points.
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var size: CGSize { CGSize(width: Self.width, height: height) }
    var centre: CGPoint { CGPoint(x: Self.width / 2, y: height / 2) }
    /// The lowest the tally along the top reaches.
    var hudFloor: CGFloat { height - safeTop - 140 }
}
