import SpriteKit

/// The Banquet Prep: the castle kitchen from above. Boards and blocks round the walls, three
/// pots on the stove in the middle, and the pantry behind its own wall at the top.
final class BanquetStage: TopDownStage {
    private static let jobs = ["FETCH", "CHOP", "PLATE", "SERVE"]

    override func build() {
        guard let grid = core.grid else { return }
        floor(margin: 10) { c, rect in
            Self.flags(c, rect.insetBy(dx: -10, dy: -10), cell: 32, stone: UIColor(red: 0.33, green: 0.30, blue: 0.27, alpha: 1), seed: 13)
            // The pantry's stone walls, and the wooden counters you can see over.
            Self.walls(c, grid, color: Toon.wallStone.shaded(1.25)) { col, r in grid.opaque[grid.index(col, r)] }
            Self.walls(c, grid, color: Toon.wood.shaded(0.8), face: 6) { col, r in !grid.opaque[grid.index(col, r)] }
        }
        // The heat of the stove.
        _ = light(at: grid.centre(5, 5), radius: 90, alpha: 0.4)
        let pass = ToonLabel("THE PASS", size: 8, color: Toon.gold)
        pass.position = CGPoint(x: grid.centre(5, 0).x, y: grid.centre(5, 0).y - 24)
        pass.zPosition = -20
        addChild(pass)
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .station:
            let node = SKNode()
            let ring = SKShapeNode(rectOf: CGSize(width: 28, height: 28), cornerRadius: 5)
            ring.strokeColor = Toon.gold
            ring.lineWidth = 2.5
            ring.glowWidth = 2
            ring.fillColor = Toon.gold.withAlphaComponent(0.15)
            ring.name = "ring"
            node.addChild(ring)
            node.addChild(ToonLabel(Self.jobs[p.state % 4], size: 7.5, color: Toon.cream))
            return node
        case .pot:
            let node = SKNode()
            let glow = Sprites.glow(Toon.ember, radius: 30)
            glow.name = "glow"
            glow.zPosition = -1
            node.addChild(glow)
            node.addChild(Props.sprite("pot", CGSize(width: 30, height: 30)) { c in
                Props.ink(c, Props.oval(3, 3, 24, 24), Toon.steel, line: 2.5)
                Props.ink(c, Props.rr(0, 12, 5, 6, 2), Toon.steel.shaded(0.7), line: 1.5)
                Props.ink(c, Props.rr(25, 12, 5, 6, 2), Toon.steel.shaded(0.7), line: 1.5)
            })
            let stew = SKShapeNode(circleOfRadius: 8.5)
            stew.lineWidth = 0
            stew.name = "stew"
            node.addChild(stew)
            let leaf = Props.dot(Toon.green, 4.5)
            leaf.position = CGPoint(x: 11, y: 12)
            leaf.name = "leaf"
            node.addChild(leaf)
            return node
        case .herbShelf:
            return Props.sprite("herbshelf", CGSize(width: 30, height: 24)) { c in
                Props.ink(c, Props.rr(2, 2, 26, 20, 3), Toon.woodDark, line: 2)
                for (x, y) in [(7.0, 7.0), (15.0, 9.0), (22.0, 7.0), (10.0, 15.0), (19.0, 16.0)] { Props.fill(c, Props.oval(x - 3, y - 3, 6, 6), Toon.green) }
            }
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        node.zPosition = 20
        switch p.kind {
        case .station:
            // Lit when there is a job waiting here.
            node.childNode(withName: "ring")?.alpha = p.value > 0 ? 1 : 0.12
        case .pot:
            let state = p.state % 100
            let colours = [Toon.ink, UIColor(red: 0.72, green: 0.40, blue: 0.16, alpha: 1), Toon.green, UIColor(white: 0.08, alpha: 1)]
            (node.childNode(withName: "stew") as? SKShapeNode)?.fillColor = colours[min(state, 3)]
            node.childNode(withName: "glow")?.alpha = state == 1 ? 0.6 : (state == 2 ? 0.9 : 0)
            (node.childNode(withName: "glow") as? SKSpriteNode)?.color = state == 2 ? Toon.green : .white
            (node.childNode(withName: "glow") as? SKSpriteNode)?.colorBlendFactor = state == 2 ? 0.8 : 0
            node.childNode(withName: "leaf")?.isHidden = p.state < 100
        default:
            break
        }
    }

    override func dress(_ figure: Courtier, _ a: ArenaActor) {
        let herb = a.carry == BanquetCore.herb
        guard herb != !figure.carry.children.isEmpty else { return }
        figure.carry.removeAllChildren()
        if herb { figure.carry.addChild(Props.dot(Toon.green, 5)) }
    }
}
