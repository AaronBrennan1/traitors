import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// Draws a mini-game. The rules live in the game; a stage only shows what is there.
protocol ArenaStage: SKNode {
    /// Draws the game as it stands, `alpha` of the way from the last step to the next.
    func sync(alpha: Double, dt: TimeInterval)
    /// Where a point of the arena is on the screen.
    func screenPoint(_ p: Vec2) -> CGPoint
    /// Turns the stick into the arena's own axes.
    func arenaVector(_ v: CGVector) -> Vec2
    /// Whether a point of the arena is near enough the picture to be worth a sound.
    func inEarshot(_ p: Vec2) -> Bool
    func figure(_ seat: PlayerID) -> Courtier?
    /// Jolts the picture, 0...1. Nothing moves in the game itself.
    func shake(_ amount: CGFloat)
    /// Screen points to one point of the arena, for the edge of what the player can see.
    var pointScale: CGFloat { get }
    /// What shows wherever the stage draws nothing.
    var backdrop: UIColor { get }
}

extension ArenaStage {
    func arenaVector(_ v: CGVector) -> Vec2 { Vec2(Double(v.dx), Double(v.dy)) }
    var pointScale: CGFloat { 1 }
}

extension CourseStage: ArenaStage {
    var backdrop: UIColor { Toon.pit }
}

extension ArenaLayout {
    /// The height the side-on stages are drawn for.
    static let base: CGFloat = 600
    /// How far a side-on stage is raised, so its ground clears the thumbs and its sky runs up under the tally.
    var lift: CGFloat { (height - Self.base) * 0.45 }
}

enum ArenaStages {
    static func make(_ config: ArenaConfig, _ game: any ArenaGame, _ layout: ArenaLayout) -> any ArenaStage {
        if let gauntlet = game as? Gauntlet { return CourseStage(config, gauntlet, layout) }
        let core = game as! ArenaCore
        switch config.setup.kind {
        case .bogRelay: return BogStage(config, core, layout)
        case .shipwreckDive: return ShipStage(config, core, layout)
        case .kiteRace: return KiteStage(config, core, layout)
        case .hurley: return HurleyStage(config, core, layout)
        case .lanternRun: return LanternStage(config, core, layout)
        case .sheepRoundUp: return SheepStage(config, core, layout)
        case .ceiliChaos: return CeiliStage(config, core, layout)
        case .marketDay: return MarketStage(config, core, layout)
        case .hedgeMaze: return MazeStage(config, core, layout)
        case .banquetPrep: return BanquetStage(config, core, layout)
        case .greatHall, .cellars, .armoury, .battlements, .crypt: return CoreStage(config, core, layout)
        }
    }
}
