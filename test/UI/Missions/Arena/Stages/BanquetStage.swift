import SceneKit

/// The Banquet Prep: the castle kitchen, with the pantry walled off along the far side.
final class BanquetStage: IsoStage {
    static let jobs = ["FETCH", "CHOP", "PLATE", "SERVE"]
    static let tops = [Toon.wood, Toon.steel, Toon.cream, Toon.goldDark]

    /// Firelight from the hearth side, the pantry cool beyond the wall.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.06, green: 0.045, blue: 0.04, alpha: 1)
        a.key = UIColor(red: 1.0, green: 0.70, blue: 0.42, alpha: 1)
        a.keyIntensity = 1500
        a.ambient = UIColor(red: 0.52, green: 0.48, blue: 0.62, alpha: 1)
        a.ambientIntensity = 430
        a.land = UIColor(red: 0.12, green: 0.09, blue: 0.08, alpha: 1)
        a.vignette = 0.75
        return a
    }
    override var halfHeight: Double { 262 }
    /// Low enough to see over into the pantry.
    override var wallHeight: CGFloat { 18 }
    override var wallColor: UIColor { Toon.limestone.shaded(0.9) }

    override func build() {
        ground(Iso.image("kitchen-floor", CGSize(width: 352, height: 416)) { c in
            for r in 0..<13 {
                for col in 0..<11 {
                    c.setFillColor(((r + col) % 2 == 0 ? UIColor(red: 0.70, green: 0.50, blue: 0.38, alpha: 1)
                                                       : UIColor(red: 0.62, green: 0.43, blue: 0.33, alpha: 1)).cgColor)
                    c.fill(CGRect(x: CGFloat(col) * 32, y: CGFloat(r) * 32, width: 32, height: 32))
                }
            }
        }, margin: 0)
    }

    private func counter(_ top: UIColor) -> SCNNode {
        let node = SCNNode()
        node.addChildNode(Iso.box(30, 16, 30, Toon.woodDark))
        let slab = Iso.box(31, 3, 31, top, round: 0.5)
        slab.position.y = 17.5
        slab.name = "top"
        node.addChildNode(slab)
        return node
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        switch p.kind {
        case .station:
            let node = counter(Self.tops[p.state % 4])
            let sign = Iso.label(Self.jobs[p.state % 4], size: 9)
            sign.position.y = 34
            node.addChildNode(sign)
            return node
        case .pot:
            let node = counter(Toon.slate)
            let pot = Iso.cylinder(10, 10, Toon.outline.shaded(1.6))
            pot.position.y = 24
            node.addChildNode(pot)
            let stew = Iso.cylinder(8.5, 1, Toon.slate)
            stew.position.y = 29.5
            stew.name = "stew"
            node.addChildNode(stew)
            let leaf = Iso.ball(3.5, Toon.green, glow: Toon.green)
            leaf.position.y = 42
            leaf.name = "leaf"
            node.addChildNode(leaf)
            let banner = Iso.label("HEAD TABLE", size: 9, color: Toon.gold)
            banner.position.y = 52
            banner.name = "banner"
            node.addChildNode(banner)
            return node
        case .herbShelf:
            let node = SCNNode()
            node.addChildNode(Iso.box(30, 26, 12, Toon.woodDark))
            for x in [-9.0, 0.0, 9.0] {
                let sprig = Iso.cone(0, 3.5, 9, Toon.green)
                sprig.position = SCNVector3(Float(x), 30, 0)
                node.addChildNode(sprig)
            }
            let sign = Iso.label("HERBS", size: 9)
            sign.position.y = 46
            node.addChildNode(sign)
            return node
        default:
            return nil
        }
    }

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        // A station with a job waiting glows.
        let glow: UIColor = p.value > 0 ? Toon.gold.shaded(0.6) : .black
        node.childNode(withName: "top", recursively: false)?.geometry?.firstMaterial?.emission.contents = glow
        guard p.kind == .pot else { return }
        let state = p.state % 10
        let colors = [Toon.slate, UIColor(red: 0.85, green: 0.45, blue: 0.2, alpha: 1), Toon.green, Toon.outline]
        let stew = node.childNode(withName: "stew", recursively: false)?.geometry?.firstMaterial
        stew?.diffuse.contents = colors[min(state, 3)]
        stew?.emission.contents = state == 1 || state == 2 ? colors[state].shaded(0.5) : UIColor.black
        node.childNode(withName: "leaf", recursively: false)?.isHidden = p.state < 100
        node.childNode(withName: "banner", recursively: false)?.isHidden = (p.state / 10) % 10 != 1
    }

    override func dress(_ figure: IsoFigure, _ a: ArenaActor) {
        figure.hold(a.carry == BanquetCore.herb ? "herb" : nil) { Iso.cone(0, 4, 9, Toon.green) }
    }
}
