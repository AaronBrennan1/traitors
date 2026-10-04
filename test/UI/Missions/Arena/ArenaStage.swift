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
    /// True only for a living traitor on a day the side quest is open. Nobody else is shown the marks.
    let questVisible: Bool
    /// The human is out of the game and only watches the others play.
    let spectating: Bool

    func color(_ seat: PlayerID) -> UIColor { cast.first { $0.id == seat }?.color ?? Toon.cream }
}

/// The screen a mini-game is drawn on. It is always 390 points wide, because in the games that
/// scroll the width is how far ahead you can see. Only the height follows the device.
struct ArenaLayout {
    static let width: CGFloat = 390
    /// The height every stage was first drawn for.
    static let base: CGFloat = 600
    let height: CGFloat
    /// What the status bar and the home indicator take, in the same points.
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var size: CGSize { CGSize(width: Self.width, height: height) }
    var centre: CGPoint { CGPoint(x: Self.width / 2, y: height / 2) }
    /// How far a side-on stage is raised, so its ground clears the thumbs and its sky runs up under the scores.
    var lift: CGFloat { (height - Self.base) * 0.45 }
    /// The lowest the scores along the top reach.
    var hudFloor: CGFloat { height - safeTop - 132 }

    static let standard = ArenaLayout(height: base, safeTop: 0, safeBottom: 0)
}

/// Draws a mini-game. The rules live in the `ArenaCore`; a stage only shows what is there.
protocol ArenaStage: AnyObject {
    func sync(_ core: ArenaCore, dt: TimeInterval)
    /// Where a point of the arena is on the screen.
    func screenPoint(_ p: Vec2, z: Double) -> CGPoint
    /// Turns the thumb-stick, in screen directions, into the arena's own axes.
    func arenaVector(_ v: CGVector) -> Vec2
    /// Screen points to one arena point, for sizing the edge of what the player can see.
    var pointScale: CGFloat { get }
    /// How much the ground is foreshortened up the screen: 1 side-on, less from above.
    var squash: CGFloat { get }
    /// Jolts the picture. Nothing moves in the game itself.
    func shake(_ amount: CGFloat)
}

enum ArenaStages {
    static func make(_ config: ArenaConfig, _ core: ArenaCore, _ layout: ArenaLayout) -> ArenaStage {
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
        }
    }
}

/// The colours of the Irish games: bog and moss, limestone, lantern light.
extension Toon {
    static let bog = Tokens.Hue.bog.ui
    static let bogWater = Tokens.Hue.bogWater.ui
    static let moss = Tokens.Hue.mossGreen.ui
    static let heather = Tokens.Hue.heather.ui
    static let limestone = Tokens.Hue.limestone.ui
    static let slate = Tokens.Hue.slate.ui
    static let turf = Tokens.Hue.turf.ui
    static let lantern = Tokens.Hue.ember.ui
    static let sky = Tokens.Hue.sky.ui
    static let sea = Tokens.Hue.sea.ui
    static let hedge = Tokens.Hue.hedge.ui
    /// The three pens of the round-up.
    static let ribbons = Tokens.Hue.ribbons.map(\.ui)
}

/// A side-on game drawn in SpriteKit: a backdrop in layers that slide past each other, the
/// players as little hooded figures, and whatever the core says is lying about.
class SideOnStage: SKNode, ArenaStage {
    let config: ArenaConfig
    let core: ArenaCore
    let layout: ArenaLayout
    private(set) var figures: [PlayerID: Courtier] = [:]
    private var props: [String: SKNode] = [:]
    private var dazed: Set<PlayerID> = []
    /// The left edge of what is on screen, in arena points.
    var cameraX = 0.0
    /// Layers that slide at a fraction of the camera's speed: how far each has to travel, and how fast.
    private var layers: [(node: SKNode, rate: CGFloat)] = []

    init(_ config: ArenaConfig, _ core: ArenaCore, _ layout: ArenaLayout) {
        self.config = config
        self.core = core
        self.layout = layout
        super.init()
        build()
        air()
        for c in config.cast {
            let f = Courtier(color: c.color, name: c.name, you: c.isHuman && !config.spectating)
            figures[c.id] = f
            addChild(f)
        }
        populated()
        sync(core, dt: 0)
    }

    required init?(coder: NSCoder) { return nil }

    // MARK: For each game

