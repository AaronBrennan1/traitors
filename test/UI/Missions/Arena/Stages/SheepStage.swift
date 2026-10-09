import SpriteKit
import TraitorsEngine
import TraitorsGauntlet

/// The Round-Up: a hillside field from above, three dry-stone pens flying their ribbons, and a
/// flock that would sooner be anywhere else.
final class SheepStage: TopDownStage {
    private var heading: [Int: CGFloat] = [:]

    override func build() {
        guard let herd = core as? SheepCore else { return }
        floor(margin: 14) { c, rect in
            let field = rect.insetBy(dx: -14, dy: -14)
            Props.wash(c, field, [(Toon.grass.shaded(0.62), 0), (Toon.grass.shaded(0.5), 1)])
            var dice = SeededRNG(seed: 21)
            // Mown stripes and tufts, so the ground is not one flat green.
            for i in 0..<9 where i % 2 == 0 {
                c.setFillColor(Toon.grass.shaded(0.68).withAlphaComponent(0.5).cgColor)
                c.fill(CGRect(x: field.minX, y: CGFloat(i) * 60, width: field.width, height: 60))
            }
            for _ in 0..<150 {
                let x = dice.cg(0, rect.width), y = dice.cg(0, rect.height)
                Props.stroke(c, Props.poly([(x, y), (x + 2, y + 5), (x + 4, y)]), Toon.moss.shaded(dice.chance(0.5) ? 0.8 : 1.2).withAlphaComponent(0.6), 1.2)
            }
            for (i, pen) in herd.pens.enumerated() {
                let box = CGRect(x: pen.centre.x - pen.half.x, y: pen.centre.y - pen.half.y, width: pen.half.x * 2, height: pen.half.y * 2)
                Props.fill(c, Props.rr(box.minX, box.minY, box.width, box.height, 4), Toon.ribbons[i].withAlphaComponent(0.28))
                // Three walls of stone, open towards the field.
                let wall = CGMutablePath()
                let towards = CGPoint(x: pen.mouth.x - pen.centre.x, y: pen.mouth.y - pen.centre.y)
                let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.maxX, y: box.minY)]
                // Start the wall at the corner after the open side, and stop one short.
                let start = abs(towards.x) > abs(towards.y) ? (towards.x > 0 ? 3 : 1) : (towards.y > 0 ? 2 : 0)
                for k in 0..<4 {
                    let pt = corners[(start + k) % 4]
                    if k == 0 { wall.move(to: pt) } else { wall.addLine(to: pt) }
                }
                Props.stroke(c, wall, Toon.outline, 9)
                Props.stroke(c, wall, Toon.limestone.shaded(0.8), 6)
            }
        }
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .pen:
            let flag = Props.flag(Toon.ribbons[p.state % 3])
            flag.setScale(1.2)
            let node = SKNode()
            node.addChild(flag)
            return node
        case .sheep:
            let ribbon = Toon.ribbons[p.state % 3]
            let dark = p.value > 0
            return Props.sprite("sheep\(p.state)\(dark)", CGSize(width: 26, height: 20)) { c in
                Props.fill(c, Props.oval(4, 13, 18, 6), UIColor.black.withAlphaComponent(0.3))
                Props.ink(c, Props.oval(2, 3, 18, 13), Toon.cream, line: 2)
                Props.ink(c, Props.oval(16, 6, 8, 7), dark ? Toon.ink : Toon.limestone, line: 1.5)
                Props.fill(c, Props.rr(8, 3.5, 5, 12, 2), ribbon)
            }
        case .dog:
            let node = SKNode()
            let ring = SKShapeNode(circleOfRadius: 13)
            ring.lineWidth = 2
            ring.fillColor = .clear
            ring.name = "ring"
            node.addChild(ring)
            node.addChild(Props.sprite("dog", CGSize(width: 22, height: 16)) { c in
                Props.ink(c, Props.oval(2, 3, 15, 10), Toon.ink.shaded(1.6), line: 2)
                Props.ink(c, Props.oval(14, 4, 7, 7), Toon.cream, line: 1.5)
            })
            return node
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        switch p.kind {
        case .pen:
            node.zPosition = 20
        case .sheep, .dog:
            // Turned the way it is going.
            let last = heading[p.id + (p.kind == .dog ? 100_000 : 0)] ?? CGFloat(p.pos.x)
            if abs(CGFloat(p.pos.x) - last) > 0.4 { node.xScale = abs(node.xScale) * (CGFloat(p.pos.x) > last ? 1 : -1) }
            heading[p.id + (p.kind == .dog ? 100_000 : 0)] = CGFloat(p.pos.x)
            if p.kind == .dog, let ring = node.childNode(withName: "ring") as? SKShapeNode {
                ring.strokeColor = p.tint >= 0 ? config.color(p.tint) : .clear
            }
        default:
            break
        }
    }
}
