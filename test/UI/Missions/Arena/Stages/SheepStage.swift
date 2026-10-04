import SceneKit

/// Sheep Round-Up: a windy hillside with three pens, a flock and a dog.
final class SheepStage: IsoStage {
    /// A low sun under storm cloud: long shadows and a grey distance.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.13, green: 0.17, blue: 0.17, alpha: 1)
        a.key = UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1)
        a.keyIntensity = 1750
        a.keyPitch = -0.55
        a.ambient = UIColor(red: 0.50, green: 0.60, blue: 0.70, alpha: 1)
        a.ambientIntensity = 540
        a.land = Toon.grass.shaded(0.8)
        a.fogStart = 1150
        a.fogEnd = 2300
        return a
    }
    override var halfHeight: Double { 300 }

    override func build() {
        ground(Iso.image("hillside", CGSize(width: 256, height: 256)) { c in
            c.setFillColor(Toon.grass.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = SeededRNG(seed: 21)
            for _ in 0..<70 {
                c.setFillColor(Toon.grass.shaded(rng.chance(0.5) ? 0.9 : 1.12).cgColor)
                c.fillEllipse(in: CGRect(x: rng.cg(0, 240), y: rng.cg(0, 240), width: rng.cg(8, 26), height: rng.cg(5, 12)))
            }
        })
        guard let sheep = core as? SheepCore else { return }
        // Dry-stone pens, open on the side that faces the field, each flying its colour.
        for (i, pen) in sheep.pens.enumerated() {
            let c = pen.centre, h = pen.half
            let inward = Vec2(core.size.x / 2 - c.x, core.size.y / 2 - c.y)
            for (dx, dy, w, l) in [(-h.x, 0.0, 6.0, h.y * 2), (h.x, 0.0, 6.0, h.y * 2), (0.0, -h.y, h.x * 2, 6.0), (0.0, h.y, h.x * 2, 6.0)] {
                // Leave out the wall the sheep come in by.
                if abs(inward.x) > abs(inward.y) ? dx * inward.x > 0 : dy * inward.y > 0 { continue }
                let wall = Iso.box(CGFloat(w), 12, CGFloat(l), Toon.limestone, round: 2)
                let at = Iso.at(Vec2(c.x + dx, c.y + dy))
                wall.position = SCNVector3(at.x, wall.position.y, at.z)
                scene.rootNode.addChildNode(wall)
            }
            let pole = Iso.cylinder(1.5, 46, Toon.woodDark)
            let flag = Iso.box(18, 12, 1.5, Toon.ribbons[i], round: 0)
            flag.position = SCNVector3(9, 38, 0)
            pole.addChildNode(flag)
            let at = Iso.at(c)
            pole.position = SCNVector3(at.x, pole.position.y, at.z)
            scene.rootNode.addChildNode(pole)
            let mat = Iso.sheet(CGFloat(h.x * 2 - 8), CGFloat(h.y * 2 - 8), Toon.ribbons[i].withAlphaComponent(0.35), lit: false)
            mat.position = Iso.at(c, 0.3)
            scene.rootNode.addChildNode(mat)
        }
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        let node = SCNNode()
        switch p.kind {
        case .sheep:
            let body = Iso.ball(8, Toon.cream)
            body.scale = SCNVector3(1.25, 0.9, 0.95)
            body.position.y = 9
            node.addChildNode(body)
            let head = Iso.ball(4.2, p.value > 0 ? Toon.outline : Toon.cream.shaded(0.86))
            head.position = SCNVector3(9, 11, 0)
            node.addChildNode(head)
            let ribbon = Iso.box(5, 3, 13, Toon.ribbons[p.state % 3], round: 0.5)
            ribbon.position = SCNVector3(-1, 15, 0)
            node.addChildNode(ribbon)
        case .dog:
            let body = Iso.ball(5.5, Toon.woodDark)
            body.scale = SCNVector3(1.5, 0.9, 0.9)
            body.position.y = 6
            node.addChildNode(body)
            let g = SCNTorus(ringRadius: 10, pipeRadius: 1)
            let ring = SCNNode(geometry: g)
            ring.position.y = 1
            ring.name = "ring"
            node.addChildNode(ring)
        default:
            return nil
        }
        return node
    }

    private var last: [Int: Vec2] = [:]

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        // Turn to face the way it is going.
        if let was = last[p.id], was.distance(to: p.pos) > 0.3 {
            node.eulerAngles.y = Float(atan2(p.pos.y - was.y, p.pos.x - was.x))
        }
        last[p.id] = p.pos
        if p.kind == .dog, let ring = node.childNode(withName: "ring", recursively: false) {
            // The ring round the dog is the colour of whoever whistled last.
            ring.isHidden = p.tint < 0
            ring.geometry?.materials = [Iso.material(config.color(p.tint), glow: config.color(p.tint))]
        }
    }
}
