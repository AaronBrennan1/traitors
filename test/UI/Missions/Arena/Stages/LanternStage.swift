import SceneKit

/// Castle Lantern Run: the ramparts at night. There is next to no light of its own, so what
/// can be seen is whatever the brazier and the lit lanterns reach.
final class LanternStage: IsoStage {
    override var wallHeight: CGFloat { 44 }
    override var wallColor: UIColor { Toon.slate }
    /// Moonlight and nothing else: enough to throw a shadow, not enough to see by.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.02, green: 0.025, blue: 0.05, alpha: 1)
        a.key = UIColor(red: 0.55, green: 0.66, blue: 1, alpha: 1)
        a.keyIntensity = 220
        a.ambient = UIColor(red: 0.55, green: 0.62, blue: 1, alpha: 1)
        a.ambientIntensity = 120
        a.rimIntensity = 0
        a.exposure = 0.2
        a.bloom = 1.3
        a.vignette = 0.8
        a.land = UIColor(red: 0.05, green: 0.055, blue: 0.08, alpha: 1)
        a.motes = Toon.ember
        return a
    }
    override var halfHeight: Double { 270 }

    override func build() {
        // Flagstones, laid in pieces so each is lit by the lanterns nearest it.
        let stones = Iso.image("flagstones", CGSize(width: 96, height: 96)) { c in
            c.setFillColor(Toon.limestone.shaded(0.8).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            c.setStrokeColor(Toon.slate.shaded(0.7).cgColor)
            c.setLineWidth(2)
            for i in 0...3 {
                c.stroke(CGRect(x: CGFloat(i % 2) * 16 - 16, y: CGFloat(i) * 32, width: 64, height: 32))
                c.stroke(CGRect(x: CGFloat(i % 2) * 16 + 48, y: CGFloat(i) * 32, width: 64, height: 32))
            }
        }
        let n = 5, side = core.size.x / Double(n)
        for r in 0..<n {
            for c in 0..<n {
                let tile = Iso.sheet(CGFloat(side), CGFloat(side), stones)
                tile.position = Iso.at(Vec2((Double(c) + 0.5) * side, (Double(r) + 0.5) * side), -0.5)
                scene.rootNode.addChildNode(tile)
            }
        }
    }

    override func populated() {
        // A little light of their own, so the player is never lost in the dark.
        guard let me = core.human, let figure = figures[me.id] else { return }
        let glow = Iso.light(Toon.cream, intensity: 260, reach: 90)
        glow.position.y = 30
        figure.addChildNode(glow)
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        let node = SCNNode()
        switch p.kind {
        case .brazier:
            node.addChildNode(Iso.cylinder(15, 12, Toon.slate.shaded(0.7)))
            let flame = Iso.cone(0, 10, 26, Toon.lantern, glow: Toon.lantern)
            flame.position.y = 25
            flame.runAction(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.25), .scale(to: 0.9, duration: 0.25)])))
            node.addChildNode(flame)
            let light = Iso.light(Toon.lantern, intensity: 1500, reach: 210)
            light.position.y = 40
            node.addChildNode(light)
        case .lantern:
            node.addChildNode(Iso.cylinder(2, 26, Toon.woodDark))
            let glass = Iso.ball(6, Toon.lantern.shaded(0.4))
            glass.position.y = 30
            glass.name = "glass"
            node.addChildNode(glass)
            let light = Iso.light(Toon.lantern, intensity: 0, reach: 100)
            light.position.y = 34
            light.name = "light"
            node.addChildNode(light)
        default:
            return nil
        }
        return node
    }

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        guard p.kind == .lantern else { return }
        let burn = CGFloat(p.value)
        node.childNode(withName: "light", recursively: false)?.light?.intensity = burn > 0 ? 500 + 700 * burn : 0
        node.childNode(withName: "light", recursively: false)?.light?.attenuationEndDistance = 120 + 110 * burn
        let glass = node.childNode(withName: "glass", recursively: false)?.geometry?.firstMaterial
        glass?.emission.contents = burn > 0 ? Toon.lantern.shaded(0.5 + 0.5 * burn) : UIColor.black
    }

    override func dress(_ figure: IsoFigure, _ a: ArenaActor) {
        figure.hold(a.carry == 1 ? "flame" : nil) {
            let flame = Iso.cone(0, 4, 10, Toon.lantern, glow: Toon.lantern)
            flame.addChildNode(Iso.light(Toon.lantern, intensity: 300, reach: 70))
            return flame
        }
    }
}
