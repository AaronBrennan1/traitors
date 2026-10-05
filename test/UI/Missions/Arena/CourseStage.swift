import SpriteKit

/// Draws a course and everything on it, flat and from straight above. The rules live in the
/// `Gauntlet`; the stage only shows what is there, a little way between one step and the next so
/// that it moves as smoothly as the screen can show it.
final class CourseStage: SKNode {
    let config: ArenaConfig
    let core: Gauntlet
    let layout: ArenaLayout
    /// The seat the picture follows: the player, or the first seat when nobody is playing.
    let focus: Int
    /// Whether what the followed seat cannot see is kept off the screen.
    let limited: Bool

    private let world = SKNode()
    private var figures: [Courtier] = []
    private var stacks: [[SKSpriteNode]] = []
    private var shownAlpha: [CGFloat] = []
    private var traps: [TrapNode] = []
    private var loose: [SKSpriteNode] = []
    private var slabs: [(tile: Int, node: SKSpriteNode)] = []
    private var candles: [SKNode] = []
    private var cameraY: CGFloat = 0
    private var trauma: CGFloat = 0
    /// Frames drawn, for anything that flickers.
    private var beat = 0

    init(_ config: ArenaConfig, _ core: Gauntlet, _ layout: ArenaLayout) {
        self.config = config
        self.core = core
        self.layout = layout
        focus = core.human ?? core.runners.firstIndex { $0.seat.isHuman } ?? 0
        limited = core.human != nil
        super.init()
        addChild(world)
        buildFloor()
        buildDecor()
        traps = core.course.hazards.enumerated().map { TrapNode($0.element, index: $0.offset, in: world) }
        for _ in core.bags {
            let bag = CourseStage.bag()
            bag.isHidden = true
            bag.zPosition = 60
            world.addChild(bag)
            loose.append(bag)
        }
        for r in core.runners {
            let who = config.cast.first { $0.id == r.id }
            let you = who?.isHuman == true && !config.spectating
            let figure = Courtier(color: who?.color ?? Toon.cream, name: who?.name, you: you)
            figure.setScale(0.82)
            var stack: [SKSpriteNode] = []
            for k in 0..<Feel.maxCarry {
                let bag = CourseStage.bag()
                bag.position = CGPoint(x: 0, y: CGFloat(k) * 9)
                bag.isHidden = true
                figure.carry.addChild(bag)
                stack.append(bag)
            }
            world.addChild(figure)
            figures.append(figure)
            stacks.append(stack)
            shownAlpha.append(1)
        }
        cameraY = CGFloat(core.runners[focus].pos.y)
        sync(alpha: 1, dt: 0)
    }

    required init?(coder: NSCoder) { return nil }

    /// Where a point of the course is on the screen.
    func screenPoint(_ p: Vec2) -> CGPoint {
        CGPoint(x: world.position.x + CGFloat(p.x), y: world.position.y + CGFloat(p.y))
    }

    /// Whether a point of the course is near enough the picture to be worth a sound.
    func inEarshot(_ p: Vec2) -> Bool { abs(CGFloat(p.y) - cameraY) < layout.height * 0.7 }

    func figure(_ seat: PlayerID) -> Courtier? { core.index(of: seat).map { figures[$0] } }

    /// Jolts the picture. Nothing moves in the game itself.
    func shake(_ amount: CGFloat) {
        if !Tokens.Motion.reduced { trauma = min(1, trauma + amount) }
    }

    // MARK: - Every frame

