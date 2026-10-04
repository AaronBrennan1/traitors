import SpriteKit

/// The Bog Relay: a Connemara bog at dawn, seen from the side. Three lanes run away from the
/// camera, so the back lane is drawn higher up and smaller.
final class BogStage: SideOnStage {
    private let fog = SKSpriteNode(color: UIColor(white: 0.86, alpha: 1), size: CGSize(width: 390, height: 1200))

    override var scrollWidth: Double? { core.size.x }

    override func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) {
        let depth = CGFloat(p.y) / 130
        return (CGPoint(x: p.x - cameraX, y: 96 + CGFloat(p.y) * 1.75 + CGFloat(z)), 1.1 - depth * 0.32)
    }

    override var mist: CGFloat { 0.16 }
    override var motes: UIColor? { UIColor(red: 1, green: 0.88, blue: 0.70, alpha: 1) }

    override func build() {
        // Dawn: slate overhead, peach where the sun is coming up behind the hills.
        let sky = Stagecraft.sky("bog", height: bleedUp, top: UIColor(red: 0.09, green: 0.13, blue: 0.19, alpha: 1),
                                 horizon: UIColor(red: 0.86, green: 0.58, blue: 0.42, alpha: 1), horizonAt: 0.52)
        sky.zPosition = -50
        addChild(sky)
        let halo = Sprites.glow(UIColor(red: 1, green: 0.62, blue: 0.36, alpha: 1), radius: 190)
        halo.alpha = 0.55
        halo.position = CGPoint(x: 290, y: 372)
        halo.zPosition = -49
        addChild(halo)
        let sun = Sprites.glow(UIColor(red: 1, green: 0.92, blue: 0.74, alpha: 1), radius: 54)
        sun.position = CGPoint(x: 290, y: 380)
        sun.zPosition = -48
        addChild(sun)
        let far = Stagecraft.band("bog-far", width: 620, height: 60, color: Toon.slate.shaded(0.9), rough: 70, seed: 3, outline: false, haze: 0.30)
        far.position.y = 330
        layer(far, rate: 0.12, z: -40)
        let mid = Stagecraft.band("bog-mid", width: 700, height: 50, color: Toon.heather.shaded(0.62), rough: 48, seed: 14, outline: false, haze: 0.14)
        mid.position.y = 312
        layer(mid, rate: 0.2, z: -35)
        let near = Stagecraft.band("bog-near", width: 760, height: 50, color: Toon.moss.shaded(0.62), rough: 36, seed: 9)
        near.position.y = 300
        layer(near, rate: 0.3, z: -30)

        // The bog itself: peat banks at either end, and dark water wherever there are no stones.
        let ground = SKNode()
        let peat = Props.sprite("bog-peat", CGSize(width: 800, height: 336)) { c in
            Props.wash(c, CGRect(x: 0, y: 0, width: 800, height: 336), [(Toon.bog.shaded(0.8), 0), (Toon.bog, 0.3), (Toon.bog.shaded(0.72), 1)])
            var rng = SeededRNG(seed: 31)
            for _ in 0..<160 {
                Props.fill(c, Props.oval(rng.cg(0, 800), rng.cg(0, 336), rng.cg(6, 22), rng.cg(2, 5)), Toon.turf.shaded(rng.chance(0.5) ? 0.7 : 1.2).withAlphaComponent(0.35))
            }
        }
        peat.anchorPoint = .zero
        ground.addChild(peat)
        let water = Props.sprite("bog-water", CGSize(width: 620, height: 250)) { c in
            // The far water takes the colour of the sky; close to, it is black.
            Props.wash(c, CGRect(x: 0, y: 0, width: 620, height: 250),
                       [(UIColor(red: 0.42, green: 0.33, blue: 0.30, alpha: 1), 0), (Toon.bogWater.shaded(1.5), 0.25), (Toon.bogWater.shaded(0.7), 1)])
            var rng = SeededRNG(seed: 47)
            for _ in 0..<46 {
                let y = rng.cg(4, 246)
                Props.fill(c, Props.rr(rng.cg(0, 600), y, rng.cg(14, 60), 1.2, 0.6), Toon.cream.withAlphaComponent(0.05 + 0.10 * (1 - y / 250)))
            }
            Props.stroke(c, Props.rr(0.5, 0.5, 619, 249, 6), Toon.outline.withAlphaComponent(0.6), 3)
        }
        water.anchorPoint = .zero
        water.position = CGPoint(x: 70, y: 76)
        ground.addChild(water)
        var rng = SeededRNG(seed: 11)
        for i in 0..<54 {
            let tall = i % 3 == 0
            let tuft = Props.sprite("tuft\(tall)", CGSize(width: 14, height: tall ? 20 : 10)) { c in
                let h: CGFloat = tall ? 19 : 9
                Props.ink(c, Props.poly([(1, h), (3, tall ? 1 : 2), (6, h - 1), (9, tall ? 4 : 1), (11, h - 1), (13, tall ? 2 : 4), (13, h)]), Toon.moss.shaded(0.8), line: 1.5)
            }
            tuft.position = CGPoint(x: rng.cg(0, 800), y: rng.chance(0.5) ? rng.cg(8, 70) : rng.cg(328, 342))
            ground.addChild(tuft)
        }
        layer(ground, rate: 1, z: -20)

        // Turf banks close to the camera slide past faster than the bog behind them.
        let front = Stagecraft.band("bog-front", width: 1100, height: 34, color: Toon.turf.shaded(0.55), rough: 22, seed: 5)
        front.position.y = -6
        layer(front, rate: 1.35, z: 560)

        apron(Toon.turf.shaded(0.33), z: 559)
        // When the weather closes in, a bank of mist rolls over the lot.
        fog.color = Tokens.Hue.mist.ui
        fog.anchorPoint = .zero
        fog.position.y = -300
        fog.zPosition = 590
        fog.alpha = 0
        addChild(fog)
    }

    override func frame(_ dt: TimeInterval) {
        let want: CGFloat = core.coverActive ? 0.62 : 0
        fog.alpha += (want - fog.alpha) * min(1, CGFloat(dt) * 2)
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .stone:
            return Props.sprite("stone", CGSize(width: 44, height: 22)) { c in
                Props.fill(c, Props.oval(5, 9, 36, 12), UIColor.black.withAlphaComponent(0.35))
                Props.ink(c, Props.oval(3, 3, 38, 14), Toon.limestone)
                Props.fill(c, Props.oval(10, 5, 16, 4), Toon.limestone.shaded(1.3).withAlphaComponent(0.7))
            }
        case .turfLight, .turfHeavy:
            let big = p.kind == .turfHeavy
            return Props.sprite("pile\(big)", CGSize(width: 46, height: 40)) { c in
                for (i, row) in (big ? [3, 2, 1] : [2, 1]).enumerated() {
                    for k in 0..<row {
                        let w: CGFloat = big ? 15 : 11, h: CGFloat = big ? 11 : 8
                        Props.ink(c, Props.rr(23 - CGFloat(row) * w / 2 + CGFloat(k) * w, 28 - CGFloat(i) * h, w - 1, h, 2), Toon.turf, line: 2)
                    }
                }
            }
        case .stack:
            let node = SKNode()
            for i in 0..<12 {
                let sod = Props.sprite("sod", CGSize(width: 16, height: 11)) { c in Props.ink(c, Props.rr(2, 2, 12, 7, 2), Toon.turf, line: 2) }
                sod.position = CGPoint(x: CGFloat(i % 4) * 11 - 16, y: CGFloat(i / 4) * 8 - 10)
                sod.name = "sod\(i)"
                node.addChild(sod)
            }
            return node
        case .hollow:
            return Props.sprite("hollow", CGSize(width: 40, height: 20)) { c in
                Props.ink(c, Props.oval(3, 3, 34, 14), Toon.outline.shaded(1.25), line: 2.5)
            }
        case .bogOak:
            let oak = Props.sprite("oak", CGSize(width: 26, height: 18)) { c in
                Props.ink(c, Props.poly([(2, 14), (8, 6), (14, 9), (20, 3), (24, 6), (16, 14)]), Toon.woodDark, line: 2.5)
            }
            let shine = Props.star(Toon.gold)
            shine.position = CGPoint(x: 8, y: 9)
            oak.addChild(shine)
            return oak
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        switch p.kind {
        case .hollow:
            node.zPosition = 4
        case .stone:
            // A sinking stone goes down into the water and comes back when left alone.
            node.zPosition = 5
            node.alpha = 1 - 0.7 * CGFloat(p.value)
            node.position.y -= 7 * CGFloat(p.value)
        case .stack:
            for i in 0..<12 { node.childNode(withName: "sod\(i)")?.isHidden = Double(i) >= p.value * 12 }
        default:
            break
        }
    }

    override func dress(_ figure: Courtier, _ a: ArenaActor) {
        let weight = a.carry % BogCore.passed
        let key = "sod\(weight)"
        if figure.carry.children.first?.name == key { return }
        figure.carry.removeAllChildren()
        guard weight > 0 else { return }
        let big = weight == BogCore.heavy
        let sod = Props.sprite("carried\(big)", CGSize(width: big ? 28 : 20, height: big ? 18 : 13)) { c in
            Props.ink(c, Props.rr(2, 2, big ? 24 : 16, big ? 14 : 9, 3), Toon.turf, line: 2.5)
        }
        sod.name = key
        figure.carry.addChild(sod)
    }
}
