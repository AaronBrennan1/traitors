import SceneKit

/// Céilí Chaos: the chequered floor of the great hall. Each dancer's tile for the coming beat
/// is lit in their colour, with a ring that closes as the beat arrives.
final class CeiliStage: IsoStage {
    /// Candlelight in the great hall.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.06, green: 0.04, blue: 0.035, alpha: 1)
        a.key = UIColor(red: 1.0, green: 0.76, blue: 0.48, alpha: 1)
        a.keyIntensity = 1350
        a.ambient = UIColor(red: 0.62, green: 0.50, blue: 0.48, alpha: 1)
        a.ambientIntensity = 430
        a.land = UIColor(red: 0.13, green: 0.085, blue: 0.065, alpha: 1)
        a.rimIntensity = 120
        a.vignette = 0.75
        a.motes = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        return a
    }
    override var halfHeight: Double { 235 }
    override var follows: Bool { false }

    override func build() {
        let side = CGFloat(CeiliCore.side)
        ground(Iso.image("ceili-floor", CGSize(width: side * 32, height: side * 32)) { c in
            for r in 0..<CeiliCore.side {
                for col in 0..<CeiliCore.side {
                    c.setFillColor(((r + col) % 2 == 0 ? Toon.cream.shaded(0.9) : Toon.woodDark).cgColor)
                    c.fill(CGRect(x: CGFloat(col) * 32, y: CGFloat(r) * 32, width: 32, height: 32))
                }
            }
        }, margin: 0)
        // The band's stage along the far side.
        let stage = Iso.box(CGFloat(core.size.x), 10, 40, Toon.wood)
        let at = Iso.at(Vec2(core.size.x / 2, core.size.y + 26))
        stage.position = SCNVector3(at.x, stage.position.y, at.z)
        scene.rootNode.addChildNode(stage)
        for i in 0..<4 {
            let player = IsoFigure(color: Toon.cloak(0.08 + 0.2 * Double(i)).shaded(0.7), name: nil, you: false)
            player.position = Iso.at(Vec2(core.size.x * (0.2 + 0.2 * Double(i)), core.size.y + 26), 10)
            scene.rootNode.addChildNode(player)
        }
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        let tile = CGFloat(CeiliCore.tile)
        switch p.kind {
        case .tile:
            let mine = p.tint == core.human?.id
            let color = config.color(p.tint)
            let node = Iso.sheet(tile - 4, tile - 4, color.withAlphaComponent(mine ? 0.85 : 0.5), lit: false)
            let wrap = SCNNode()
            node.position.y = 0.4
            wrap.addChildNode(node)
            let g = SCNTorus(ringRadius: 20, pipeRadius: mine ? 1.8 : 1)
            g.materials = [Iso.material(mine ? Toon.gold : color, glow: mine ? Toon.gold : color)]
            let ring = SCNNode(geometry: g)
            ring.position.y = 1.5
            ring.name = "ring"
            wrap.addChildNode(ring)
            return wrap
        case .crack:
            let node = Iso.sheet(tile - 6, tile - 6, Iso.image("crack", CGSize(width: 40, height: 40)) { c in
                c.setStrokeColor(Toon.outline.cgColor)
                c.setLineWidth(2.5)
                c.move(to: CGPoint(x: 4, y: 8))
                for (x, y) in [(14, 16), (10, 24), (22, 22), (28, 34), (36, 30)] { c.addLine(to: CGPoint(x: x, y: y)) }
                c.strokePath()
            }, lit: false)
            let wrap = SCNNode()
            node.position.y = 0.6
            wrap.addChildNode(node)
            return wrap
        default:
            return nil
        }
    }

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        switch p.kind {
        case .tile:
            // The ring closes on the tile as the beat comes.
            let k = Float(1.7 - 1.0 * p.value)
            node.childNode(withName: "ring", recursively: false)?.scale = SCNVector3(k, 1, k)
        case .crack:
            node.isHidden = !config.questVisible
        default:
            break
        }
    }
}