    func sync(alpha: Double, dt: TimeInterval) {
        beat += 1
        let course = core.course
        let lead = core.runners[focus]
        let me = lerp(lead.last, lead.pos, alpha)

        // The picture runs a little ahead of whoever it follows, towards where they are going.
        let ahead = clamp(lead.vel.y * 0.3, -70, 70) + (lead.carry > 0 ? 50 : -30)
        // The ends of the course stop clear of the tally at the top and the thumbs at the bottom.
        let lo = layout.height / 2 - 120, hi = CGFloat(course.size.y) - layout.height / 2 + layout.safeTop + 150
        let want = min(max(CGFloat(me.y + ahead), lo), max(lo, hi))
        cameraY += (want - cameraY) * CGFloat(1 - exp(-5 * dt))
        if dt == 0 { cameraY = want }
        trauma = max(0, trauma - CGFloat(dt) * 1.6)
        let jolt = trauma * trauma * 9
        world.position = CGPoint(x: jolt * CGFloat.random(in: -1...1), y: layout.height / 2 - cameraY + jolt * CGFloat.random(in: -1...1))

        for (i, trap) in traps.enumerated() { trap.update(core.hazards[i], alpha: alpha, frame: beat) }

        for (tile, node) in slabs {
            let f = core.floor[tile]
            node.isHidden = f < 0
            node.colorBlendFactor = f > 0 ? 0.45 : 0
            let centre = course.centre(of: tile)
            node.position = CGPoint(x: CGFloat(centre.x) + (f > 0 ? CGFloat(beat % 4 < 2 ? 1.2 : -1.2) : 0), y: CGFloat(centre.y))
        }

        for (i, bag) in core.bags.enumerated() {
            let node = loose[i]
            node.isHidden = bag.ttl == 0 || (bag.ttl < Feel.ticks(1.5) && bag.ttl % 12 < 5)
            if bag.ttl > 0 { node.position = CGPoint(x: bag.pos.x, y: bag.pos.y) }
        }

        for (i, candle) in candles.enumerated() where i < core.dark.count { candle.alpha = core.dark[i] > 0 ? 0.08 : 1 }

        let dim = core.course.vision < 200
        for (i, r) in core.runners.enumerated() {
            let figure = figures[i]
            let p = lerp(r.last, r.pos, alpha)
            figure.position = CGPoint(x: p.x, y: p.y + 13)
            figure.zPosition = 100 + CGFloat(course.size.y - p.y) * 0.05
            figure.isHidden = !r.up
            figure.animate(dt, velocity: CGVector(dx: r.vel.x, dy: r.vel.y))
            for (k, bag) in stacks[i].enumerated() { bag.isHidden = k >= r.carry }

            // Whoever the player cannot see is a shape at the edge of sight, or nothing at all in the dark.
            var show: CGFloat = 1
            if limited, i != focus, !r.seenBy.has(lead.id) {
                show = dim || core.vision(lead.pos, r.pos) < 200 ? 0 : 0.4
            }
            shownAlpha[i] += (show - shownAlpha[i]) * CGFloat(1 - exp(-10 * dt))
            figure.alpha = shownAlpha[i] * (r.blink > 0 && r.blink % 10 < 5 ? 0.4 : 1)

            if r.dash > 0, r.up, beat % 2 == 0, shownAlpha[i] > 0.5 {
                let ghost = Props.dot(config.color(r.id), 8)
                ghost.position = CGPoint(x: p.x, y: p.y + 6)
                ghost.zPosition = 90
                ghost.alpha = 0.45
                world.addChild(ghost)
                ghost.run(.sequence([.group([.fadeOut(withDuration: 0.22), .scale(to: 0.5, duration: 0.22)]), .removeFromParent()]))
            }
        }
    }

    private func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    // MARK: - Building

    /// A sack of gold.
    static func bag() -> SKSpriteNode {
        Props.sprite("goldbag", CGSize(width: 16, height: 16)) { c in
            Props.ink(c, Props.oval(2, 4.5, 12, 10), Toon.gold, line: 2)
            Props.ink(c, Props.rr(5.5, 1.5, 5, 4.5, 1.5), Toon.goldDark, line: 1.5)
            Props.fill(c, Props.oval(5, 7, 3, 3), UIColor.white.withAlphaComponent(0.55))
        }
    }

