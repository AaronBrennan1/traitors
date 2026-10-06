import SpriteKit

/// The Hedge Maze from above: gravel walks between clipped hedges, the bell tower in the
/// middle, and no seeing further than the next corner. The shared map sits in the corner of the screen.
final class MazeStage: TopDownStage {
    private var hedges: SKSpriteNode?
    private var drawn = -1
    private var cells: [SKSpriteNode] = []
    private let pin = SKSpriteNode(color: Toon.gold, size: CGSize(width: 4, height: 4))

    override func build() {
        floor(margin: 6) { c, rect in
            let all = rect.insetBy(dx: -6, dy: -6)
            c.setFillColor(UIColor(red: 0.40, green: 0.37, blue: 0.31, alpha: 1).cgColor)
            c.fill(all)
            var dice = SeededRNG(seed: 41)
            for _ in 0..<900 {
                Props.fill(c, Props.oval(dice.cg(0, rect.width), dice.cg(0, rect.height), 2, 1.5),
                           (dice.chance(0.5) ? Toon.limestone : Toon.outline).withAlphaComponent(0.22))
            }
        }
        buildMap()
    }

    /// The hedges move, so they are drawn apart from the gravel and again whenever they have.
    private func grow() {
        guard let grid = core.grid, drawn != core.gridVersion else { return }
        drawn = core.gridVersion
        hedges?.removeFromParent()
        let size = CGSize(width: core.size.x, height: core.size.y)
        let node = SKSpriteNode(texture: Self.bake(size) { c in Self.walls(c, grid, color: Toon.hedge, face: 7) }, size: size)
        node.anchorPoint = .zero
        node.zPosition = -90
        addChild(node)
        hedges = node
    }

    private func buildMap() {
        let n = MazeCore.cells, side: CGFloat = 6
        let map = SKNode()
        let back = SKSpriteNode(color: Toon.ink.withAlphaComponent(0.8), size: CGSize(width: CGFloat(n) * side + 8, height: CGFloat(n) * side + 8))
        back.anchorPoint = .zero
        back.position = CGPoint(x: -4, y: -4)
        map.addChild(back)
        for i in 0..<n * n {
            let cell = SKSpriteNode(color: Toon.cream, size: CGSize(width: side - 1, height: side - 1))
            cell.position = CGPoint(x: (CGFloat(i % n) + 0.5) * side, y: (CGFloat(i / n) + 0.5) * side)
            map.addChild(cell)
            cells.append(cell)
        }
        let bell = SKSpriteNode(color: Toon.ember, size: CGSize(width: 5, height: 5))
        bell.position = CGPoint(x: CGFloat(n) * side / 2, y: CGFloat(n) * side / 2)
        map.addChild(bell)
        pin.zPosition = 2
        map.addChild(pin)
        map.position = CGPoint(x: 14, y: layout.hudFloor - CGFloat(n) * side - 14)
        overlay = map
    }

    override func frame(_ dt: TimeInterval) {
        grow()
        guard let maze = core as? MazeCore else { return }
        for (i, cell) in cells.enumerated() { cell.alpha = maze.revealed[i] ? 0.75 : 0.12 }
        if let me = focus {
            let k = 6 / (2 * CGFloat(MazeCore.block))
            pin.position = CGPoint(x: (CGFloat(me.pos.x) - CGFloat(MazeCore.block) / 2) * k, y: (CGFloat(me.pos.y) - CGFloat(MazeCore.block) / 2) * k)
        }
    }

    override func makeProp(_ p: Prop) -> SKNode? {
        switch p.kind {
        case .bell:
            let node = SKNode()
            let glow = Sprites.glow(Toon.ember, radius: 46)
            glow.alpha = 0.5
            node.addChild(glow)
            node.addChild(Props.bell())
            return node
        case .sigil:
            let star = Props.star(UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1))
            if !Tokens.Motion.reduced { star.run(.repeatForever(.rotate(byAngle: .pi, duration: 2.4))) }
            return star
        case .post:
            return Props.flag(Toon.cream)
        case .statue:
            return Props.sprite("statue", CGSize(width: 22, height: 26)) { c in
                Props.ink(c, Props.rr(4, 17, 14, 7, 2), Toon.limestone.shaded(0.7), line: 2)
                Props.ink(c, Props.rr(7, 8, 8, 10, 3), Toon.limestone, line: 2)
                Props.ink(c, Props.oval(7, 2, 8, 8), Toon.limestone, line: 2)
            }
        default:
            return nil
        }
    }

    override func updateProp(_ node: SKNode, _ p: Prop, dt: TimeInterval) {
        // A find already claimed is only a shadow of itself.
        if p.kind == .sigil || p.kind == .post { node.alpha = p.state == 1 ? 0.25 : 1 }
        // Whatever is round the corner and out of sight is not drawn.
        guard let me = core.human, let radius = core.sightRadius else { return }
        node.isHidden = p.hidden || p.pos.distance(to: me.pos) > radius * 1.1
    }
}
