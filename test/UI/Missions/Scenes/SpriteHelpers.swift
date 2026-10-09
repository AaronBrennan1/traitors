import SpriteKit

/// Node builders. Everything is drawn from shapes and SF Symbols; there are no image assets.
enum Sprites {
    static func disc(_ radius: CGFloat, fill: UIColor, stroke: UIColor? = nil, line: CGFloat = 2) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: radius)
        n.fillColor = fill
        n.strokeColor = stroke ?? .clear
        n.lineWidth = stroke == nil ? 0 : line
        return n
    }

    /// A soft additive glow.
    static func glow(_ color: UIColor, radius: CGFloat) -> SKSpriteNode {
        let n = SKSpriteNode(texture: radial([(color.withAlphaComponent(0.85), 0), (color.withAlphaComponent(0), 1)]),
                             size: CGSize(width: radius * 2, height: radius * 2))
        n.blendMode = .add
        return n
    }

    /// A soft patch of colour that does not add light: mist, haze, the dark at the edge of the picture.
    static func haze(_ color: UIColor, size: CGSize, alpha: CGFloat) -> SKSpriteNode {
        let n = SKSpriteNode(texture: radial([(color.withAlphaComponent(alpha), 0), (color.withAlphaComponent(alpha * 0.5), 0.5), (color.withAlphaComponent(0), 1)]), size: size)
        return n
    }

    /// The corners of the picture drawn down into the dark.
    static func vignette(size: CGSize, strength: CGFloat) -> SKSpriteNode {
        let dark = Toon.ink
        let t = radial([(dark.withAlphaComponent(0), 0), (dark.withAlphaComponent(0), 0.52), (dark.withAlphaComponent(strength * 0.45), 0.8), (dark.withAlphaComponent(strength), 1)], fillBeyond: true)
        return SKSpriteNode(texture: t, size: size)
    }

    /// Darkness with a soft hole in the middle, for the lantern. At scale 1 the hole is 210 points across its radius.
    static func darkness() -> SKSpriteNode {
        let dark = UIColor.black.withAlphaComponent(0.97)
        let t = radial([(dark.withAlphaComponent(0), 0), (dark.withAlphaComponent(0), 0.07), (dark, 0.135), (dark, 1)], fillBeyond: true)
        return SKSpriteNode(texture: t, size: CGSize(width: 3200, height: 3200))
    }

    private static func radial(_ stops: [(UIColor, CGFloat)], fillBeyond: Bool = false) -> SKTexture {
        let side: CGFloat = fillBeyond ? 512 : 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let colors = stops.map { $0.0.cgColor } as CFArray
            let locations = stops.map { $0.1 }
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            let c = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2,
                                             options: fillBeyond ? [.drawsAfterEndLocation] : [])
        }
        return SKTexture(image: image)
    }
}

/// A thumb-stick that appears wherever the thumb lands.
final class ThumbStick: SKNode {
    private let reach: CGFloat = 40
    private let knob = Sprites.disc(17, fill: Toon.cream.withAlphaComponent(0.55))
    private var origin: CGPoint?
    /// Direction and strength of the push, length 0...1.
    private(set) var vector = CGVector.zero

    override init() {
        super.init()
        addChild(Sprites.disc(reach, fill: Toon.cream.withAlphaComponent(0.08), stroke: Toon.cream.withAlphaComponent(0.3)))
        addChild(knob)
        zPosition = 900
        isHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    func begin(_ p: CGPoint) {
        origin = p
        position = p
        knob.position = .zero
        vector = .zero
        isHidden = false
    }

    func move(_ p: CGPoint) {
        guard let o = origin else { return }
        let dx = p.x - o.x, dy = p.y - o.y
        let len = hypot(dx, dy)
        guard len > 0.5 else { vector = .zero; knob.position = .zero; return }
        let pull = min(len, reach)
        knob.position = CGPoint(x: dx / len * pull, y: dy / len * pull)
        vector = CGVector(dx: dx / len * pull / reach, dy: dy / len * pull / reach)
    }

    /// Stands the stick somewhere with a push already on it, for a demonstration with no thumb of its own.
    func show(at p: CGPoint, push v: CGVector) {
        position = p
        knob.position = CGPoint(x: v.dx * reach, y: v.dy * reach)
        isHidden = false
    }

    func end() {
        origin = nil
        vector = .zero
        isHidden = true
    }
}

extension CGPoint {
    func distance(to o: CGPoint) -> CGFloat { hypot(x - o.x, y - o.y) }
}
