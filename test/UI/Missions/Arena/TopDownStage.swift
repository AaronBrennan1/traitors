import SpriteKit

/// A game seen flat and from straight above, like the gauntlet, but all on one screen: the whole
/// arena is fitted between the tally and the thumbs, and nothing scrolls.
class TopDownStage: CoreStage {
    /// The room there is for the arena, in screen points from the bottom.
    private var room: (low: CGFloat, high: CGFloat) { (layout.safeBottom + 104, layout.hudFloor - 10) }

    override var zoom: CGFloat {
        min(1.25, ArenaLayout.width / CGFloat(core.size.x), (room.high - room.low) / CGFloat(core.size.y))
    }

    override var home: CGPoint {
        let k = zoom
        return CGPoint(x: (ArenaLayout.width - CGFloat(core.size.x) * k) / 2,
                       y: room.low + (room.high - room.low - CGFloat(core.size.y) * k) / 2)
    }

    override func project(_ p: Vec2, z: Double) -> (CGPoint, CGFloat) { (CGPoint(x: p.x, y: p.y + z), 1) }
    override var backdrop: UIColor { Toon.pit }
    override var figureScale: CGFloat { 0.82 }
    override var figureLift: CGFloat { 12 }

    // MARK: Painting

    /// A picture painted once, in the arena's own axes with y running up. It is not kept once the stage is gone.
    static func bake(_ size: CGSize, _ paint: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            paint(ctx.cgContext)
        }
        return SKTexture(image: image)
    }

    /// Lays a painted floor under the whole arena, and a little beyond it.
    @discardableResult
    func floor(margin: CGFloat = 0, z: CGFloat = -100, _ paint: (CGContext, CGRect) -> Void) -> SKSpriteNode {
        let size = CGSize(width: CGFloat(core.size.x) + 2 * margin, height: CGFloat(core.size.y) + 2 * margin)
        let texture = Self.bake(size) { c in
            c.translateBy(x: margin, y: margin)
            paint(c, CGRect(x: 0, y: 0, width: core.size.x, height: core.size.y))
        }
        let node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = .zero
        node.position = CGPoint(x: -margin, y: -margin)
        node.zPosition = z
        addChild(node)
        return node
    }

    /// Flagstones the way the gauntlet lays them: a dark joint, a stone a shade off its neighbours, a lit top edge.
    static func flags(_ c: CGContext, _ rect: CGRect, cell: CGFloat, stone: UIColor, joint: UIColor = Toon.wallStone, seed: UInt64 = 3) {
        c.setFillColor(joint.cgColor)
        c.fill(rect)
        var row = 0
        var y = rect.minY
        while y < rect.maxY - 0.5 {
            var col = 0
            var x = rect.minX
            while x < rect.maxX - 0.5 {
                var dice = SeededRNG.derived(UInt64(row * 131 + col), seed)
                let box = CGRect(x: x, y: y, width: min(cell, rect.maxX - x), height: min(cell, rect.maxY - y)).insetBy(dx: 0.75, dy: 0.75)
                let shade = stone.shaded(dice.cg(0.9, 1.1))
                c.setFillColor(shade.cgColor)
                c.fill(box)
                c.setFillColor(shade.shaded(1.14).cgColor)
                c.fill(CGRect(x: box.minX + 0.75, y: box.maxY - 2.25, width: box.width - 1.5, height: 1.5))
                x += cell
                col += 1
            }
            y += cell
            row += 1
        }
    }

    /// Walls standing on a grid: a lit cap, and a dark face on the side towards the eye.
    static func walls(_ c: CGContext, _ grid: ArenaGrid, color: UIColor, face: CGFloat = 9, where wanted: (Int, Int) -> Bool = { _, _ in true }) {
        let cell = CGFloat(grid.cell)
        for r in 0..<grid.rows {
            for col in 0..<grid.cols where grid.isSolid(col, r) && wanted(col, r) {
                let box = CGRect(x: CGFloat(col) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                c.setFillColor(color.cgColor)
                c.fill(box)
                if !(grid.isSolid(col, r - 1) && grid.inside(col, r - 1)) || !wanted(col, r - 1) {
                    c.setFillColor(color.shaded(0.55).cgColor)
                    c.fill(CGRect(x: box.minX, y: box.minY, width: cell, height: face))
                }
                c.setFillColor(color.shaded(1.14).cgColor)
                c.fill(CGRect(x: box.minX + 1, y: box.maxY - 4, width: cell - 2, height: 3))
            }
        }
    }

    /// A pool of light on the floor.
    func light(at p: Vec2, radius: CGFloat, color: UIColor = Toon.ember, alpha: CGFloat = 0.55, pulse: Bool = true) -> SKSpriteNode {
        let glow = Sprites.glow(color, radius: radius)
        glow.position = CGPoint(x: p.x, y: p.y)
        glow.zPosition = -40
        glow.alpha = alpha
        addChild(glow)
        if pulse, !Tokens.Motion.reduced {
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: alpha * 0.7, duration: 0.7), .fadeAlpha(to: alpha, duration: 0.9)])))
        }
        return glow
    }
}