    /// The floor is painted once, in slabs ten rows deep, and never touched again.
    private func buildFloor() {
        let course = core.course
        let cols = Course.cols, cell = CGFloat(Course.cell), deep = 10
        func tile(_ c: Int, _ r: Int) -> Tile {
            c >= 0 && r >= 0 && c < cols && r < course.rows ? course.tiles[r * cols + c] : .wall
        }
        func solidFloor(_ t: Tile) -> Bool { t != .void && t != .wall && t != .crumble }
        for chunk in 0..<(course.rows + deep - 1) / deep {
            let size = CGSize(width: CGFloat(cols) * cell, height: CGFloat(deep) * cell)
            let texture = Props.texture("course|\(course.kind.rawValue)|\(chunk)", size, scale: 2) { ctx in
                Props.fill(ctx, CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), Toon.pit)
                for r in chunk * deep..<min(course.rows, (chunk + 1) * deep) {
                    for c in 0..<cols {
                        // Drawing runs down the page; the course runs up it.
                        let box = CGRect(x: CGFloat(c) * cell, y: size.height - CGFloat(r - chunk * deep + 1) * cell, width: cell, height: cell)
                        var dice = SeededRNG.derived(UInt64(r * cols + c), 3)
                        let t = tile(c, r)
                        switch t {
                        case .wall:
                            ctx.setFillColor(Toon.wallStone.cgColor)
                            ctx.fill(box)
                            if tile(c, r - 1) != .wall {
                                ctx.setFillColor(Toon.wallStone.shaded(0.55).cgColor)
                                ctx.fill(CGRect(x: box.minX, y: box.maxY - 9, width: cell, height: 9))
                            }
                            ctx.setFillColor(Toon.wallStone.shaded(1.12).cgColor)
                            ctx.fill(CGRect(x: box.minX + 1, y: box.minY + 1, width: cell - 2, height: 3))
                        case .void, .crumble:
                            // The face of the floor above, dropping away into the dark.
                            if solidFloor(tile(c, r + 1)) {
                                Props.wash(ctx, CGRect(x: box.minX, y: box.minY, width: cell, height: 12),
                                           [(Toon.flagstone.shaded(0.5), 0), (Toon.pit, 1)])
                            }
                        case .floor, .alcove, .hoard, .vault:
                            var stone = Toon.flagstone.shaded(CGFloat(dice.range(0.9, 1.1)))
                            if t == .alcove { stone = stone.shaded(0.6) }
                            if t == .hoard { stone = UIColor(red: 0.42, green: 0.36, blue: 0.22, alpha: 1).shaded(CGFloat(dice.range(0.92, 1.08))) }
                            if t == .vault { stone = UIColor(red: 0.13, green: 0.20, blue: 0.19, alpha: 1) }
                            ctx.setFillColor(Toon.wallStone.cgColor)
                            ctx.fill(box)
                            ctx.setFillColor(stone.cgColor)
                            ctx.fill(box.insetBy(dx: 0.75, dy: 0.75))
                            ctx.setFillColor(stone.shaded(1.14).cgColor)
                            ctx.fill(CGRect(x: box.minX + 1.5, y: box.minY + 1.5, width: cell - 3, height: 1.5))
                            if t == .hoard {
                                for _ in 0..<3 {
                                    let x = box.minX + CGFloat(dice.range(5, 21)), y = box.minY + CGFloat(dice.range(5, 21))
                                    Props.fill(ctx, Props.oval(x, y, 5, 4), Toon.gold.shaded(CGFloat(dice.range(0.7, 1.05))))
                                }
                            }
                            if t == .vault, tile(c, r - 1) != .vault {
                                ctx.setFillColor(Toon.gold.cgColor)
                                ctx.fill(CGRect(x: box.minX, y: box.maxY - 3, width: cell, height: 3))
                            }
                        }
                    }
                }
            }
            let slab = SKSpriteNode(texture: texture, size: size)
            slab.anchorPoint = .zero
            slab.position = CGPoint(x: 0, y: CGFloat(chunk * deep) * cell)
            slab.zPosition = 0
            world.addChild(slab)
        }
        // Crumbling floor is drawn tile by tile, because it comes and goes.
        for t in course.crumbles {
            let node = Props.sprite("crumble", CGSize(width: cell, height: cell)) { ctx in
                let box = CGRect(x: 0, y: 0, width: cell, height: cell)
                ctx.setFillColor(Toon.wallStone.cgColor)
                ctx.fill(box)
                ctx.setFillColor(Toon.flagstoneHi.cgColor)
                ctx.fill(box.insetBy(dx: 1, dy: 1))
                Props.stroke(ctx, Props.poly([(4, 6), (12, 13), (9, 20), (17, 26)]), Toon.wallStone, 1.4)
                Props.stroke(ctx, Props.poly([(26, 4), (20, 11), (24, 17)]), Toon.wallStone, 1.2)
            }
            node.color = Toon.danger
            node.zPosition = 5
            world.addChild(node)
            slabs.append((t, node))
        }
    }

    /// The things that stand about the course and do not move: braziers, levers, candles, the two ends.
    private func buildDecor() {
        let course = core.course
        for b in course.braziers {
            let glow = Sprites.glow(Toon.ember, radius: 44)
            glow.position = CGPoint(x: b.x, y: b.y)
            glow.zPosition = 20
            glow.alpha = 0.55
            world.addChild(glow)
            if !Tokens.Motion.reduced {
                glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.38, duration: 0.7), .fadeAlpha(to: 0.6, duration: 0.9)])))
            }
            let bowl = Props.dot(Toon.ember, 6)
            bowl.position = glow.position
            bowl.zPosition = 21
            world.addChild(bowl)
        }
        for m in course.mechanisms {
            let at = CGPoint(x: m.pos.x, y: m.pos.y)
            switch m.kind {
            case .lever:
                let lever = Props.sprite("lever", CGSize(width: 20, height: 22)) { c in
                    Props.ink(c, Props.rr(3, 13, 14, 7, 2), Toon.woodDark, line: 2)
                    Props.stroke(c, Props.poly([(10, 15), (14, 4)]), Toon.steel, 3)
                    Props.ink(c, Props.oval(11, 1, 6, 6), Toon.steel, line: 1.5)
                }
                lever.position = at
                lever.zPosition = 22
                world.addChild(lever)
            case .sconce:
                let holder = SKNode()
                holder.position = at
                holder.zPosition = 22
                let light = Sprites.glow(Toon.ember, radius: 70)
                light.alpha = 0.5
                holder.addChild(light)
                holder.addChild(Props.dot(Toon.cream, 4))
                world.addChild(holder)
                candles.append(holder)
            case .vault:
                break
            }
        }
        let chest = Props.chest(Toon.gold)
        chest.position = CGPoint(x: course.vault.x, y: course.vault.y)
        chest.zPosition = 22
        world.addChild(chest)
    }
}

