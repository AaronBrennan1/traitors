import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// The colours of the outdoor games: bog and moss, limestone, sea.
extension Toon {
    static let bog = Tokens.Hue.bog.ui
    static let bogWater = Tokens.Hue.bogWater.ui
    static let moss = Tokens.Hue.mossGreen.ui
    static let heather = Tokens.Hue.heather.ui
    static let limestone = Tokens.Hue.limestone.ui
    static let slate = Tokens.Hue.slate.ui
    static let turf = Tokens.Hue.turf.ui
    static let sea = Tokens.Hue.sea.ui
    static let hedge = Tokens.Hue.hedge.ui
    /// The three pens of the round-up.
    static let ribbons = Tokens.Hue.ribbons.map(\.ui)
}

/// Draws any of the games that are not the gauntlet: the players as little hooded figures, and
/// whatever the game says is lying about. Each game's own stage lays down the ground and says how
/// an arena point falls on the screen.
class CoreStage: SKNode, ArenaStage {
    let config: ArenaConfig
    let core: ArenaCore
    let layout: ArenaLayout
    private(set) var figures: [PlayerID: Courtier] = [:]
    private var props: [String: SKNode] = [:]
    private var marks: [(works: Int, node: SKNode)] = []
    private var dazed: Set<PlayerID> = []
    /// The left edge of what is on screen, in arena points.
    var cameraX = 0.0
    /// Layers that slide at a fraction of the camera's speed.
    private var layers: [(node: SKNode, rate: CGFloat)] = []
    private var trauma: CGFloat = 0
    /// Something to lay over the whole screen, above the dark: a map, say.
    var overlay: SKNode?

    init(_ config: ArenaConfig, _ core: ArenaCore, _ layout: ArenaLayout) {
        self.config = config
        self.core = core
        self.layout = layout
        super.init()
        setScale(zoom)
        position = home
        build()
        air()
        for c in config.cast {
            let f = Courtier(color: c.color, name: c.name, you: c.isHuman && !config.spectating)
            figures[c.id] = f
            addChild(f)
        }
        // What the hand can work, marked for a traitor and nobody else.
        if config.setup.humanHasHand {
            for w in core.works {
                let m = Stagecraft.handMark()
                addChild(m)
                marks.append((w.id, m))
            }
        }
        populated()
        sync(alpha: 1, dt: 0)
    }

    required init?(coder: NSCoder) { return nil }

    // MARK: For each game

