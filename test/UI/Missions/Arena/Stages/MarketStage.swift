import SceneKit

/// Market Day Scramble: a village square with nine stalls, a cart and a crowd.
final class MarketStage: IsoStage {
    static let goods = ["EGGS", "BREAD", "CHEESE", "APPLES", "BUTTER", "HONEY", "FISH", "FLOWERS", "BOOKS"]

    /// An overcast evening, the square lit as much by its own lanterns as by the sky.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        a.key = UIColor(red: 0.80, green: 0.86, blue: 1.0, alpha: 1)
        a.keyIntensity = 1450
        a.keyPitch = -0.6
        a.shadow = 0.7
        a.ambient = UIColor(red: 0.58, green: 0.62, blue: 0.74, alpha: 1)
        a.ambientIntensity = 440
        a.land = Toon.limestone.shaded(0.62)
        a.rimIntensity = 120
        a.fogStart = 1200
        a.fogEnd = 2400
        return a
    }
    override var halfHeight: Double { 290 }
    override var wallHeight: CGFloat { 16 }
    override var wallColor: UIColor { Toon.wood }

    override func build() {
        ground(Iso.image("cobbles", CGSize(width: 256, height: 256)) { c in
            c.setFillColor(Toon.limestone.shaded(0.86).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = SeededRNG(seed: 13)
            for _ in 0..<160 {
                c.setFillColor(Toon.limestone.shaded(rng.chance(0.5) ? 0.74 : 0.96).cgColor)
                c.fillEllipse(in: CGRect(x: rng.cg(0, 250), y: rng.cg(0, 250), width: rng.cg(6, 12), height: rng.cg(4, 8)))
            }
        })
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        let node = SCNNode()
        switch p.kind {
        case .stall:
            // The counter is the wall underneath; this is the awning and the sign over it.
            let cloth = Toon.cloak(Double(p.state) / 9).shaded(p.state < 6 ? 1 : 0.6)
            for x in [-27.0, 27.0] {
                let post = Iso.cylinder(1.5, 38, Toon.woodDark)
                post.position.x = Float(x)
                node.addChildNode(post)
            }
            let awning = Iso.box(62, 4, 34, cloth, round: 1)
            awning.position.y = 38
            awning.name = "awning"
            node.addChildNode(awning)
            let sign = Iso.label(Self.goods[p.state % 9], size: 9)
            sign.position.y = 52
            node.addChildNode(sign)
            let tag = Iso.ball(4, Toon.gold, glow: Toon.gold)
            tag.position = SCNVector3(0, 66, 0)
            tag.name = "tag"
            node.addChildNode(tag)
            for x in [-27.0, 27.0] {
                let lamp = Iso.ball(2.6, Toon.ember, glow: Toon.ember)
                lamp.position = SCNVector3(Float(x), 33, 15)
                node.addChildNode(lamp)
            }
            let basket = Iso.cylinder(5, 6, Toon.straw)
            basket.position = SCNVector3(20, 19, -8)
            node.addChildNode(basket)
        case .cart:
            node.addChildNode(Iso.box(46, 14, 26, Toon.wood))
            for x in [-16.0, 16.0] {
                let wheel = Iso.cylinder(8, 3, Toon.woodDark)
                wheel.eulerAngles.x = .pi / 2
                wheel.position = SCNVector3(Float(x), 8, -15)
                node.addChildNode(wheel)
            }
            let sign = Iso.label("CART", size: 9, color: Toon.gold)
            sign.position.y = 30
            node.addChildNode(sign)
        case .shopper:
            let coat = [Toon.slate, Toon.woodDark, Toon.heather.shaded(0.7), Toon.moss.shaded(0.7)][p.state % 4]
            node.addChildNode(Iso.cone(3, 7.5, 17, coat))
            let head = Iso.ball(5, Toon.cream.shaded(0.9))
            head.position.y = 20
            node.addChildNode(head)
        default:
            return nil
        }
        return node
    }

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        guard p.kind == .stall else { return }
        // A gold bead marks a stall that still has something on your list. Sold out, the awning fades.
        node.childNode(withName: "tag", recursively: false)?.isHidden = p.tint < 0
        node.childNode(withName: "awning", recursively: false)?.opacity = p.value > 0 || p.state >= 6 ? 1 : 0.4
    }

    override func dress(_ figure: IsoFigure, _ a: ArenaActor) {
        figure.hold(a.carry > 0 ? "basket\(a.carry)" : nil) {
            let stack = SCNNode()
            for i in 0..<a.carry {
                let parcel = Iso.box(8, 6, 8, Toon.straw)
                parcel.position.y += Float(i) * 6
                stack.addChildNode(parcel)
            }
            return stack
        }
    }
}