    /// Lays down the backdrop.
    func build() {}
    /// Called once the players are standing in it.
    func populated() {}
    /// Where an arena point falls on screen, and how big things there are drawn.
    func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) { (CGPoint(x: p.x - cameraX, y: p.y), 1) }
    func makeProp(_ p: Prop) -> SKNode? { nil }
    func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {}
    /// Shows what a player is carrying or doing.
    func dress(_ figure: Courtier, _ a: ArenaActor) {}
    /// Anything else to do each frame.
    func frame(_ dt: TimeInterval) {}
    /// How wide the arena is, for a camera that follows. Nil keeps the camera still.
    var scrollWidth: Double? { nil }
    /// How far from the left of the screen the followed player is kept.
    var lead: Double { 195 }
    var pointScale: CGFloat { 1 }
    var squash: CGFloat { 1 }

    /// How thick the drifting mist is, and what colour. Nought for none.
    var mist: CGFloat { 0.10 }
    var mistColor: UIColor { Tokens.Hue.mist.ui }
    /// What drifts in the air: pollen, spray, silt. Nil for nothing.
    var motes: UIColor? { Toon.cream }
    var vignette: CGFloat { 0.75 }

    // MARK: Shared

    /// The air between the scene and the eye: mist that drifts, motes that float, the corners drawn down.
    /// It lies over everything, so every stage gets it without asking.
    private func air() {
        let tall = bleedUp + bleedDown
        let mid = CGPoint(x: ArenaLayout.width / 2, y: (bleedUp - bleedDown) / 2)
        let still = Tokens.Motion.reduced
        if mist > 0 {
            for i in 0..<2 {
                let bank = Sprites.haze(mistColor, size: CGSize(width: 620, height: 210), alpha: mist * (i == 0 ? 1 : 0.7))
                bank.position = CGPoint(x: i == 0 ? 60 : 330, y: i == 0 ? 190 : 330)
                bank.zPosition = 575
                addChild(bank)
                if !still {
                    let travel: CGFloat = i == 0 ? 150 : -120, time = i == 0 ? 17.0 : 23.0
                    let out = SKAction.moveBy(x: travel, y: 0, duration: time), back = SKAction.moveBy(x: -travel, y: 0, duration: time)
                    out.timingMode = .easeInEaseOut
                    back.timingMode = .easeInEaseOut
                    bank.run(.repeatForever(.sequence([out, back])))
                }
            }
        }
        if let motes, !still {
            let e = SKEmitterNode()
            e.particleTexture = Sprites.glow(.white, radius: 8).texture
            e.particleSize = CGSize(width: 9, height: 9)
            e.particleColor = motes
            e.particleColorBlendFactor = 1
            e.particleBlendMode = .add
            e.particleBirthRate = 4
            e.particleLifetime = 8
            e.particleLifetimeRange = 3
            e.particlePositionRange = CGVector(dx: ArenaLayout.width, dy: tall * 0.8)
            e.particleSpeed = 7
            e.particleSpeedRange = 5
            e.emissionAngleRange = 2 * .pi
            e.xAcceleration = 2
            e.particleAlpha = 0
            e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.42, 0.42, 0], times: [0, 0.2, 0.75, 1])
            e.particleScale = 0.3
            e.particleScaleRange = 0.16
            e.position = mid
            e.zPosition = 585
            e.advanceSimulationTime(8)
            addChild(e)
        }
        if vignette > 0 {
            let v = Sprites.vignette(size: CGSize(width: ArenaLayout.width * 1.5, height: tall * 1.12), strength: vignette)
            v.position = mid
            v.zPosition = 593
            addChild(v)
        }
    }

    func layer(_ node: SKNode, rate: CGFloat, z: CGFloat) {
        node.zPosition = z
        addChild(node)
        layers.append((node, rate))
    }

    /// Whoever the camera follows: the human, or the front runner when only watching.
    var focus: ArenaActor? {
        core.human ?? core.actors.max { core.count(of: $0) < core.count(of: $1) }
    }

    /// The stage is drawn as if on the old short screen and raised whole, so nothing in `project` has to know.
    func screenPoint(_ p: Vec2, z: Double) -> CGPoint {
        let at = project(p, z: z).0
        return CGPoint(x: at.x, y: at.y + layout.lift)
    }

    func shake(_ amount: CGFloat) {
        if !Tokens.Motion.reduced { FX.shake(self, amount: amount) }
    }

    /// How far the sky has to run above the old screen, and the ground below it, to fill a tall one.
    var bleedUp: CGFloat { layout.height - layout.lift }
    var bleedDown: CGFloat { layout.lift + 12 }

    /// Fills in under the ground, down to the bottom of a tall screen.
    func apron(_ color: UIColor, z: CGFloat = -42) {
        let n = Stagecraft.rect(CGSize(width: ArenaLayout.width, height: bleedDown + 2), color)
        n.position.y = -bleedDown
        n.zPosition = z
        addChild(n)
    }
    func arenaVector(_ v: CGVector) -> Vec2 { Vec2(Double(v.dx), Double(v.dy)) }

    func sync(_ core: ArenaCore, dt: TimeInterval) {
        if let width = scrollWidth, let f = focus {
            let want = clamp(f.pos.x - lead, 0, max(0, width - 390))
            cameraX += (want - cameraX) * min(1, dt * 6 + (dt == 0 ? 1 : 0))
        }
        for l in layers { l.node.position.x = -CGFloat(cameraX) * l.rate }
        frame(dt)

        let me = core.human
        for a in core.actors {
            guard let f = figures[a.id] else { continue }
            let (pt, scale) = project(a.pos, z: 0)
            f.position = pt
            f.setScale(scale)
            f.zPosition = 500 - pt.y
            f.animate(dt, velocity: CGVector(dx: a.vel.x, dy: a.vel.y))
            if a.stun > 0.2, !dazed.contains(a.id), stunShows {
                dazed.insert(a.id)
                f.daze(a.stun)
            } else if a.stun <= 0 {
                dazed.remove(a.id)
            }
            // In the games where sight is short, the others are only there when you can see them.
            let seen = me == nil || a === me || !core.hidesUnseen || a.seenBy.has(me!.id)
            f.alpha += ((seen ? 1 : 0) - f.alpha) * min(1, CGFloat(dt) * 8 + (dt == 0 ? 1 : 0))
            dress(f, a)
        }

        var live: Set<String> = []
        for p in core.props() {
            let key = "\(p.kind.rawValue)-\(p.id)"
            live.insert(key)
            var node = props[key]
            if node == nil {
                guard let made = makeProp(p) else { continue }
                props[key] = made
                addChild(made)
                node = made
            }
            guard let node else { continue }
            let (pt, scale) = project(p.pos, z: p.z)
            node.position = pt
            node.setScale(scale)
            node.zPosition = 500 - project(p.pos, z: 0).0.y - 1
            node.isHidden = p.hidden
            mark(node, on: p.secret && config.questVisible)
            updateProp(node, p, dt: dt)
        }
        for (key, node) in props where !live.contains(key) {
            node.removeFromParent()
            props[key] = nil
        }
    }

    /// Whether being stunned shows as a daze. Not where the core uses it for something else.
    var stunShows: Bool { true }

    /// The mark only a traitor on the side quest sees: a red diamond bobbing over the thing.
    private func mark(_ node: SKNode, on: Bool) {
        let existing = node.childNode(withName: "mark")
        if on, existing == nil {
            let m = Stagecraft.questMark()
            m.name = "mark"
            m.position = CGPoint(x: 0, y: 26)
            m.zPosition = 50
            node.addChild(m)
        } else if !on {
            existing?.removeFromParent()
        }
    }
}

