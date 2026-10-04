import SpriteKit

/// Cliffside Kite Race: the cliff path along the bottom, sea stacks in the middle distance and
/// the open sea behind. The camera runs with the player.
final class KiteStage: SideOnStage {
    private static let cliff: CGFloat = 150

    override var scrollWidth: Double? { core.size.x }
    override var lead: Double { 110 }

    override func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) {
        let x = CGFloat(p.x - cameraX)
        if z > 0 { return (CGPoint(x: x, y: Self.cliff + 10 + CGFloat(z) * 1.35), 1) }
        return (CGPoint(x: x, y: 84 + CGFloat(p.y) * 0.9), 0.9)
    }

    override func build() {
        // The edge of a storm: dark overhead, a band of pale gold along the horizon.
        let sky = Stagecraft.sky("kite", height: bleedUp, top: UIColor(red: 0.10, green: 0.13, blue: 0.19, alpha: 1),
                                 horizon: UIColor(red: 0.80, green: 0.70, blue: 0.50, alpha: 1), horizonAt: 0.56)
        sky.zPosition = -50
        addChild(sky)
        // Cloud in two banks, the nearer sliding past the further.
        for (i, y) in [470.0, 395.0].enumerated() {
            let bank = SKNode()
            var rng = SeededRNG(seed: UInt64(60 + i))
            for k in 0..<7 {
                let puff = Sprites.haze(UIColor(red: 0.20, green: 0.23, blue: 0.30, alpha: 1), size: CGSize(width: rng.cg(180, 300), height: rng.cg(50, 90)), alpha: 0.75)
                puff.position = CGPoint(x: CGFloat(k) * 150 + rng.cg(-30, 30), y: y + Double(rng.cg(-18, 18)))
                bank.addChild(puff)
            }
            layer(bank, rate: i == 0 ? 0.03 : 0.06, z: -48 + CGFloat(i))
        }
        let sea = Props.sprite("kite-sea", CGSize(width: 390, height: 190)) { c in
            Props.wash(c, CGRect(x: 0, y: 0, width: 390, height: 190), [(UIColor(red: 0.62, green: 0.60, blue: 0.48, alpha: 1), 0), (Toon.sea.shaded(1.1), 0.12), (Toon.sea.shaded(0.5), 1)])
            var rng = SeededRNG(seed: 52)
            for _ in 0..<40 {
                let y = rng.cg(10, 185)
                Props.fill(c, Props.rr(rng.cg(0, 380), y, rng.cg(6, 20) * (0.4 + y / 190), 1.4, 0.7), Toon.cream.withAlphaComponent(0.10 + 0.14 * y / 190))
            }
        }
        sea.anchorPoint = .zero
        sea.position.y = Self.cliff - 20
        sea.zPosition = -46
        addChild(sea)
        let headland = Stagecraft.band("kite-head", width: 900, height: 30, color: Toon.moss.shaded(0.5), rough: 46, seed: 6, outline: false, haze: 0.28)
        headland.position.y = 300
        layer(headland, rate: 0.08, z: -45)

        // The cliff top, laid end to end for the length of the course.
        let ground = SKNode()
        var x: CGFloat = -40
        var i = 0
        while x < CGFloat(core.size.x) + 400 {
            let grass = Stagecraft.band("kite-grass\(i % 3)", width: 600, height: Self.cliff - 16, color: Toon.grass.shaded(0.85), rough: 12, seed: UInt64(20 + i % 3))
            grass.position.x = x
            ground.addChild(grass)
            x += 598
            i += 1
        }
        layer(ground, rate: 1, z: -20)
        apron(Toon.grass.shaded(0.5), z: -21)
        // The finish.
        if let kite = core as? KiteCore {
            let post = Props.flag(Toon.gold)
            post.position = CGPoint(x: CGFloat(kite.course), y: Self.cliff + 6)
            ground.addChild(post)
        }
    }

    /// Spray off the sea.
    override var motes: UIColor? { UIColor(white: 1, alpha: 1) }
    override var mist: CGFloat { 0.08 }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .ring:
            let ring = SKShapeNode(ellipseOf: CGSize(width: 22, height: 58))
            ring.strokeColor = Toon.ember
            ring.lineWidth = 4
            ring.glowWidth = 3
            ring.fillColor = Toon.gold.withAlphaComponent(0.10)
            return ring
        case .spire:
            // A sea stack: the tip is where the node sits and the rock runs down into the sea.
            let tall: CGFloat = 420
            let rock = Props.sprite("stack", CGSize(width: 54, height: tall)) { c in
                Props.ink(c, Props.poly([(27, 2), (36, 40), (44, 110), (50, tall), (4, tall), (12, 100), (20, 36)]), Toon.slate)
                Props.fill(c, Props.poly([(27, 4), (32, 40), (27, 60), (22, 38)]), Toon.limestone)
            }
            rock.anchorPoint = CGPoint(x: 0.5, y: 1)
            rock.position.y = 4
            let node = SKNode()
            node.addChild(rock)
            return node
        case .gull:
            return Props.sprite("gull", CGSize(width: 30, height: 16)) { c in
                Props.stroke(c, Props.poly([(2, 5), (9, 2), (15, 9), (21, 2), (28, 5), (21, 5), (15, 12), (9, 5)]), Toon.outline, 4)
                Props.fill(c, Props.poly([(2, 5), (9, 2), (15, 9), (21, 2), (28, 5), (21, 5), (15, 12), (9, 5)]), Toon.cream)
            }
        case .kite:
            let color = config.color(p.tint)
            let node = SKNode()
            let string = SKShapeNode()
            string.strokeColor = Toon.cream.withAlphaComponent(0.7)
            string.lineWidth = 1.5
            string.name = "string"
            string.zPosition = -1
            node.addChild(string)
            let sail = Props.sprite("kite|\(color.description)", CGSize(width: 26, height: 32)) { c in
                Props.ink(c, Props.poly([(13, 2), (24, 13), (13, 30), (2, 13)]), color, line: 2.5)
                Props.stroke(c, Props.poly([(13, 2), (13, 30)]), Toon.outline, 1.5)
            }
            node.addChild(sail)
            return node
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        node.zPosition = p.kind == .spire ? 40 : (p.kind == .kite ? 450 : 60)
        guard p.kind == .kite, let string = node.childNode(withName: "string") as? SKShapeNode else { return }
        let hand = project(p.pos, z: 0).0
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: hand.x - node.position.x, y: hand.y + 12 - node.position.y))
        string.path = path
        // A caught kite hangs crooked on the rock.
        node.children.last?.zRotation = p.state == 1 ? 0.6 : 0
    }
}
