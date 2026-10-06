import SpriteKit

/// The Lantern Run: the ramparts at night from above. The stones are all but black, and what
/// can be seen is what the brazier and the lanterns are lighting.
final class LanternStage: TopDownStage {
    private var fire: SKSpriteNode?

    override func build() {
        guard let grid = core.grid else { return }
        floor(margin: 10) { c, rect in
            Self.flags(c, rect.insetBy(dx: -10, dy: -10), cell: 32, stone: UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1), joint: Toon.pit, seed: 9)
            Self.walls(c, grid, color: UIColor(red: 0.16, green: 0.18, blue: 0.23, alpha: 1))
        }
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .brazier:
            let node = SKNode()
            let glow = Sprites.glow(Toon.ember, radius: 110)
            glow.name = "glow"
            glow.zPosition = -1
            node.addChild(glow)
            let bowl = Props.sprite("brazier", CGSize(width: 30, height: 30)) { c in
                Props.ink(c, Props.oval(3, 3, 24, 24), Toon.steel.shaded(0.6), line: 2.5)
                Props.fill(c, Props.oval(8, 8, 14, 14), Toon.ember)
                Props.fill(c, Props.oval(11, 11, 8, 8), Toon.cream)
            }
            bowl.name = "bowl"
            node.addChild(bowl)
            return node
        case .lantern:
            let node = SKNode()
            let glow = Sprites.glow(Toon.ember, radius: 80)
            glow.name = "glow"
            glow.zPosition = -1
            node.addChild(glow)
            let post = Props.sprite("lantern", CGSize(width: 18, height: 18)) { c in
                Props.ink(c, Props.rr(3, 3, 12, 12, 3), Toon.woodDark, line: 2)
            }
            node.addChild(post)
            let flame = Props.dot(Toon.cream, 3.5)
            flame.name = "flame"
            node.addChild(flame)
            return node
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        node.zPosition = -30
        switch p.kind {
        case .brazier:
            // Smothered, it gives no light and no flame.
            let lit = p.state == 1
            node.childNode(withName: "glow")?.alpha = lit ? 0.75 : 0.04
            node.childNode(withName: "bowl")?.alpha = lit ? 1 : 0.35
        case .lantern:
            let burn = CGFloat(p.value)
            if let glow = node.childNode(withName: "glow") {
                glow.alpha = burn > 0 ? 0.25 + 0.5 * burn : 0
                glow.setScale(0.55 + 0.45 * burn)
            }
            node.childNode(withName: "flame")?.isHidden = burn <= 0
        default:
            break
        }
    }

    override func dress(_ figure: Courtier, _ a: ArenaActor) {
        let lit = a.carry == 1
        guard lit != !figure.carry.children.isEmpty else { return }
        figure.carry.removeAllChildren()
        guard lit else { return }
        let glow = Sprites.glow(Toon.ember, radius: 26)
        glow.alpha = 0.8
        figure.carry.addChild(glow)
        figure.carry.addChild(Props.dot(Toon.cream, 3.5))
    }
}