    /// Lays down the ground.
    func build() {}
    /// Called once the players are standing on it.
    func populated() {}
    /// Where an arena point falls in the stage's own space, and how big things there are drawn.
    func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) { (CGPoint(x: p.x - cameraX, y: p.y + z), 1) }
    func makeProp(_ p: Prop) -> SKNode? { nil }
    func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {}
    /// Shows what a player is carrying or doing.
    func dress(_ figure: Courtier, _ a: ArenaActor) {}
    /// Anything else to do each frame.
    func frame(_ dt: TimeInterval) {}
    /// Where the mark over something the hand can work goes.
    func markPoint(_ w: Works) -> CGPoint {
        let at = project(w.pos, z: 0).0
        return CGPoint(x: at.x, y: at.y + 24)
    }
    /// How wide the arena is, for a camera that follows. Nil keeps the camera still.
    var scrollWidth: Double? { nil }
    /// How far from the left of the screen the followed player is kept.
    var lead: Double { 195 }
    /// Where the stage sits on the screen when nothing is shaking it, and how big it is drawn.
    var home: CGPoint { CGPoint(x: 0, y: layout.lift) }
    var zoom: CGFloat { 1 }
    var pointScale: CGFloat { zoom }
    var backdrop: UIColor { Toon.outline }
    var figureScale: CGFloat { 1 }
    /// How far a figure is drawn above the point it stands on, so that its feet are on it.
    var figureLift: CGFloat { 0 }
    /// Whether being stunned shows as a daze. Not where the game uses it for something else.
    var stunShows: Bool { true }

    /// How thick the drifting mist is, and what colour. Nought for none.
    var mist: CGFloat { 0 }
    var mistColor: UIColor { Toon.mist }
    /// What drifts in the air: pollen, spray, silt. Nil for nothing.
    var motes: UIColor? { nil }

    // MARK: Shared

    /// The air between the scene and the eye: mist that drifts and motes that float.
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

    func screenPoint(_ p: Vec2) -> CGPoint {
        let at = project(p, z: 0).0
        return CGPoint(x: home.x + at.x * zoom, y: home.y + at.y * zoom)
    }

    func inEarshot(_ p: Vec2) -> Bool { scrollWidth == nil || abs(p.x - cameraX - 195) < 320 }
    func figure(_ seat: PlayerID) -> Courtier? { figures[seat] }

    func shake(_ amount: CGFloat) {
        if !Tokens.Motion.reduced { trauma = min(1, trauma + amount) }
    }

    /// How far the sky has to run above a side-on stage, and the ground below it, to fill a tall screen.
    var bleedUp: CGFloat { layout.height - layout.lift }
    var bleedDown: CGFloat { layout.lift + 12 }

    /// Fills in under the ground, down to the bottom of a tall screen.
    func apron(_ color: UIColor, z: CGFloat = -42) {
        let n = Stagecraft.rect(CGSize(width: ArenaLayout.width, height: bleedDown + 2), color)
        n.position.y = -bleedDown
        n.zPosition = z
        addChild(n)
    }

    func sync(alpha: Double, dt: TimeInterval) {
        if let width = scrollWidth, let f = focus {
            let want = clamp(f.pos.x - lead, 0, max(0, width - 390))
            cameraX += (want - cameraX) * (dt == 0 ? 1 : 1 - exp(-6 * dt))
        }
        for l in layers { l.node.position.x = -CGFloat(cameraX) * l.rate }
        trauma = max(0, trauma - CGFloat(dt) * 1.6)
        let jolt = trauma * trauma * 9
        position = CGPoint(x: home.x + jolt * CGFloat.random(in: -1...1), y: home.y + jolt * CGFloat.random(in: -1...1))
        frame(dt)

        let me = core.human
        let ease = dt == 0 ? 1 : CGFloat(1 - exp(-8 * dt))
        for a in core.actors {
            guard let f = figures[a.id] else { continue }
            let p = a.last + (a.pos - a.last) * alpha
            let (pt, scale) = project(p, z: 0)
            f.position = CGPoint(x: pt.x, y: pt.y + figureLift)
            f.setScale(scale * figureScale)
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
            f.alpha += ((seen ? 1 : 0) - f.alpha) * ease
            dress(f, a)
        }

        var live: Set<String> = []
        for p in core.props() {
            let key = "\(p.kind.rawValue)-\(p.id)"
            live.insert(key)
            var node = props[key]
            var fresh = false
            if node == nil {
                guard let made = makeProp(p) else { continue }
                props[key] = made
                addChild(made)
                node = made
                fresh = true
            }
            guard let node else { continue }
            let (pt, scale) = project(p.pos, z: p.z)
            // The game moves in steps. What it moves is eased from one to the next.
            let glide = fresh || dt == 0 ? 1 : CGFloat(1 - exp(-28 * dt))
            node.position = CGPoint(x: node.position.x + (pt.x - node.position.x) * glide, y: node.position.y + (pt.y - node.position.y) * glide)
            node.setScale(scale)
            node.zPosition = 500 - project(p.pos, z: 0).0.y - 1
            node.isHidden = p.hidden
            updateProp(node, p, dt: dt)
        }
        for (key, node) in props where !live.contains(key) {
            node.removeFromParent()
            props[key] = nil
        }
        for (id, node) in marks {
            guard let w = core.works.first(where: { $0.id == id }) else { continue }
            node.position = markPoint(w)
            node.zPosition = 540
            node.alpha = core.worksUsable(w) ? 1 : 0.25
        }
    }
}

/// Bits of scenery and marking shared by the stages.
enum Stagecraft {
    /// The mark only a traitor sees: a red diamond bobbing over whatever the hand can work.
    static func handMark() -> SKNode {
        let m = Props.sprite("handmark", CGSize(width: 14, height: 18)) { c in
            Props.ink(c, Props.poly([(7, 2), (12, 9), (7, 16), (2, 9)]), Toon.red.shaded(1.15), line: 2)
        }
        let holder = SKNode()
        holder.addChild(m)
        if !Tokens.Motion.reduced {
            m.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.45), .moveBy(x: 0, y: -4, duration: 0.45)])))
        }
        return holder
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
                c.setFillColor(Toon.mist.withAlphaComponent(haze).cgColor)
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
