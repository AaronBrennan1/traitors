import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// Hurley Target Practice on the castle lawn. The lawn runs away from the camera to the outer
/// wall, so things further up it are drawn smaller and closer together.
final class HurleyStage: CoreStage {
    /// The core uses a stun as the pause between strikes, which is not a daze.
    override var stunShows: Bool { false }
    override var backdrop: UIColor { Toon.grass.shaded(0.45) }

    override func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) {
        let t = CGFloat(p.y) / 480
        let squeeze = 1 - 0.3 * t
        return (CGPoint(x: 195 + (CGFloat(p.x) - 195) * squeeze, y: 50 + CGFloat(p.y) * 0.86 + CGFloat(z)), 1 - 0.42 * t)
    }

    override func build() {
        // The last of the evening: rose over the castle wall, night coming on above.
        let sky = Stagecraft.sky("hurley", height: bleedUp, top: UIColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1),
                                 horizon: UIColor(red: 0.88, green: 0.52, blue: 0.36, alpha: 1), horizonAt: 0.9)
        sky.zPosition = -50
        addChild(sky)
        // Stripes of mown lawn, narrower as they go back.
        for i in 0..<10 {
            let y0 = project(Vec2(0, Double(i) * 48), z: 0).0.y, y1 = project(Vec2(0, Double(i + 1) * 48), z: 0).0.y
            let stripe = Stagecraft.rect(CGSize(width: 390, height: y1 - y0 + 1), (i % 2 == 0 ? Toon.grass : Toon.grass.shaded(0.84)).shaded(0.62 + 0.05 * CGFloat(i)))
            stripe.position.y = y0
            stripe.zPosition = -40
            addChild(stripe)
        }
        let apron = Stagecraft.rect(CGSize(width: 390, height: 52), Toon.grass.shaded(0.55))
        apron.zPosition = -41
        addChild(apron)
        self.apron(Toon.grass.shaded(0.45))
        // The outer wall along the back of the lawn, with a tower at each end.
        let wall = Props.sprite("hurley-wall", CGSize(width: 390, height: 74)) { c in
            let stone = Toon.limestone.shaded(0.62)
            Props.ink(c, Props.rr(-6, 26, 402, 54, 0), stone)
            for i in 0..<14 { Props.ink(c, Props.rr(CGFloat(i) * 29 - 4, 16, 17, 14, 0), stone, line: 2.5) }
            for x in [40.0, 322.0] {
                Props.ink(c, Props.rr(x, 2, 30, 74, 2), stone.shaded(0.8))
                // A lit window in each tower.
                Props.fill(c, Props.rr(x + 11, 22, 8, 13, 3), Toon.ember)
            }
            for x in [120.0, 195.0, 262.0] { Props.fill(c, Props.rr(x, 44, 6, 10, 2.5), Toon.ember.withAlphaComponent(0.85)) }
        }
        for x in [55.0, 337.0, 123.0, 198.0, 265.0] {
            let glow = Sprites.glow(Toon.ember, radius: 26)
            glow.alpha = 0.55
            glow.position = CGPoint(x: x, y: x == 55 || x == 337 ? 494 : 473)
            glow.zPosition = -29
            addChild(glow)
        }
        // The shadow of the wall, long across the lawn.
        let shadow = Props.sprite("hurley-shadow", CGSize(width: 390, height: 120)) { c in
            Props.wash(c, CGRect(x: 0, y: 0, width: 390, height: 120), [(Toon.ink.withAlphaComponent(0.55), 0), (Toon.ink.withAlphaComponent(0), 1)])
        }
        shadow.anchorPoint = CGPoint(x: 0, y: 1)
        shadow.position.y = 450
        shadow.zPosition = -31
        addChild(shadow)
        wall.anchorPoint = .zero
        wall.position.y = 448
        wall.zPosition = -30
        addChild(wall)
    }

    /// Pollen in the low sun.
    override var motes: UIColor? { Toon.ember }
    override var mist: CGFloat { 0.06 }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .target:
            return p.state == 1 ? Props.cart(gold: false) : Props.strawKnight(gold: p.state == 3)
        case .bell:
            let bell = Props.bell()
            let node = SKNode()
            node.addChild(bell)
            return node
        case .ball:
            let ball = Props.dot(Toon.cream, 4)
            return ball
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        switch p.kind {
        case .bell:
            node.setScale(0.7)
            node.children.first?.zRotation = CGFloat(sin(p.value * 18) * 0.5 * p.value)
        case .ball:
            node.zPosition = 520
        default:
            break
        }
    }
}
