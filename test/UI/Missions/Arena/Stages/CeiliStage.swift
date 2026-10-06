import SpriteKit

/// The Céilí: the boards of the great hall from above. Each dancer's tile lights in their own
/// colour, with a ring that closes on it as the beat comes.
final class CeiliStage: TopDownStage {
    private var pulse: SKSpriteNode?

    override func build() {
        guard let dance = core as? CeiliCore else { return }
        let tile = CGFloat(CeiliCore.tile)
        floor(margin: 12) { c, rect in
            c.setFillColor(Toon.woodDark.shaded(0.5).cgColor)
            c.fill(rect.insetBy(dx: -12, dy: -12))
            for r in 0..<CeiliCore.side {
                for col in 0..<CeiliCore.side {
                    var dice = SeededRNG.derived(UInt64(r * 7 + col), 17)
                    let box = CGRect(x: CGFloat(col) * tile, y: CGFloat(r) * tile, width: tile, height: tile).insetBy(dx: 1, dy: 1)
                    let wood = ((r + col) % 2 == 0 ? Toon.wood : Toon.wood.shaded(0.8)).shaded(dice.cg(0.62, 0.74))
                    c.setFillColor(wood.cgColor)
                    c.fill(box)
                    // Three boards to a tile, running the other way on every second one.
                    for k in 1..<3 {
                        let at = CGFloat(k) * tile / 3
                        let seam = (r + col) % 2 == 0 ? CGRect(x: box.minX + at, y: box.minY, width: 0.8, height: box.height)
                                                      : CGRect(x: box.minX, y: box.minY + at, width: box.width, height: 0.8)
                        c.setFillColor(Toon.outline.withAlphaComponent(0.35).cgColor)
                        c.fill(seam)
                    }
                    c.setFillColor(wood.shaded(1.18).cgColor)
                    c.fill(CGRect(x: box.minX + 1, y: box.maxY - 2, width: box.width - 2, height: 1.2))
                }
            }
        }
        // Candlelight in the middle of the floor that swells on the beat.
        pulse = light(at: Vec2(core.size.x / 2, core.size.y / 2), radius: 190, alpha: 0.2, pulse: false)
        _ = dance
    }

    override func frame(_ dt: TimeInterval) {
        guard let dance = core as? CeiliCore else { return }
        let since = 1 - dance.beatProgress
        pulse?.alpha = 0.14 + 0.3 * CGFloat(since * since)
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .tile:
            let color = config.color(p.tint)
            let mine = p.tint == core.human?.id
            let node = SKNode()
            let pad = SKShapeNode(rectOf: CGSize(width: 38, height: 38), cornerRadius: 6)
            pad.fillColor = color.withAlphaComponent(mine ? 0.55 : 0.3)
            pad.strokeColor = mine ? Toon.gold : color
            pad.lineWidth = mine ? 3 : 1.5
            node.addChild(pad)
            let ring = SKShapeNode(circleOfRadius: 19)
            ring.strokeColor = mine ? Toon.gold : color
            ring.lineWidth = mine ? 3 : 1.5
            ring.fillColor = .clear
            ring.name = "ring"
            node.addChild(ring)
            return node
        case .crack:
            return Props.sprite("crackedboard", CGSize(width: 40, height: 40)) { c in
                Props.stroke(c, Props.poly([(6, 8), (16, 17), (12, 26), (22, 34)]), Toon.outline.withAlphaComponent(0.85), 1.8)
                Props.stroke(c, Props.poly([(34, 6), (26, 15), (30, 23)]), Toon.outline.withAlphaComponent(0.85), 1.5)
                Props.stroke(c, Props.poly([(16, 17), (26, 15)]), Toon.outline.withAlphaComponent(0.6), 1.2)
            }
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        node.zPosition = p.kind == .crack ? -20 : -10
        // The ring closes on the tile as the beat lands.
        if p.kind == .tile { node.childNode(withName: "ring")?.setScale(2.2 - 1.2 * CGFloat(p.value)) }
    }
}