/// Bits of scenery and marking shared by the side-on stages.
enum Stagecraft {
    static func questMark() -> SKNode {
        let m = Props.sprite("questmark", CGSize(width: 18, height: 22)) { c in
            Props.ink(c, Props.poly([(9, 2), (16, 11), (9, 20), (2, 11)]), Toon.red.shaded(1.15), line: 2.5)
        }
        m.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.45), .moveBy(x: 0, y: -5, duration: 0.45)])))
        return m
    }

    /// A sky that is one colour overhead and another at the horizon, the height asked for.
    static func sky(_ key: String, height: CGFloat, top: UIColor, horizon: UIColor, horizonAt: CGFloat = 0.72) -> SKSpriteNode {
        let size = CGSize(width: ArenaLayout.width, height: height)
        let texture = Props.texture("sky|\(key)|\(Int(height))", size, scale: 1) { c in
            Props.wash(c, CGRect(origin: .zero, size: size), [(top, 0), (horizon, horizonAt), (horizon.shaded(1.12), 1)])
        }
        let node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = .zero
        return node
    }

    /// A band of land as wide as needed, with a ragged top edge drawn from a seed. It is lit along
    /// its top and falls away into shadow, and `haze` greys it for distance.
    static func band(_ key: String, width: CGFloat, height: CGFloat, color: UIColor, rough: CGFloat, seed: UInt64, outline: Bool = true,
                     haze: CGFloat = 0) -> SKSpriteNode {
        let size = CGSize(width: width, height: height + rough)
        let texture = Props.texture("band|\(key)", size, scale: 2) { c in
            var rng = SeededRNG(seed: seed)
            var pts: [(CGFloat, CGFloat)] = [(0, height + rough)]
            var x: CGFloat = 0
            while x <= width {
                pts.append((x, rough > 0 ? rng.cg(0, rough) : 0))
                x += max(18, rough * 1.4)
            }
            pts.append((width, rough > 0 ? rng.cg(0, rough) : 0))
            pts.append((width, height + rough))
            let path = Props.poly(pts)
            c.saveGState()
            c.addPath(path)
            c.clip()
            Props.wash(c, CGRect(origin: .zero, size: size), [(color.shaded(1.12), 0), (color, 0.35), (color.shaded(0.6), 1)])
            if haze > 0 {
                c.setFillColor(Tokens.Hue.mist.ui.withAlphaComponent(haze).cgColor)
                c.fill(CGRect(origin: .zero, size: size))
            }
            c.restoreGState()
            if outline {
                // Only the top edge catches the light.
                let top = CGMutablePath()
                for (i, pt) in pts.dropFirst().dropLast().enumerated() {
                    if i == 0 { top.move(to: CGPoint(x: pt.0, y: pt.1)) } else { top.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
                }
                Props.stroke(c, top, color.shaded(1.35).withAlphaComponent(0.55), 1.5)
            }
        }
        let node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = .zero
        return node
    }

    static func rect(_ size: CGSize, _ color: UIColor) -> SKSpriteNode {
        let n = SKSpriteNode(color: color, size: size)
        n.anchorPoint = .zero
        return n
    }
}