/// One trap on the screen: what warns, and what hurts. The warning always wears the one colour
/// kept for danger, so it reads the same on every course.
private final class TrapNode {
    private let kind: HazardKind
    private let tell: SKSpriteNode
    private let strike: SKSpriteNode
    private var streaks: [SKSpriteNode] = []

    init(_ h: Hazard, index: Int, in world: SKNode) {
        kind = h.kind
        let from = CGPoint(x: h.a.x, y: h.a.y)
        let d = h.b - h.a
        let length = CGFloat(d.length)
        let mid = CGPoint(x: (h.a.x + h.b.x) / 2, y: (h.a.y + h.b.y) / 2)
        let angle = atan2(CGFloat(d.y), CGFloat(d.x))

        func strip(_ color: UIColor, thick: CGFloat) -> SKSpriteNode {
            let n = SKSpriteNode(color: color, size: CGSize(width: max(length, 4), height: thick))
            n.position = mid
            n.zRotation = angle
            return n
        }
        func patch(_ color: UIColor) -> SKSpriteNode {
            let n = SKSpriteNode(color: color, size: CGSize(width: abs(d.x), height: abs(d.y)))
            n.position = mid
            return n
        }
        func still(_ node: SKNode, z: CGFloat = 8) {
            node.zPosition = z
            world.addChild(node)
        }

        switch h.kind {
        case .blade:
            // The groove it runs in is always there to be read.
            still(strip(Toon.pit.withAlphaComponent(0.75), thick: 4))
            tell = Sprites.glow(Toon.danger, radius: 30)
            strike = Props.sprite("blade", CGSize(width: 34, height: 34)) { c in
                var pts: [(CGFloat, CGFloat)] = []
                for i in 0..<16 {
                    let a = CGFloat(i) * .pi / 8, r: CGFloat = i % 2 == 0 ? 15.5 : 10.5
                    pts.append((17 + cos(a) * r, 17 + sin(a) * r))
                }
                Props.ink(c, Props.poly(pts), Toon.steel, line: 2)
                Props.fill(c, Props.oval(13, 13, 8, 8), Toon.wallStone)
            }
            strike.color = Toon.danger
        case .barrel:
            let chute = Props.dot(Toon.woodDark, 11)
            chute.position = from
            still(chute)
            tell = strip(Toon.danger, thick: 24)
            strike = Props.sprite("barrel", CGSize(width: 30, height: 30)) { c in
                Props.ink(c, Props.oval(2, 2, 26, 26), Toon.wood)
                Props.stroke(c, Props.oval(7, 7, 16, 16), Toon.woodDark, 2)
                Props.stroke(c, Props.poly([(4, 15), (26, 15)]), Toon.steel, 2)
            }
        case .spikes:
            let bed = patch(Toon.pit.withAlphaComponent(0.35))
            still(bed)
            tell = patch(Toon.danger)
            let size = CGSize(width: abs(d.x), height: abs(d.y))
            strike = SKSpriteNode(texture: Props.texture("spikes|\(Int(size.width))x\(Int(size.height))", size) { c in
                var y: CGFloat = 5
                while y < size.height - 2 {
                    var x: CGFloat = 5
                    while x < size.width - 2 {
                        Props.ink(c, Props.poly([(x - 3.5, y + 4), (x, y - 5), (x + 3.5, y + 4)]), Toon.steel, line: 1.5)
                        x += 10
                    }
                    y += 10
                }
            }, size: size)
            strike.position = mid
        case .flame:
            for end in [h.a, h.b] {
                let grate = SKSpriteNode(color: Toon.pit.withAlphaComponent(0.8), size: CGSize(width: 12, height: 12))
                grate.position = CGPoint(x: end.x, y: end.y)
                still(grate)
            }
            tell = strip(Toon.danger, thick: 8)
            strike = strip(Toon.ember, thick: 18)
            let core = SKSpriteNode(color: Toon.cream, size: CGSize(width: max(length, 4), height: 6))
            strike.addChild(core)
            let light = Sprites.glow(Toon.ember, radius: max(length, 60) * 0.6)
            light.yScale = 0.4
            light.alpha = 0.7
            strike.addChild(light)
        case .darts:
            for p in h.plates {
                let plate = SKSpriteNode(color: Toon.steel.withAlphaComponent(0.55), size: CGSize(width: 22, height: 22))
                plate.position = CGPoint(x: p.x, y: p.y)
                still(plate)
                let stud = SKSpriteNode(color: Toon.wallStone, size: CGSize(width: 8, height: 8))
                stud.position = plate.position
                still(stud, z: 9)
            }
            still(strip(Toon.pit.withAlphaComponent(0.5), thick: 2))
            tell = strip(Toon.danger, thick: 5)
            strike = strip(Toon.cream, thick: 5)
        case .gust:
            tell = patch(Toon.mist)
            strike = patch(Toon.mist)
            strike.alpha = 0.16
            let run = CGFloat(abs(d.x)), tall = CGFloat(abs(d.y))
            for k in 0..<7 {
                let streak = SKSpriteNode(color: Toon.cream.withAlphaComponent(0.5), size: CGSize(width: 34, height: 2))
                streak.position = CGPoint(x: -run / 2 + CGFloat(k) * run / 7, y: -tall / 2 + CGFloat(k * 37 % 80) / 80 * tall)
                strike.addChild(streak)
                streaks.append(streak)
            }
        }
        tell.zPosition = 30
        tell.alpha = 0
        strike.zPosition = 80
        world.addChild(tell)
        world.addChild(strike)
    }

