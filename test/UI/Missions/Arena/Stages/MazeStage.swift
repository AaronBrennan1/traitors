import SceneKit

/// The Hedge Maze: tall hedges, a bell tower in the middle, and statues down the dead ends.
final class MazeStage: IsoStage {
    /// Dusk: the last of the sun along the tops of the hedges.
    override var atmosphere: Atmosphere {
        var a = Atmosphere()
        a.sky = UIColor(red: 0.03, green: 0.07, blue: 0.06, alpha: 1)
        a.key = UIColor(red: 1.0, green: 0.70, blue: 0.42, alpha: 1)
        a.keyIntensity = 1500
        a.keyPitch = -0.5
        a.ambient = UIColor(red: 0.42, green: 0.55, blue: 0.68, alpha: 1)
        a.ambientIntensity = 430
        a.land = Toon.hedge.shaded(0.75)
        a.motes = UIColor(red: 0.80, green: 1.0, blue: 0.50, alpha: 1)
        return a
    }
    override var halfHeight: Double { 215 }
    override var wallHeight: CGFloat { 30 }
    override var wallColor: UIColor { Toon.hedge }

    override func build() {
        ground(Iso.image("gravel", CGSize(width: 256, height: 256)) { c in
            c.setFillColor(UIColor(red: 0.74, green: 0.69, blue: 0.56, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var rng = SeededRNG(seed: 17)
            for _ in 0..<260 {
                c.setFillColor(UIColor(white: rng.chance(0.5) ? 0.5 : 0.9, alpha: 0.25).cgColor)
                c.fillEllipse(in: CGRect(x: rng.cg(0, 252), y: rng.cg(0, 252), width: 3, height: 3))
            }
        }, margin: 20)
    }

    override func makeProp(_ p: Prop) -> SCNNode? {
        let node = SCNNode()
        switch p.kind {
        case .bell:
            node.addChildNode(Iso.box(20, 6, 20, Toon.limestone))
            for (x, z) in [(-8.0, -8.0), (8.0, -8.0), (-8.0, 8.0), (8.0, 8.0)] {
                let post = Iso.cylinder(1.5, 40, Toon.limestone.shaded(0.85))
                post.position = SCNVector3(Float(x), post.position.y, Float(z))
                node.addChildNode(post)
            }
            let roof = Iso.cone(0, 16, 14, Toon.slate)
            roof.position.y = 47
            node.addChildNode(roof)
            let bell = Iso.ball(6, Toon.gold, glow: Toon.goldDark)
            bell.position.y = 28
            node.addChildNode(bell)
        case .sigil:
            let blue = UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1)
            let g = SCNPyramid(width: 9, height: 9, length: 9)
            g.materials = [Iso.material(blue, glow: blue)]
            let top = SCNNode(geometry: g), bottom = SCNNode(geometry: g)
            bottom.eulerAngles.x = .pi
            let gem = SCNNode()
            gem.addChildNode(top)
            gem.addChildNode(bottom)
            gem.position.y = 16
            gem.runAction(.repeatForever(.rotateBy(x: 0, y: 2, z: 0, duration: 1.2)))
            node.addChildNode(gem)
        case .post:
            node.addChildNode(Iso.cylinder(2, 24, Toon.woodDark))
            let board = Iso.box(16, 11, 2, Toon.cream)
            board.position.y = 24
            node.addChildNode(board)
        case .statue:
            node.addChildNode(Iso.box(13, 8, 13, Toon.limestone.shaded(0.8)))
            let body = Iso.cone(3, 5.5, 18, Toon.limestone)
            body.position.y = 17
            node.addChildNode(body)
            let head = Iso.ball(4.5, Toon.limestone)
            head.position.y = 30
            node.addChildNode(head)
        default:
            return nil
        }
        return node
    }

    override func updateProp(_ node: SCNNode, _ p: Prop, dt: TimeInterval) {
        // What you have already claimed stays, faded, for the others to find.
        if p.kind == .sigil || p.kind == .post { node.opacity = p.state == 1 ? 0.25 : 1 }
        // Nothing shows through the hedges until you are near enough to see it.
        guard p.kind != .bell, let me = core.human, let radius = core.sightRadius else { return }
        node.isHidden = p.pos.distance(to: me.pos) > radius * 1.15
    }
}
