import SpriteKit

/// Market Day: a cobbled square from above, nine stalls under striped awnings, the cart at the
/// top and a crowd drifting through it.
final class MarketStage: TopDownStage {
    private static let goods = ["BREAD", "CHEESE", "APPLES", "HAM", "EGGS", "HONEY", "FISH", "FLOWERS", "BOOKS"]

    override func build() {
        guard let grid = core.grid else { return }
        floor(margin: 8) { c, rect in
            Self.flags(c, rect.insetBy(dx: -8, dy: -8), cell: 15, stone: UIColor(red: 0.37, green: 0.34, blue: 0.31, alpha: 1), seed: 5)
            // The counters the stalls stand on.
            Self.walls(c, grid, color: Toon.woodDark, face: 7)
        }
        _ = light(at: (core as? MarketCore)?.cart ?? .zero, radius: 70, alpha: 0.3)
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .cart:
            let node = SKNode()
            let cart = Props.sprite("market-cart", CGSize(width: 64, height: 40)) { c in
                Props.ink(c, Props.rr(6, 6, 52, 24, 4), Toon.wood, line: 2.5)
                Props.stroke(c, Props.poly([(10, 14), (54, 14)]), Toon.woodDark, 2)
                Props.stroke(c, Props.poly([(10, 22), (54, 22)]), Toon.woodDark, 2)
                for x in [8.0, 46.0] { Props.ink(c, Props.oval(x, 26, 12, 12), Toon.woodDark, line: 2) }
            }
            cart.name = "cart"
            node.addChild(cart)
            return node
        case .stall:
            let node = SKNode()
            let awning = Props.sprite("awning\(p.state)", CGSize(width: 64, height: 30)) { c in
                let cloth = Toon.cloak(Double(p.state) / 9)
                Props.ink(c, Props.rr(2, 2, 60, 24, 4), cloth, line: 2.5)
                for i in 0..<4 { Props.fill(c, Props.rr(9 + CGFloat(i) * 15, 4, 7, 20, 0), Toon.cream.withAlphaComponent(0.35)) }
                Props.stroke(c, Props.poly([(4, 24), (10, 28), (16, 24), (22, 28), (28, 24), (34, 28), (40, 24), (46, 28), (52, 24), (58, 28)]), cloth.shaded(0.7), 2)
            }
            node.addChild(awning)
            let label = ToonLabel(Self.goods[p.state % 9], size: 7, color: Toon.cream)
            label.position = CGPoint(x: 0, y: 3)
            node.addChild(label)
            for i in 0..<3 {
                let pip = Props.dot(Toon.cream, 2.5)
                pip.position = CGPoint(x: CGFloat(i) * 8 - 8, y: -9)
                pip.name = "pip\(i)"
                node.addChild(pip)
            }
            let tag = Props.dot(Toon.gold, 5)
            tag.position = CGPoint(x: 26, y: 12)
            tag.name = "tag"
            if !Tokens.Motion.reduced { tag.run(.repeatForever(.sequence([.scale(to: 1.3, duration: 0.4), .scale(to: 1, duration: 0.4)]))) }
            node.addChild(tag)
            return node
        case .shopper:
            let cloth = [Toon.slate, Toon.heather.shaded(0.7), Toon.moss.shaded(0.8), Toon.straw.shaded(0.6)][p.state % 4]
            return Props.sprite("shopper\(p.state % 4)", CGSize(width: 18, height: 18)) { c in
                Props.ink(c, Props.oval(2, 2, 14, 14), cloth, line: 2)
                Props.fill(c, Props.oval(6, 6, 6, 6), cloth.shaded(0.6))
            }
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        switch p.kind {
        case .cart:
            // Tipped on its side, with nothing going onto it.
            node.childNode(withName: "cart")?.zRotation = p.state == 1 ? 1.1 : 0
        case .stall:
            for i in 0..<3 { node.childNode(withName: "pip\(i)")?.alpha = Double(i) < p.value * 3 - 0.01 ? 1 : 0.15 }
            node.childNode(withName: "tag")?.isHidden = p.tint < 0
            node.zPosition = 20
        case .shopper:
            node.zPosition = 30
        default:
            break
        }
    }

    override func dress(_ figure: Courtier, _ a: ArenaActor) {
        guard figure.carry.children.count != a.carry else { return }
        figure.carry.removeAllChildren()
        for k in 0..<a.carry {
            let parcel = Props.sprite("parcel", CGSize(width: 14, height: 11)) { c in
                Props.ink(c, Props.rr(1.5, 1.5, 11, 8, 2), Toon.straw, line: 1.5)
                Props.stroke(c, Props.poly([(7, 1.5), (7, 9.5)]), Toon.red, 1.2)
            }
            parcel.position = CGPoint(x: 0, y: CGFloat(k) * 8)
            figure.carry.addChild(parcel)
        }
    }
}
