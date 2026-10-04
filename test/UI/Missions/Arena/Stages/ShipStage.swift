import SpriteKit

/// The Shipwreck Dive in cross-section: the boat on the surface, the water column, and the
/// wreck's rooms on the seabed. The whole bay fits on screen.
final class ShipStage: SideOnStage {
    private static let k: CGFloat = 0.72
    private static let origin = CGPoint(x: 8, y: 66)

    override var pointScale: CGFloat { Self.k }

    override func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) {
        (CGPoint(x: Self.origin.x + CGFloat(p.x) * Self.k, y: Self.origin.y + CGFloat(p.y + z) * Self.k), 0.72)
    }

    override func build() {
        guard let ship = core as? ShipCore, let grid = core.grid else { return }
        let top = project(Vec2(0, ship.surface), z: 0).0.y
        // A moonlit night over the bay.
        let sky = Stagecraft.sky("ship", height: bleedUp - top, top: UIColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1),
                                 horizon: UIColor(red: 0.20, green: 0.30, blue: 0.40, alpha: 1), horizonAt: 0.85)
        sky.position.y = top
        sky.zPosition = -50
        addChild(sky)
        let moon = Sprites.glow(UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), radius: 46)
        moon.position = CGPoint(x: 300, y: top + 86)
        moon.zPosition = -49
        addChild(moon)
        let hills = Stagecraft.band("ship-hills", width: 390, height: 16, color: Toon.moss.shaded(0.35), rough: 22, seed: 4, outline: false)
        hills.position.y = top
        hills.zPosition = -49
        addChild(hills)
        // The water darkens with depth, from moonlit green at the surface to black over the sand.
        let water = Props.sprite("ship-water", CGSize(width: 390, height: top + 2)) { c in
            Props.wash(c, CGRect(x: 0, y: 0, width: 390, height: top + 2),
                       [(Toon.sea.shaded(1.25), 0), (Toon.sea.shaded(0.8), 0.25), (Toon.sea.shaded(0.38), 0.7), (Toon.sea.shaded(0.22), 1)])
            Props.fill(c, Props.rr(0, 0, 390, 2.5, 0), UIColor(red: 0.80, green: 0.92, blue: 1, alpha: 0.55))
        }
        water.anchorPoint = .zero
        water.zPosition = -48
        addChild(water)
        // Moonlight comes down through it in shafts.
        for (x, w, tilt) in [(70.0, 34.0, 0.16), (190.0, 54.0, 0.10), (300.0, 28.0, 0.20)] {
            let ray = SKSpriteNode(color: UIColor(red: 0.70, green: 0.90, blue: 1, alpha: 1), size: CGSize(width: w, height: top * 0.8))
            ray.anchorPoint = CGPoint(x: 0.5, y: 1)
            ray.position = CGPoint(x: x, y: top)
            ray.zRotation = tilt
            ray.alpha = 0.05
            ray.blendMode = .add
            ray.zPosition = -46
            addChild(ray)
            if !Tokens.Motion.reduced {
                ray.run(.repeatForever(.sequence([.fadeAlpha(to: 0.09, duration: 2.6 + w / 20), .fadeAlpha(to: 0.04, duration: 2.6 + w / 20)])))
            }
        }
        let sandColor = UIColor(red: 0.40, green: 0.38, blue: 0.30, alpha: 1)
        let sand = Stagecraft.band("ship-sand", width: 390, height: Self.origin.y - 6, color: sandColor, rough: 10, seed: 8)
        sand.zPosition = -47
        addChild(sand)
        apron(sandColor.shaded(0.55), z: -47)

        // The hull, plank by plank.
        let side = CGFloat(grid.cell) * Self.k
        for r in 0..<grid.rows {
            for c in 0..<grid.cols where grid.isSolid(c, r) {
                let plank = Props.sprite("plank\((c + r) % 2)", CGSize(width: 20, height: 20)) { ctx in
                    let wood = (c + r) % 2 == 0 ? Toon.woodDark : Toon.woodDark.shaded(0.82)
                    Props.wash(ctx, CGRect(x: 0, y: 0, width: 20, height: 20), [(wood.shaded(1.12), 0), (wood.shaded(0.8), 1)])
                    // Grain, and a barnacle or two.
                    for y in [6.0, 13.0] { Props.stroke(ctx, Props.poly([(1, y), (19, y + ((c + r) % 2 == 0 ? 1 : -1))]), Toon.outline.withAlphaComponent(0.22), 1) }
                    Props.fill(ctx, Props.oval((c + r) % 2 == 0 ? 4 : 13, 3, 2.5, 2.5), Toon.limestone.withAlphaComponent(0.35))
                    Props.stroke(ctx, Props.rr(0, 0, 20, 20, 0), Toon.outline.withAlphaComponent(0.55), 1.5)
                }
                plank.size = CGSize(width: side + 0.5, height: side + 0.5)
                plank.position = project(grid.centre(c, r), z: 0).0
                plank.zPosition = -10
                addChild(plank)
            }
        }
    }

    override var mist: CGFloat { 0.05 }
    override var mistColor: UIColor { Toon.sea.shaded(1.6) }
    /// Silt hanging in the water.
    override var motes: UIColor? { UIColor(red: 0.70, green: 0.86, blue: 0.90, alpha: 1) }

    override func populated() {
        // The diver's lamp: a little warm light of your own in the murk.
        guard let me = core.human, let figure = figures[me.id] else { return }
        let lamp = Sprites.glow(Toon.ember, radius: 70)
        lamp.alpha = 0.32
        lamp.zPosition = -3
        figure.addChild(lamp)
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .boat:
            return Props.sprite("boat", CGSize(width: 120, height: 44)) { c in
                Props.ink(c, Props.poly([(4, 14), (116, 14), (100, 38), (20, 38)]), Toon.wood)
                Props.ink(c, Props.rr(56, 2, 6, 14, 2), Toon.woodDark, line: 2)
            }
        case .chest:
            let chest = Props.chest(p.state == 1 ? Toon.gold : (p.state == 2 ? Toon.steel : Toon.wood))
            chest.setScale(p.state == 1 ? 1.0 : 0.7)
            let node = SKNode()
            node.addChild(chest)
            return node
        case .eel:
            return Props.sprite("eel", CGSize(width: 46, height: 16)) { c in
                Props.ink(c, Props.poly([(2, 8), (12, 3), (24, 9), (34, 3), (44, 8), (34, 13), (24, 11), (12, 13)]), Toon.green.shaded(0.7), line: 2.5)
                Props.fill(c, Props.oval(37, 6, 3, 3), Toon.cream)
            }
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        if p.kind == .eel { node.xScale = abs(node.xScale) * (p.state == 1 ? 1 : -1) }
        // Whatever is out of sight in the murk is not drawn.
        guard p.kind != .boat, let me = core.human, let radius = core.sightRadius else { return }
        node.isHidden = p.hidden || p.pos.distance(to: me.pos) > radius * 1.1
    }
}