    func update(_ h: Hazard, alpha: Double, frame: Int) {
        let p = h.last + (h.pos - h.last) * alpha
        let at = CGPoint(x: p.x, y: p.y)
        let pulse: CGFloat = frame % 10 < 5 ? 1 : 0.6
        let warning = CGFloat(h.warning)
        switch kind {
        case .blade:
            strike.position = at
            strike.zRotation -= h.hurried ? 0.5 : 0.22
            strike.alpha = h.awake ? 1 : 0.25
            strike.colorBlendFactor = h.hurried ? 0.6 : 0
            tell.position = at
            tell.alpha = h.state == .warn ? 0.9 * pulse : (h.hurried ? 0.5 : 0)
        case .barrel:
            strike.isHidden = h.state != .live
            strike.position = at
            strike.zRotation -= 0.2
            tell.alpha = h.state == .warn ? (0.18 + 0.3 * warning) * pulse : (h.state == .live ? 0.1 : 0)
        case .spikes:
            strike.isHidden = h.state != .live
            tell.alpha = h.state == .warn ? 0.15 + 0.4 * warning * pulse : 0
        case .flame:
            strike.isHidden = h.state != .live
            strike.yScale = frame % 6 < 3 ? 1 : 0.8
            tell.alpha = h.state == .warn ? (0.25 + 0.5 * warning) * pulse : 0
        case .darts:
            strike.isHidden = h.state != .live
            tell.alpha = h.state == .warn ? 0.9 * pulse : 0
        case .gust:
            strike.isHidden = h.state != .live
            tell.alpha = h.state == .warn ? 0.06 + 0.14 * warning : 0
            if h.state == .live {
                let way: CGFloat = h.push.x >= 0 ? 1 : -1, run = strike.size.width
                for s in streaks {
                    s.position.x += way * 7
                    if s.position.x > run / 2 { s.position.x -= run }
                    if s.position.x < -run / 2 { s.position.x += run }
                }
            }
        }
        if !h.awake, kind != .blade { tell.alpha = 0 }
    }
}
